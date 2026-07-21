import Testing
import UIKit
@testable import PicaHub

@MainActor
private final class ControlledReaderImageLoader: ReaderImageLoading {
    enum CancellationResult {
        case immediateCancellationError
        case delayedAPIError
    }

    private(set) var startedURLs: [URL] = []
    private(set) var activeURLs = Set<URL>()
    private(set) var cancelledURLs: [URL] = []
    private(set) var cancelledTargetWidths: [Int] = []
    private(set) var retriedURLs: [URL] = []
    private(set) var decodedCacheClearCount = 0
    private(set) var peakActiveLoadCount = 0
    private var continuations: [URL: CheckedContinuation<UIImage, any Error>] = [:]
    private var cancelledContinuations: [URL: [CheckedContinuation<UIImage, any Error>]] = [:]
    private let cancellationResult: CancellationResult

    init(cancellationResult: CancellationResult = .immediateCancellationError) {
        self.cancellationResult = cancellationResult
    }

    func load(_ url: URL) async throws -> UIImage {
        startedURLs.append(url)
        activeURLs.insert(url)
        peakActiveLoadCount = max(peakActiveLoadCount, activeURLs.count)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[url] = continuation
        }
    }

    func retry(_ url: URL) async throws -> UIImage {
        retriedURLs.append(url)
        return try await load(url)
    }

    func cancelLoading(for url: URL) {
        cancelledURLs.append(url)
        activeURLs.remove(url)
        guard let continuation = continuations.removeValue(forKey: url) else { return }
        switch cancellationResult {
        case .immediateCancellationError:
            continuation.resume(throwing: CancellationError())
        case .delayedAPIError:
            cancelledContinuations[url, default: []].append(continuation)
        }
    }

    func cancelLoading(for url: URL, targetPixelWidth: Int) {
        cancelledTargetWidths.append(targetPixelWidth)
        cancelLoading(for: url)
    }

    func removeDecodedImages() {
        decodedCacheClearCount += 1
    }

    func finish(_ url: URL, size: CGSize = CGSize(width: 100, height: 200)) {
        activeURLs.remove(url)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        continuations.removeValue(forKey: url)?.resume(returning: image)
    }

    func fail(_ url: URL) {
        activeURLs.remove(url)
        continuations.removeValue(forKey: url)?.resume(throwing: APIError.connection("offline"))
    }

    func finishDelayedCancellation(_ url: URL) {
        guard var pending = cancelledContinuations[url], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        cancelledContinuations[url] = pending
        continuation.resume(throwing: APIError.cancelled)
    }
}

@MainActor
struct ReaderImageModelTests {
    @Test func individualFailurePreservesSurroundingImagesAndRepeatedRetryStartsOnce() async throws {
        let urls = try (0..<3).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(urls: urls, loader: loader)

        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs.count == 3 }
        loader.finish(urls[0])
        loader.fail(urls[1])
        loader.finish(urls[2])
        await waitUntil {
            Self.isLoaded(model.state(at: 0))
                && Self.isFailed(model.state(at: 1))
                && Self.isLoaded(model.state(at: 2))
        }

        model.retry(1)
        model.retry(1)
        await waitUntil { loader.retriedURLs.count == 1 }
        loader.finish(urls[1])
        await waitUntil { Self.isLoaded(model.state(at: 1)) }

        #expect(loader.retriedURLs == [urls[1]])
        #expect(Self.isLoaded(model.state(at: 0)))
        #expect(Self.isLoaded(model.state(at: 2)))
    }

    @Test func prioritizesVisibleImageAndOnlyPrefetchesBoundedLookAheadRange() async throws {
        let urls = try (0..<8).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 3,
            maximumConcurrentLoads: 2
        )

        model.updateVisibleIndex(3)
        await waitUntil { loader.startedURLs.count == 2 }

        #expect(loader.startedURLs == [urls[3], urls[4]])
        #expect(loader.activeURLs.count == 2)
        #expect(loader.startedURLs.allSatisfy { [urls[3], urls[4], urls[5], urls[6]].contains($0) })

        loader.finish(urls[3])
        await waitUntil { loader.startedURLs.count == 3 }
        #expect(loader.startedURLs.last == urls[5])

        loader.finish(urls[4])
        await waitUntil { loader.startedURLs.count == 4 }
        #expect(loader.startedURLs.last == urls[6])
        #expect(!loader.startedURLs.contains(urls[7]))
        #expect(loader.peakActiveLoadCount == 2)
        model.cancelAll()
    }

    @Test func cancelAllStopsEveryActiveLoadAndLeavesCancelledImagesIdle() async throws {
        let urls = try (0..<5).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader(cancellationResult: .delayedAPIError)
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            maximumConcurrentLoads: 3
        )

        model.updateVisibleIndex(1)
        await waitUntil { loader.activeURLs == Set(urls[1...3]) }

        model.cancelAll()

        #expect(loader.activeURLs.isEmpty)
        #expect(Set(loader.cancelledURLs) == Set(urls[1...3]))
        #expect(urls[1...3].indices.allSatisfy { Self.isIdle(model.state(at: $0)) })

        for url in urls[1...3] {
            loader.finishDelayedCancellation(url)
        }
        await Task.yield()

        #expect(urls[1...3].indices.allSatisfy { Self.isIdle(model.state(at: $0)) })
        #expect(urls[1...3].indices.allSatisfy { !Self.isFailed(model.state(at: $0)) })
    }

    @Test func changingVisiblePositionCancelsObsoletePrefetchBeforeStartingNewRange() async throws {
        let urls = try (0..<8).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            maximumConcurrentLoads: 3
        )

        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs.count == 3 }
        model.updateVisibleIndex(5)
        await waitUntil { loader.activeURLs == Set([urls[5], urls[6], urls[7]]) }

        #expect(Set(loader.cancelledURLs).isSuperset(of: Set([urls[0], urls[1], urls[2]])))
        #expect(loader.startedURLs.suffix(3) == [urls[5], urls[6], urls[7]])
        #expect(loader.activeURLs.count == 3)
        model.cancelAll()
    }

    @Test func rapidJumpBackIgnoresLateCancellationAndAutomaticallyReloadsVisibleRange() async throws {
        let urls = try (0..<8).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader(cancellationResult: .delayedAPIError)
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            maximumConcurrentLoads: 3
        )

        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs == Set(urls[0...2]) }
        model.updateVisibleIndex(5)
        await waitUntil { loader.activeURLs == Set(urls[5...7]) }
        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs == Set(urls[0...2]) }

        for url in urls[0...2] {
            loader.finishDelayedCancellation(url)
        }
        await Task.yield()

        #expect(loader.startedURLs.filter { urls[0...2].contains($0) }.count == 6)
        #expect(urls[0...2].indices.allSatisfy { index in
            Self.isLoading(model.state(at: index))
        })

        for url in urls[0...2] {
            loader.finish(url)
        }
        await waitUntil { urls[0...2].indices.allSatisfy { Self.isLoaded(model.state(at: $0)) } }

        #expect(urls[0...2].indices.allSatisfy { !Self.isFailed(model.state(at: $0)) })
        model.cancelAll()
        for url in urls[5...7] {
            loader.finishDelayedCancellation(url)
        }
    }

    @Test func decodedResidencyStaysBoundedAndKeepsAspectRatioAfterEviction() async throws {
        let urls = try (0..<8).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            residentBehindCount: 1,
            residentAheadCount: 1,
            maximumConcurrentLoads: 3
        )

        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs == Set(urls[0...2]) }
        for url in urls[0...2] {
            loader.finish(url, size: CGSize(width: 120, height: 240))
        }
        await waitUntil { model.residentImageCount == 2 }
        #expect(Self.isIdle(model.state(at: 2)))

        model.updateVisibleIndex(4)
        await waitUntil { loader.activeURLs == Set(urls[4...6]) }

        #expect(model.residentImageCount == 0)
        #expect(Self.isIdle(model.state(at: 0)))
        #expect(model.aspectRatio(at: 0) == 0.5)

        for url in urls[4...6] {
            loader.finish(url)
        }
        await waitUntil { model.residentImageCount == 2 }
        #expect(Self.isIdle(model.state(at: 6)))
        #expect(model.residentImageCount <= 3)
    }

    @Test func shortReverseScrollUsesBackwardResidentWindowWithoutReloading() async throws {
        let urls = try (0..<6).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            residentBehindCount: 1,
            residentAheadCount: 2,
            maximumConcurrentLoads: 3
        )

        model.updateVisibleIndex(2)
        await waitUntil { loader.activeURLs == Set(urls[2...4]) }
        for url in urls[2...4] { loader.finish(url) }
        await waitUntil { model.residentImageCount == 3 }

        model.updateVisibleIndex(3)
        await Task.yield()
        model.updateVisibleIndex(2)
        await Task.yield()

        #expect(Self.isLoaded(model.state(at: 2)))
        #expect(model.cacheSource(at: 2) == .resident)
        let diagnostic = try #require(model.cacheDiagnostics[2])
        #expect(diagnostic.resourceIdentifier.hasPrefix("example.com/"))
        #expect(!diagnostic.resourceIdentifier.contains("?"))
        #expect(loader.startedURLs.filter { $0 == urls[2] }.count == 1)
    }

    @Test func backgroundingCancelsPrefetchAndKeepsOnlyVisibleDecodedImage() async throws {
        let urls = try (0..<5).map { index in
            try #require(URL(string: "https://example.com/\(index).jpg"))
        }
        let loader = ControlledReaderImageLoader()
        let model = ReaderImageModel(
            urls: urls,
            loader: loader,
            lookAheadCount: 2,
            maximumConcurrentLoads: 3,
            targetPixelWidth: 900
        )

        model.updateVisibleIndex(0)
        await waitUntil { loader.activeURLs == Set(urls[0...2]) }
        loader.finish(urls[0])
        await waitUntil { Self.isLoaded(model.state(at: 0)) }
        model.handleBackgrounding()
        await Task.yield()

        #expect(model.residentImageCount == 1)
        #expect(Set(loader.cancelledURLs).isSuperset(of: Set(urls[1...2])))
        #expect(loader.cancelledTargetWidths.allSatisfy { $0 == 900 })
        #expect(loader.decodedCacheClearCount == 1)

        model.handleForegrounding()
        await waitUntil { loader.activeURLs == Set(urls[1...2]) }
        #expect(model.visibleIndex == 0)
        model.cancelAll()
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待异步图片调度状态超时")
    }

    private static func isLoaded(_ state: ReaderImageModel.State) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func isLoading(_ state: ReaderImageModel.State) -> Bool {
        if case .loading = state { return true }
        return false
    }

    private static func isIdle(_ state: ReaderImageModel.State) -> Bool {
        if case .idle = state { return true }
        return false
    }

    private static func isFailed(_ state: ReaderImageModel.State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

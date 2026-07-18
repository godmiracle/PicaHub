import Testing
import UIKit
@testable import PicaHub

@MainActor
private final class ControlledReaderImageLoader: ReaderImageLoading {
    private(set) var startedURLs: [URL] = []
    private(set) var activeURLs = Set<URL>()
    private(set) var cancelledURLs: [URL] = []
    private(set) var retriedURLs: [URL] = []
    private var continuations: [URL: CheckedContinuation<UIImage, any Error>] = [:]

    func load(_ url: URL) async throws -> UIImage {
        startedURLs.append(url)
        activeURLs.insert(url)
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
        continuations.removeValue(forKey: url)?.resume(throwing: CancellationError())
    }

    func removeDecodedImages() {}

    func finish(_ url: URL) {
        activeURLs.remove(url)
        continuations.removeValue(forKey: url)?.resume(returning: UIImage())
    }

    func fail(_ url: URL) {
        activeURLs.remove(url)
        continuations.removeValue(forKey: url)?.resume(throwing: APIError.connection("offline"))
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
        #expect(!loader.startedURLs.contains(urls[7]))
        model.cancelAll()
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

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        attempts: Int = 100
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待异步图片调度状态超时")
    }

    private static func isLoaded(_ state: ReaderImageModel.State) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func isFailed(_ state: ReaderImageModel.State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

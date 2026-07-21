import Foundation
import Testing
import UIKit
@testable import PicaHub

private actor ImageLoadQueue {
    private var results: [Result<(Data, HTTPURLResponse), APIError>]
    private(set) var policies: [URLRequest.CachePolicy] = []

    init(results: [Result<(Data, HTTPURLResponse), APIError>]) {
        self.results = results
    }

    func load(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        policies.append(request.cachePolicy)
        guard !results.isEmpty else { throw APIError.invalidResponse }
        return try results.removeFirst().get()
    }
}

private actor GatedImageLoader {
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    private(set) var callCount = 0

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with result: Result<(Data, HTTPURLResponse), APIError>) {
        continuation?.resume(with: result.mapError { $0 as any Error })
        continuation = nil
    }
}

private actor SequencedImageLoader {
    private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), any Error>] = [:]
    private(set) var callCount = 0

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        let call = callCount
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func finish(
        call: Int,
        with result: Result<(Data, HTTPURLResponse), APIError>
    ) {
        continuations.removeValue(forKey: call)?.resume(with: result.mapError { $0 as any Error })
    }
}

private actor CancellationObservingImageLoader {
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancelPendingLoad() }
        }
    }

    private func cancelPendingLoad() {
        cancellationCount += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@MainActor
struct ImagePipelineTests {
    @Test func decodedImageCacheAvoidsRepeatedLoading() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(results: [.success((Self.imageData(), response))])
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        let first = try await pipeline.load(url)
        let second = try await pipeline.load(url)

        #expect(first === second)
        #expect(await queue.policies == [.returnCacheDataElseLoad])
    }

    @Test func retryEvictsDecodedImageAndBypassesURLCache() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(
            results: [
                .failure(.connection("offline")),
                .success((Self.imageData(), response)),
            ]
        )
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        do {
            _ = try await pipeline.load(url)
            Issue.record("Expected initial image load to fail")
        } catch {
            #expect(error as? APIError == .connection("offline"))
        }
        _ = try await pipeline.retry(url)

        #expect(await queue.policies == [.returnCacheDataElseLoad, .reloadIgnoringLocalCacheData])
        #expect(pipeline.cachedImage(for: url) != nil)
    }

    @Test func concurrentRequestsForSameImageShareOneLoad() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let loader = GatedImageLoader()
        let pipeline = ImagePipeline(loader: { request in try await loader.load(request) })

        let first = Task { @MainActor in try await pipeline.load(url) }
        while await loader.callCount == 0 { await Task.yield() }
        let second = Task { @MainActor in try await pipeline.load(url) }
        await loader.finish(with: .success((Self.imageData(), response)))

        _ = try await first.value
        _ = try await second.value
        #expect(await loader.callCount == 1)
    }

    @Test func cancelledOldTaskCannotClearImmediatelyReloadedTask() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let loader = SequencedImageLoader()
        let pipeline = ImagePipeline(loader: { request in try await loader.load(request) })

        let first = Task { @MainActor in try await pipeline.load(url) }
        while await loader.callCount == 0 { await Task.yield() }

        pipeline.cancelLoading(for: url)
        let second = Task { @MainActor in try await pipeline.load(url) }
        while await loader.callCount < 2 { await Task.yield() }

        await loader.finish(call: 1, with: .failure(.cancelled))
        await loader.finish(call: 2, with: .success((Self.imageData(), response)))

        _ = try? await first.value
        _ = try await second.value
        #expect(pipeline.cachedImage(for: url) != nil)
    }

    @Test func cancellingOneSharedConsumerKeepsOtherConsumerAlive() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let loader = GatedImageLoader()
        let pipeline = ImagePipeline(loader: { request in try await loader.load(request) })

        let first = Task { @MainActor in try await pipeline.load(url) }
        while await loader.callCount == 0 { await Task.yield() }
        let second = Task { @MainActor in try await pipeline.load(url) }
        await waitUntil { pipeline.registeredConsumerCount(for: url) == 2 }
        pipeline.cancelLoading(for: url)

        await loader.finish(with: .success((Self.imageData(), response)))
        _ = try await first.value
        _ = try await second.value

        #expect(await loader.callCount == 1)
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
        Issue.record("等待图片管线状态超时")
    }

    @Test func cancellingLastConsumerCancelsUnderlyingTask() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let loader = CancellationObservingImageLoader()
        let pipeline = ImagePipeline(loader: { request in try await loader.load(request) })

        let load = Task { @MainActor in try await pipeline.load(url) }
        while await loader.callCount == 0 { await Task.yield() }

        pipeline.cancelLoading(for: url)
        while await loader.cancellationCount == 0 { await Task.yield() }

        _ = try? await load.value
        #expect(await loader.cancellationCount == 1)
    }

    @Test func clearingDecodedCachePreservesRawURLCachePolicy() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(
            results: [
                .success((Self.imageData(), response)),
                .success((Self.imageData(), response)),
            ]
        )
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        _ = try await pipeline.load(url)
        pipeline.removeDecodedImages()
        _ = try await pipeline.load(url)

        #expect(await queue.policies == [.returnCacheDataElseLoad, .returnCacheDataElseLoad])
    }

    @Test func targetWidthsUseIndependentDecodedCacheEntries() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(
            results: [
                .success((Self.imageData(size: CGSize(width: 400, height: 800)), response)),
                .success((Self.imageData(size: CGSize(width: 400, height: 800)), response)),
            ]
        )
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        let small = try await pipeline.load(url, targetPixelWidth: 100)
        let large = try await pipeline.load(url, targetPixelWidth: 200)
        let cachedSmall = try await pipeline.load(url, targetPixelWidth: 100)

        #expect(small !== large)
        #expect(small === cachedSmall)
        #expect(await queue.policies.count == 2)
    }

    @Test func portraitDecodeTreatsTargetAsWidthInsteadOfLongestEdge() async throws {
        let url = try #require(URL(string: "https://example.com/portrait.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(
            results: [.success((Self.imageData(size: CGSize(width: 100, height: 400)), response))]
        )
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        let image = try await pipeline.load(url, targetPixelWidth: 50)
        let cgImage = try #require(image.cgImage)

        #expect(abs(cgImage.width - 50) <= 1)
        #expect(abs(cgImage.height - 200) <= 1)
    }

    @Test func decodedByteBudgetDownsamplesLongImage() async throws {
        let url = try #require(URL(string: "https://example.com/long.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(
            results: [.success((Self.imageData(size: CGSize(width: 1_000, height: 4_000)), response))]
        )
        let pipeline = ImagePipeline(
            maximumDecodedImageBytes: 1 * 1_024 * 1_024,
            loader: { request in try await queue.load(request) }
        )

        let image = try await pipeline.load(url, targetPixelWidth: 500)
        let cgImage = try #require(image.cgImage)

        #expect(cgImage.width <= 257)
        #expect(cgImage.height <= 1_025)
        #expect(cgImage.bytesPerRow * cgImage.height <= 1_100_000)
    }

    @Test func cacheSourceDistinguishesEncodedDecodedAndNetworkLoadsWithoutExposingQuery() async throws {
        let url = try #require(
            URL(string: "https://example.com/image.png?token=secret&signature=private")
        )
        let response = Self.response(url: url)
        let data = Self.imageData()
        let queue = ImageLoadQueue(
            results: [
                .success((data, response)),
                .success((data, response)),
            ]
        )
        let cachedResponse = CachedURLResponse(response: response, data: data)
        let pipeline = ImagePipeline(
            loader: { request in try await queue.load(request) },
            cachedResponseLookup: { _ in cachedResponse }
        )

        _ = try await pipeline.load(url, targetPixelWidth: 100)
        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 100) == .encodedOrRevalidated)

        _ = try await pipeline.load(url, targetPixelWidth: 100)
        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 100) == .decoded)

        _ = try await pipeline.retry(url, targetPixelWidth: 100)
        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 100) == .network)

        let diagnostic = try #require(
            pipeline.cacheDiagnostic(for: url, targetPixelWidth: 100)
        )
        #expect(diagnostic.source == .network)
        #expect(diagnostic.targetPixelWidth == 100)
        #expect(diagnostic.resourceIdentifier.hasPrefix("example.com/"))
        #expect(!diagnostic.resourceIdentifier.contains("?"))
        #expect(!diagnostic.resourceIdentifier.contains("token"))
        #expect(!diagnostic.resourceIdentifier.contains("secret"))
        #expect(!diagnostic.resourceIdentifier.contains("signature"))
        #expect(!diagnostic.resourceIdentifier.contains("private"))
    }

    @Test func cacheDiagnosticsRemainIsolatedByTargetWidth() async throws {
        let url = try #require(URL(string: "https://example.com/image.png?token=secret"))
        let response = Self.response(url: url)
        let data = Self.imageData()
        let queue = ImageLoadQueue(
            results: [
                .success((data, response)),
                .success((data, response)),
            ]
        )
        let cachedResponse = CachedURLResponse(response: response, data: data)
        let pipeline = ImagePipeline(
            loader: { request in try await queue.load(request) },
            cachedResponseLookup: { request in
                request.cachePolicy == .reloadIgnoringLocalCacheData ? nil : cachedResponse
            }
        )

        _ = try await pipeline.load(url, targetPixelWidth: 100)
        _ = try await pipeline.retry(url, targetPixelWidth: 200)

        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 100) == .encodedOrRevalidated)
        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 200) == .network)
    }

    @Test func exactSizeCancellationDoesNotCancelAnotherTargetWidth() async throws {
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = Self.response(url: url)
        let loader = SequencedImageLoader()
        let pipeline = ImagePipeline(loader: { request in try await loader.load(request) })

        let small = Task { @MainActor in try await pipeline.load(url, targetPixelWidth: 100) }
        while await loader.callCount < 1 { await Task.yield() }
        let large = Task { @MainActor in try await pipeline.load(url, targetPixelWidth: 200) }
        while await loader.callCount < 2 { await Task.yield() }

        pipeline.cancelLoading(for: url, targetPixelWidth: 100)
        await loader.finish(call: 1, with: .success((Self.imageData(), response)))
        await loader.finish(call: 2, with: .success((Self.imageData(), response)))

        _ = try? await small.value
        _ = try await large.value
        _ = try await pipeline.load(url, targetPixelWidth: 200)
        #expect(await loader.callCount == 2)
    }

    @Test func sameChapterReentryUsesDecodedEntryWithoutAnotherRequest() async throws {
        let url = try #require(URL(string: "https://example.com/chapter-image.png"))
        let response = Self.response(url: url)
        let queue = ImageLoadQueue(results: [.success((Self.imageData(), response))])
        let pipeline = ImagePipeline(loader: { request in try await queue.load(request) })

        _ = try await pipeline.load(url, targetPixelWidth: 600)
        _ = try await pipeline.load(url, targetPixelWidth: 600)

        #expect(await queue.policies == [.returnCacheDataElseLoad])
        #expect(pipeline.cacheSource(for: url, targetPixelWidth: 600) == .decoded)
    }

    private static func imageData(size: CGSize = CGSize(width: 2, height: 2)) -> Data {
        UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func response(url: URL) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
    }
}

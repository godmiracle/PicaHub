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

    private static func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
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

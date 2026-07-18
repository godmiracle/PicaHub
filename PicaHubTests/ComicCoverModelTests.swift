import Foundation
import Testing
import UIKit
@testable import PicaHub

private actor CoverResponseQueue {
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

@MainActor
struct ComicCoverModelTests {
    @Test func successfulImageOnlyLoadsOnce() async throws {
        let url = try #require(URL(string: "https://example.com/cover.png"))
        let response = Self.response(url: url)
        let queue = CoverResponseQueue(results: [.success((Self.imageData(), response))])
        let model = ComicCoverModel(url: url) { request in try await queue.load(request) }

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.state == .loaded)
        #expect(model.image != nil)
        #expect(await queue.policies == [.returnCacheDataElseLoad])
    }

    @Test func failureCanRetryWhileBypassingURLCache() async throws {
        let url = try #require(URL(string: "https://example.com/cover.png"))
        let response = Self.response(url: url)
        let queue = CoverResponseQueue(
            results: [.failure(.connection("offline")), .success((Self.imageData(), response))]
        )
        let model = ComicCoverModel(url: url) { request in try await queue.load(request) }

        await model.loadIfNeeded()
        #expect(model.state == .failed)

        await model.retry()
        #expect(model.state == .loaded)
        #expect(await queue.policies == [.returnCacheDataElseLoad, .reloadIgnoringLocalCacheData])
    }

    private static func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.systemIndigo.setFill()
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

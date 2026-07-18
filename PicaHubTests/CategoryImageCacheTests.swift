import Foundation
import Testing
import UIKit
@testable import PicaHub

private actor ImageRequestRecorder {
    private(set) var cachePolicies: [URLRequest.CachePolicy] = []

    func record(_ request: URLRequest) {
        cachePolicies.append(request.cachePolicy)
    }
}

@MainActor
struct CategoryImageCacheTests {
    @Test func keepsFirstImageUntilCacheIsManuallyCleared() async throws {
        let attempts = AttemptCounter()
        let requests = ImageRequestRecorder()
        let imageData = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let cache = CategoryImageCache { request in
            _ = await attempts.increment()
            await requests.record(request)
            return (
                imageData,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/png"]
                )!
            )
        }
        let firstURL = try #require(URL(string: "https://example.com/first.png"))
        let changedURL = try #require(URL(string: "https://example.com/changed.png"))

        let initial = try await cache.load(categoryID: "featured", from: firstURL)
        let retained = try await cache.load(categoryID: "featured", from: changedURL)

        #expect(initial === retained)
        #expect(await attempts.value == 1)

        cache.removeAll()
        let refreshed = try await cache.load(
            categoryID: "featured",
            from: changedURL,
            reloadIgnoringURLCache: true
        )

        #expect(initial !== refreshed)
        #expect(await attempts.value == 2)
        #expect(await requests.cachePolicies == [.returnCacheDataElseLoad, .reloadIgnoringLocalCacheData])
    }
}

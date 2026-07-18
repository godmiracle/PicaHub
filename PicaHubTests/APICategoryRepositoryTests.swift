import Foundation
import Testing
@testable import PicaHub

struct APICategoryRepositoryTests {
    @Test func filtersWebCategoriesAndPreservesServiceOrder() async throws {
        let responseData = Data(
            #"{"code":200,"message":"success","data":{"categories":[{"_id":"first","title":"可浏览一","isWeb":false,"active":true},{"_id":"web","title":"网页分类","isWeb":true,"active":true},{"title":"可浏览二"}]}}"#.utf8
        )
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        let repository = APICategoryRepository(client: client)

        let categories = try await repository.fetchCategories(policy: .useCache)

        #expect(categories.map(\.title) == ["可浏览一", "可浏览二"])
        #expect(categories[1].thumb == nil)
        #expect(categories[1].isWeb == nil)
    }

    @Test func cachedCategoriesRemainStableUntilExplicitReload() async throws {
        let attempts = AttemptCounter()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                let attempt = await attempts.increment()
                let responseData = Data(
                    "{\"code\":200,\"message\":\"success\",\"data\":{\"categories\":[{\"_id\":\"featured\",\"title\":\"大家都在看\",\"thumb\":{\"fileServer\":\"https://s2.picacomic.com\",\"path\":\"cover-\(attempt).jpg\"}}]}}".utf8
                )
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        let repository = APICategoryRepository(client: client)

        let initial = try await repository.fetchCategories(policy: .useCache)
        let cached = try await repository.fetchCategories(policy: .useCache)
        let refreshed = try await repository.fetchCategories(policy: .reloadIgnoringCache)

        #expect(initial.first?.thumb?.path == "cover-1.jpg")
        #expect(cached.first?.thumb?.path == "cover-1.jpg")
        #expect(refreshed.first?.thumb?.path == "cover-2.jpg")
        #expect(await attempts.value == 2)
    }
}

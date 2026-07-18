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

        let categories = try await repository.fetchCategories()

        #expect(categories.map(\.title) == ["可浏览一", "可浏览二"])
        #expect(categories[1].thumb == nil)
        #expect(categories[1].isWeb == nil)
    }
}

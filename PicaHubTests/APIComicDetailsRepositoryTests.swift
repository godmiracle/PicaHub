import Foundation
import Testing
@testable import PicaHub

struct APIComicDetailsRepositoryTests {
    @Test func loadsDetailsAndRequestedChapterPage() async throws {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                let data: Data
                if request.url?.path.hasSuffix("/eps") == true {
                    #expect(request.url?.query == "page=2")
                    data = Data(
                        #"{"code":200,"message":"success","data":{"eps":{"docs":[{"_id":"chapter","title":"第二话","order":2}],"limit":40,"page":2,"pages":2,"total":41}}}"#.utf8
                    )
                } else {
                    data = Data(
                        #"{"code":200,"message":"success","data":{"comic":{"_id":"comic","title":"测试漫画","thumb":{"fileServer":"https://example.com","path":"cover.jpg"},"isFavourite":false}}}"#.utf8
                    )
                }
                return (
                    data,
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
        let repository = APIComicDetailsRepository(client: client)

        let details = try await repository.fetchDetails(comicID: "comic")
        let chapters = try await repository.fetchChapters(comicID: "comic", page: 2)

        #expect(details.title == "测试漫画")
        #expect(chapters.docs.first?.id == "chapter")
        #expect(chapters.page == 2)
    }
}

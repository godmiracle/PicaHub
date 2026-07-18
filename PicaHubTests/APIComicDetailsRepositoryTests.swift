import Foundation
import Testing
@testable import PicaHub

private actor ChapterPageRecorder {
    private(set) var pages: [Int] = []

    func record(_ page: Int) {
        pages.append(page)
    }
}

struct APIComicDetailsRepositoryTests {
    @Test func loadsDetailsAndAllChapterPagesNewestFirstWithoutDuplicates() async throws {
        let recorder = ChapterPageRecorder()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                let data: Data
                if request.url?.path.hasSuffix("/eps") == true {
                    let page = Int(
                        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "page" })?.value ?? ""
                    ) ?? 0
                    await recorder.record(page)
                    data = Self.chapterResponse(page: page)
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
        let chapters = try await repository.fetchAllChapters(comicID: "comic")

        #expect(details.title == "测试漫画")
        #expect(await recorder.pages == [1, 2, 3])
        #expect(chapters.map(\.id) == ["newest", "middle", "shared", "oldest"])
    }

    private static func chapterResponse(page: Int) -> Data {
        let json: String
        switch page {
        case 1:
            json = #"{"code":200,"message":"success","data":{"eps":{"docs":[{"_id":"oldest","title":"第一话","order":1},{"_id":"shared","title":"第二话","order":2}],"limit":2,"page":1,"pages":3,"total":5}}}"#
        case 2:
            json = #"{"code":200,"message":"success","data":{"eps":{"docs":[{"_id":"shared","title":"第二话","order":2},{"_id":"middle","title":"第三话","order":3}],"limit":2,"page":2,"pages":3,"total":5}}}"#
        case 3:
            json = #"{"code":200,"message":"success","data":{"eps":{"docs":[{"_id":"newest","title":"第四话","order":4}],"limit":2,"page":3,"pages":3,"total":5}}}"#
        default:
            json = #"{"code":200,"message":"success","data":{"eps":{"docs":[],"limit":2,"page":0,"pages":3,"total":5}}}"#
        }
        return Data(json.utf8)
    }
}

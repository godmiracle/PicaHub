import Foundation
import Testing
@testable import PicaHub

struct APIComicRepositoryTests {
    @Test func sendsSelectedCategorySortAndPage() async throws {
        let responseData = Data(
            #"{"code":200,"message":"success","data":{"comics":{"docs":[],"limit":20,"page":2,"pages":3,"total":50}}}"#.utf8
        )
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                #expect(request.url?.absoluteString == "https://picaapi.go2778.com/comics?page=2&c=%E9%AA%91%E5%A3%AB&s=ld")
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
        let repository = APIComicRepository(client: client)

        let page = try await repository.fetchComics(category: "骑士", sort: .mostLiked, page: 2)

        #expect(page.page == 2)
        #expect(page.pages == 3)
    }

    @Test func searchSendsEncodedKeywordAndPage() async throws {
        let responseData = Data(
            #"{"code":200,"message":"success","data":{"comics":{"docs":[],"limit":20,"page":3,"pages":3,"total":41}}}"#.utf8
        )
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                #expect(request.url?.absoluteString == "https://picaapi.go2778.com/comics/advanced-search?page=3")
                #expect(request.httpMethod == "POST")
                let body = try #require(request.httpBody)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["keyword"] as? String == "骑士")
                #expect(json["sort"] as? String == "dd")
                #expect((json["categories"] as? [String])?.isEmpty == true)
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
        let repository = APIComicRepository(client: client)

        let page = try await repository.searchComics(keyword: "骑士", page: 3)

        #expect(page.page == 3)
    }
}

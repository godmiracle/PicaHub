import Foundation
import Testing
@testable import PicaHub

private actor FavoriteServerStub {
    private(set) var isFavorite: Bool
    private(set) var mutationCount = 0

    init(isFavorite: Bool) {
        self.isFavorite = isFavorite
    }

    func respond(to request: URLRequest) -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let data: Data
        if path.hasSuffix("/favourite"), request.httpMethod == "POST" {
            isFavorite.toggle()
            mutationCount += 1
            data = Data(#"{"code":200,"message":"success","data":{"action":"ok"}}"#.utf8)
        } else if path == "/comics/comic" {
            data = Data(
                "{\"code\":200,\"message\":\"success\",\"data\":{\"comic\":{\"_id\":\"comic\",\"title\":\"测试漫画\",\"thumb\":{\"fileServer\":\"https://example.com\",\"path\":\"cover.jpg\"},\"isFavourite\":\(isFavorite)}}}".utf8
            )
        } else {
            data = Data(#"{"code":200,"message":"success","data":{"comics":{"docs":[],"limit":20,"page":2,"pages":4,"total":61}}}"#.utf8)
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
    }
}

struct APIFavoriteRepositoryTests {
    @Test func fetchesDetailFavoriteState() async throws {
        let server = FavoriteServerStub(isFavorite: true)
        let repository = makeRepository(server: server)

        #expect(try await repository.fetchFavoriteState(comicID: "comic"))
        #expect(await server.mutationCount == 0)
    }

    @Test func mutationIsConfirmedByFreshDetailStateAndAvoidsUnneededToggle() async throws {
        let server = FavoriteServerStub(isFavorite: false)
        let repository = makeRepository(server: server)

        #expect(try await repository.setFavorite(comicID: "comic", isFavorite: true))
        #expect(try await repository.setFavorite(comicID: "comic", isFavorite: true))
        #expect(await server.mutationCount == 1)
    }

    @Test func fetchesSelectedFavoriteSortAndPage() async throws {
        let server = FavoriteServerStub(isFavorite: false)
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                #expect(request.url?.absoluteString == "https://picaapi.go2778.com/users/favourite?page=2&s=da")
                return await server.respond(to: request)
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        let repository = APIFavoriteRepository(client: client)

        let page = try await repository.fetchFavorites(sort: .oldest, page: 2)

        #expect(page.page == 2)
        #expect(page.pages == 4)
    }

    private func makeRepository(server: FavoriteServerStub) -> APIFavoriteRepository {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in await server.respond(to: request) },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        return APIFavoriteRepository(client: client)
    }
}

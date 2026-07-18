import Foundation

struct APIComicRepository: ComicRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        try await client.send(PicaEndpoints.comics(page: page, category: category, sort: sort)).comics
    }

    func searchComics(keyword: String, page: Int) async throws -> Page<ComicSummary> {
        try await client.send(PicaEndpoints.search(keyword: keyword, page: page)).comics
    }
}

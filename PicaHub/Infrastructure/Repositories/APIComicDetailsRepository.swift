import Foundation

struct APIComicDetailsRepository: ComicDetailsRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchDetails(comicID: String) async throws -> ComicDetails {
        try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic
    }

    func fetchChapters(comicID: String, page: Int) async throws -> Page<Chapter> {
        try await client.send(PicaEndpoints.chapters(comicID: comicID, page: page)).eps
    }
}

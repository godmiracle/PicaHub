import Foundation

struct APIFavoriteRepository: FavoriteRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchFavoriteState(comicID: String) async throws -> Bool {
        try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic.isFavourite
    }

    func setFavorite(comicID: String, isFavorite: Bool) async throws -> Bool {
        let currentState = try await fetchFavoriteState(comicID: comicID)
        guard currentState != isFavorite else { return currentState }

        _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comicID))
        let confirmedState = try await fetchFavoriteState(comicID: comicID)
        guard confirmedState == isFavorite else {
            throw FavoriteRepositoryError.confirmationMismatch
        }
        return confirmedState
    }

    func fetchFavorites(sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        try await client.send(PicaEndpoints.favorites(page: page, sort: sort)).comics
    }
}

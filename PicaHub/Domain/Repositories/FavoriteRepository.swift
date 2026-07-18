import Foundation

enum FavoriteRepositoryError: Error, Sendable, Equatable {
    case confirmationMismatch
}

protocol FavoriteRepository: Sendable {
    func fetchFavoriteState(comicID: String) async throws -> Bool
    func setFavorite(comicID: String, isFavorite: Bool) async throws -> Bool
    func fetchFavorites(sort: ComicSort, page: Int) async throws -> Page<ComicSummary>
}

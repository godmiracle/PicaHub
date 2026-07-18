import Foundation

protocol ComicRepository: Sendable {
    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary>
}

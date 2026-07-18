import Foundation

protocol ComicRepository: Sendable {
    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary>
    func searchComics(keyword: String, page: Int) async throws -> Page<ComicSummary>
}

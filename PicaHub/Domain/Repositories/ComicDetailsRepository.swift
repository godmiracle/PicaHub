import Foundation

protocol ComicDetailsRepository: Sendable {
    func fetchDetails(comicID: String) async throws -> ComicDetails
    func fetchChapters(comicID: String, page: Int) async throws -> Page<Chapter>
}

import Foundation

protocol ComicDetailsRepository: Sendable {
    func fetchDetails(comicID: String) async throws -> ComicDetails
    func fetchAllChapters(comicID: String) async throws -> [Chapter]
}

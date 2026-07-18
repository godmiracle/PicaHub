import Foundation

protocol CategoryRepository: Sendable {
    func fetchCategories() async throws -> [ComicCategory]
}

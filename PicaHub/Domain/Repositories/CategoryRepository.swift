import Foundation

enum CategoryFetchPolicy: Sendable, Equatable {
    case useCache
    case reloadIgnoringCache
}

protocol CategoryRepository: Sendable {
    func fetchCategories(policy: CategoryFetchPolicy) async throws -> [ComicCategory]
}

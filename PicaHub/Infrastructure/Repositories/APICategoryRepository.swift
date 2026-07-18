import Foundation

actor APICategoryRepository: CategoryRepository {
    private let client: APIClient
    private var cachedCategories: [ComicCategory]?

    init(client: APIClient) {
        self.client = client
    }

    func fetchCategories(policy: CategoryFetchPolicy) async throws -> [ComicCategory] {
        if case .useCache = policy, let cachedCategories {
            return cachedCategories
        }

        let categories = try await client.send(PicaEndpoints.categories).categories.filter { $0.isWeb != true }
        cachedCategories = categories
        return categories
    }
}

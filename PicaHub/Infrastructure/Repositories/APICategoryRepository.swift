import Foundation

struct APICategoryRepository: CategoryRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchCategories() async throws -> [ComicCategory] {
        try await client.send(PicaEndpoints.categories).categories.filter { $0.isWeb != true }
    }
}

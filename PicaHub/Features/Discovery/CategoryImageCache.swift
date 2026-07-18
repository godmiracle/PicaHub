import Foundation
import UIKit

@MainActor
final class CategoryImageCache {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private var images: [String: UIImage] = [:]
    private var loadingTasks: [String: Task<UIImage, any Error>] = [:]
    private var generation = 0
    private let loader: Loader

    init(loader: @escaping Loader = CategoryImageCache.liveLoader) {
        self.loader = loader
    }

    func image(for categoryID: String) -> UIImage? {
        images[categoryID]
    }

    func load(
        categoryID: String,
        from url: URL,
        reloadIgnoringURLCache: Bool = false
    ) async throws -> UIImage {
        if let image = images[categoryID] {
            return image
        }
        if let loadingTask = loadingTasks[categoryID] {
            return try await loadingTask.value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = reloadIgnoringURLCache ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        let loader = loader
        let loadGeneration = generation
        let task = Task {
            let (data, response) = try await loader(request)
            guard (200...299).contains(response.statusCode), let image = UIImage(data: data) else {
                throw APIError.invalidResponse
            }
            return image
        }
        loadingTasks[categoryID] = task

        do {
            let image = try await task.value
            guard generation == loadGeneration else { throw CancellationError() }
            images[categoryID] = image
            loadingTasks[categoryID] = nil
            return image
        } catch {
            if generation == loadGeneration {
                loadingTasks[categoryID] = nil
            }
            throw error
        }
    }

    func removeAll() {
        generation += 1
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        images.removeAll()
    }

    private nonisolated static let liveLoader: Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, response)
    }
}

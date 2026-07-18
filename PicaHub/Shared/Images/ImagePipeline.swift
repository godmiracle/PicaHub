import Foundation
import UIKit

@MainActor
final class ImagePipeline {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let decodedImages = NSCache<NSURL, UIImage>()
    private var loadingTasks: [URL: Task<UIImage, any Error>] = [:]
    private let loader: Loader

    init(
        decodedImageCostLimit: Int = 64 * 1_024 * 1_024,
        loader: @escaping Loader = ImagePipeline.liveLoader
    ) {
        decodedImages.totalCostLimit = max(0, decodedImageCostLimit)
        self.loader = loader
    }

    func cachedImage(for url: URL) -> UIImage? {
        decodedImages.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async throws -> UIImage {
        if let image = cachedImage(for: url) {
            return image
        }
        return try await load(url, cachePolicy: .returnCacheDataElseLoad)
    }

    func retry(_ url: URL) async throws -> UIImage {
        decodedImages.removeObject(forKey: url as NSURL)
        return try await load(url, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func cancelLoading(for url: URL) {
        loadingTasks.removeValue(forKey: url)?.cancel()
    }

    func cancelAllLoading() {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }

    func removeDecodedImages() {
        decodedImages.removeAllObjects()
    }

    private func load(_ url: URL, cachePolicy: URLRequest.CachePolicy) async throws -> UIImage {
        if let task = loadingTasks[url] {
            return try await task.value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy
        let loader = loader
        let task = Task {
            let (data, response) = try await loader(request)
            try Task.checkCancellation()
            guard (200...299).contains(response.statusCode), let image = UIImage(data: data) else {
                throw APIError.invalidResponse
            }
            return image
        }
        loadingTasks[url] = task

        do {
            let image = try await task.value
            try Task.checkCancellation()
            decodedImages.setObject(image, forKey: url as NSURL, cost: Self.decodedCost(of: image))
            loadingTasks[url] = nil
            return image
        } catch {
            loadingTasks[url] = nil
            throw error
        }
    }

    private static func decodedCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private nonisolated static let liveLoader: Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, response)
    }
}

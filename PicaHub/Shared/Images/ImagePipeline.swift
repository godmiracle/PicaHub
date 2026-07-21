import Foundation
import CryptoKit
import ImageIO
import UIKit

enum ImageCacheSource: String, Sendable {
    case resident
    case decoded
    case encodedOrRevalidated
    case network
}

struct ImageCacheDiagnostic: Equatable, Sendable {
    let source: ImageCacheSource
    let resourceIdentifier: String
    let targetPixelWidth: Int?

    init(source: ImageCacheSource, url: URL, targetPixelWidth: Int?) {
        self.source = source
        resourceIdentifier = Self.resourceIdentifier(for: url)
        self.targetPixelWidth = targetPixelWidth
    }

    private static func resourceIdentifier(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? "unknown-host"
        let pathDigest = SHA256.hash(data: Data(url.path(percentEncoded: true).utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(host)/\(pathDigest)"
    }
}

@MainActor
final class ImagePipeline {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct LoadKey: Hashable {
        let url: URL
        let targetPixelWidth: Int?
    }

    private let decodedImages = NSCache<NSURL, UIImage>()
    private var loadingTasks: [LoadKey: Task<UIImage, any Error>] = [:]
    private var loadingGenerations: [LoadKey: Int] = [:]
    private var loadingConsumers: [LoadKey: [UUID: Bool]] = [:]
    private var cacheDiagnostics: [LoadKey: ImageCacheDiagnostic] = [:]
    private var nextLoadingGeneration = 0
    private let loader: Loader
    private let cachedResponseLookup: @Sendable (URLRequest) -> CachedURLResponse?
    private let maximumDecodedImageBytes: Int

    init(
        decodedImageCostLimit: Int = 64 * 1_024 * 1_024,
        maximumDecodedImageBytes: Int = 48 * 1_024 * 1_024,
        loader: @escaping Loader = ImagePipeline.liveLoader,
        cachedResponseLookup: @escaping @Sendable (URLRequest) -> CachedURLResponse? = ImagePipeline.liveCachedResponseLookup
    ) {
        decodedImages.totalCostLimit = max(0, decodedImageCostLimit)
        self.maximumDecodedImageBytes = max(1, maximumDecodedImageBytes)
        self.loader = loader
        self.cachedResponseLookup = cachedResponseLookup
    }

    func cachedImage(for url: URL) -> UIImage? {
        decodedImages.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async throws -> UIImage {
        try await load(url, targetPixelWidth: nil)
    }

    func load(_ url: URL, targetPixelWidth: Int) async throws -> UIImage {
        try await load(url, targetPixelWidth: targetPixelWidth > 0 ? targetPixelWidth : nil)
    }

    func retry(_ url: URL) async throws -> UIImage {
        try await retry(url, targetPixelWidth: nil)
    }

    func retry(_ url: URL, targetPixelWidth: Int) async throws -> UIImage {
        try await retry(url, targetPixelWidth: targetPixelWidth > 0 ? targetPixelWidth : nil)
    }

    private func load(_ url: URL, targetPixelWidth: Int?) async throws -> UIImage {
        let key = LoadKey(url: url, targetPixelWidth: targetPixelWidth)
        if let image = decodedImages.object(forKey: cacheKey(for: url, targetPixelWidth: targetPixelWidth)) {
            recordDiagnostic(source: .decoded, for: key)
            return image
        }
        return try await load(
            url,
            cachePolicy: .returnCacheDataElseLoad,
            targetPixelWidth: targetPixelWidth
        )
    }

    private func retry(_ url: URL, targetPixelWidth: Int?) async throws -> UIImage {
        decodedImages.removeObject(forKey: cacheKey(for: url, targetPixelWidth: targetPixelWidth))
        return try await load(
            url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            targetPixelWidth: targetPixelWidth
        )
    }

    private func cacheKey(for url: URL, targetPixelWidth: Int?) -> NSURL {
        guard let targetPixelWidth else { return url as NSURL }
        return NSURL(string: "\(url.absoluteString)#width=\(targetPixelWidth)")!
    }

    func cacheSource(for url: URL, targetPixelWidth: Int? = nil) -> ImageCacheSource? {
        cacheDiagnostic(for: url, targetPixelWidth: targetPixelWidth)?.source
    }

    func cacheDiagnostic(for url: URL, targetPixelWidth: Int? = nil) -> ImageCacheDiagnostic? {
        cacheDiagnostics[LoadKey(url: url, targetPixelWidth: targetPixelWidth)]
    }

    func registeredConsumerCount(for url: URL, targetPixelWidth: Int? = nil) -> Int {
        loadingConsumers[LoadKey(url: url, targetPixelWidth: targetPixelWidth)]?.count ?? 0
    }

    func cancelLoading(for url: URL) {
        guard let key = loadingConsumers.keys.first(where: { $0.url == url }),
              var consumers = loadingConsumers[key],
              let consumer = consumers.keys.first(where: { consumers[$0] == false })
        else {
            for key in Array(loadingTasks.keys) where key.url == url {
                loadingTasks.removeValue(forKey: key)?.cancel()
                loadingGenerations[key] = nil
            }
            return
        }
        consumers[consumer] = true
        loadingConsumers[key] = consumers
        cancelTaskIfNoConsumers(for: key)
    }

    func cancelLoading(for url: URL, targetPixelWidth: Int) {
        cancelLoading(for: LoadKey(url: url, targetPixelWidth: targetPixelWidth > 0 ? targetPixelWidth : nil))
    }

    func cancelAllLoading() {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        loadingGenerations.removeAll()
        loadingConsumers.removeAll()
    }

    func removeDecodedImages() {
        decodedImages.removeAllObjects()
    }

    private func load(
        _ url: URL,
        cachePolicy: URLRequest.CachePolicy,
        targetPixelWidth: Int?
    ) async throws -> UIImage {
        let key = LoadKey(url: url, targetPixelWidth: targetPixelWidth)
        if let task = loadingTasks[key] {
            let consumer = registerConsumer(for: key)
            defer { releaseConsumer(consumer, for: key) }
            return try await task.value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy
        let loader = loader
        let cachedResponseLookup = cachedResponseLookup
        let maximumDecodedImageBytes = maximumDecodedImageBytes
        let source: ImageCacheSource = cachePolicy != .reloadIgnoringLocalCacheData
            && cachedResponseLookup(request) != nil
            ? .encodedOrRevalidated
            : .network
        nextLoadingGeneration += 1
        let generation = nextLoadingGeneration
        let task = Task {
            let (data, response) = try await loader(request)
            try Task.checkCancellation()
            guard (200...299).contains(response.statusCode),
                  let image = Self.decode(
                      data: data,
                      targetPixelWidth: targetPixelWidth,
                      maximumDecodedImageBytes: maximumDecodedImageBytes
                  )
            else {
                throw APIError.invalidResponse
            }
            return image
        }
        loadingTasks[key] = task
        loadingGenerations[key] = generation
        let consumer = registerConsumer(for: key)
        defer { releaseConsumer(consumer, for: key) }

        do {
            let image = try await task.value
            guard loadingGenerations[key] == generation else {
                return image
            }
            decodedImages.setObject(
                image,
                forKey: cacheKey(for: url, targetPixelWidth: targetPixelWidth),
                cost: Self.decodedCost(of: image)
            )
            recordDiagnostic(source: source, for: key)
            loadingTasks[key] = nil
            loadingGenerations[key] = nil
            try Task.checkCancellation()
            return image
        } catch {
            guard loadingGenerations[key] == generation else {
                throw error
            }
            loadingTasks[key] = nil
            loadingGenerations[key] = nil
            throw error
        }
    }

    private func recordDiagnostic(source: ImageCacheSource, for key: LoadKey) {
        let diagnostic = ImageCacheDiagnostic(
            source: source,
            url: key.url,
            targetPixelWidth: key.targetPixelWidth
        )
        cacheDiagnostics[key] = diagnostic
        AppDiagnostics.imageCacheResult(diagnostic)
    }

    private func registerConsumer(for key: LoadKey) -> UUID {
        let consumer = UUID()
        loadingConsumers[key, default: [:]][consumer] = false
        return consumer
    }

    private func releaseConsumer(_ consumer: UUID, for key: LoadKey) {
        guard var consumers = loadingConsumers[key] else { return }
        consumers.removeValue(forKey: consumer)
        loadingConsumers[key] = consumers.isEmpty ? nil : consumers
        cancelTaskIfNoConsumers(for: key)
    }

    private func cancelTaskIfNoConsumers(for key: LoadKey) {
        if let consumers = loadingConsumers[key],
           !consumers.isEmpty,
           !consumers.values.allSatisfy({ $0 })
        {
            return
        }
        loadingTasks.removeValue(forKey: key)?.cancel()
        loadingGenerations[key] = nil
    }

    private func cancelLoading(for key: LoadKey) {
        guard var consumers = loadingConsumers[key],
              let consumer = consumers.keys.first(where: { consumers[$0] == false })
        else {
            loadingTasks.removeValue(forKey: key)?.cancel()
            loadingGenerations[key] = nil
            loadingConsumers[key] = nil
            return
        }
        consumers[consumer] = true
        loadingConsumers[key] = consumers
        cancelTaskIfNoConsumers(for: key)
    }

    private static func decodedCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private static func decode(
        data: Data,
        targetPixelWidth: Int?,
        maximumDecodedImageBytes: Int
    ) -> UIImage? {
        guard let targetPixelWidth,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return UIImage(data: data) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = Self.pixelDimension(properties[kCGImagePropertyPixelWidth]),
              let sourceHeight = Self.pixelDimension(properties[kCGImagePropertyPixelHeight]),
              sourceWidth > 0,
              sourceHeight > 0
        else { return UIImage(data: data) }

        let requestedWidth = min(CGFloat(targetPixelWidth), sourceWidth)
        let aspectRatio = sourceHeight / sourceWidth
        let budgetWidth = sqrt(CGFloat(maximumDecodedImageBytes) / max(4 * aspectRatio, 1))
        let decodedWidth = max(1, min(requestedWidth, budgetWidth))
        let decodedHeight = decodedWidth * aspectRatio
        let maximumPixelSize = max(decodedWidth, decodedHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ceil(maximumPixelSize)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: image)
    }

    private static func pixelDimension(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let value = value as? CGFloat { return value }
        return nil
    }

    private nonisolated static let imageURLCache = URLCache(
        memoryCapacity: 32 * 1_024 * 1_024,
        diskCapacity: 256 * 1_024 * 1_024,
        diskPath: "PicaHub.ImagePipeline"
    )

    private nonisolated static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = imageURLCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private nonisolated static let liveCachedResponseLookup: @Sendable (URLRequest) -> CachedURLResponse? = { request in
        imageURLCache.cachedResponse(for: request)
    }

    private nonisolated static let liveLoader: Loader = { request in
        let (data, response) = try await imageSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, response)
    }
}

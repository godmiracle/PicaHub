import Foundation
import Observation
import UIKit

@MainActor
protocol ReaderImageLoading: AnyObject {
    func load(_ url: URL) async throws -> UIImage
    func load(_ url: URL, targetPixelWidth: Int) async throws -> UIImage
    func retry(_ url: URL) async throws -> UIImage
    func retry(_ url: URL, targetPixelWidth: Int) async throws -> UIImage
    func cancelLoading(for url: URL)
    func cancelLoading(for url: URL, targetPixelWidth: Int)
    func removeDecodedImages()
    func cacheSource(for url: URL, targetPixelWidth: Int?) -> ImageCacheSource?
}

extension ImagePipeline: ReaderImageLoading {}

extension ReaderImageLoading {
    func load(_ url: URL, targetPixelWidth: Int) async throws -> UIImage {
        try await load(url)
    }

    func retry(_ url: URL, targetPixelWidth: Int) async throws -> UIImage {
        try await retry(url)
    }

    func cancelLoading(for url: URL, targetPixelWidth: Int) {
        cancelLoading(for: url)
    }

    func cacheSource(for url: URL, targetPixelWidth: Int?) -> ImageCacheSource? {
        nil
    }
}

@MainActor
@Observable
final class ReaderImageModel {
    enum State {
        case idle
        case loading
        case loaded(UIImage)
        case failed(message: String)
    }

    private(set) var visibleIndex = 0
    private(set) var states: [State]
    private(set) var aspectRatios: [CGFloat?]
    private(set) var cacheDiagnostics: [Int: ImageCacheDiagnostic] = [:]

    @ObservationIgnored private let urls: [URL?]
    @ObservationIgnored private let loader: any ReaderImageLoading
    @ObservationIgnored private let lookAheadCount: Int
    @ObservationIgnored private let residentBehindCount: Int
    @ObservationIgnored private let residentAheadCount: Int
    @ObservationIgnored private let maximumConcurrentLoads: Int
    @ObservationIgnored private let targetPixelWidth: Int
    @ObservationIgnored private var loadingTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var loadGenerations: [Int: Int] = [:]
    @ObservationIgnored private var completedLoadIndices = Set<Int>()
    @ObservationIgnored private var nextLoadGeneration = 0

    init(
        urls: [URL?],
        loader: any ReaderImageLoading,
        lookAheadCount: Int = 2,
        residentBehindCount: Int = 2,
        residentAheadCount: Int = 2,
        maximumConcurrentLoads: Int = 3,
        targetPixelWidth: Int = 0
    ) {
        self.urls = urls
        self.loader = loader
        self.lookAheadCount = max(0, lookAheadCount)
        self.residentBehindCount = max(0, residentBehindCount)
        self.residentAheadCount = max(0, residentAheadCount)
        self.maximumConcurrentLoads = max(1, maximumConcurrentLoads)
        self.targetPixelWidth = max(0, targetPixelWidth)
        states = urls.map { url in
            url == nil ? .failed(message: "图片地址无效") : .idle
        }
        aspectRatios = Array(repeating: nil, count: urls.count)
    }

    func state(at index: Int) -> State {
        guard states.indices.contains(index) else {
            return .failed(message: "图片不存在")
        }
        return states[index]
    }

    func aspectRatio(at index: Int) -> CGFloat? {
        guard aspectRatios.indices.contains(index) else { return nil }
        return aspectRatios[index]
    }

    var residentImageCount: Int {
        states.reduce(into: 0) { count, state in
            if case .loaded = state { count += 1 }
        }
    }

    func cacheSource(at index: Int) -> ImageCacheSource? {
        cacheDiagnostics[index]?.source
    }

    func updateVisibleIndex(_ index: Int) {
        guard urls.indices.contains(index) else { return }
        visibleIndex = index
        if case .loaded = states[index] {
            recordDiagnostic(source: .resident, at: index)
        }
        cancelObsoleteLoads()
        evictImagesOutsideResidentWindow()
        prioritizeVisibleLoad()
        scheduleLoads()
    }

    func retry(_ index: Int) {
        guard urls.indices.contains(index), urls[index] != nil else { return }
        guard case .failed = states[index] else { return }
        cancelLoad(at: index)
        states[index] = .idle
        startLoad(at: index, isRetry: true)
    }

    func cancelAll() {
        for index in Array(loadingTasks.keys) {
            cancelLoad(at: index)
        }
    }

    func handleMemoryPressure() {
        cancelPrefetches()
        evictDecodedImages(keeping: [visibleIndex])
        loader.removeDecodedImages()
    }

    func handleBackgrounding() {
        cancelPrefetches()
        evictDecodedImages(keeping: [visibleIndex])
        loader.removeDecodedImages()
    }

    func handleForegrounding() {
        prioritizeVisibleLoad()
        scheduleLoads()
    }

    private var desiredIndices: Range<Int> {
        let upperBound = min(urls.count, visibleIndex + lookAheadCount + 1)
        return visibleIndex..<upperBound
    }

    private var residentIndices: Range<Int> {
        let lowerBound = max(0, visibleIndex - residentBehindCount)
        let upperBound = min(urls.count, visibleIndex + residentAheadCount + 1)
        return lowerBound..<upperBound
    }

    private func cancelObsoleteLoads() {
        let desired = Set(desiredIndices)
        for index in loadingTasks.keys where !desired.contains(index) {
            cancelLoad(at: index)
        }
    }

    private func cancelPrefetches() {
        for index in Array(loadingTasks.keys) where index != visibleIndex {
            cancelLoad(at: index)
        }
    }

    private func evictImagesOutsideResidentWindow() {
        evictDecodedImages(keeping: Set(residentIndices))
    }

    private func evictDecodedImages(keeping retainedIndices: Set<Int>) {
        for index in states.indices where !retainedIndices.contains(index) {
            if case .loaded = states[index] {
                states[index] = .idle
            }
        }
    }

    private func prioritizeVisibleLoad() {
        guard needsLoad(at: visibleIndex), loadingTasks.count >= maximumConcurrentLoads else {
            return
        }
        if let furthestPrefetch = loadingTasks.keys
            .filter({ $0 != visibleIndex })
            .max()
        {
            cancelLoad(at: furthestPrefetch)
        }
    }

    private func scheduleLoads() {
        for index in desiredIndices where loadingTasks.count < maximumConcurrentLoads {
            guard needsLoad(at: index) else { continue }
            startLoad(at: index, isRetry: false)
        }
    }

    private func needsLoad(at index: Int) -> Bool {
        guard urls.indices.contains(index), urls[index] != nil, loadingTasks[index] == nil else {
            return false
        }
        if case .idle = states[index] {
            return residentIndices.contains(index) || !completedLoadIndices.contains(index)
        }
        return false
    }

    private func startLoad(at index: Int, isRetry: Bool) {
        guard let url = urls[index], loadingTasks[index] == nil else { return }
        nextLoadGeneration += 1
        let generation = nextLoadGeneration
        loadGenerations[index] = generation
        states[index] = .loading
        loadingTasks[index] = Task { [weak self] in
            guard let self else { return }
            do {
                let image: UIImage
                if targetPixelWidth > 0 {
                    image = try await (isRetry
                        ? loader.retry(url, targetPixelWidth: targetPixelWidth)
                        : loader.load(url, targetPixelWidth: targetPixelWidth))
                } else {
                    image = try await (isRetry ? loader.retry(url) : loader.load(url))
                }
                try Task.checkCancellation()
                finishLoad(at: index, generation: generation, result: .success(image))
            } catch is CancellationError {
                finishCancellation(at: index, generation: generation)
            } catch {
                if Self.isCancellation(error) {
                    finishCancellation(at: index, generation: generation)
                } else {
                    finishLoad(at: index, generation: generation, result: .failure(error))
                }
            }
        }
    }

    private func finishLoad(
        at index: Int,
        generation: Int,
        result: Result<UIImage, any Error>
    ) {
        guard loadGenerations[index] == generation else { return }
        loadingTasks[index] = nil
        loadGenerations[index] = nil
        switch result {
        case let .success(image):
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            if pixelWidth > 0, pixelHeight > 0 {
                aspectRatios[index] = pixelWidth / pixelHeight
            }
            completedLoadIndices.insert(index)
            states[index] = residentIndices.contains(index) ? .loaded(image) : .idle
            if let url = urls[index] {
                let source = loader.cacheSource(
                    for: url,
                    targetPixelWidth: targetPixelWidth > 0 ? targetPixelWidth : nil
                ) ?? .network
                recordDiagnostic(source: source, at: index)
            }
        case .failure:
            completedLoadIndices.remove(index)
            states[index] = .failed(message: "图片加载失败")
        }
        scheduleLoads()
    }

    private func recordDiagnostic(source: ImageCacheSource, at index: Int) {
        guard urls.indices.contains(index), let url = urls[index] else { return }
        let diagnostic = ImageCacheDiagnostic(
            source: source,
            url: url,
            targetPixelWidth: targetPixelWidth > 0 ? targetPixelWidth : nil
        )
        cacheDiagnostics[index] = diagnostic
        AppDiagnostics.imageCacheResult(diagnostic)
    }

    private func finishCancellation(at index: Int, generation: Int) {
        guard loadGenerations[index] == generation else { return }
        loadingTasks[index] = nil
        loadGenerations[index] = nil
        if states.indices.contains(index), case .loading = states[index] {
            states[index] = .idle
        }
        scheduleLoads()
    }

    private func cancelLoad(at index: Int) {
        guard let task = loadingTasks.removeValue(forKey: index) else { return }
        loadGenerations[index] = nil
        task.cancel()
        if let url = urls[index] {
            if targetPixelWidth > 0 {
                loader.cancelLoading(for: url, targetPixelWidth: targetPixelWidth)
            } else {
                loader.cancelLoading(for: url)
            }
        }
        if case .loading = states[index] {
            states[index] = .idle
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }
}

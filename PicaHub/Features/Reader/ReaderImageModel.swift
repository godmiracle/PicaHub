import Foundation
import Observation
import UIKit

@MainActor
protocol ReaderImageLoading: AnyObject {
    func load(_ url: URL) async throws -> UIImage
    func retry(_ url: URL) async throws -> UIImage
    func cancelLoading(for url: URL)
    func removeDecodedImages()
}

extension ImagePipeline: ReaderImageLoading {}

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

    @ObservationIgnored private let urls: [URL?]
    @ObservationIgnored private let loader: any ReaderImageLoading
    @ObservationIgnored private let lookAheadCount: Int
    @ObservationIgnored private let maximumConcurrentLoads: Int
    @ObservationIgnored private var loadingTasks: [Int: Task<Void, Never>] = [:]

    init(
        urls: [URL?],
        loader: any ReaderImageLoading,
        lookAheadCount: Int = 2,
        maximumConcurrentLoads: Int = 3
    ) {
        self.urls = urls
        self.loader = loader
        self.lookAheadCount = max(0, lookAheadCount)
        self.maximumConcurrentLoads = max(1, maximumConcurrentLoads)
        states = urls.map { url in
            url == nil ? .failed(message: "图片地址无效") : .idle
        }
    }

    func state(at index: Int) -> State {
        guard states.indices.contains(index) else {
            return .failed(message: "图片不存在")
        }
        return states[index]
    }

    func updateVisibleIndex(_ index: Int) {
        guard urls.indices.contains(index) else { return }
        visibleIndex = index
        cancelObsoleteLoads()
        prioritizeVisibleLoad()
        scheduleLoads()
    }

    func retry(_ index: Int) {
        guard urls.indices.contains(index), urls[index] != nil else { return }
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
        loader.removeDecodedImages()
    }

    private var desiredIndices: Range<Int> {
        let upperBound = min(urls.count, visibleIndex + lookAheadCount + 1)
        return visibleIndex..<upperBound
    }

    private func cancelObsoleteLoads() {
        let desired = Set(desiredIndices)
        for index in loadingTasks.keys where !desired.contains(index) {
            cancelLoad(at: index)
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
        if case .idle = states[index] { return true }
        return false
    }

    private func startLoad(at index: Int, isRetry: Bool) {
        guard let url = urls[index], loadingTasks[index] == nil else { return }
        states[index] = .loading
        loadingTasks[index] = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await (isRetry ? loader.retry(url) : loader.load(url))
                try Task.checkCancellation()
                finishLoad(at: index, result: .success(image))
            } catch is CancellationError {
                finishCancellation(at: index)
            } catch {
                finishLoad(at: index, result: .failure(error))
            }
        }
    }

    private func finishLoad(at index: Int, result: Result<UIImage, any Error>) {
        loadingTasks[index] = nil
        switch result {
        case let .success(image):
            states[index] = .loaded(image)
        case .failure:
            states[index] = .failed(message: "图片加载失败")
        }
        scheduleLoads()
    }

    private func finishCancellation(at index: Int) {
        loadingTasks[index] = nil
        if states.indices.contains(index), case .loading = states[index] {
            states[index] = .idle
        }
        scheduleLoads()
    }

    private func cancelLoad(at index: Int) {
        guard let task = loadingTasks.removeValue(forKey: index) else { return }
        task.cancel()
        if let url = urls[index] {
            loader.cancelLoading(for: url)
        }
        if case .loading = states[index] {
            states[index] = .idle
        }
    }
}

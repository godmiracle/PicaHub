import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ComicCoverModel {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var state: State = .idle
    private(set) var image: UIImage?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let loader: Loader

    init(url: URL, loader: @escaping Loader = ComicCoverModel.liveLoader) {
        self.url = url
        self.loader = loader
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await load(cachePolicy: .returnCacheDataElseLoad)
    }

    func retry() async {
        guard state != .loading else { return }
        await load(cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func load(cachePolicy: URLRequest.CachePolicy) async {
        state = .loading
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy

        do {
            let (data, response) = try await loader(request)
            try Task.checkCancellation()
            guard (200...299).contains(response.statusCode), let image = UIImage(data: data) else {
                throw APIError.invalidResponse
            }
            self.image = image
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            image = nil
            state = .failed
        }
    }

    private nonisolated static let liveLoader: Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, response)
    }
}

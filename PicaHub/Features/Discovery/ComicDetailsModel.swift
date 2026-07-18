import Foundation
import Observation

enum DetailsResourceState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(message: String)
}

@MainActor
@Observable
final class ComicDetailsModel {
    let comicID: String
    private(set) var detailsState: DetailsResourceState<ComicDetails> = .idle
    private(set) var chaptersState: DetailsResourceState<[Chapter]> = .idle

    @ObservationIgnored private let repository: any ComicDetailsRepository

    init(comicID: String, repository: any ComicDetailsRepository) {
        self.comicID = comicID
        self.repository = repository
    }

    func loadIfNeeded() async {
        async let details: Void = loadDetailsIfNeeded()
        async let chapters: Void = loadChaptersIfNeeded()
        _ = await (details, chapters)
    }

    func retryDetails() async {
        detailsState = .idle
        await loadDetailsIfNeeded()
    }

    func retryChapters() async {
        chaptersState = .idle
        await loadChaptersIfNeeded()
    }

    private func loadDetailsIfNeeded() async {
        guard detailsState == .idle else { return }
        detailsState = .loading
        do {
            let details = try await repository.fetchDetails(comicID: comicID)
            try Task.checkCancellation()
            detailsState = .loaded(details)
        } catch {
            detailsState = Self.isCancellation(error)
                ? .idle
                : .failed(message: Self.message(for: error))
        }
    }

    private func loadChaptersIfNeeded() async {
        guard chaptersState == .idle else { return }
        chaptersState = .loading
        do {
            let page = try await repository.fetchChapters(comicID: comicID, page: 1)
            try Task.checkCancellation()
            chaptersState = .loaded(page.docs)
        } catch {
            chaptersState = Self.isCancellation(error)
                ? .idle
                : .failed(message: Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "加载失败，请稍后重试"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }
}

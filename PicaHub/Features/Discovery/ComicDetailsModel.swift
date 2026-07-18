import Foundation
import Observation

enum DetailsResourceState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(message: String)
}

enum FavoriteControlOperation: Equatable, Sendable {
    case idle
    case updating
    case refreshing
}

@MainActor
@Observable
final class ComicDetailsModel {
    let comicID: String
    private(set) var detailsState: DetailsResourceState<ComicDetails> = .idle
    private(set) var chaptersState: DetailsResourceState<[Chapter]> = .idle
    private(set) var confirmedFavoriteState: Bool?
    private(set) var favoriteOperation: FavoriteControlOperation = .idle
    private(set) var favoriteErrorMessage: String?

    @ObservationIgnored private let repository: any ComicDetailsRepository
    @ObservationIgnored private let favoriteRepository: any FavoriteRepository
    @ObservationIgnored private let onConfirmedFavoriteChange: @MainActor (String, Bool) -> Void

    init(
        comicID: String,
        repository: any ComicDetailsRepository,
        favoriteRepository: any FavoriteRepository,
        onConfirmedFavoriteChange: @escaping @MainActor (String, Bool) -> Void = { _, _ in }
    ) {
        self.comicID = comicID
        self.repository = repository
        self.favoriteRepository = favoriteRepository
        self.onConfirmedFavoriteChange = onConfirmedFavoriteChange
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

    func toggleFavorite() async {
        guard let confirmedFavoriteState, favoriteOperation == .idle else { return }
        favoriteOperation = .updating
        favoriteErrorMessage = nil
        defer { favoriteOperation = .idle }

        do {
            let confirmedState = try await favoriteRepository.setFavorite(
                comicID: comicID,
                isFavorite: !confirmedFavoriteState
            )
            try Task.checkCancellation()
            self.confirmedFavoriteState = confirmedState
            onConfirmedFavoriteChange(comicID, confirmedState)
        } catch {
            guard !Self.isCancellation(error) else { return }
            favoriteErrorMessage = Self.favoriteMessage(for: error)
        }
    }

    func refreshFavoriteState() async {
        guard favoriteOperation == .idle else { return }
        favoriteOperation = .refreshing
        favoriteErrorMessage = nil
        defer { favoriteOperation = .idle }

        do {
            let confirmedState = try await favoriteRepository.fetchFavoriteState(comicID: comicID)
            try Task.checkCancellation()
            self.confirmedFavoriteState = confirmedState
            onConfirmedFavoriteChange(comicID, confirmedState)
        } catch {
            guard !Self.isCancellation(error) else { return }
            favoriteErrorMessage = Self.favoriteMessage(for: error)
        }
    }

    private func loadDetailsIfNeeded() async {
        guard detailsState == .idle else { return }
        detailsState = .loading
        do {
            let details = try await repository.fetchDetails(comicID: comicID)
            try Task.checkCancellation()
            detailsState = .loaded(details)
            confirmedFavoriteState = details.isFavourite
            onConfirmedFavoriteChange(comicID, details.isFavourite)
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
            let chapters = try await repository.fetchAllChapters(comicID: comicID)
            try Task.checkCancellation()
            chaptersState = .loaded(chapters)
        } catch {
            chaptersState = Self.isCancellation(error)
                ? .idle
                : .failed(message: Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "加载失败，请稍后重试"
    }

    private static func favoriteMessage(for error: Error) -> String {
        if error as? FavoriteRepositoryError == .confirmationMismatch {
            return "无法确认收藏结果，请刷新服务端状态"
        }
        return (error as? APIError)?.userMessage ?? "收藏操作失败，请刷新服务端状态"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }
}

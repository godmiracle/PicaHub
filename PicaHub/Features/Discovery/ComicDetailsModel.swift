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
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var detailsTask: Task<ComicDetails, any Error>?
    @ObservationIgnored private var chaptersTask: Task<[Chapter], any Error>?
    @ObservationIgnored private var favoriteTask: Task<Bool, any Error>?

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
        let generation = requestGeneration
        favoriteOperation = .updating
        favoriteErrorMessage = nil
        defer {
            if generation == requestGeneration {
                favoriteOperation = .idle
                favoriteTask = nil
            }
        }

        do {
            let favoriteRepository = favoriteRepository
            let comicID = comicID
            let task = Task {
                try await favoriteRepository.setFavorite(
                    comicID: comicID,
                    isFavorite: !confirmedFavoriteState
                )
            }
            favoriteTask = task
            let confirmedState = try await task.value
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            self.confirmedFavoriteState = confirmedState
            onConfirmedFavoriteChange(comicID, confirmedState)
        } catch {
            guard generation == requestGeneration else { return }
            guard !Self.isCancellation(error) else { return }
            favoriteErrorMessage = Self.favoriteMessage(for: error)
        }
    }

    func refreshFavoriteState() async {
        guard favoriteOperation == .idle else { return }
        let generation = requestGeneration
        favoriteOperation = .refreshing
        favoriteErrorMessage = nil
        defer {
            if generation == requestGeneration {
                favoriteOperation = .idle
                favoriteTask = nil
            }
        }

        do {
            let favoriteRepository = favoriteRepository
            let comicID = comicID
            let task = Task { try await favoriteRepository.fetchFavoriteState(comicID: comicID) }
            favoriteTask = task
            let confirmedState = try await task.value
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            self.confirmedFavoriteState = confirmedState
            onConfirmedFavoriteChange(comicID, confirmedState)
        } catch {
            guard generation == requestGeneration else { return }
            guard !Self.isCancellation(error) else { return }
            favoriteErrorMessage = Self.favoriteMessage(for: error)
        }
    }

    func cancel() {
        requestGeneration += 1
        detailsTask?.cancel()
        chaptersTask?.cancel()
        favoriteTask?.cancel()
        detailsTask = nil
        chaptersTask = nil
        favoriteTask = nil
        if detailsState == .loading { detailsState = .idle }
        if chaptersState == .loading { chaptersState = .idle }
        favoriteOperation = .idle
    }

    private func loadDetailsIfNeeded() async {
        guard detailsState == .idle else { return }
        let generation = requestGeneration
        detailsState = .loading
        do {
            let repository = repository
            let comicID = comicID
            let task = Task { try await repository.fetchDetails(comicID: comicID) }
            detailsTask = task
            let details = try await task.value
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            detailsState = .loaded(details)
            confirmedFavoriteState = details.isFavourite
            onConfirmedFavoriteChange(comicID, details.isFavourite)
        } catch {
            guard generation == requestGeneration else { return }
            detailsState = Self.isCancellation(error)
                ? .idle
                : .failed(message: Self.message(for: error))
        }
        if generation == requestGeneration { detailsTask = nil }
    }

    private func loadChaptersIfNeeded() async {
        guard chaptersState == .idle else { return }
        let generation = requestGeneration
        chaptersState = .loading
        do {
            let repository = repository
            let comicID = comicID
            let task = Task { try await repository.fetchAllChapters(comicID: comicID) }
            chaptersTask = task
            let chapters = try await task.value
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            chaptersState = .loaded(chapters)
        } catch {
            guard generation == requestGeneration else { return }
            chaptersState = Self.isCancellation(error)
                ? .idle
                : .failed(message: Self.message(for: error))
        }
        if generation == requestGeneration { chaptersTask = nil }
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

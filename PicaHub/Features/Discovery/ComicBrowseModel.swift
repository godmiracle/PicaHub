import Foundation
import Observation

@MainActor
@Observable
final class ComicBrowseModel {
    struct Content: Equatable {
        var comics: [ComicSummary]
        var currentPage: Int
        var totalPages: Int
        var isLoadingNextPage = false
        var isRefreshing = false
        var nextPageErrorMessage: String?
    }

    enum State: Equatable {
        case idle
        case loading
        case content(Content)
        case empty
        case failed(message: String)
    }

    let category: String
    private(set) var sort: ComicSort
    private(set) var state: State = .idle
    private(set) var refreshErrorMessage: String?

    @ObservationIgnored private let repository: any ComicRepository
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var isLoadingNextPage = false

    init(
        category: String,
        sort: ComicSort = .newest,
        repository: any ComicRepository
    ) {
        self.category = category
        self.sort = sort
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await loadFirstPage(retaining: nil, generation: requestGeneration)
    }

    func retry() async {
        requestGeneration += 1
        await loadFirstPage(retaining: nil, generation: requestGeneration)
    }

    func changeSort(to newSort: ComicSort) async {
        guard newSort != sort else { return }
        sort = newSort
        requestGeneration += 1
        isLoadingNextPage = false
        await loadFirstPage(retaining: nil, generation: requestGeneration)
    }

    func refresh() async {
        let existing: Content?
        if case let .content(content) = state {
            existing = content
        } else {
            existing = nil
        }
        requestGeneration += 1
        isLoadingNextPage = false
        await loadFirstPage(retaining: existing, generation: requestGeneration)
    }

    func loadNextPageIfNeeded(after comicID: String) async {
        guard case let .content(content) = state, content.comics.last?.id == comicID else { return }
        await loadNextPage()
    }

    func retryNextPage() async {
        await loadNextPage()
    }

    func dismissRefreshError() {
        refreshErrorMessage = nil
    }

    private func loadFirstPage(retaining existing: Content?, generation: Int) async {
        refreshErrorMessage = nil
        if var existing {
            existing.isRefreshing = true
            existing.nextPageErrorMessage = nil
            state = .content(existing)
        } else {
            state = .loading
        }

        do {
            let page = try await repository.fetchComics(category: category, sort: sort, page: 1)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            let comics = Self.deduplicated(page.docs)
            if comics.isEmpty {
                state = .empty
            } else {
                state = .content(
                    Content(
                        comics: comics,
                        currentPage: 1,
                        totalPages: max(1, page.pages)
                    )
                )
            }
        } catch {
            guard generation == requestGeneration else { return }
            let message = Self.message(for: error)
            if var existing {
                existing.isRefreshing = false
                state = .content(existing)
                refreshErrorMessage = message
            } else if !Self.isCancellation(error) {
                state = .failed(message: message)
            }
        }
    }

    private func loadNextPage() async {
        guard !isLoadingNextPage, case var .content(content) = state else { return }
        guard content.currentPage < content.totalPages else { return }

        isLoadingNextPage = true
        content.isLoadingNextPage = true
        content.nextPageErrorMessage = nil
        state = .content(content)
        let nextPage = content.currentPage + 1
        let generation = requestGeneration
        defer { isLoadingNextPage = false }

        do {
            let page = try await repository.fetchComics(category: category, sort: sort, page: nextPage)
            try Task.checkCancellation()
            guard generation == requestGeneration, case var .content(current) = state else { return }
            current.comics = Self.deduplicated(current.comics + page.docs)
            current.currentPage = nextPage
            current.totalPages = max(nextPage, page.pages)
            current.isLoadingNextPage = false
            state = .content(current)
        } catch {
            guard generation == requestGeneration, case var .content(current) = state else { return }
            current.isLoadingNextPage = false
            if !Self.isCancellation(error) {
                current.nextPageErrorMessage = Self.message(for: error)
            }
            state = .content(current)
        }
    }

    private static func deduplicated(_ comics: [ComicSummary]) -> [ComicSummary] {
        var seen = Set<String>()
        return comics.filter { seen.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "漫画加载失败，请稍后重试"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }
}

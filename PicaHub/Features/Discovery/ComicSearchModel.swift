import Foundation
import Observation

@MainActor
@Observable
final class ComicSearchModel {
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
        case loading(keyword: String)
        case content(Content)
        case noResults(keyword: String)
        case failed(keyword: String, message: String)
    }

    private(set) var state: State = .idle
    private(set) var keyword: String?
    private(set) var validationMessage: String?
    private(set) var refreshErrorMessage: String?

    @ObservationIgnored private let repository: any ComicRepository
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var isLoadingNextPage = false
    @ObservationIgnored private var activeRequest: Task<Page<ComicSummary>, any Error>?

    init(repository: any ComicRepository) {
        self.repository = repository
    }

    func search(_ rawKeyword: String) async {
        let normalized = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRequest?.cancel()
        requestGeneration += 1
        isLoadingNextPage = false

        guard !normalized.isEmpty else {
            keyword = nil
            validationMessage = "请输入搜索关键词"
            refreshErrorMessage = nil
            state = .idle
            return
        }

        keyword = normalized
        validationMessage = nil
        await loadFirstPage(keyword: normalized, retaining: nil, generation: requestGeneration)
    }

    func retry() async {
        guard let keyword else { return }
        requestGeneration += 1
        await loadFirstPage(keyword: keyword, retaining: nil, generation: requestGeneration)
    }

    func refresh() async {
        guard let keyword else { return }
        let existing: Content?
        if case let .content(content) = state {
            existing = content
        } else {
            existing = nil
        }
        requestGeneration += 1
        isLoadingNextPage = false
        await loadFirstPage(keyword: keyword, retaining: existing, generation: requestGeneration)
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

    func cancel() {
        requestGeneration += 1
        activeRequest?.cancel()
        activeRequest = nil
        isLoadingNextPage = false
    }

    private func loadFirstPage(
        keyword: String,
        retaining existing: Content?,
        generation: Int
    ) async {
        refreshErrorMessage = nil
        if var existing {
            existing.isRefreshing = true
            existing.nextPageErrorMessage = nil
            state = .content(existing)
        } else {
            state = .loading(keyword: keyword)
        }

        do {
            let page = try await request(keyword: keyword, page: 1)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            let comics = Self.deduplicated(page.docs)
            if comics.isEmpty {
                state = .noResults(keyword: keyword)
            } else {
                state = .content(
                    Content(comics: comics, currentPage: 1, totalPages: max(1, page.pages))
                )
            }
        } catch {
            guard generation == requestGeneration else { return }
            if var existing {
                existing.isRefreshing = false
                state = .content(existing)
                if !Self.isCancellation(error) {
                    refreshErrorMessage = Self.message(for: error)
                }
            } else if !Self.isCancellation(error) {
                state = .failed(keyword: keyword, message: Self.message(for: error))
            }
        }
    }

    private func loadNextPage() async {
        guard let keyword, !isLoadingNextPage, case var .content(content) = state else { return }
        guard content.currentPage < content.totalPages else { return }

        isLoadingNextPage = true
        content.isLoadingNextPage = true
        content.nextPageErrorMessage = nil
        state = .content(content)
        let nextPage = content.currentPage + 1
        let generation = requestGeneration
        defer { isLoadingNextPage = false }

        do {
            let page = try await request(keyword: keyword, page: nextPage)
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

    private func request(keyword: String, page: Int) async throws -> Page<ComicSummary> {
        activeRequest?.cancel()
        let repository = repository
        let task = Task {
            try await repository.searchComics(keyword: keyword, page: page)
        }
        activeRequest = task
        return try await task.value
    }

    private static func deduplicated(_ comics: [ComicSummary]) -> [ComicSummary] {
        var seen = Set<String>()
        return comics.filter { seen.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "搜索失败，请稍后重试"
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }
}

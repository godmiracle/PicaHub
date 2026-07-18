import Foundation
import Observation

@MainActor
@Observable
final class CategoryModel {
    enum State: Equatable {
        case idle
        case loading
        case content(categories: [ComicCategory], isRefreshing: Bool)
        case empty
        case failed(message: String)
    }

    private(set) var state: State = .idle
    private(set) var refreshErrorMessage: String?

    @ObservationIgnored private let repository: any CategoryRepository
    @ObservationIgnored private var isRequestInFlight = false

    init(repository: any CategoryRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await load(retaining: nil)
    }

    func retry() async {
        await load(retaining: nil)
    }

    func refresh() async {
        let existingCategories: [ComicCategory]?
        if case let .content(categories, _) = state {
            existingCategories = categories
        } else {
            existingCategories = nil
        }
        await load(retaining: existingCategories)
    }

    func dismissRefreshError() {
        refreshErrorMessage = nil
    }

    private func load(retaining existingCategories: [ComicCategory]?) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        refreshErrorMessage = nil
        if let existingCategories {
            state = .content(categories: existingCategories, isRefreshing: true)
        } else {
            state = .loading
        }
        defer { isRequestInFlight = false }

        do {
            let categories = try await repository.fetchCategories()
            try Task.checkCancellation()
            state = categories.isEmpty ? .empty : .content(categories: categories, isRefreshing: false)
        } catch is CancellationError {
            restoreAfterCancellation(existingCategories)
        } catch APIError.cancelled {
            restoreAfterCancellation(existingCategories)
        } catch let error as APIError {
            handleFailure(message: error.userMessage, existingCategories: existingCategories)
        } catch {
            handleFailure(message: "分类加载失败，请稍后重试", existingCategories: existingCategories)
        }
    }

    private func restoreAfterCancellation(_ existingCategories: [ComicCategory]?) {
        if let existingCategories {
            state = .content(categories: existingCategories, isRefreshing: false)
        } else {
            state = .idle
        }
    }

    private func handleFailure(message: String, existingCategories: [ComicCategory]?) {
        if let existingCategories {
            state = .content(categories: existingCategories, isRefreshing: false)
            refreshErrorMessage = message
        } else {
            state = .failed(message: message)
        }
    }
}

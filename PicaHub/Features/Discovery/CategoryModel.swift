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
        _ = await load(retaining: nil, policy: .useCache)
    }

    func retry() async {
        _ = await load(retaining: nil, policy: .useCache)
    }

    func refresh() async -> Bool {
        let existingCategories: [ComicCategory]?
        if case let .content(categories, _) = state {
            existingCategories = categories
        } else {
            existingCategories = nil
        }
        return await load(retaining: existingCategories, policy: .reloadIgnoringCache)
    }

    func dismissRefreshError() {
        refreshErrorMessage = nil
    }

    private func load(
        retaining existingCategories: [ComicCategory]?,
        policy: CategoryFetchPolicy
    ) async -> Bool {
        guard !isRequestInFlight else { return false }
        isRequestInFlight = true
        refreshErrorMessage = nil
        if let existingCategories {
            state = .content(categories: existingCategories, isRefreshing: true)
        } else {
            state = .loading
        }
        defer { isRequestInFlight = false }

        do {
            let categories = try await repository.fetchCategories(policy: policy)
            try Task.checkCancellation()
            state = categories.isEmpty ? .empty : .content(categories: categories, isRefreshing: false)
            return true
        } catch is CancellationError {
            restoreAfterCancellation(existingCategories)
            return false
        } catch APIError.cancelled {
            restoreAfterCancellation(existingCategories)
            return false
        } catch let error as APIError {
            handleFailure(message: error.userMessage, existingCategories: existingCategories)
            return false
        } catch {
            handleFailure(message: "分类加载失败，请稍后重试", existingCategories: existingCategories)
            return false
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

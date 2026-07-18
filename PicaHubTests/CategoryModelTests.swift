import Testing
@testable import PicaHub

private actor CategoryRepositoryStub: CategoryRepository {
    private var results: [Result<[ComicCategory], APIError>]
    private(set) var callCount = 0

    init(results: [Result<[ComicCategory], APIError>]) {
        self.results = results
    }

    func fetchCategories() async throws -> [ComicCategory] {
        callCount += 1
        guard !results.isEmpty else { throw APIError.invalidResponse }
        return try results.removeFirst().get()
    }
}

private actor RefreshCategoryRepository: CategoryRepository {
    private let initialCategories: [ComicCategory]
    private var continuation: CheckedContinuation<[ComicCategory], any Error>?
    private(set) var callCount = 0

    init(initialCategories: [ComicCategory]) {
        self.initialCategories = initialCategories
    }

    func fetchCategories() async throws -> [ComicCategory] {
        callCount += 1
        if callCount == 1 { return initialCategories }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishRefresh(with result: Result<[ComicCategory], APIError>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}

@MainActor
struct CategoryModelTests {
    @Test func initialLoadPresentsCategories() async {
        let categories = [Self.category(id: "one", title: "分类一")]
        let repository = CategoryRepositoryStub(results: [.success(categories)])
        let model = CategoryModel(repository: repository)

        await model.loadIfNeeded()

        #expect(model.state == .content(categories: categories, isRefreshing: false))
        #expect(await repository.callCount == 1)
    }

    @Test func emptyResponsePresentsEmptyState() async {
        let repository = CategoryRepositoryStub(results: [.success([])])
        let model = CategoryModel(repository: repository)

        await model.loadIfNeeded()

        #expect(model.state == .empty)
    }

    @Test func failureCanRetrySuccessfully() async {
        let categories = [Self.category(id: "retry", title: "重试成功")]
        let repository = CategoryRepositoryStub(
            results: [.failure(.timedOut), .success(categories)]
        )
        let model = CategoryModel(repository: repository)

        await model.loadIfNeeded()
        #expect(model.state == .failed(message: APIError.timedOut.userMessage))

        await model.retry()
        #expect(model.state == .content(categories: categories, isRefreshing: false))
        #expect(await repository.callCount == 2)
    }

    @Test func refreshKeepsExistingContentUntilReplacementSucceeds() async {
        let original = [Self.category(id: "old", title: "旧分类")]
        let replacement = [Self.category(id: "new", title: "新分类")]
        let repository = RefreshCategoryRepository(initialCategories: original)
        let model = CategoryModel(repository: repository)
        await model.loadIfNeeded()

        let refresh = Task { await model.refresh() }
        while await repository.callCount < 2 { await Task.yield() }

        #expect(model.state == .content(categories: original, isRefreshing: true))
        await repository.finishRefresh(with: .success(replacement))
        await refresh.value
        #expect(model.state == .content(categories: replacement, isRefreshing: false))
    }

    @Test func refreshFailureKeepsExistingContentAndExposesMessage() async {
        let original = [Self.category(id: "old", title: "旧分类")]
        let repository = RefreshCategoryRepository(initialCategories: original)
        let model = CategoryModel(repository: repository)
        await model.loadIfNeeded()

        let refresh = Task { await model.refresh() }
        while await repository.callCount < 2 { await Task.yield() }
        await repository.finishRefresh(with: .failure(.connection("offline")))
        await refresh.value

        #expect(model.state == .content(categories: original, isRefreshing: false))
        #expect(model.refreshErrorMessage == APIError.connection("offline").userMessage)
    }

    private static func category(id: String, title: String) -> ComicCategory {
        ComicCategory(
            remoteID: id,
            title: title,
            description: nil,
            thumb: nil,
            isWeb: false,
            active: true
        )
    }
}

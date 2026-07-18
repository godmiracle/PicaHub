import Testing
@testable import PicaHub

private struct FavoriteListRequest: Sendable, Equatable {
    let sort: ComicSort
    let page: Int
}

private actor FavoriteListRepositoryStub: FavoriteRepository {
    private var results: [Result<Page<ComicSummary>, APIError>]
    private(set) var requests: [FavoriteListRequest] = []

    init(results: [Result<Page<ComicSummary>, APIError>]) {
        self.results = results
    }

    func fetchFavoriteState(comicID: String) async throws -> Bool {
        throw APIError.invalidRequest
    }

    func setFavorite(comicID: String, isFavorite: Bool) async throws -> Bool {
        throw APIError.invalidRequest
    }

    func fetchFavorites(sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        requests.append(FavoriteListRequest(sort: sort, page: page))
        guard !results.isEmpty else { throw APIError.invalidResponse }
        return try results.removeFirst().get()
    }
}

@MainActor
struct FavoritesModelTests {
    @Test func initialPageUsesDefaultSort() async {
        let page = Self.page(number: 1, pages: 2, comics: [Self.comic("one")])
        let repository = FavoriteListRepositoryStub(results: [.success(page)])
        let model = FavoritesModel(repository: repository)

        await model.loadIfNeeded()

        #expect(model.state == .content(.init(comics: page.docs, currentPage: 1, totalPages: 2)))
        #expect(await repository.requests == [FavoriteListRequest(sort: .newest, page: 1)])
    }

    @Test func nextPageAppendsUniqueComicsAndStopsAtBoundary() async {
        let duplicate = Self.comic("duplicate")
        let repository = FavoriteListRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 2, comics: [Self.comic("one"), duplicate])),
                .success(Self.page(number: 2, pages: 2, comics: [duplicate, Self.comic("two")])),
            ]
        )
        let model = FavoritesModel(repository: repository)
        await model.loadIfNeeded()

        await model.loadNextPageIfNeeded(after: duplicate.id)
        await model.loadNextPageIfNeeded(after: "two")

        guard case let .content(content) = model.state else {
            Issue.record("Expected favorite content")
            return
        }
        #expect(content.comics.map(\.id) == ["one", "duplicate", "two"])
        #expect(content.currentPage == 2)
        #expect(await repository.requests.count == 2)
    }

    @Test func sortChangeReloadsFirstPage() async {
        let repository = FavoriteListRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 1, comics: [Self.comic("newest")])),
                .success(Self.page(number: 1, pages: 1, comics: [Self.comic("oldest")])),
            ]
        )
        let model = FavoritesModel(repository: repository)
        await model.loadIfNeeded()

        await model.changeSort(to: .oldest)

        #expect(model.sort == .oldest)
        #expect(await repository.requests.last == FavoriteListRequest(sort: .oldest, page: 1))
        guard case let .content(content) = model.state else {
            Issue.record("Expected favorite content")
            return
        }
        #expect(content.comics.map(\.id) == ["oldest"])
    }

    @Test func refreshFailureRetainsExistingContent() async {
        let existing = Self.comic("existing")
        let repository = FavoriteListRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 1, comics: [existing])),
                .failure(.timedOut),
            ]
        )
        let model = FavoritesModel(repository: repository)
        await model.loadIfNeeded()

        await model.refresh()

        guard case let .content(content) = model.state else {
            Issue.record("Expected retained favorite content")
            return
        }
        #expect(content.comics == [existing])
        #expect(!content.isRefreshing)
        #expect(model.refreshErrorMessage == APIError.timedOut.userMessage)
    }

    @Test func refreshAdoptsExternalFavoriteChangesFromServer() async {
        let removedExternally = Self.comic("removed-externally")
        let retained = Self.comic("retained")
        let addedExternally = Self.comic("added-externally")
        let repository = FavoriteListRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 1, comics: [removedExternally, retained])),
                .success(Self.page(number: 1, pages: 1, comics: [retained, addedExternally])),
            ]
        )
        let model = FavoritesModel(repository: repository)
        await model.loadIfNeeded()

        await model.refresh()

        guard case let .content(content) = model.state else {
            Issue.record("Expected refreshed favorite content")
            return
        }
        #expect(content.comics == [retained, addedExternally])
        #expect(model.refreshErrorMessage == nil)
        #expect(await repository.requests == [
            FavoriteListRequest(sort: .newest, page: 1),
            FavoriteListRequest(sort: .newest, page: 1),
        ])
    }

    @Test func emptyAndInitialFailureUseDedicatedStates() async {
        let emptyRepository = FavoriteListRepositoryStub(
            results: [.success(Self.page(number: 1, pages: 0, comics: []))]
        )
        let emptyModel = FavoritesModel(repository: emptyRepository)
        await emptyModel.loadIfNeeded()
        #expect(emptyModel.state == .empty)

        let failedRepository = FavoriteListRepositoryStub(results: [.failure(.timedOut)])
        let failedModel = FavoritesModel(repository: failedRepository)
        await failedModel.loadIfNeeded()
        #expect(failedModel.state == .failed(message: APIError.timedOut.userMessage))
    }

    @Test func confirmedUnfavoriteRemovesComicWithoutRestart() async {
        let first = Self.comic("first")
        let removed = Self.comic("removed")
        let repository = FavoriteListRepositoryStub(
            results: [.success(Self.page(number: 1, pages: 1, comics: [first, removed]))]
        )
        let model = FavoritesModel(repository: repository)
        await model.loadIfNeeded()

        await model.applyConfirmedFavoriteChange(comicID: removed.id, isFavorite: false)

        guard case let .content(content) = model.state else {
            Issue.record("Expected retained favorite content")
            return
        }
        #expect(content.comics == [first])
        #expect(await repository.requests.count == 1)
    }

    private static func page(
        number: Int,
        pages: Int,
        comics: [ComicSummary]
    ) -> Page<ComicSummary> {
        Page(docs: comics, limit: 20, page: number, pages: pages, total: comics.count)
    }

    private static func comic(_ id: String) -> ComicSummary {
        ComicSummary(
            id: id,
            title: "漫画 \(id)",
            author: nil,
            pagesCount: nil,
            epsCount: nil,
            finished: nil,
            categories: nil,
            tags: nil,
            thumb: ImageReference(
                fileServer: "https://example.com",
                path: "\(id).jpg",
                originalName: nil
            ),
            likesCount: nil,
            totalViews: nil
        )
    }
}

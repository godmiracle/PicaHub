import Testing
@testable import PicaHub

private actor ComicDetailsRepositoryStub: ComicDetailsRepository {
    private var detailResults: [Result<ComicDetails, APIError>]
    private var chapterResults: [Result<[Chapter], APIError>]
    private(set) var detailCalls = 0
    private(set) var chapterCalls = 0

    init(
        detailResults: [Result<ComicDetails, APIError>],
        chapterResults: [Result<[Chapter], APIError>]
    ) {
        self.detailResults = detailResults
        self.chapterResults = chapterResults
    }

    func fetchDetails(comicID: String) async throws -> ComicDetails {
        detailCalls += 1
        guard !detailResults.isEmpty else { throw APIError.invalidResponse }
        return try detailResults.removeFirst().get()
    }

    func fetchAllChapters(comicID: String) async throws -> [Chapter] {
        chapterCalls += 1
        guard !chapterResults.isEmpty else { throw APIError.invalidResponse }
        return try chapterResults.removeFirst().get()
    }
}

private actor FavoriteRepositoryStub: FavoriteRepository {
    private var fetchResults: [Result<Bool, APIError>]
    private var setResults: [Result<Bool, APIError>]
    private let setDelay: Duration?
    private(set) var fetchCalls = 0
    private(set) var setCalls = 0

    init(
        fetchResults: [Result<Bool, APIError>] = [],
        setResults: [Result<Bool, APIError>] = [],
        setDelay: Duration? = nil
    ) {
        self.fetchResults = fetchResults
        self.setResults = setResults
        self.setDelay = setDelay
    }

    func fetchFavoriteState(comicID: String) async throws -> Bool {
        fetchCalls += 1
        guard !fetchResults.isEmpty else { throw APIError.invalidResponse }
        return try fetchResults.removeFirst().get()
    }

    func setFavorite(comicID: String, isFavorite: Bool) async throws -> Bool {
        setCalls += 1
        if let setDelay { try await Task.sleep(for: setDelay) }
        guard !setResults.isEmpty else { throw APIError.invalidResponse }
        return try setResults.removeFirst().get()
    }

    func fetchFavorites(sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        Page(docs: [], limit: 20, page: page, pages: 1, total: 0)
    }
}

@MainActor
struct ComicDetailsModelTests {
    @Test func detailsRemainVisibleWhenChaptersFail() async {
        let details = Self.details()
        let repository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.failure(.timedOut)]
        )
        let model = ComicDetailsModel(
            comicID: details.id,
            repository: repository,
            favoriteRepository: FavoriteRepositoryStub()
        )

        await model.loadIfNeeded()

        #expect(model.detailsState == .loaded(details))
        #expect(model.chaptersState == .failed(message: APIError.timedOut.userMessage))
    }

    @Test func chaptersRemainVisibleWhenDetailsFail() async {
        let chapters = [Chapter(id: "one", title: "第一话", order: 1, updatedAt: nil)]
        let repository = ComicDetailsRepositoryStub(
            detailResults: [.failure(.connection("offline"))],
            chapterResults: [.success(chapters)]
        )
        let model = ComicDetailsModel(
            comicID: "comic",
            repository: repository,
            favoriteRepository: FavoriteRepositoryStub()
        )

        await model.loadIfNeeded()

        #expect(model.detailsState == .failed(message: APIError.connection("offline").userMessage))
        #expect(model.chaptersState == .loaded(chapters))
    }

    @Test func retryChaptersDoesNotReloadSuccessfulDetails() async {
        let details = Self.details()
        let chapters = [Chapter(id: "one", title: "第一话", order: 1, updatedAt: nil)]
        let repository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.failure(.timedOut), .success(chapters)]
        )
        let model = ComicDetailsModel(
            comicID: details.id,
            repository: repository,
            favoriteRepository: FavoriteRepositoryStub()
        )
        await model.loadIfNeeded()

        await model.retryChapters()

        #expect(model.detailsState == .loaded(details))
        #expect(model.chaptersState == .loaded(chapters))
        #expect(await repository.detailCalls == 1)
        #expect(await repository.chapterCalls == 2)
    }

    @Test func favoriteChangesOnlyAfterRepositoryConfirmation() async {
        let details = Self.details()
        let detailsRepository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.success([])]
        )
        let favoriteRepository = FavoriteRepositoryStub(setResults: [.success(true)])
        let model = ComicDetailsModel(
            comicID: details.id,
            repository: detailsRepository,
            favoriteRepository: favoriteRepository
        )
        await model.loadIfNeeded()

        await model.toggleFavorite()

        #expect(model.confirmedFavoriteState == true)
        #expect(model.favoriteErrorMessage == nil)
        #expect(await favoriteRepository.setCalls == 1)
    }

    @Test func ambiguousFailureKeepsConfirmedStateUntilExplicitRefresh() async {
        let details = Self.details()
        let detailsRepository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.success([])]
        )
        let favoriteRepository = FavoriteRepositoryStub(
            fetchResults: [.success(true)],
            setResults: [.failure(.timedOut)]
        )
        let model = ComicDetailsModel(
            comicID: details.id,
            repository: detailsRepository,
            favoriteRepository: favoriteRepository
        )
        await model.loadIfNeeded()

        await model.toggleFavorite()

        #expect(model.confirmedFavoriteState == false)
        #expect(model.favoriteErrorMessage == APIError.timedOut.userMessage)

        await model.refreshFavoriteState()

        #expect(model.confirmedFavoriteState == true)
        #expect(model.favoriteErrorMessage == nil)
        #expect(await favoriteRepository.setCalls == 1)
        #expect(await favoriteRepository.fetchCalls == 1)
    }

    @Test func repeatedTapStartsOnlyOneMutation() async {
        let details = Self.details()
        let detailsRepository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.success([])]
        )
        let favoriteRepository = FavoriteRepositoryStub(
            setResults: [.success(true)],
            setDelay: .milliseconds(100)
        )
        let model = ComicDetailsModel(
            comicID: details.id,
            repository: detailsRepository,
            favoriteRepository: favoriteRepository
        )
        await model.loadIfNeeded()

        async let first: Void = model.toggleFavorite()
        await Task.yield()
        async let second: Void = model.toggleFavorite()
        _ = await (first, second)

        #expect(model.confirmedFavoriteState == true)
        #expect(await favoriteRepository.setCalls == 1)
    }

    private static func details() -> ComicDetails {
        ComicDetails(
            id: "comic",
            title: "测试漫画",
            description: nil,
            author: nil,
            chineseTeam: nil,
            tags: nil,
            thumb: ImageReference(
                fileServer: "https://example.com",
                path: "cover.jpg",
                originalName: nil
            ),
            pagesCount: nil,
            epsCount: nil,
            finished: nil,
            isFavourite: false,
            isLiked: nil,
            likesCount: nil,
            viewsCount: nil,
            commentsCount: nil
        )
    }
}

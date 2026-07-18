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

@MainActor
struct ComicDetailsModelTests {
    @Test func detailsRemainVisibleWhenChaptersFail() async {
        let details = Self.details()
        let repository = ComicDetailsRepositoryStub(
            detailResults: [.success(details)],
            chapterResults: [.failure(.timedOut)]
        )
        let model = ComicDetailsModel(comicID: details.id, repository: repository)

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
        let model = ComicDetailsModel(comicID: "comic", repository: repository)

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
        let model = ComicDetailsModel(comicID: details.id, repository: repository)
        await model.loadIfNeeded()

        await model.retryChapters()

        #expect(model.detailsState == .loaded(details))
        #expect(model.chaptersState == .loaded(chapters))
        #expect(await repository.detailCalls == 1)
        #expect(await repository.chapterCalls == 2)
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

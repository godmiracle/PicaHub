import Testing
@testable import PicaHub

private struct ComicRequest: Sendable, Equatable {
    let category: String
    let sort: ComicSort
    let page: Int
}

private actor ComicRepositoryStub: ComicRepository {
    private var results: [Result<Page<ComicSummary>, APIError>]
    private(set) var requests: [ComicRequest] = []

    init(results: [Result<Page<ComicSummary>, APIError>]) {
        self.results = results
    }

    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        requests.append(ComicRequest(category: category, sort: sort, page: page))
        guard !results.isEmpty else { throw APIError.invalidResponse }
        return try results.removeFirst().get()
    }
}

private actor GatedComicRepository: ComicRepository {
    private let firstPage: Page<ComicSummary>
    private var continuation: CheckedContinuation<Page<ComicSummary>, any Error>?
    private(set) var requests: [ComicRequest] = []

    init(firstPage: Page<ComicSummary>) {
        self.firstPage = firstPage
    }

    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        requests.append(ComicRequest(category: category, sort: sort, page: page))
        if page == 1 { return firstPage }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishNextPage(_ page: Page<ComicSummary>) {
        continuation?.resume(returning: page)
        continuation = nil
    }
}

@MainActor
struct ComicBrowseModelTests {
    @Test func initialPageUsesSelectedCategoryAndDefaultSort() async {
        let firstPage = Self.page(number: 1, pages: 2, comics: [Self.comic("one")])
        let repository = ComicRepositoryStub(results: [.success(firstPage)])
        let model = ComicBrowseModel(category: "骑士", repository: repository)

        await model.loadIfNeeded()

        #expect(model.state == .content(.init(comics: firstPage.docs, currentPage: 1, totalPages: 2)))
        #expect(await repository.requests == [ComicRequest(category: "骑士", sort: .newest, page: 1)])
    }

    @Test func nextPageAppendsUniqueComicsAndStopsAtBoundary() async {
        let duplicate = Self.comic("duplicate")
        let firstPage = Self.page(number: 1, pages: 2, comics: [Self.comic("one"), duplicate])
        let secondPage = Self.page(number: 2, pages: 2, comics: [duplicate, Self.comic("two"), Self.comic("two")])
        let repository = ComicRepositoryStub(results: [.success(firstPage), .success(secondPage)])
        let model = ComicBrowseModel(category: "骑士", repository: repository)
        await model.loadIfNeeded()

        await model.loadNextPageIfNeeded(after: duplicate.id)
        await model.loadNextPageIfNeeded(after: "two")

        guard case let .content(content) = model.state else {
            Issue.record("Expected comic content")
            return
        }
        #expect(content.comics.map(\.id) == ["one", "duplicate", "two"])
        #expect(content.currentPage == 2)
        #expect(await repository.requests.count == 2)
    }

    @Test func duplicateNextPageTriggersShareOneInFlightRequest() async {
        let last = Self.comic("last")
        let repository = GatedComicRepository(
            firstPage: Self.page(number: 1, pages: 2, comics: [last])
        )
        let model = ComicBrowseModel(category: "骑士", repository: repository)
        await model.loadIfNeeded()

        let first = Task { await model.loadNextPageIfNeeded(after: last.id) }
        while await repository.requests.count < 2 { await Task.yield() }
        let duplicate = Task { await model.loadNextPageIfNeeded(after: last.id) }
        await duplicate.value
        await repository.finishNextPage(Self.page(number: 2, pages: 2, comics: [Self.comic("new")]))
        await first.value

        #expect(await repository.requests.count == 2)
    }

    @Test func sortChangeResetsToFirstPage() async {
        let repository = ComicRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 1, comics: [Self.comic("newest")])),
                .success(Self.page(number: 1, pages: 1, comics: [Self.comic("liked")])),
            ]
        )
        let model = ComicBrowseModel(category: "骑士", repository: repository)
        await model.loadIfNeeded()

        await model.changeSort(to: .mostLiked)

        guard case let .content(content) = model.state else {
            Issue.record("Expected comic content")
            return
        }
        #expect(model.sort == .mostLiked)
        #expect(content.comics.map(\.id) == ["liked"])
        #expect(await repository.requests.last == ComicRequest(category: "骑士", sort: .mostLiked, page: 1))
    }

    @Test func nextPageFailureKeepsExistingContentForRetry() async {
        let firstPage = Self.page(number: 1, pages: 2, comics: [Self.comic("one")])
        let repository = ComicRepositoryStub(results: [.success(firstPage), .failure(.timedOut)])
        let model = ComicBrowseModel(category: "骑士", repository: repository)
        await model.loadIfNeeded()

        await model.loadNextPageIfNeeded(after: "one")

        guard case let .content(content) = model.state else {
            Issue.record("Expected retained content")
            return
        }
        #expect(content.comics.map(\.id) == ["one"])
        #expect(content.currentPage == 1)
        #expect(content.nextPageErrorMessage == APIError.timedOut.userMessage)
    }

    @Test func emptyFirstPageUsesEmptyState() async {
        let repository = ComicRepositoryStub(
            results: [.success(Self.page(number: 1, pages: 0, comics: []))]
        )
        let model = ComicBrowseModel(category: "空分类", repository: repository)

        await model.loadIfNeeded()

        #expect(model.state == .empty)
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

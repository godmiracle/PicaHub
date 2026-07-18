import Testing
@testable import PicaHub

private actor SearchRepositoryStub: ComicRepository {
    private var results: [Result<Page<ComicSummary>, APIError>]
    private(set) var requests: [(keyword: String, page: Int)] = []

    init(results: [Result<Page<ComicSummary>, APIError>]) {
        self.results = results
    }

    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        throw APIError.invalidRequest
    }

    func searchComics(keyword: String, page: Int) async throws -> Page<ComicSummary> {
        requests.append((keyword, page))
        guard !results.isEmpty else { throw APIError.invalidResponse }
        return try results.removeFirst().get()
    }

    var requestCount: Int { requests.count }
    var lastKeyword: String? { requests.last?.keyword }
}

private actor SupersedingSearchRepository: ComicRepository {
    private(set) var requestedKeywords: [String] = []
    private(set) var cancelledKeywords: [String] = []

    func fetchComics(category: String, sort: ComicSort, page: Int) async throws -> Page<ComicSummary> {
        throw APIError.invalidRequest
    }

    func searchComics(keyword: String, page: Int) async throws -> Page<ComicSummary> {
        requestedKeywords.append(keyword)
        if keyword == "旧关键词" {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                cancelledKeywords.append(keyword)
                throw CancellationError()
            }
        }
        return ComicSearchModelTests.page(
            number: page,
            pages: 1,
            comics: [ComicSearchModelTests.comic(keyword)]
        )
    }
}

@MainActor
struct ComicSearchModelTests {
    @Test func emptyKeywordIsRejectedWithoutRequest() async {
        let repository = SearchRepositoryStub(results: [])
        let model = ComicSearchModel(repository: repository)

        await model.search("   \n")

        #expect(model.state == .idle)
        #expect(model.validationMessage == "请输入搜索关键词")
        #expect(await repository.requestCount == 0)
    }

    @Test func successfulSearchNormalizesKeywordAndPresentsResults() async {
        let page = Self.page(number: 1, pages: 2, comics: [Self.comic("one")])
        let repository = SearchRepositoryStub(results: [.success(page)])
        let model = ComicSearchModel(repository: repository)

        await model.search("  骑士  ")

        #expect(model.keyword == "骑士")
        #expect(model.state == .content(.init(comics: page.docs, currentPage: 1, totalPages: 2)))
        #expect(await repository.lastKeyword == "骑士")
    }

    @Test func validSearchWithNoResultsHasDedicatedState() async {
        let repository = SearchRepositoryStub(
            results: [.success(Self.page(number: 1, pages: 0, comics: []))]
        )
        let model = ComicSearchModel(repository: repository)

        await model.search("不存在")

        #expect(model.state == .noResults(keyword: "不存在"))
    }

    @Test func paginationDeduplicatesAndStopsAtReportedBoundary() async {
        let duplicate = Self.comic("duplicate")
        let repository = SearchRepositoryStub(
            results: [
                .success(Self.page(number: 1, pages: 2, comics: [Self.comic("one"), duplicate])),
                .success(Self.page(number: 2, pages: 2, comics: [duplicate, Self.comic("two")])),
            ]
        )
        let model = ComicSearchModel(repository: repository)
        await model.search("分页")

        await model.loadNextPageIfNeeded(after: duplicate.id)
        await model.loadNextPageIfNeeded(after: "two")

        guard case let .content(content) = model.state else {
            Issue.record("Expected search content")
            return
        }
        #expect(content.comics.map(\.id) == ["one", "duplicate", "two"])
        #expect(await repository.requestCount == 2)
    }

    @Test func newKeywordCancelsAndSupersedesOlderSearch() async {
        let repository = SupersedingSearchRepository()
        let model = ComicSearchModel(repository: repository)

        let oldSearch = Task { await model.search("旧关键词") }
        while await repository.requestedKeywords.isEmpty { await Task.yield() }
        await model.search("新关键词")
        await oldSearch.value

        #expect(model.keyword == "新关键词")
        guard case let .content(content) = model.state else {
            Issue.record("Expected newest search content")
            return
        }
        #expect(content.comics.map(\.id) == ["新关键词"])
        #expect(await repository.cancelledKeywords == ["旧关键词"])
    }

    nonisolated static func page(
        number: Int,
        pages: Int,
        comics: [ComicSummary]
    ) -> Page<ComicSummary> {
        Page(docs: comics, limit: 20, page: number, pages: pages, total: comics.count)
    }

    nonisolated static func comic(_ id: String) -> ComicSummary {
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

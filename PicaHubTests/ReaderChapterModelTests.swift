import Foundation
import Testing
@testable import PicaHub

private actor ControlledChapterImageRepository: ChapterImageRepository {
    private var continuations: [Int: CheckedContinuation<[ChapterImage], any Error>] = [:]
    private(set) var requestedOrders: [Int] = []

    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        requestedOrders.append(chapterOrder)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[chapterOrder] = continuation
        }
    }

    func finish(order: Int, images: [ChapterImage]) {
        continuations.removeValue(forKey: order)?.resume(returning: images)
    }
}

private struct ImmediateChapterImageRepository: ChapterImageRepository {
    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        []
    }
}

private actor RecordingChapterImageRepository: ChapterImageRepository {
    private(set) var requestedOrders: [Int] = []

    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        requestedOrders.append(chapterOrder)
        return []
    }
}

private actor SavedReaderProgressStore: ReadingProgressStore {
    private var progress: ReadingProgress?

    init(progress: ReadingProgress?) {
        self.progress = progress
    }

    func loadProgress(for comicID: String) -> ReadingProgress? {
        progress
    }

    func saveProgress(_ progress: ReadingProgress, for comicID: String) {
        self.progress = progress
    }

    func removeProgress(for comicID: String) {
        progress = nil
    }
}

private actor SequenceChapterImageRepository: ChapterImageRepository {
    enum Outcome: Sendable {
        case success([ChapterImage])
        case failure(APIError)
    }

    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        guard !outcomes.isEmpty else { return [] }
        switch outcomes.removeFirst() {
        case let .success(images): return images
        case let .failure(error): throw error
        }
    }
}

@MainActor
struct ReaderChapterModelTests {
    @Test func explicitSelectionIgnoresSavedChapterAndRequestsSelectedChapter() async {
        let selectedChapter = Chapter(
            id: "selected",
            title: "第三话",
            order: 1,
            updatedAt: nil
        )
        let savedChapter = Chapter(
            id: "saved",
            title: "第一话",
            order: 2,
            updatedAt: nil
        )
        let repository = RecordingChapterImageRepository()
        let progressStore = SavedReaderProgressStore(
            progress: ReadingProgress(chapterOrder: savedChapter.order, imageIndex: 7)
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: [savedChapter, selectedChapter],
            initialChapter: selectedChapter,
            repository: repository,
            progressStore: progressStore
        )

        model.loadCurrentChapter()
        await waitUntil { model.contentState == .empty }

        #expect(model.currentChapter == selectedChapter)
        #expect(await repository.requestedOrders == [selectedChapter.order])
    }

    @Test func validChapterWithoutImagesProducesDedicatedEmptyState() async {
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: Self.chapters,
            initialChapter: Self.chapters[0],
            repository: SequenceChapterImageRepository(outcomes: [.success([])])
        )

        model.loadCurrentChapter()
        await waitUntil { model.contentState == .empty }

        #expect(model.images.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func imageListFailureCanRetryWithoutLosingChapterMetadataOrDuplicatingImages() async {
        let chapter = Self.chapters[1]
        let expectedImages = [Self.image(id: "one"), Self.image(id: "two")]
        let repository = SequenceChapterImageRepository(
            outcomes: [.failure(.connection("offline")), .success(expectedImages)]
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: Self.chapters,
            initialChapter: chapter,
            repository: repository
        )

        model.loadCurrentChapter()
        await waitUntil {
            if case .failed = model.contentState { return true }
            return false
        }
        #expect(model.currentChapter == chapter)

        model.loadCurrentChapter()
        await waitUntil { model.contentState == .content }

        #expect(model.currentChapter == chapter)
        #expect(model.images == expectedImages)
    }

    @Test func navigationUsesNarrativeDirectionWithNewestFirstChapterList() {
        let chapters = Self.chapters
        let repository = ImmediateChapterImageRepository()
        let middle = chapters[1]
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: chapters,
            initialChapter: middle,
            repository: repository
        )

        #expect(model.previousChapter?.order == 1)
        #expect(model.nextChapter?.order == 3)
        #expect(model.goToPreviousChapter())
        #expect(model.currentChapter.order == 1)
        #expect(model.previousChapter == nil)
        #expect(!model.goToPreviousChapter())

    }

    @Test func latestAndOldestChapterBoundariesDisableUnavailableDirection() {
        let chapters = Self.chapters
        let repository = ImmediateChapterImageRepository()
        let latest = ReaderChapterModel(
            comicID: "comic",
            chapters: chapters,
            initialChapter: chapters[0],
            repository: repository
        )
        let oldest = ReaderChapterModel(
            comicID: "comic",
            chapters: chapters,
            initialChapter: chapters[2],
            repository: repository
        )

        #expect(latest.nextChapter == nil)
        #expect(!latest.goToNextChapter())
        #expect(oldest.previousChapter == nil)
        #expect(!oldest.goToPreviousChapter())
    }

    @Test func chapterChangeCancelsOldWorkAndLateOldResultCannotReplaceCurrentImages() async {
        let chapters = Self.chapters
        let repository = ControlledChapterImageRepository()
        var cancelledImageWorkCount = 0
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: chapters,
            initialChapter: chapters[1],
            repository: repository,
            cancelImageWork: { cancelledImageWorkCount += 1 }
        )

        model.loadCurrentChapter()
        await waitUntil { await repository.requestedOrders == [2] }
        #expect(model.goToPreviousChapter())
        await waitUntil { await repository.requestedOrders == [2, 1] }

        await repository.finish(order: 2, images: [Self.image(id: "old")])
        await repository.finish(order: 1, images: [Self.image(id: "current")])
        await waitUntil { model.images.first?.id == "current" }

        #expect(model.currentChapter.order == 1)
        #expect(model.images.map(\.id) == ["current"])
        #expect(cancelledImageWorkCount == 2)
    }

    private static let chapters = [
        Chapter(id: "three", title: "第三话", order: 3, updatedAt: nil),
        Chapter(id: "two", title: "第二话", order: 2, updatedAt: nil),
        Chapter(id: "one", title: "第一话", order: 1, updatedAt: nil),
    ]

    private static func image(id: String) -> ChapterImage {
        ChapterImage(
            id: id,
            media: ImageReference(
                fileServer: "https://example.com",
                path: "\(id).jpg",
                originalName: nil
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        attempts: Int = 100
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("等待章节状态超时")
    }
}

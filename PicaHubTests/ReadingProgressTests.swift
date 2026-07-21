import Foundation
import Testing
@testable import PicaHub

private actor MemoryReadingProgressStore: ReadingProgressStore {
    private var progressByComicID: [String: ReadingProgress]

    init(progressByComicID: [String: ReadingProgress] = [:]) {
        self.progressByComicID = progressByComicID
    }

    func loadProgress(for comicID: String) -> ReadingProgress? {
        progressByComicID[comicID]
    }

    func saveProgress(_ progress: ReadingProgress, for comicID: String) {
        progressByComicID[comicID] = progress
    }

    func removeProgress(for comicID: String) {
        progressByComicID[comicID] = nil
    }
}

private struct ProgressChapterImageRepository: ChapterImageRepository {
    let imageCountByOrder: [Int: Int]

    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        (0..<(imageCountByOrder[chapterOrder] ?? 0)).map { index in
            ChapterImage(
                id: "\(chapterOrder)-\(index)",
                media: ImageReference(
                    fileServer: "https://example.com",
                    path: "\(chapterOrder)-\(index).jpg",
                    originalName: nil
                )
            )
        }
    }
}

@MainActor
struct ReadingProgressTests {
    @Test func legacyJSONDecodesWithoutChapterID() throws {
        let data = try #require(#"{"chapterOrder":7,"imageIndex":3}"#.data(using: .utf8))

        let progress = try JSONDecoder().decode(ReadingProgress.self, from: data)

        #expect(progress == ReadingProgress(chapterOrder: 7, imageIndex: 3))
        #expect(progress.chapterID == nil)
    }

    @Test func newJSONContainsChapterIdentityAndPosition() throws {
        let progress = ReadingProgress(chapterID: "chapter-a", chapterOrder: 7, imageIndex: 3)

        let encoded = try JSONEncoder().encode(progress)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["chapterID"] as? String == "chapter-a")
        #expect(object["chapterOrder"] as? Int == 7)
        #expect(object["imageIndex"] as? Int == 3)
    }

    @Test func userDefaultsStorePersistsProgressPerComic() async throws {
        let suiteName = "PicaHubTests.ReadingProgress.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsReadingProgressStore(defaults: defaults)

        await store.saveProgress(ReadingProgress(chapterID: "chapter-a", chapterOrder: 12, imageIndex: 4), for: "comic-a")
        await store.saveProgress(ReadingProgress(chapterID: "chapter-b", chapterOrder: 3, imageIndex: 1), for: "comic-b")

        #expect(await store.loadProgress(for: "comic-a") == ReadingProgress(chapterID: "chapter-a", chapterOrder: 12, imageIndex: 4))
        #expect(await store.loadProgress(for: "comic-b") == ReadingProgress(chapterID: "chapter-b", chapterOrder: 3, imageIndex: 1))
        await store.removeProgress(for: "comic-a")
        #expect(await store.loadProgress(for: "comic-a") == nil)
    }

    @Test func restorationUsesSavedChapterAndClampsStaleImageIndex() async {
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterID: "two", chapterOrder: 2, imageIndex: 99)]
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: Self.chapters,
            initialChapter: Self.chapters[0],
            repository: ProgressChapterImageRepository(imageCountByOrder: [2: 3]),
            progressStore: store
        )

        await model.restoreProgressAndLoad()
        await waitUntil { !model.isLoading && model.images.count == 3 }
        await waitUntil {
            await store.loadProgress(for: "comic") == ReadingProgress(chapterID: "two", chapterOrder: 2, imageIndex: 2)
        }

        #expect(model.currentChapter.order == 2)
        #expect(model.currentImageIndex == 2)
    }

    @Test func restorationPrefersChapterIDAfterChapterReordering() async {
        let reorderedChapters = [
            Chapter(id: "two", title: "第二话", order: 20, updatedAt: nil),
            Chapter(id: "three", title: "第三话", order: 10, updatedAt: nil),
        ]
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterID: "two", chapterOrder: 2, imageIndex: 1)]
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: reorderedChapters,
            initialChapter: reorderedChapters[1],
            repository: ProgressChapterImageRepository(imageCountByOrder: [20: 3]),
            progressStore: store
        )

        await model.restoreProgressAndLoad()
        await waitUntil { !model.isLoading && model.images.count == 3 }

        #expect(model.currentChapter.id == "two")
        #expect(model.currentChapter.order == 20)
        #expect(model.currentImageIndex == 1)
    }

    @Test func legacyProgressFallsBackToChapterOrder() async {
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterOrder: 2, imageIndex: 1)]
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: Self.chapters,
            initialChapter: Self.chapters[0],
            repository: ProgressChapterImageRepository(imageCountByOrder: [2: 3]),
            progressStore: store
        )

        await model.restoreProgressAndLoad()
        await waitUntil { !model.isLoading && model.images.count == 3 }

        #expect(model.currentChapter.id == "two")
        #expect(model.currentImageIndex == 1)
    }

    @Test func staleChapterFallsBackToInitialChapterAndReplacesProgress() async {
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterID: "gone", chapterOrder: 99, imageIndex: 8)]
        )
        let model = ReaderChapterModel(
            comicID: "comic",
            chapters: Self.chapters,
            initialChapter: Self.chapters[0],
            repository: ProgressChapterImageRepository(imageCountByOrder: [3: 2]),
            progressStore: store
        )

        await model.restoreProgressAndLoad()
        await waitUntil { !model.isLoading && model.images.count == 2 }
        await waitUntil {
            await store.loadProgress(for: "comic") == ReadingProgress(chapterID: "three", chapterOrder: 3, imageIndex: 0)
        }

        #expect(model.currentChapter.order == 3)
        #expect(model.currentImageIndex == 0)
    }

    private static let chapters = [
        Chapter(id: "three", title: "第三话", order: 3, updatedAt: nil),
        Chapter(id: "two", title: "第二话", order: 2, updatedAt: nil),
        Chapter(id: "one", title: "第一话", order: 1, updatedAt: nil),
    ]

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待读取进度状态超时")
    }
}

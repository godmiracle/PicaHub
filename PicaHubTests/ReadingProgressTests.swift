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
    @Test func userDefaultsStorePersistsProgressPerComic() async throws {
        let suiteName = "PicaHubTests.ReadingProgress.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsReadingProgressStore(defaults: defaults)

        await store.saveProgress(ReadingProgress(chapterOrder: 12, imageIndex: 4), for: "comic-a")
        await store.saveProgress(ReadingProgress(chapterOrder: 3, imageIndex: 1), for: "comic-b")

        #expect(await store.loadProgress(for: "comic-a") == ReadingProgress(chapterOrder: 12, imageIndex: 4))
        #expect(await store.loadProgress(for: "comic-b") == ReadingProgress(chapterOrder: 3, imageIndex: 1))
        await store.removeProgress(for: "comic-a")
        #expect(await store.loadProgress(for: "comic-a") == nil)
    }

    @Test func restorationUsesSavedChapterAndClampsStaleImageIndex() async {
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterOrder: 2, imageIndex: 99)]
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
            await store.loadProgress(for: "comic") == ReadingProgress(chapterOrder: 2, imageIndex: 2)
        }

        #expect(model.currentChapter.order == 2)
        #expect(model.currentImageIndex == 2)
    }

    @Test func staleChapterFallsBackToInitialChapterAndReplacesProgress() async {
        let store = MemoryReadingProgressStore(
            progressByComicID: ["comic": ReadingProgress(chapterOrder: 99, imageIndex: 8)]
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
            await store.loadProgress(for: "comic") == ReadingProgress(chapterOrder: 3, imageIndex: 0)
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
        attempts: Int = 100
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("等待读取进度状态超时")
    }
}

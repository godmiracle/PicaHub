import Foundation
import Observation

@MainActor
@Observable
final class ReaderChapterModel {
    private(set) var currentChapter: Chapter
    private(set) var images: [ChapterImage] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var previousChapter: Chapter? {
        guard let index = currentIndex, chapters.indices.contains(index + 1) else { return nil }
        return chapters[index + 1]
    }

    var nextChapter: Chapter? {
        guard let index = currentIndex, index > chapters.startIndex else { return nil }
        return chapters[index - 1]
    }

    @ObservationIgnored private let comicID: String
    @ObservationIgnored private let chapters: [Chapter]
    @ObservationIgnored private let repository: any ChapterImageRepository
    @ObservationIgnored private let cancelImageWork: @MainActor () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0

    init(
        comicID: String,
        chapters: [Chapter],
        initialChapter: Chapter,
        repository: any ChapterImageRepository,
        cancelImageWork: @escaping @MainActor () -> Void = {}
    ) {
        self.comicID = comicID
        self.chapters = chapters
        self.currentChapter = initialChapter
        self.repository = repository
        self.cancelImageWork = cancelImageWork
    }

    func loadCurrentChapter() {
        startLoadingCurrentChapter()
    }

    @discardableResult
    func goToPreviousChapter() -> Bool {
        guard let previousChapter else { return false }
        select(previousChapter)
        return true
    }

    @discardableResult
    func goToNextChapter() -> Bool {
        guard let nextChapter else { return false }
        select(nextChapter)
        return true
    }

    func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        cancelImageWork()
        isLoading = false
    }

    private var currentIndex: Int? {
        chapters.firstIndex(where: { $0.id == currentChapter.id })
    }

    private func select(_ chapter: Chapter) {
        guard chapter.id != currentChapter.id else { return }
        currentChapter = chapter
        images = []
        errorMessage = nil
        startLoadingCurrentChapter()
    }

    private func startLoadingCurrentChapter() {
        loadGeneration += 1
        let generation = loadGeneration
        let chapter = currentChapter
        loadTask?.cancel()
        cancelImageWork()
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let images = try await repository.fetchAllImages(
                    comicID: comicID,
                    chapterOrder: chapter.order
                )
                try Task.checkCancellation()
                guard generation == loadGeneration, chapter.id == currentChapter.id else { return }
                self.images = images
                isLoading = false
                loadTask = nil
            } catch is CancellationError {
                finishCancellation(generation: generation)
            } catch {
                guard generation == loadGeneration, chapter.id == currentChapter.id else { return }
                errorMessage = Self.message(for: error)
                isLoading = false
                loadTask = nil
            }
        }
    }

    private func finishCancellation(generation: Int) {
        guard generation == loadGeneration else { return }
        isLoading = false
        loadTask = nil
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "章节加载失败，请稍后重试"
    }
}

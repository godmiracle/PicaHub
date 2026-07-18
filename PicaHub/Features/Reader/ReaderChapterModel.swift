import Foundation
import Observation

enum ReaderContentState: Equatable {
    case idle
    case loading
    case content
    case empty
    case failed(message: String)
}

@MainActor
@Observable
final class ReaderChapterModel {
    private(set) var currentChapter: Chapter
    private(set) var images: [ChapterImage] = []
    private(set) var currentImageIndex = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var contentState: ReaderContentState {
        if isLoading { return .loading }
        if let errorMessage { return .failed(message: errorMessage) }
        guard hasLoadedCurrentChapter else { return .idle }
        return images.isEmpty ? .empty : .content
    }

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
    @ObservationIgnored private let progressStore: any ReadingProgressStore
    @ObservationIgnored private let cancelImageWork: @MainActor () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var restoredImageIndex: Int?
    @ObservationIgnored private var hasLoadedCurrentChapter = false

    init(
        comicID: String,
        chapters: [Chapter],
        initialChapter: Chapter,
        repository: any ChapterImageRepository,
        progressStore: any ReadingProgressStore = UserDefaultsReadingProgressStore(),
        cancelImageWork: @escaping @MainActor () -> Void = {}
    ) {
        self.comicID = comicID
        self.chapters = chapters
        self.currentChapter = initialChapter
        self.repository = repository
        self.progressStore = progressStore
        self.cancelImageWork = cancelImageWork
    }

    func loadCurrentChapter() {
        startLoadingCurrentChapter()
    }

    func restoreProgressAndLoad() async {
        if let progress = await progressStore.loadProgress(for: comicID) {
            if let savedChapter = chapters.first(where: { $0.order == progress.chapterOrder }) {
                currentChapter = savedChapter
                restoredImageIndex = max(0, progress.imageIndex)
            } else {
                restoredImageIndex = 0
            }
        }
        startLoadingCurrentChapter()
    }

    func updateVisibleImageIndex(_ index: Int) {
        guard images.indices.contains(index), index != currentImageIndex else { return }
        currentImageIndex = index
        persistCurrentProgress()
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
        currentImageIndex = 0
        restoredImageIndex = nil
        hasLoadedCurrentChapter = false
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
        hasLoadedCurrentChapter = false
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
                let requestedIndex = restoredImageIndex ?? 0
                currentImageIndex = images.isEmpty
                    ? 0
                    : min(max(0, requestedIndex), images.count - 1)
                restoredImageIndex = nil
                hasLoadedCurrentChapter = true
                isLoading = false
                loadTask = nil
                persistCurrentProgress()
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

    private func persistCurrentProgress() {
        let progress = ReadingProgress(
            chapterOrder: currentChapter.order,
            imageIndex: currentImageIndex
        )
        Task { await progressStore.saveProgress(progress, for: comicID) }
    }
}

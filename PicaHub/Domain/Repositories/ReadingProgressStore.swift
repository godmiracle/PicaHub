import Foundation

protocol ReadingProgressStore: Sendable {
    func loadProgress(for comicID: String) async -> ReadingProgress?
    func saveProgress(_ progress: ReadingProgress, for comicID: String) async
    func removeProgress(for comicID: String) async
}

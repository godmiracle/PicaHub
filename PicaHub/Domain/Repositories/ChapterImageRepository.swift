import Foundation

protocol ChapterImageRepository: Sendable {
    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage]
}

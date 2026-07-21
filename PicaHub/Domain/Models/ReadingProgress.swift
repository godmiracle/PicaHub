import Foundation

struct ReadingProgress: Codable, Sendable, Equatable {
    let chapterID: String?
    let chapterOrder: Int
    let imageIndex: Int

    init(chapterID: String? = nil, chapterOrder: Int, imageIndex: Int) {
        self.chapterID = chapterID
        self.chapterOrder = chapterOrder
        self.imageIndex = imageIndex
    }
}

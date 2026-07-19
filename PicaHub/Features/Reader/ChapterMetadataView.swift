import SwiftUI

struct ChapterMetadataPresentation: Equatable {
    let title: String
    let orderLabel: String

    init(chapter: Chapter) {
        title = chapter.title
        orderLabel = "第 \(chapter.order) 话"
    }
}

struct ChapterMetadataView: View {
    private let chapterID: String
    private let presentation: ChapterMetadataPresentation

    init(chapter: Chapter) {
        chapterID = chapter.id
        presentation = ChapterMetadataPresentation(chapter: chapter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.title)
                .font(.headline)
                .accessibilityIdentifier("chapter-title-\(chapterID)")
            Text(presentation.orderLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("chapter-order-\(chapterID)")
        }
    }
}

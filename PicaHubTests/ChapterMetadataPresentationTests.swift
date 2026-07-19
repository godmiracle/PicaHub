import Testing
@testable import PicaHub

struct ChapterMetadataPresentationTests {
    @Test func preservesIndependentServerTitleAndOrderSemantics() {
        let chapter = Chapter(
            id: "chapter",
            title: "第三话",
            order: 1,
            updatedAt: nil
        )

        let presentation = ChapterMetadataPresentation(chapter: chapter)

        #expect(presentation.title == "第三话")
        #expect(presentation.orderLabel == "第 1 话")
    }
}

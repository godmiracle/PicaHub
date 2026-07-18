import Testing
@testable import PicaHub

struct ComicRowPresentationTests {
    @Test func mapsAvailableSummaryMetadata() {
        let presentation = ComicRowPresentation(
            comic: Self.comic(
                author: "作者",
                pagesCount: 42,
                epsCount: 7,
                finished: true,
                categories: ["冒险", "冒险", "奇幻", "剧情", "额外"],
                likesCount: 120,
                totalViews: 340
            )
        )

        #expect(presentation.author == "作者")
        #expect(presentation.pages == "42P")
        #expect(presentation.episodes == "7话")
        #expect(presentation.status == "完结")
        #expect(presentation.likes == "120")
        #expect(presentation.views == "340")
        #expect(presentation.categories == ["冒险", "奇幻", "剧情"])
    }

    @Test func missingOptionalMetadataUsesIntentionalFallbacks() {
        let presentation = ComicRowPresentation(
            comic: Self.comic(
                author: "  ",
                pagesCount: nil,
                epsCount: nil,
                finished: nil,
                categories: nil,
                likesCount: nil,
                totalViews: nil
            )
        )

        #expect(presentation.author == "作者未知")
        #expect(presentation.pages == "页数未知")
        #expect(presentation.episodes == "章节未知")
        #expect(presentation.status == "状态未知")
        #expect(presentation.likes == "--")
        #expect(presentation.views == "--")
        #expect(presentation.categories.isEmpty)
    }

    private static func comic(
        author: String?,
        pagesCount: Int?,
        epsCount: Int?,
        finished: Bool?,
        categories: [String]?,
        likesCount: Int?,
        totalViews: Int?
    ) -> ComicSummary {
        ComicSummary(
            id: "comic",
            title: "测试漫画",
            author: author,
            pagesCount: pagesCount,
            epsCount: epsCount,
            finished: finished,
            categories: categories,
            tags: nil,
            thumb: ImageReference(
                fileServer: "https://example.com",
                path: "cover.png",
                originalName: nil
            ),
            likesCount: likesCount,
            totalViews: totalViews
        )
    }
}

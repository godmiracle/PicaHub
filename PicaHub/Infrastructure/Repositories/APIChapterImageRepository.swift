import Foundation

struct APIChapterImageRepository: ChapterImageRepository {
    private let client: APIClient
    private let maximumConcurrentPages: Int

    init(client: APIClient, maximumConcurrentPages: Int = 3) {
        self.client = client
        self.maximumConcurrentPages = max(1, maximumConcurrentPages)
    }

    func fetchAllImages(comicID: String, chapterOrder: Int) async throws -> [ChapterImage] {
        let firstPage = try await fetchPage(comicID: comicID, chapterOrder: chapterOrder, page: 1)
        var imagesByPage = [1: firstPage.docs]

        if firstPage.pages > 1 {
            try await fetchRemainingPages(
                comicID: comicID,
                chapterOrder: chapterOrder,
                totalPages: firstPage.pages,
                imagesByPage: &imagesByPage
            )
        }

        var seenImageIDs = Set<String>()
        return (1...max(1, firstPage.pages)).flatMap { imagesByPage[$0] ?? [] }.filter { image in
            seenImageIDs.insert(image.id).inserted
        }
    }

    private func fetchRemainingPages(
        comicID: String,
        chapterOrder: Int,
        totalPages: Int,
        imagesByPage: inout [Int: [ChapterImage]]
    ) async throws {
        let client = client
        let concurrentLimit = min(maximumConcurrentPages, totalPages - 1)

        try await withThrowingTaskGroup(of: (Int, [ChapterImage]).self) { group in
            var nextPage = 2

            for _ in 0..<concurrentLimit {
                let page = nextPage
                group.addTask {
                    try Task.checkCancellation()
                    let response = try await client.send(
                        PicaEndpoints.chapterImages(
                            comicID: comicID,
                            order: chapterOrder,
                            page: page
                        )
                    )
                    return (page, response.pages.docs)
                }
                nextPage += 1
            }

            while let (page, images) = try await group.next() {
                imagesByPage[page] = images

                if nextPage <= totalPages {
                    let page = nextPage
                    group.addTask {
                        try Task.checkCancellation()
                        let response = try await client.send(
                            PicaEndpoints.chapterImages(
                                comicID: comicID,
                                order: chapterOrder,
                                page: page
                            )
                        )
                        return (page, response.pages.docs)
                    }
                    nextPage += 1
                }
            }
        }
    }

    private func fetchPage(
        comicID: String,
        chapterOrder: Int,
        page: Int
    ) async throws -> Page<ChapterImage> {
        try await client.send(
            PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: page)
        ).pages
    }
}

import Foundation

struct APIComicDetailsRepository: ComicDetailsRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchDetails(comicID: String) async throws -> ComicDetails {
        try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic
    }

    func fetchAllChapters(comicID: String) async throws -> [Chapter] {
        let firstPage = try await fetchChapterPage(comicID: comicID, page: 1)
        var serviceOrderedChapters = firstPage.docs

        if firstPage.pages > 1 {
            for page in 2...firstPage.pages {
                try Task.checkCancellation()
                let nextPage = try await fetchChapterPage(comicID: comicID, page: page)
                serviceOrderedChapters.append(contentsOf: nextPage.docs)
            }
        }

        var seenChapterIDs = Set<String>()
        let uniqueChapters = serviceOrderedChapters.filter { chapter in
            seenChapterIDs.insert(chapter.id).inserted
        }

        // The service paginates oldest-first. The reference client merges pages in
        // service order, then reverses once so readers see the latest chapter first.
        return Array(uniqueChapters.reversed())
    }

    private func fetchChapterPage(comicID: String, page: Int) async throws -> Page<Chapter> {
        try await client.send(PicaEndpoints.chapters(comicID: comicID, page: page)).eps
    }
}

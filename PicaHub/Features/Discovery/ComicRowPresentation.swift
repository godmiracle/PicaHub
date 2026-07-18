import Foundation

struct ComicRowPresentation: Equatable {
    let title: String
    let author: String
    let pages: String
    let episodes: String
    let status: String
    let likes: String
    let views: String
    let categories: [String]

    init(comic: ComicSummary) {
        title = comic.title
        let normalizedAuthor = comic.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        author = normalizedAuthor.flatMap { $0.isEmpty ? nil : $0 } ?? "作者未知"
        pages = comic.pagesCount.map { "\($0)P" } ?? "页数未知"
        episodes = comic.epsCount.map { "\($0)话" } ?? "章节未知"
        status = comic.finished.map { $0 ? "完结" : "连载" } ?? "状态未知"
        likes = comic.likesCount.map(String.init) ?? "--"
        views = comic.totalViews.map(String.init) ?? "--"
        var seenCategories = Set<String>()
        categories = (comic.categories ?? [])
            .filter { !$0.isEmpty && seenCategories.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }
}

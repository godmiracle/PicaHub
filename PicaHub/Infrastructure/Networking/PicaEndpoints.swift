import Foundation

enum PicaEndpoints {
    static func login(email: String, password: String) throws -> APIEndpoint<LoginResponse> {
        try .json(
            method: .post,
            path: "auth/sign-in",
            body: LoginRequest(email: email, password: password),
            requiresAuthentication: false
        )
    }

    static let categories = APIEndpoint<CategoryResponse>(method: .get, path: "categories")

    static func comics(
        page: Int,
        category: String? = nil,
        sort: ComicSort = .newest
    ) -> APIEndpoint<ComicPageResponse> {
        var query = [APIQueryItem("page", String(page))]
        if let category, !category.isEmpty {
            query.append(APIQueryItem("c", category))
        }
        query.append(APIQueryItem("s", sort.rawValue))
        return APIEndpoint(method: .get, path: "comics", query: query)
    }

    static func search(keyword: String, page: Int) throws -> APIEndpoint<ComicPageResponse> {
        struct SearchBody: Encodable, Sendable {
            let keyword: String
            let sort: String
            let categories: [String]
        }
        return try .json(
            method: .post,
            path: "comics/advanced-search",
            query: [APIQueryItem("page", String(page))],
            body: SearchBody(keyword: keyword, sort: ComicSort.newest.rawValue, categories: [])
        )
    }

    static func comicDetails(id: String) -> APIEndpoint<ComicDetailsResponse> {
        APIEndpoint(method: .get, path: "comics/\(id)")
    }

    static func chapters(comicID: String, page: Int) -> APIEndpoint<ChaptersResponse> {
        APIEndpoint(
            method: .get,
            path: "comics/\(comicID)/eps",
            query: [APIQueryItem("page", String(page))]
        )
    }

    static func chapterImages(
        comicID: String,
        order: Int,
        page: Int
    ) -> APIEndpoint<ChapterImagesResponse> {
        APIEndpoint(
            method: .get,
            path: "comics/\(comicID)/order/\(order)/pages",
            query: [APIQueryItem("page", String(page))]
        )
    }

    static func toggleFavorite(comicID: String) -> APIEndpoint<FavoriteActionResponse> {
        APIEndpoint(
            method: .post,
            path: "comics/\(comicID)/favourite",
            allowsAutomaticRetry: false
        )
    }

    static func favorites(page: Int, sort: ComicSort = .newest) -> APIEndpoint<ComicPageResponse> {
        APIEndpoint(
            method: .get,
            path: "users/favourite",
            query: [
                APIQueryItem("page", String(page)),
                APIQueryItem("s", sort.rawValue),
            ]
        )
    }
}

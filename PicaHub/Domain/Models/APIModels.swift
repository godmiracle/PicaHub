import Foundation

struct LoginRequest: Codable, Sendable, Equatable {
    let email: String
    let password: String
}

struct LoginResponse: Codable, Sendable, Equatable {
    let token: String
}

struct ImageReference: Codable, Sendable, Equatable {
    let fileServer: String
    let path: String
    let originalName: String?
}

struct CategoryResponse: Codable, Sendable, Equatable {
    let categories: [ComicCategory]
}

struct ComicCategory: Codable, Sendable, Identifiable, Equatable {
    let remoteID: String?
    let title: String
    let description: String?
    let thumb: ImageReference?
    let isWeb: Bool?
    let active: Bool?

    var id: String {
        remoteID ?? "category:\(title)"
    }

    enum CodingKeys: String, CodingKey {
        case remoteID = "_id"
        case title, description, thumb, isWeb, active
    }
}

struct ComicPageResponse: Codable, Sendable, Equatable {
    let comics: Page<ComicSummary>
}

struct Page<Item: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    let docs: [Item]
    let limit: Int
    let page: Int
    let pages: Int
    let total: Int
}

struct ComicSummary: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let author: String?
    let pagesCount: Int?
    let epsCount: Int?
    let finished: Bool?
    let categories: [String]?
    let tags: [String]?
    let thumb: ImageReference
    let likesCount: Int?
    let totalViews: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, pagesCount, epsCount, finished, categories, tags, thumb, likesCount, totalViews
    }
}

struct ComicDetailsResponse: Codable, Sendable, Equatable {
    let comic: ComicDetails
}

struct ComicDetails: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let author: String?
    let chineseTeam: String?
    let tags: [String]?
    let thumb: ImageReference
    let pagesCount: Int?
    let epsCount: Int?
    let finished: Bool?
    let isFavourite: Bool
    let isLiked: Bool?
    let likesCount: Int?
    let viewsCount: Int?
    let commentsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, description, author, chineseTeam, tags, thumb, pagesCount, epsCount, finished
        case isFavourite, isLiked, likesCount, viewsCount, commentsCount
    }
}

struct ChaptersResponse: Codable, Sendable, Equatable {
    let eps: Page<Chapter>
}

struct Chapter: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let order: Int
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, order
        case updatedAt = "updated_at"
    }
}

struct ChapterImagesResponse: Codable, Sendable, Equatable {
    let pages: Page<ChapterImage>
    let ep: ChapterEpisode?
}

struct ChapterImage: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let media: ImageReference

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case media
    }
}

struct ChapterEpisode: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title
    }
}

struct FavoriteActionResponse: Codable, Sendable, Equatable {
    let action: String
}

enum ComicSort: String, Codable, Sendable, CaseIterable {
    case newest = "dd"
    case oldest = "da"
    case mostLiked = "ld"
    case mostViewed = "vd"
}

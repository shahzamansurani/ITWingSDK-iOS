import Foundation

public struct MediaLibraryResponse: Codable, Sendable {
    public var settings: MediaLibrarySettings
    public var categories: [ITWingMediaCategory]
    public var items: [ITWingMediaItem]
    public var trending: [ITWingMediaItem]

    enum CodingKeys: String, CodingKey {
        case settings
        case categories
        case items
        case wallpapers
        case trending
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decodeIfPresent(MediaLibrarySettings.self, forKey: .settings)
            ?? MediaLibrarySettings(enabled: true, topLimit: 10, defaultSort: "trending", placements: [:])
        categories = try values.decodeIfPresent([ITWingMediaCategory].self, forKey: .categories) ?? []
        items = try values.decodeIfPresent([ITWingMediaItem].self, forKey: .items)
            ?? values.decodeIfPresent([ITWingMediaItem].self, forKey: .wallpapers)
            ?? []
        trending = try values.decodeIfPresent([ITWingMediaItem].self, forKey: .trending) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(settings, forKey: .settings)
        try values.encode(categories, forKey: .categories)
        try values.encode(items, forKey: .items)
        try values.encode(trending, forKey: .trending)
    }
}

public struct MediaLibrarySettings: Codable, Sendable {
    public var enabled: Bool
    public var topLimit: Int
    public var defaultSort: String
    public var placements: [String: MediaPlacementConfig]

    enum CodingKeys: String, CodingKey {
        case enabled
        case topLimit = "top_limit"
        case defaultSort = "default_sort"
        case placements
    }

    public init(enabled: Bool, topLimit: Int, defaultSort: String, placements: [String: MediaPlacementConfig]) {
        self.enabled = enabled
        self.topLimit = topLimit
        self.defaultSort = defaultSort
        self.placements = placements
    }
}

public struct ITWingMediaCategory: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var slug: String?
    public var description: String?
    public var imageUrl: String?
    public var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case description
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
    }
}

public struct ITWingMediaItem: Codable, Sendable, Hashable {
    public var id: String
    public var categoryId: String?
    public var categorySlug: String?
    public var title: String
    public var slug: String?
    public var mediaUrl: String
    public var thumbnailUrl: String?
    public var mimeType: String?
    public var durationMs: Int?
    public var tags: [String]
    public var isFeatured: Bool
    public var isPremium: Bool
    public var sortOrder: Int?
    public var stats: [String: Int]
    public var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case categorySlug = "category_slug"
        case title
        case slug
        case mediaUrl = "media_url"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case mimeType = "mime_type"
        case durationMs = "duration_ms"
        case tags
        case isFeatured = "is_featured"
        case isPremium = "is_premium"
        case sortOrder = "sort_order"
        case stats
        case metadata
    }

    public var displayImageUrl: String {
        thumbnailUrl?.isEmpty == false ? thumbnailUrl! : mediaUrl
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        categoryId = try values.decodeIfPresent(String.self, forKey: .categoryId)
        categorySlug = try values.decodeIfPresent(String.self, forKey: .categorySlug)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        slug = try values.decodeIfPresent(String.self, forKey: .slug)
        mediaUrl = try values.decodeIfPresent(String.self, forKey: .mediaUrl)
            ?? values.decodeIfPresent(String.self, forKey: .imageUrl)
            ?? ""
        thumbnailUrl = try values.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        durationMs = try values.decodeIfPresent(Int.self, forKey: .durationMs)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFeatured = try values.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        isPremium = try values.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder)
        stats = (try? values.decodeIfPresent([String: Int].self, forKey: .stats)) ?? [:]
        let flexibleMetadata = try? values.decodeIfPresent([String: ITWingFlexibleStringValue].self, forKey: .metadata)
        metadata = flexibleMetadata?.compactMapValues(\.value) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(categoryId, forKey: .categoryId)
        try values.encodeIfPresent(categorySlug, forKey: .categorySlug)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(slug, forKey: .slug)
        try values.encode(mediaUrl, forKey: .mediaUrl)
        try values.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try values.encodeIfPresent(mimeType, forKey: .mimeType)
        try values.encodeIfPresent(durationMs, forKey: .durationMs)
        try values.encode(tags, forKey: .tags)
        try values.encode(isFeatured, forKey: .isFeatured)
        try values.encode(isPremium, forKey: .isPremium)
        try values.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try values.encode(stats, forKey: .stats)
        try values.encode(metadata, forKey: .metadata)
    }
}

struct MediaLibraryEnvelope: Decodable {
    let data: MediaLibraryResponse
}

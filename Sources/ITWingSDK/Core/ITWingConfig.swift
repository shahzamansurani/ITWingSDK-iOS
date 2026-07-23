import Foundation

public struct ITWingConfig: Codable, Sendable {
    public var configVersion: Int
    public var ttlSeconds: Int
    public var ads: AdsConfig
    public var app: AppConfig
    public var features: [String: Bool]
    public var remoteConfig: [String: String]
    public var notifications: NotificationConfig
    public var subscriptions: SubscriptionConfig
    public var apiKeys: [String: ApiKeyConfig]
    public var startupFlow: StartupFlowConfig
    public var dialogs: DialogConfig
    public var wallpapers: MediaLibraryConfig
    public var ringtones: MediaLibraryConfig
    public var videos: MediaLibraryConfig
    public var vpnServers: MediaLibraryConfig

    public static let empty = ITWingConfig(
        configVersion: 0,
        ttlSeconds: 3600,
        ads: AdsConfig(),
        app: AppConfig(),
        features: [:],
        remoteConfig: [:],
        notifications: NotificationConfig(),
        subscriptions: SubscriptionConfig(),
        apiKeys: [:],
        startupFlow: StartupFlowConfig(),
        dialogs: DialogConfig(),
        wallpapers: MediaLibraryConfig(kind: "wallpapers"),
        ringtones: MediaLibraryConfig(kind: "ringtones"),
        videos: MediaLibraryConfig(kind: "videos"),
        vpnServers: MediaLibraryConfig(kind: "vpn_servers")
    )

    enum CodingKeys: String, CodingKey {
        case configVersion = "config_version"
        case ttlSeconds = "ttl_seconds"
        case ads
        case app
        case features
        case remoteConfig = "remote_config"
        case notifications
        case subscriptions
        case apiKeys = "api_keys"
        case startupFlow = "startup_flow"
        case dialogs
        case wallpapers
        case ringtones
        case videos
        case vpnServers = "vpn_servers"
    }

    public init(
        configVersion: Int,
        ttlSeconds: Int,
        ads: AdsConfig,
        app: AppConfig,
        features: [String: Bool],
        remoteConfig: [String: String],
        notifications: NotificationConfig,
        subscriptions: SubscriptionConfig,
        apiKeys: [String: ApiKeyConfig],
        startupFlow: StartupFlowConfig = StartupFlowConfig(),
        dialogs: DialogConfig = DialogConfig(),
        wallpapers: MediaLibraryConfig = MediaLibraryConfig(kind: "wallpapers"),
        ringtones: MediaLibraryConfig = MediaLibraryConfig(kind: "ringtones"),
        videos: MediaLibraryConfig = MediaLibraryConfig(kind: "videos"),
        vpnServers: MediaLibraryConfig = MediaLibraryConfig(kind: "vpn_servers")
    ) {
        self.configVersion = configVersion
        self.ttlSeconds = ttlSeconds
        self.ads = ads
        self.app = app
        self.features = features
        self.remoteConfig = remoteConfig
        self.notifications = notifications
        self.subscriptions = subscriptions
        self.apiKeys = apiKeys
        self.startupFlow = startupFlow
        self.dialogs = dialogs
        self.wallpapers = wallpapers
        self.ringtones = ringtones
        self.videos = videos
        self.vpnServers = vpnServers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        configVersion = try values.decodeIfPresent(Int.self, forKey: .configVersion) ?? 0
        ttlSeconds = try values.decodeIfPresent(Int.self, forKey: .ttlSeconds) ?? 3600
        ads = try values.decodeIfPresent(AdsConfig.self, forKey: .ads) ?? AdsConfig()
        app = try values.decodeIfPresent(AppConfig.self, forKey: .app) ?? AppConfig()
        features = values.decodeLossyBoolDictionaryIfPresent(forKey: .features)
        let flexibleRemote = try values.decodeIfPresent([String: ITWingFlexibleStringValue].self, forKey: .remoteConfig)
        remoteConfig = flexibleRemote?.compactMapValues(\.value) ?? [:]
        notifications = try values.decodeIfPresent(NotificationConfig.self, forKey: .notifications) ?? NotificationConfig()
        subscriptions = try values.decodeIfPresent(SubscriptionConfig.self, forKey: .subscriptions) ?? SubscriptionConfig()
        apiKeys = (try? values.decode([String: ApiKeyConfig].self, forKey: .apiKeys)) ?? [:]
        startupFlow = try values.decodeIfPresent(StartupFlowConfig.self, forKey: .startupFlow) ?? StartupFlowConfig()
        dialogs = try values.decodeIfPresent(DialogConfig.self, forKey: .dialogs) ?? DialogConfig()
        wallpapers = try values.decodeIfPresent(MediaLibraryConfig.self, forKey: .wallpapers) ?? MediaLibraryConfig(kind: "wallpapers")
        ringtones = try values.decodeIfPresent(MediaLibraryConfig.self, forKey: .ringtones) ?? MediaLibraryConfig(kind: "ringtones")
        videos = try values.decodeIfPresent(MediaLibraryConfig.self, forKey: .videos) ?? MediaLibraryConfig(kind: "videos")
        vpnServers = try values.decodeIfPresent(MediaLibraryConfig.self, forKey: .vpnServers) ?? MediaLibraryConfig(kind: "vpn_servers")
        if wallpapers.kind.isEmpty { wallpapers.kind = "wallpapers" }
        if ringtones.kind.isEmpty { ringtones.kind = "ringtones" }
        if videos.kind.isEmpty { videos.kind = "videos" }
        if vpnServers.kind.isEmpty { vpnServers.kind = "vpn_servers" }
    }
}

public struct AppConfig: Codable, Sendable {
    public var name: String?
    public var title: String?
    public var iconUrl: String?
    public var launcherIconUrl: String?
    public var splashLogoUrl: String?
    public var status: String?
    public var maintenance: Bool = false
    public var privacyPolicyUrl: String?
    public var termsUrl: String?
    public var disclaimerUrl: String?
    public var legal: [String: LegalDocumentConfig]
    public var colors: [String: String]
    public var splash: SplashConfig = SplashConfig()
    public var loadingLottieUrl: String?
    public var loadingAdTimeoutMs: Int = 7000
    public var splashBackgroundUrl: String?
    public var splashCenterImageUrl: String?
    public var splashLottieUrl: String?
    public var splashTitle: String?
    public var splashSubtitle: String?
    public var splashBackgroundColor: String?
    public var splashTitleTextColor: String?
    public var splashSubtitleTextColor: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case iconUrl = "icon_url"
        case launcherIconUrl = "launcher_icon_url"
        case splashLogoUrl = "splash_logo_url"
        case status
        case maintenance
        case privacyPolicyUrl = "privacy_policy_url"
        case termsUrl = "terms_url"
        case disclaimerUrl = "disclaimer_url"
        case legal
        case colors
        case splash
        case loadingLottieUrl = "loading_lottie_url"
        case loadingAdTimeoutMs = "loading_ad_timeout_ms"
        case splashBackgroundUrl = "splash_background_url"
        case splashCenterImageUrl = "splash_center_image_url"
        case splashLottieUrl = "splash_lottie_url"
        case splashTitle = "splash_title"
        case splashSubtitle = "splash_subtitle"
        case splashBackgroundColor = "splash_background_color"
        case splashTitleTextColor = "splash_title_text_color"
        case splashSubtitleTextColor = "splash_subtitle_text_color"
    }

    public init(
        name: String? = nil,
        title: String? = nil,
        iconUrl: String? = nil,
        launcherIconUrl: String? = nil,
        splashLogoUrl: String? = nil,
        status: String? = nil,
        maintenance: Bool = false,
        privacyPolicyUrl: String? = nil,
        termsUrl: String? = nil,
        disclaimerUrl: String? = nil,
        legal: [String: LegalDocumentConfig] = [:],
        colors: [String: String] = [:],
        splash: SplashConfig = SplashConfig()
    ) {
        self.name = name
        self.title = title
        self.iconUrl = iconUrl
        self.launcherIconUrl = launcherIconUrl
        self.splashLogoUrl = splashLogoUrl
        self.status = status
        self.maintenance = maintenance
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.disclaimerUrl = disclaimerUrl
        self.legal = legal
        self.colors = colors
        self.splash = splash
        self.loadingLottieUrl = nil
        self.loadingAdTimeoutMs = 7000
        self.splashBackgroundUrl = nil
        self.splashCenterImageUrl = nil
        self.splashLottieUrl = nil
        self.splashTitle = nil
        self.splashSubtitle = nil
        self.splashBackgroundColor = nil
        self.splashTitleTextColor = nil
        self.splashSubtitleTextColor = nil
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        iconUrl = try values.decodeIfPresent(String.self, forKey: .iconUrl)
        launcherIconUrl = try values.decodeIfPresent(String.self, forKey: .launcherIconUrl)
        splashLogoUrl = try values.decodeIfPresent(String.self, forKey: .splashLogoUrl)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        maintenance = try values.decodeIfPresent(Bool.self, forKey: .maintenance) ?? false
        privacyPolicyUrl = try values.decodeIfPresent(String.self, forKey: .privacyPolicyUrl)
        termsUrl = try values.decodeIfPresent(String.self, forKey: .termsUrl)
        disclaimerUrl = try values.decodeIfPresent(String.self, forKey: .disclaimerUrl)
        legal = try values.decodeIfPresent([String: LegalDocumentConfig].self, forKey: .legal) ?? [:]
        colors = try values.decodeIfPresent([String: String].self, forKey: .colors) ?? [:]
        splash = try values.decodeIfPresent(SplashConfig.self, forKey: .splash) ?? SplashConfig()
        loadingLottieUrl = try values.decodeIfPresent(String.self, forKey: .loadingLottieUrl)
        loadingAdTimeoutMs = (try? values.decode(Int.self, forKey: .loadingAdTimeoutMs))
            ?? Int((try? values.decode(String.self, forKey: .loadingAdTimeoutMs)) ?? "")
            ?? 7000
        splashBackgroundUrl = try values.decodeIfPresent(String.self, forKey: .splashBackgroundUrl)
        splashCenterImageUrl = try values.decodeIfPresent(String.self, forKey: .splashCenterImageUrl)
        splashLottieUrl = try values.decodeIfPresent(String.self, forKey: .splashLottieUrl)
        splashTitle = try values.decodeIfPresent(String.self, forKey: .splashTitle)
        splashSubtitle = try values.decodeIfPresent(String.self, forKey: .splashSubtitle)
        splashBackgroundColor = try values.decodeIfPresent(String.self, forKey: .splashBackgroundColor)
        splashTitleTextColor = try values.decodeIfPresent(String.self, forKey: .splashTitleTextColor)
        splashSubtitleTextColor = try values.decodeIfPresent(String.self, forKey: .splashSubtitleTextColor)
    }
}

public struct LegalDocumentConfig: Codable, Sendable {
    public var format: String?
    public var title: String?
    public var url: String?
    public var content: String?
    public var version: String?
    public var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case format, title, url, content, version
        case publishedAt = "published_at"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decodeIfPresent(String.self, forKey: .format)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        content = try values.decodeIfPresent(String.self, forKey: .content)
        version = try values.decodeIfPresent(ITWingFlexibleStringValue.self, forKey: .version)?.value
        publishedAt = try values.decodeIfPresent(String.self, forKey: .publishedAt)
    }
}

public struct SplashConfig: Codable, Sendable {
    public var seconds: Int = 7
    public var adFormat: String = "none"
    public var style: String?
    public var title: String?
    public var subtitle: String?
    public var backgroundUrl: String?
    public var centerImageUrl: String?
    public var lottieUrl: String?
    public var backgroundColor: String?
    public var titleTextColor: String?
    public var subtitleTextColor: String?
    public var titleTextSize: Double?
    public var subtitleTextSize: Double?

    enum CodingKeys: String, CodingKey {
        case seconds, style, title, subtitle
        case adFormat = "ad_format"
        case backgroundUrl = "background_url"
        case centerImageUrl = "center_image_url"
        case lottieUrl = "lottie_url"
        case backgroundColor = "background_color"
        case titleTextColor = "title_text_color"
        case subtitleTextColor = "subtitle_text_color"
        case titleTextSize = "title_text_size_sp"
        case subtitleTextSize = "subtitle_text_size_sp"
    }

    public init(seconds: Int = 7, adFormat: String = "none") {
        self.seconds = seconds
        self.adFormat = adFormat
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        seconds = (try? values.decode(Int.self, forKey: .seconds))
            ?? Int((try? values.decode(String.self, forKey: .seconds)) ?? "") ?? 7
        seconds = min(15, max(0, seconds))
        adFormat = try values.decodeIfPresent(String.self, forKey: .adFormat) ?? "none"
        style = try values.decodeIfPresent(String.self, forKey: .style)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        subtitle = try values.decodeIfPresent(String.self, forKey: .subtitle)
        backgroundUrl = try values.decodeIfPresent(String.self, forKey: .backgroundUrl)
        centerImageUrl = try values.decodeIfPresent(String.self, forKey: .centerImageUrl)
        lottieUrl = try values.decodeIfPresent(String.self, forKey: .lottieUrl)
        backgroundColor = try values.decodeIfPresent(String.self, forKey: .backgroundColor)
        titleTextColor = try values.decodeIfPresent(String.self, forKey: .titleTextColor)
        subtitleTextColor = try values.decodeIfPresent(String.self, forKey: .subtitleTextColor)
        titleTextSize = (try? values.decode(Double.self, forKey: .titleTextSize))
        subtitleTextSize = (try? values.decode(Double.self, forKey: .subtitleTextSize))
    }
}

public struct ApiKeyConfig: Codable, Sendable {
    public var id: String?
    public var name: String
    public var value: String
    public var provider: String?
    public var proxyEndpoint: String?
    public var baseUrl: String?
    public var description: String?
    public var dailyQuota: Int?
    public var dailyUsage: Int
    public var poolSize: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case provider
        case proxyEndpoint = "proxy_endpoint"
        case baseUrl = "base_url"
        case description
        case dailyQuota = "daily_quota"
        case dailyUsage = "daily_usage"
        case poolSize = "pool_size"
    }

    public init(
        id: String? = nil,
        name: String,
        value: String,
        provider: String? = nil,
        proxyEndpoint: String? = nil,
        baseUrl: String? = nil,
        description: String? = nil,
        dailyQuota: Int? = nil,
        dailyUsage: Int = 0,
        poolSize: Int = 1
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.provider = provider
        self.proxyEndpoint = proxyEndpoint
        self.baseUrl = baseUrl
        self.description = description
        self.dailyQuota = dailyQuota
        self.dailyUsage = dailyUsage
        self.poolSize = poolSize
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = try values.decodeIfPresent(String.self, forKey: .value) ?? ""
        provider = try values.decodeIfPresent(String.self, forKey: .provider)
        proxyEndpoint = try values.decodeIfPresent(String.self, forKey: .proxyEndpoint)
        baseUrl = try values.decodeIfPresent(String.self, forKey: .baseUrl)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        dailyQuota = try values.decodeIfPresent(Int.self, forKey: .dailyQuota)
        dailyUsage = try values.decodeIfPresent(Int.self, forKey: .dailyUsage) ?? 0
        poolSize = try values.decodeIfPresent(Int.self, forKey: .poolSize) ?? 1
    }
}

public struct AdsConfig: Codable, Sendable {
    public var globalEnabled: Bool = false
    public var testMode: Bool = false
    public var admobAppId: String?
    public var futureFormats: [String] = []
    public var placements: [AdPlacementConfig] = []
    public var customAds: [ITWingCustomAd] = []

    enum CodingKeys: String, CodingKey {
        case globalEnabled = "global_enabled"
        case testMode = "test_mode"
        case admobAppId = "admob_app_id"
        case futureFormats = "future_formats"
        case placements
        case customAds = "custom_ads"
    }
}

public struct AdPlacementConfig: Codable, Sendable {
    public var name: String
    public var format: String
    public var enabled: Bool
    public var testMode: Bool
    public var priority: Int?
    public var triggerInterval: Int?
    public var refreshSeconds: Int?
    public var cooldownSeconds: Int?
    public var sessionCap: Int?
    public var dailyCap: Int?
    public var metadata: [String: String?]?
    public var customAd: ITWingCustomAd?
    public var units: [AdUnitConfig]

    enum CodingKeys: String, CodingKey {
        case name
        case format
        case enabled
        case testMode = "test_mode"
        case priority
        case triggerInterval = "trigger_interval"
        case refreshSeconds = "refresh_seconds"
        case cooldownSeconds = "cooldown_seconds"
        case sessionCap = "session_cap"
        case dailyCap = "daily_cap"
        case metadata
        case customAd = "custom_ad"
        case units
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? ""
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        testMode = try values.decodeIfPresent(Bool.self, forKey: .testMode) ?? false
        priority = try values.decodeIfPresent(Int.self, forKey: .priority)
        triggerInterval = try values.decodeIfPresent(Int.self, forKey: .triggerInterval)
        refreshSeconds = try values.decodeIfPresent(Int.self, forKey: .refreshSeconds)
        cooldownSeconds = try values.decodeIfPresent(Int.self, forKey: .cooldownSeconds)
        sessionCap = try values.decodeIfPresent(Int.self, forKey: .sessionCap)
        dailyCap = try values.decodeIfPresent(Int.self, forKey: .dailyCap)
        let flexible = try values.decodeIfPresent([String: ITWingFlexibleStringValue].self, forKey: .metadata)
        metadata = flexible?.mapValues(\.value)
        customAd = try values.decodeIfPresent(ITWingCustomAd.self, forKey: .customAd)
        units = try values.decodeIfPresent([AdUnitConfig].self, forKey: .units) ?? []
    }
}

public struct AdUnitConfig: Codable, Sendable {
    public var network: String
    public var adUnitId: String
    public var waterfallOrder: Int

    enum CodingKeys: String, CodingKey {
        case network
        case adUnitId = "ad_unit_id"
        case waterfallOrder = "waterfall_order"
    }
}

public struct NotificationConfig: Codable, Sendable {
    public var provider: String = "onesignal"
    public var enabled: Bool = false
    public var onesignalAppId: String?
    public var promptForPermission: Bool = false
    public var segments: [String] = []
    public var tags: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case provider
        case enabled
        case onesignalAppId = "onesignal_app_id"
        case promptForPermission = "prompt_for_permission"
        case segments
        case tags
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? "onesignal"
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        onesignalAppId = try values.decodeIfPresent(String.self, forKey: .onesignalAppId)
        promptForPermission = try values.decodeIfPresent(Bool.self, forKey: .promptForPermission) ?? false
        segments = try values.decodeIfPresent([String].self, forKey: .segments) ?? []
        if let dictionary = try? values.decode([String: String].self, forKey: .tags) {
            tags = dictionary
        } else if let list = try? values.decode([String].self, forKey: .tags) {
            tags = Dictionary(uniqueKeysWithValues: list.map { ($0, "true") })
        } else {
            tags = [:]
        }
    }

}

public struct SubscriptionConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var verifyEndpoint: String = "/subscriptions/verify"
    public var restoreEndpoint: String = "/subscriptions/restore"
    public var products: [SubscriptionProductConfig] = []

    enum CodingKeys: String, CodingKey {
        case enabled
        case verifyEndpoint = "verify_endpoint"
        case restoreEndpoint = "restore_endpoint"
        case products
    }
}

public struct SubscriptionProductConfig: Codable, Sendable {
    public var id: String
    public var name: String
    public var store: String
    public var productId: String
    public var basePlanId: String?
    public var offerId: String?
    public var billingPeriod: String
    public var price: Double?
    public var currency: String?
    public var removesAds: Bool
    public var entitlements: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case store
        case productId = "product_id"
        case basePlanId = "base_plan_id"
        case offerId = "offer_id"
        case billingPeriod = "billing_period"
        case price
        case currency
        case removesAds = "removes_ads"
        case entitlements
    }
}

public struct StartupFlowConfig: Codable, Sendable {
    public var flowOnboarding: Bool
    public var flowTerms: Bool
    public var termsUrl: String?
    public var termsContent: String?
    public var onboardingPages: [OnboardingPageConfig]
    public var onboardingAdScope: String
    public var onboardingActivityAdFormat: String
    public var onboardingActivityAdPlacement: String?
    public var termsAdFormat: String
    public var termsBannerPlacement: String?
    public var termsInterstitialEnabled: Bool
    public var termsInterstitialPlacement: String?
    public var blockAdsWhenVpnActive: Bool

    enum CodingKeys: String, CodingKey {
        case flowOnboarding = "flow_onboarding"
        case flowTerms = "flow_terms"
        case termsUrl = "terms_url"
        case termsContent = "terms_content"
        case onboardingPages = "onboarding_pages"
        case onboardingAdScope = "onboarding_ad_scope"
        case onboardingActivityAdFormat = "onboarding_activity_ad_format"
        case onboardingActivityAdPlacement = "onboarding_activity_ad_placement"
        case termsAdFormat = "terms_ad_format"
        case termsBannerPlacement = "terms_banner_placement"
        case termsInterstitialEnabled = "terms_interstitial_enabled"
        case termsInterstitialPlacement = "terms_interstitial_placement"
        case blockAdsWhenVpnActive = "block_ads_when_vpn_active"
    }

    public init(
        flowOnboarding: Bool = true,
        flowTerms: Bool = true,
        termsUrl: String? = nil,
        termsContent: String? = nil,
        onboardingPages: [OnboardingPageConfig] = [],
        onboardingAdScope: String = "activity",
        onboardingActivityAdFormat: String = "native",
        onboardingActivityAdPlacement: String? = "native_large",
        termsAdFormat: String = "banner",
        termsBannerPlacement: String? = "banner_adaptive",
        termsInterstitialEnabled: Bool = true,
        termsInterstitialPlacement: String? = "interstitial",
        blockAdsWhenVpnActive: Bool = false
    ) {
        self.flowOnboarding = flowOnboarding
        self.flowTerms = flowTerms
        self.termsUrl = termsUrl
        self.termsContent = termsContent
        self.onboardingPages = onboardingPages
        self.onboardingAdScope = onboardingAdScope
        self.onboardingActivityAdFormat = onboardingActivityAdFormat
        self.onboardingActivityAdPlacement = onboardingActivityAdPlacement
        self.termsAdFormat = termsAdFormat
        self.termsBannerPlacement = termsBannerPlacement
        self.termsInterstitialEnabled = termsInterstitialEnabled
        self.termsInterstitialPlacement = termsInterstitialPlacement
        self.blockAdsWhenVpnActive = blockAdsWhenVpnActive
    }
}

public struct OnboardingPageConfig: Codable, Sendable {
    public var title: String
    public var description: String
    public var imageUrl: String?
    public var nativePlacement: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case imageUrl = "image_url"
        case nativePlacement = "native_placement"
    }
}

public struct DialogConfig: Codable, Sendable {
    public var enabled: Bool
    public var title: String
    public var description: String
    public var positiveButton: String
    public var negativeButton: String
    public var nativePlacement: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case title
        case description
        case positiveButton = "positive_button"
        case negativeButton = "negative_button"
        case nativePlacement = "native_placement"
    }

    public init(
        enabled: Bool = true,
        title: String = "Exit App?",
        description: String = "Do you really want to exit the app?",
        positiveButton: String = "Cancel",
        negativeButton: String = "Exit",
        nativePlacement: String? = "native_large"
    ) {
        self.enabled = enabled
        self.title = title
        self.description = description
        self.positiveButton = positiveButton
        self.negativeButton = negativeButton
        self.nativePlacement = nativePlacement
    }
}

public struct MediaLibraryConfig: Codable, Sendable {
    public var kind: String
    public var enabled: Bool
    public var topTrendsLimit: Int
    public var placements: [String: MediaPlacementConfig]

    enum CodingKeys: String, CodingKey {
        case kind
        case enabled
        case topTrendsLimit = "top_trends_limit"
        case placements
    }

    public init(kind: String, enabled: Bool = false, topTrendsLimit: Int = 10, placements: [String: MediaPlacementConfig] = [:]) {
        self.kind = kind
        self.enabled = enabled
        self.topTrendsLimit = topTrendsLimit
        self.placements = placements
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? ""
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        topTrendsLimit = try values.decodeIfPresent(Int.self, forKey: .topTrendsLimit) ?? 10
        placements = (try? values.decode([String: MediaPlacementConfig].self, forKey: .placements)) ?? [:]
    }

}

private struct LossyBoolValue: Decodable {
    let value: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let integer = try? container.decode(Int.self) {
            value = integer != 0
        } else if let string = try? container.decode(String.self) {
            value = ["1", "true", "yes", "on", "enabled"].contains(string.lowercased())
        } else {
            value = nil
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyBoolDictionaryIfPresent(forKey key: Key) -> [String: Bool] {
        guard let values = try? decode([String: LossyBoolValue].self, forKey: key) else {
            return [:]
        }
        return values.compactMapValues(\.value)
    }
}

public struct MediaPlacementConfig: Codable, Sendable {
    public var name: String
    public var viewType: String
    public var enabled: Bool
    public var limit: Int
    public var columns: Int
    public var horizontal: Bool
    public var showTitle: Bool
    public var sort: String
    public var categoryMode: String
    public var contentSource: String
    public var categoryId: String?
    public var selectedItemIds: [String]
    public var rewardedPlacement: String?

    enum CodingKeys: String, CodingKey {
        case name
        case viewType = "view_type"
        case type
        case enabled
        case limit
        case columns
        case horizontal
        case showTitle = "show_title"
        case sort
        case categoryMode = "category_mode"
        case categoryDisplayMode = "category_display_mode"
        case contentSource = "content_source"
        case categoryId = "category_id"
        case selectedItemIds = "selected_item_ids"
        case rewardedPlacement = "rewarded_placement"
        case premiumUnlockPlacement = "premium_unlock_placement"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        viewType = try values.decodeIfPresent(String.self, forKey: .viewType)
            ?? values.decodeIfPresent(String.self, forKey: .type)
            ?? "items"
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        limit = try values.decodeIfPresent(Int.self, forKey: .limit) ?? 60
        columns = try values.decodeIfPresent(Int.self, forKey: .columns) ?? 1
        horizontal = try values.decodeIfPresent(Bool.self, forKey: .horizontal) ?? false
        showTitle = try values.decodeIfPresent(Bool.self, forKey: .showTitle) ?? true
        sort = try values.decodeIfPresent(String.self, forKey: .sort) ?? "trending"
        categoryMode = try values.decodeIfPresent(String.self, forKey: .categoryMode)
            ?? values.decodeIfPresent(String.self, forKey: .categoryDisplayMode)
            ?? "text"
        contentSource = try values.decodeIfPresent(String.self, forKey: .contentSource) ?? "entire_library"
        categoryId = try values.decodeIfPresent(String.self, forKey: .categoryId)
        selectedItemIds = try values.decodeIfPresent([String].self, forKey: .selectedItemIds) ?? []
        rewardedPlacement = try values.decodeIfPresent(String.self, forKey: .rewardedPlacement)
            ?? values.decodeIfPresent(String.self, forKey: .premiumUnlockPlacement)
            ?? "rewarded"
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(viewType, forKey: .viewType)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(limit, forKey: .limit)
        try values.encode(columns, forKey: .columns)
        try values.encode(horizontal, forKey: .horizontal)
        try values.encode(showTitle, forKey: .showTitle)
        try values.encode(sort, forKey: .sort)
        try values.encode(categoryMode, forKey: .categoryMode)
        try values.encode(contentSource, forKey: .contentSource)
        try values.encodeIfPresent(categoryId, forKey: .categoryId)
        try values.encode(selectedItemIds, forKey: .selectedItemIds)
        try values.encodeIfPresent(rewardedPlacement, forKey: .rewardedPlacement)
    }

    public init(
        name: String = "",
        viewType: String = "wallpapers",
        enabled: Bool = true,
        limit: Int = 60,
        columns: Int = 2,
        horizontal: Bool = false,
        showTitle: Bool = true,
        sort: String = "trending",
        categoryMode: String = "text",
        contentSource: String = "library",
        categoryId: String? = nil,
        selectedItemIds: [String] = [],
        rewardedPlacement: String? = "rewarded"
    ) {
        self.name = name
        self.viewType = viewType
        self.enabled = enabled
        self.limit = limit
        self.columns = columns
        self.horizontal = horizontal
        self.showTitle = showTitle
        self.sort = sort
        self.categoryMode = categoryMode
        self.contentSource = contentSource
        self.categoryId = categoryId
        self.selectedItemIds = selectedItemIds
        self.rewardedPlacement = rewardedPlacement
    }
}

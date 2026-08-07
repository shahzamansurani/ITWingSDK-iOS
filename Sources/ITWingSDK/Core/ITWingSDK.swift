import Foundation
import GoogleMobileAds
import UIKit

public enum ITWingSDK {
    /// Semantic version sent to the IT Wing backend with every SDK request.
    public static let version = "1.0.3"

    private static let lock = NSLock()
    private static var repository: ConfigRepository?
    private static var currentConfig: ITWingConfig = .empty
    private static var adsBlockedByHost = false
    private static var adsBlockedByEntitlement = false
    private static var adsBlockedByPurchaseFlow = false

    public static var interstitial = InterstitialManager(configProvider: { currentConfig })
    public static var rewarded = RewardedManager(configProvider: { currentConfig })
    public static var appOpen = AppOpenManager(configProvider: { currentConfig })

    public static var config: ITWingConfig {
        lock.lock()
        defer { lock.unlock() }
        return currentConfig
    }

    static var repo: ConfigRepository? {
        repository
    }

    public static func initialize(apiKey: String, options: ITWingOptions = .default) {
        let repo = ConfigRepository(apiKey: apiKey, options: options)
        repository = repo
        AnalyticsClient.shared.configure(repository: repo)
        AnalyticsClient.shared.track("sdk_initialized", properties: ["platform": "ios"])
        AnalyticsClient.shared.track("app_open")
        AnalyticsClient.shared.track("session_start")

        Task {
            if let cached = repo.loadCachedConfig() {
                setConfig(cached)
                if #available(iOS 15.0, *) { await ITWingSubscriptionManager.shared.sync() }
                AnalyticsClient.shared.track("sdk_cached_config_loaded", properties: ["config_version": cached.configVersion])
                await MainActor.run {
                    MobileAds.shared.start(completionHandler: nil)
                    appOpen.startAutomaticPresentation()
                }
            }

            do {
                let remote = try await repo.bootstrap()
                setConfig(remote)
                if #available(iOS 15.0, *) { await ITWingSubscriptionManager.shared.sync() }
                AnalyticsClient.shared.track("sdk_config_loaded", properties: ["config_version": remote.configVersion])
                await MainActor.run {
                    MobileAds.shared.start(completionHandler: nil)
                    if remote.notifications.promptForPermission {
                        ITWingNotificationManager.shared.requestPermission()
                    }
                    appOpen.startAutomaticPresentation()
                }
            } catch {
                NSLog("[ITWingSDK] bootstrap failed: %@", String(describing: error))
                AnalyticsClient.shared.track("sdk_bootstrap_failed", properties: ["message": error.localizedDescription])
            }
        }
    }

    public static func refreshConfig() async throws {
        guard let repository else { return }
        if let config = try await repository.syncConfig(lastVersion: currentConfig.configVersion) {
            setConfig(config)
        }
    }

    public static func isReady() -> Bool {
        currentConfig.configVersion > 0
    }

    public static func isFeatureEnabled(_ key: String, defaultValue: Bool = false) -> Bool {
        currentConfig.features[key] ?? defaultValue
    }

    public static func string(_ key: String, defaultValue: String = "") -> String {
        currentConfig.remoteConfig[key] ?? defaultValue
    }

    public static func apiKey(_ key: String, defaultValue: String = "") -> String {
        guard let config = currentConfig.apiKeys[key], !config.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        reportApiKeyUsage(key, config: config)
        return config.value
    }

    public static func getApiKey(_ key: String, defaultValue: String = "") -> String {
        apiKey(key, defaultValue: defaultValue)
    }

    public static func apiBaseUrl(_ key: String, defaultValue: String = "") -> String {
        normalizeBaseUrl(currentConfig.apiKeys[key]?.baseUrl) ?? normalizeBaseUrl(defaultValue) ?? defaultValue
    }

    public static func getApiBaseUrl(_ key: String, defaultValue: String = "") -> String {
        apiBaseUrl(key, defaultValue: defaultValue)
    }

    public static func appTitle(defaultValue: String = "") -> String {
        currentConfig.app.title ?? currentConfig.app.name ?? defaultValue
    }

    public static func logoUrl() -> URL? {
        [currentConfig.app.splashLogoUrl, currentConfig.app.launcherIconUrl, currentConfig.app.iconUrl]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    public static func getColor(_ name: String, defaultValue: String = "") -> String {
        currentConfig.app.colors[name] ?? defaultValue
    }

    public static func appUrl(_ kind: String) -> String? {
        switch kind {
        case "privacy", "privacy_policy":
            return currentConfig.app.legal["privacy_policy"]?.url ?? currentConfig.app.privacyPolicyUrl
        case "terms": return currentConfig.app.legal["terms"]?.url ?? currentConfig.app.termsUrl
        case "disclaimer": return currentConfig.app.legal["disclaimer"]?.url ?? currentConfig.app.disclaimerUrl
        default: return nil
        }
    }

    public static func legalContent(_ kind: String) -> String? {
        let key = kind == "privacy" ? "privacy_policy" : kind
        return config.app.legal[key]?.content
            ?? (key == "privacy_policy" ? config.app.legal["privacy"]?.content : nil)
    }

    public static func subscriptionProducts() -> [SubscriptionProductConfig] {
        currentConfig.subscriptions.products
    }

    public static func isAdFree() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adsBlockedByEntitlement
    }

    public static func currentSubscription() -> ITWingActiveSubscription? {
        if #available(iOS 15.0, *) {
            return ITWingSubscriptionManager.shared.activeSubscription
        }
        return nil
    }

    public static func billingDiagnostics() -> [String: Any] {
        if #available(iOS 15.0, *) {
            return ITWingSubscriptionManager.shared.diagnostics()
        }

        return [
            "configured_products": currentConfig.subscriptions.products.map(\.productId),
            "loaded_store_products": [],
            "missing_store_products": currentConfig.subscriptions.products.map(\.productId),
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "last_storekit_message": "StoreKit purchases require iOS 15 or later.",
        ]
    }

    public static func setAdsBlocked(_ blocked: Bool) {
        lock.lock()
        guard adsBlockedByHost != blocked else {
            lock.unlock()
            return
        }
        adsBlockedByHost = blocked
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .itwingAdsAvailabilityDidChange, object: nil)
        }
    }

    public static func canRequestAds() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentConfig.ads.globalEnabled && !adsBlockedByHost && !adsBlockedByEntitlement && !adsBlockedByPurchaseFlow
    }

    /// User-initiated rewarded ads must remain available while a host app has
    /// paused inline/background ads (for example, during an active VPN tunnel).
    static func canRequestRewardedAds() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentConfig.ads.globalEnabled && !adsBlockedByEntitlement && !adsBlockedByPurchaseFlow
    }

    static func setPremiumAdsBlocked(_ blocked: Bool) {
        lock.lock()
        let changed = adsBlockedByEntitlement != blocked
        adsBlockedByEntitlement = blocked
        lock.unlock()
        if changed {
            DispatchQueue.main.async {
                if blocked {
                    interstitial.clearCachedAds()
                    rewarded.clearCachedAds()
                    appOpen.clearCachedAds()
                }
                NotificationCenter.default.post(name: .itwingAdsAvailabilityDidChange, object: nil)
                NotificationCenter.default.post(name: .itwingPremiumEntitlementDidChange, object: nil)
            }
        }
    }

    static func setPurchaseFlowAdsBlocked(_ blocked: Bool) {
        lock.lock()
        let changed = adsBlockedByPurchaseFlow != blocked
        adsBlockedByPurchaseFlow = blocked
        lock.unlock()
        if changed {
            DispatchQueue.main.async {
                if blocked {
                    interstitial.clearCachedAds()
                    rewarded.clearCachedAds()
                    appOpen.clearCachedAds()
                }
                NotificationCenter.default.post(name: .itwingAdsAvailabilityDidChange, object: nil)
            }
        }
    }

    public static func uiColor(_ name: String, defaultValue: UIColor) -> UIColor {
        UIColor.itwingHex(getColor(name, defaultValue: ""), fallback: defaultValue)
    }

    public static func showLoadingDialog(from presenter: UIViewController, title: String = "Loading") -> ITWingLoadingHandle {
        ITWingUI.showLoading(from: presenter, title: title)
    }

    public static func showActionDialog(
        from presenter: UIViewController,
        title: String? = nil,
        message: String? = nil,
        positive: String? = nil,
        negative: String? = nil,
        onResult: @escaping (ITWingDialogResult) -> Void
    ) {
        ITWingUI.showActionDialog(from: presenter, title: title, message: message, positive: positive, negative: negative, onResult: onResult)
    }

    public static func fetchWallpapers(placement: String? = nil, categoryId: String? = nil, limit: Int? = nil, sort: String? = nil) async throws -> MediaLibraryResponse {
        try await repositoryOrThrow().fetchMedia(kind: "wallpapers", placement: placement, categoryId: categoryId, limit: limit, sort: sort)
    }

    public static func fetchRingtones(placement: String? = nil, categoryId: String? = nil, limit: Int? = nil, sort: String? = nil) async throws -> MediaLibraryResponse {
        try await repositoryOrThrow().fetchMedia(kind: "ringtones", placement: placement, categoryId: categoryId, limit: limit, sort: sort)
    }

    public static func fetchVideos(placement: String? = nil, categoryId: String? = nil, limit: Int? = nil, sort: String? = nil) async throws -> MediaLibraryResponse {
        try await repositoryOrThrow().fetchMedia(kind: "videos", placement: placement, categoryId: categoryId, limit: limit, sort: sort)
    }

    public static func fetchVpnServers(placement: String? = nil, categoryId: String? = nil, limit: Int? = nil, sort: String? = nil) async throws -> MediaLibraryResponse {
        try await repositoryOrThrow().fetchMedia(kind: "vpn_servers", placement: placement, categoryId: categoryId, limit: limit, sort: sort)
    }

    public static func trackMediaEvent(kind: String, itemId: String, eventType: String, metadata: [String: Any] = [:]) {
        guard let repository else { return }
        Task {
            try? await repository.submitMediaEvent(kind: kind, itemId: itemId, eventType: eventType, metadata: metadata)
        }
    }

    public static func fetchCustomAds(format: String? = nil, placement: String? = nil) async throws -> [ITWingCustomAd] {
        try await repositoryOrThrow().fetchCustomAds(format: format, placement: placement)
    }

    public static func trackCustomAdEvent(adId: String, eventType: String, metadata: [String: Any] = [:]) {
        guard let repository else { return }
        Task {
            try? await repository.submitCustomAdEvent(adId: adId, eventType: eventType, metadata: metadata)
        }
    }

    public static func trackCustomAdImpression(_ adId: String, metadata: [String: Any] = [:]) {
        trackCustomAdEvent(adId: adId, eventType: "impression", metadata: metadata)
    }

    public static func trackCustomAdClick(_ adId: String, metadata: [String: Any] = [:]) {
        trackCustomAdEvent(adId: adId, eventType: "click", metadata: metadata)
    }

    public static func registerPushToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        registerPushToken(token)
    }

    public static func registerPushToken(_ token: String) {
        guard let repository, !token.isEmpty else { return }
        Task {
            try? await repository.registerPushToken(token)
        }
    }

    public static func requestNotificationPermission() {
        ITWingNotificationManager.shared.requestPermission()
    }

    private static func setConfig(_ config: ITWingConfig) {
        lock.lock()
        currentConfig = config
        lock.unlock()
        DispatchQueue.main.async {
            configureAdMobTestDevices(testMode: config.ads.testMode)
            NotificationCenter.default.post(name: .itwingConfigDidChange, object: nil)
            // Google explicitly permits loading only after Mobile Ads startup.
            // Waiting for this completion also prevents the first rewarded
            // request from racing SDK initialization on a cold launch.
            MobileAds.shared.start { _ in
                DispatchQueue.main.async {
                    if canRequestAds() {
                        interstitial.load("interstitial")
                        rewarded.load("rewarded")
                    }
                }
            }
        }
    }

    /// Test-device hashes are app/device specific, so host apps provide them
    /// through Info.plist. They are applied only while the backend's iOS test
    /// mode is enabled and are cleared for production delivery.
    private static func configureAdMobTestDevices(testMode: Bool) {
        guard testMode else {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
            return
        }
        let configured = Bundle.main.object(forInfoDictionaryKey: "ITWING_ADMOB_TEST_DEVICE_IDS") as? [String] ?? []
        let identifiers = configured
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = identifiers
        if !identifiers.isEmpty {
            NSLog("[ITWingSDK] configured %ld AdMob test device(s)", identifiers.count)
        }
    }

    private static func repositoryOrThrow() throws -> ConfigRepository {
        guard let repository else { throw ConfigError.invalidResponse }
        return repository
    }

    private static func reportApiKeyUsage(_ key: String, config: ApiKeyConfig) {
        guard let repository else { return }
        Task {
            do {
                let shouldRotate = try await repository.reportApiKeyUsage(configKey: key, selectedKeyId: config.id)
                if shouldRotate {
                    try? await refreshConfig()
                }
            } catch {
                AnalyticsClient.shared.track("api_key_usage_report_failed", properties: ["key": key, "message": error.localizedDescription])
            }
        }
    }

    private static func normalizeBaseUrl(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") else {
            return nil
        }
        if !value.hasSuffix("/") {
            value += "/"
        }
        return value
    }
}

extension Notification.Name {
    static let itwingConfigDidChange = Notification.Name("ITWingSDK.configDidChange")
    static let itwingAdsAvailabilityDidChange = Notification.Name("ITWingSDK.adsAvailabilityDidChange")
    static let itwingPremiumEntitlementDidChange = Notification.Name("ITWingSDK.premiumEntitlementDidChange")
}

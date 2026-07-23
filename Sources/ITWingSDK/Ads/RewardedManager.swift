import Foundation
import GoogleMobileAds
import UIKit

public final class RewardedManager: NSObject, FullScreenContentDelegate {
    private enum LoadFailure: LocalizedError {
        case timeout
        var errorDescription: String? { "The rewarded ad did not load before the configured timeout." }
    }
    private let configProvider: () -> ITWingConfig
    private let frequency = FrequencyController()
    private var ads: [String: RewardedAd] = [:]
    // Google full-screen ads must remain strongly owned for the entire
    // presentation. The cache relinquishes ownership when an ad is consumed.
    private var activeAd: RewardedAd?
    private var activePlacementName: String?
    private var rewardEarned = false
    private var pendingReward: (() -> Void)?
    private weak var activePresenter: UIViewController?
    private var activeLoadToken: UUID?
    private var activeLoadingHandle: ITWingLoadingHandle?
    private var isPresentingRewarded = false
    private var presentationPending = false
    private var loadingPlacements: Set<String> = []
    private var lastLoadAttemptAt: [String: Date] = [:]
    private let minimumLoadInterval: TimeInterval = 20
    private var waitingPlacements: Set<String> = []
    private var waitTokens: [String: UUID] = [:]
    private var fullScreenToken: UUID?

    init(configProvider: @escaping () -> ITWingConfig) {
        self.configProvider = configProvider
    }

    var hasActiveFullScreenRequest: Bool {
        isPresentingRewarded || presentationPending || !waitingPlacements.isEmpty || activeAd != nil
    }

    public func load(_ placementName: String) {
        guard ITWingSDK.canRequestRewardedAds(),
              let placement = placement(named: placementName),
              let unit = placement.units.first(where: { $0.network == "admob" }),
              !loadingPlacements.contains(placementName),
              canStartPreload(placementName) else { return }
        loadingPlacements.insert(placementName)
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "rewarded", "network": "admob"])

        Task { @MainActor in
            defer { self.loadingPlacements.remove(placementName) }
            do {
                let ad = try await loadRewardedAd(unitId: unit.adUnitId)
                ad.fullScreenContentDelegate = self
                ad.paidEventHandler = { adValue in
                    AnalyticsClient.shared.track("ad_paid", properties: [
                        "placement": placementName,
                        "format": "rewarded",
                        "network": "admob",
                        "revenue_micros": Int((adValue.value.doubleValue * 1_000_000).rounded()),
                        "currency": adValue.currencyCode,
                        "precision": adValue.precision.rawValue,
                        "ad_unit_id": unit.adUnitId,
                    ])
                }
                ads[placementName] = ad
                AnalyticsClient.shared.track("ad_loaded", properties: ["placement": placementName, "format": "rewarded", "network": "admob"])
            } catch {
                AnalyticsClient.shared.track("rewarded_load_failed", properties: ["placement": placementName])
            }
        }
    }

    private func canStartPreload(_ placementName: String) -> Bool {
        let now = Date()
        if let previous = lastLoadAttemptAt[placementName],
           now.timeIntervalSince(previous) < minimumLoadInterval { return false }
        lastLoadAttemptAt[placementName] = now
        return true
    }

    public func show(from viewController: UIViewController, placement placementName: String, onReward: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                self.show(from: viewController, placement: placementName, onReward: onReward)
            }
            return
        }
        guard !isPresentingRewarded && !presentationPending else {
            showRetryCancel(
                from: viewController,
                placementName: placementName,
                message: "Another rewarded ad is already open. Close it and try again.",
                onReward: onReward
            )
            return
        }
        // A second tap must not create another network request or another
        // dialog while the first user-initiated request is still waiting.
        guard !waitingPlacements.contains(placementName) else { return }
        // Rewarded show never owns a modal loader. It either presents a
        // preloaded ad immediately or offers an explicit Retry/Cancel dialog.
        activeLoadToken = nil
        activeLoadingHandle?.dismiss()
        activeLoadingHandle = nil
        let presenter = ITWingUI.presentationHost(fallback: viewController)
        guard ITWingSDK.canRequestRewardedAds() else {
            AnalyticsClient.shared.track("ad_suppressed", properties: ["placement": placementName, "format": "rewarded", "reason": "global_disabled"])
            ITWingUI.showError(from: presenter, title: "Ad unavailable", message: "Rewarded ads are disabled for iOS in the admin panel.")
            return
        }
        guard let placement = placement(named: placementName) else {
            AnalyticsClient.shared.track("ad_suppressed", properties: ["placement": placementName, "format": "rewarded", "reason": "placement_missing"])
            ITWingUI.showError(from: presenter, title: "Ad unavailable", message: "The rewarded placement is missing or disabled.")
            return
        }
        guard frequency.canShow(placement, countTrigger: true) else {
            AnalyticsClient.shared.track("ad_suppressed", properties: ["placement": placementName, "format": "rewarded", "reason": "frequency_cap"])
            ITWingUI.showError(from: presenter, title: "Ad unavailable", message: "This rewarded placement has reached its frequency limit.")
            return
        }
        guard let token = FullScreenAdCoordinator.shared.tryBegin() else {
            frequency.refundTrigger(placement)
            showRetryCancel(
                from: presenter,
                placementName: placementName,
                message: "Another full-screen ad is already open. Close it and try again.",
                onReward: onReward
            )
            return
        }
        fullScreenToken = token
        if let customAd = placement.selectedCustomAd(in: configProvider()) {
            presentCustomRewarded(customAd, placement: placement, from: presenter, onReward: onReward, network: "custom")
            return
        }

        guard let ad = ads.removeValue(forKey: placementName) else {
            load(placementName)
            AnalyticsClient.shared.track("ad_not_ready", properties: ["placement": placementName, "format": "rewarded"])
            waitForPreloadedAdAndShow(
                from: presenter,
                placementName: placementName,
                onReward: onReward
            )
            return
        }

        presentLoadedAd(
            ad,
            placement: placement,
            placementName: placementName,
            from: presenter,
            onReward: onReward
        )
    }

    /// Matches Android's RewardedAdPreloader flow: one user action starts (or
    /// joins) one load, waits for the configured bounded period, and presents
    /// automatically as soon as the cached ad becomes available.
    private func waitForPreloadedAdAndShow(
        from viewController: UIViewController,
        placementName: String,
        onReward: @escaping () -> Void
    ) {
        guard !waitingPlacements.contains(placementName) else { return }
        waitingPlacements.insert(placementName)
        let token = UUID()
        waitTokens[placementName] = token
        let timeoutMilliseconds = max(1_500, min(configProvider().app.loadingAdTimeoutMs, 10_000))
        let startedAt = Date()
        let loading = ITWingUI.showLoading(
            from: ITWingUI.presentationHost(fallback: viewController),
            title: ""
        )
        activeLoadingHandle = loading

        func finishWaiting() {
            waitingPlacements.remove(placementName)
            waitTokens.removeValue(forKey: placementName)
            activeLoadingHandle = nil
        }

        func poll() {
            guard waitTokens[placementName] == token else { return }
            if let ad = ads.removeValue(forKey: placementName),
               let placement = placement(named: placementName) {
                finishWaiting()
                loading.dismiss { [weak self, weak viewController] in
                    guard let self, let viewController else { return }
                    self.presentLoadedAd(
                        ad,
                        placement: placement,
                        placementName: placementName,
                        from: viewController,
                        onReward: onReward
                    )
                }
                return
            }

            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            if elapsedMilliseconds >= timeoutMilliseconds {
                finishWaiting()
                loading.dismiss { [weak self, weak viewController] in
                    guard let self, let viewController else { return }
                    if let placement = self.placement(named: placementName),
                       let fallback = placement.fallbackCustomAd(in: self.configProvider()) {
                        self.presentCustomRewarded(fallback, placement: placement, from: viewController, onReward: onReward, network: "custom_fallback")
                        return
                    }
                    self.showRetryCancel(
                        from: viewController,
                        placementName: placementName,
                        message: "The ad did not load within \(timeoutMilliseconds / 1_000) seconds. Check your connection and try again.",
                        onReward: onReward
                    )
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: poll)
    }

    private func showRetryCancel(
        from fallback: UIViewController,
        placementName: String,
        message: String,
        onReward: @escaping () -> Void,
        attempt: Int = 0
    ) {
        if !isPresentingRewarded && !presentationPending {
            FullScreenAdCoordinator.shared.end(fullScreenToken)
            fullScreenToken = nil
        }
        DispatchQueue.main.async { [weak self, weak fallback] in
            guard let self, let fallback else { return }
            let host = ITWingUI.presentationHost(fallback: fallback)
            guard host.viewIfLoaded?.window != nil else {
                guard attempt < 3 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak fallback] in
                    guard let self, let fallback else { return }
                    self.showRetryCancel(
                        from: fallback,
                        placementName: placementName,
                        message: message,
                        onReward: onReward,
                        attempt: attempt + 1
                    )
                }
                return
            }
            ITWingUI.showError(
                from: host,
                title: "Ad not ready",
                message: message,
                retry: { [weak self, weak host] in
                    guard let self, let host else { return }
                    self.show(from: host, placement: placementName, onReward: onReward)
                }
            )
        }
    }

    public func showWithOptIn(from viewController: UIViewController, placement placementName: String, onReward: @escaping () -> Void) {
        guard let placement = placement(named: placementName) else { return }
        ITWingUI.showActionDialog(
            from: viewController,
            title: (placement.metadata?["intro_title"] ?? nil) ?? "Rewarded ad",
            message: (placement.metadata?["intro_message"] ?? nil) ?? "Watch the full rewarded ad to continue.",
            positive: (placement.metadata?["intro_positive_text"] ?? nil) ?? "Watch Ad",
            negative: (placement.metadata?["intro_negative_text"] ?? nil) ?? "Skip"
        ) { [weak self, weak viewController] result in
            guard result == .positive, let viewController else { return }
            self?.show(from: viewController, placement: placementName, onReward: onReward)
        }
    }

    private func presentLoadedAd(
        _ ad: RewardedAd,
        placement: AdPlacementConfig,
        placementName: String,
        from presenter: UIViewController,
        onReward: @escaping () -> Void
    ) {
        let host = ITWingUI.presentationHost(fallback: presenter)
        guard host.viewIfLoaded?.window != nil else {
            ads[placementName] = ad
            showRetryCancel(
                from: presenter,
                placementName: placementName,
                message: "The ad screen is not ready yet. Please try again.",
                onReward: onReward
            )
            return
        }
        do {
            try ad.canPresent(from: host)
        } catch {
            load(placementName)
            showRetryCancel(
                from: host,
                placementName: placementName,
                message: "Google Mobile Ads could not present the loaded rewarded ad: \(error.localizedDescription)",
                onReward: onReward
            )
            return
        }

        activePlacementName = placementName
        activePresenter = host
        activeAd = ad
        rewardEarned = false
        pendingReward = onReward
        presentationPending = true
        NSLog("[ITWingSDK][Rewarded] presenting placement=%@", placementName)
        ad.present(from: host) {
            NSLog("[ITWingSDK][Rewarded] reward granted placement=%@", placementName)
            self.rewardEarned = true
            AnalyticsClient.shared.track("reward_earned", properties: [
                "placement": placementName,
                "format": "rewarded",
                "network": "admob",
            ])
        }
    }

    public func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let completedPlacement = activePlacementName
        NSLog(
            "[ITWingSDK][Rewarded] dismissed placement=%@ rewardEarned=%@",
            completedPlacement ?? "unknown",
            rewardEarned ? "true" : "false"
        )
        if let completedPlacement {
            AnalyticsClient.shared.track("ad_dismissed", properties: ["placement": completedPlacement, "format": "rewarded", "network": "admob"])
        }
        if rewardEarned {
            pendingReward?()
        }
        rewardEarned = false
        pendingReward = nil
        activeAd = nil
        activePresenter = nil
        activePlacementName = nil
        isPresentingRewarded = false
        presentationPending = false
        activeLoadingHandle = nil
        finishFullScreen()
        if let completedPlacement {
            load(completedPlacement)
        }
    }

    public func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let failedPlacement = activePlacementName
        NSLog("[ITWingSDK][Rewarded] presentation failed: %@", error.localizedDescription)
        if let failedPlacement {
            AnalyticsClient.shared.track("ad_show_failed", properties: ["placement": failedPlacement, "format": "rewarded", "network": "admob", "message": error.localizedDescription])
        }
        let rewardCallback = pendingReward
        let presenter = activePresenter
        rewardEarned = false
        pendingReward = nil
        activeAd = nil
        activePlacementName = nil
        isPresentingRewarded = false
        presentationPending = false
        activeLoadingHandle?.dismiss()
        activeLoadingHandle = nil
        activePresenter = nil
        if let failedPlacement,
           let placement = placement(named: failedPlacement),
           let fallback = placement.fallbackCustomAd(in: configProvider()),
           let presenter,
           let rewardCallback {
            presentCustomRewarded(fallback, placement: placement, from: presenter, onReward: rewardCallback, network: "custom_fallback")
        } else if let failedPlacement {
            if let placement = placement(named: failedPlacement) {
                frequency.refundTrigger(placement)
            }
            finishFullScreen()
            load(failedPlacement)
        }
    }

    public func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        NSLog("[ITWingSDK][Rewarded] will present placement=%@", activePlacementName ?? "unknown")
        presentationPending = false
        isPresentingRewarded = true
        if let activePlacementName {
            if let placement = placement(named: activePlacementName) {
                frequency.markShown(placement)
            }
            AnalyticsClient.shared.track(
                "ad_show_started",
                properties: ["placement": activePlacementName, "format": "rewarded", "network": "admob"]
            )
            AnalyticsClient.shared.track(
                "ad_impression",
                properties: ["placement": activePlacementName, "format": "rewarded", "network": "admob"]
            )
        }
    }

    private func loadAndShow(_ viewController: UIViewController, placementName: String, placement: AdPlacementConfig, loading: ITWingLoadingHandle, onReward: @escaping () -> Void) {
        guard let unit = placement.units.first(where: { $0.network == "admob" }),
              !unit.adUnitId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AnalyticsClient.shared.track("ad_suppressed", properties: ["placement": placementName, "format": "rewarded", "reason": "ios_unit_missing"])
            loading.dismiss {
                if let fallback = placement.fallbackCustomAd(in: self.configProvider()) {
                    self.presentCustomRewarded(fallback, placement: placement, from: viewController, onReward: onReward, network: "custom_fallback")
                } else {
                    ITWingUI.showError(from: ITWingUI.presentationHost(fallback: viewController), title: "Ad unavailable", message: "No iOS rewarded AdMob unit is configured for this placement.")
                }
            }
            return
        }
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "rewarded", "network": "admob"])
        let loadToken = UUID()
        activeLoadToken = loadToken
        let watchdogMilliseconds = max(1_500, min(configProvider().app.loadingAdTimeoutMs + 1_000, 11_000))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(watchdogMilliseconds)) { [weak self, weak viewController] in
            guard let self, self.activeLoadToken == loadToken else { return }
            self.activeLoadToken = nil
            loading.dismiss {
                self.activeLoadingHandle = nil
                guard let viewController else { return }
                if let fallback = placement.fallbackCustomAd(in: self.configProvider()) {
                    self.presentCustomRewarded(fallback, placement: placement, from: viewController, onReward: onReward, network: "custom_fallback")
                    return
                }
                ITWingUI.showError(
                    from: ITWingUI.presentationHost(fallback: viewController),
                    title: "Ad not ready",
                    message: "The rewarded ad did not become ready in time. Please try again."
                )
            }
        }
        Task { @MainActor in
            do {
                let ad = try await loadRewardedAd(unitId: unit.adUnitId)
                guard self.activeLoadToken == loadToken else { return }
                self.activeLoadToken = nil
                ad.fullScreenContentDelegate = self
                loading.dismiss {
                    self.activeLoadingHandle = nil
                    let host = ITWingUI.presentationHost(fallback: viewController)
                    self.activePlacementName = placementName
                    self.activePresenter = host
                    self.activeAd = ad
                    self.rewardEarned = false
                    self.pendingReward = onReward
                    self.isPresentingRewarded = true
                    ad.present(from: host) {
                        self.rewardEarned = true
                        AnalyticsClient.shared.track("reward_earned", properties: ["placement": placementName, "format": "rewarded", "network": "admob"])
                    }
                }
            } catch {
                guard self.activeLoadToken == loadToken else { return }
                self.activeLoadToken = nil
                AnalyticsClient.shared.track("rewarded_load_failed", properties: ["placement": placementName])
                loading.dismiss {
                    self.activeLoadingHandle = nil
                    if let fallback = placement.fallbackCustomAd(in: self.configProvider()) {
                        self.presentCustomRewarded(fallback, placement: placement, from: viewController, onReward: onReward, network: "custom_fallback")
                        return
                    }
                    ITWingUI.showError(
                        from: ITWingUI.presentationHost(fallback: viewController),
                        title: "Ad not ready",
                        message: "The ad could not be loaded: \(error.localizedDescription)",
                        retry: { self.show(from: ITWingUI.presentationHost(fallback: viewController), placement: placementName, onReward: onReward) }
                    )
                }
            }
        }
    }

    private func presentCustomRewarded(_ ad: ITWingCustomAd, placement: AdPlacementConfig, from presenter: UIViewController, onReward: @escaping () -> Void, network: String) {
        let controller = ITWingCustomFullScreenAdController(
            ad: ad,
            placement: placement,
            onReward: {
                AnalyticsClient.shared.track("reward_earned", properties: ["placement": placement.name, "format": "rewarded", "network": network])
                onReward()
            },
            onDismiss: { self.finishFullScreen() }
        )
        ITWingUI.presentationHost(fallback: presenter).present(controller, animated: true) {
            self.frequency.markShown(placement)
            AnalyticsClient.shared.track("ad_impression", properties: ["placement": placement.name, "format": "rewarded", "network": network])
        }
    }

    private func placement(named name: String) -> AdPlacementConfig? {
        configProvider().ads.placements.first { $0.name == name && $0.format == "rewarded" && $0.enabled }
    }

    private func finishFullScreen() {
        let token = fullScreenToken
        fullScreenToken = nil
        Task { @MainActor in
            InlineAdSafetyGate.shared.arm()
            FullScreenAdCoordinator.shared.end(token)
        }
    }

    @MainActor
    private func loadRewardedAd(unitId: String) async throws -> RewardedAd {
        let milliseconds = max(500, min(configProvider().app.loadingAdTimeoutMs, 10_000))
        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            Task { @MainActor in
                do {
                    let ad = try await RewardedAd.load(with: unitId, request: Request())
                    guard !completed else { return }
                    completed = true
                    continuation.resume(returning: ad)
                } catch {
                    guard !completed else { return }
                    completed = true
                    continuation.resume(throwing: error)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                guard !completed else { return }
                completed = true
                continuation.resume(throwing: LoadFailure.timeout)
            }
        }
    }
}

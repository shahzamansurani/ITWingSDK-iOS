import Foundation
import GoogleMobileAds
import UIKit

public final class InterstitialManager: NSObject, FullScreenContentDelegate {
    private let configProvider: () -> ITWingConfig
    private let frequency = FrequencyController()
    private var ads: [String: InterstitialAd] = [:]
    private var activePlacementName: String?
    private var pendingCompletion: (() -> Void)?
    private weak var pendingPresenter: UIViewController?
    private var loadingPlacements: Set<String> = []
    private var lastLoadAttemptAt: [String: Date] = [:]
    private let minimumLoadInterval: TimeInterval = 20

    init(configProvider: @escaping () -> ITWingConfig) {
        self.configProvider = configProvider
    }

    public func load(_ placementName: String) {
        guard ITWingSDK.canRequestAds(),
              let placement = placement(named: placementName),
              let unit = placement.units.first(where: { $0.network == "admob" }),
              !unit.adUnitId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !loadingPlacements.contains(placementName),
              canStartPreload(placementName) else { return }
        loadingPlacements.insert(placementName)
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "interstitial", "network": "admob"])

        Task { @MainActor in
            defer { self.loadingPlacements.remove(placementName) }
            do {
                let ad = try await InterstitialAd.load(with: unit.adUnitId, request: Request())
                ad.fullScreenContentDelegate = self
                ad.paidEventHandler = { adValue in
                    AnalyticsClient.shared.track("ad_paid", properties: [
                        "placement": placementName,
                        "format": "interstitial",
                        "network": "admob",
                        "revenue_micros": Int((adValue.value.doubleValue * 1_000_000).rounded()),
                        "currency": adValue.currencyCode,
                        "precision": adValue.precision.rawValue,
                        "ad_unit_id": unit.adUnitId,
                    ])
                }
                ads[placementName] = ad
                AnalyticsClient.shared.track("ad_loaded", properties: ["placement": placementName, "format": "interstitial", "network": "admob"])
            } catch {
                AnalyticsClient.shared.track("interstitial_load_failed", properties: ["placement": placementName])
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

    public func show(from viewController: UIViewController, placement placementName: String, onComplete: @escaping () -> Void = {}) {
        let presenter = ITWingUI.presentationHost(fallback: viewController)
        let loading = ITWingUI.showLoading(from: presenter, title: "")
        guard ITWingSDK.canRequestAds(),
              let placement = placement(named: placementName),
              frequency.canShow(placement, countTrigger: true) else {
            loading.dismiss(completion: onComplete)
            return
        }
        if let customAd = placement.selectedCustomAd(in: configProvider()) {
            loading.dismiss {
                let controller = ITWingCustomFullScreenAdController(ad: customAd, placement: placement) {
                    self.frequency.markShown(placement)
                    onComplete()
                }
                ITWingUI.presentationHost(fallback: presenter).present(controller, animated: true)
                AnalyticsClient.shared.track("ad_impression", properties: ["placement": placementName, "format": "interstitial", "network": "custom"])
            }
            return
        }
        guard let ad = ads.removeValue(forKey: placementName) else {
            // Match Android: keep the host action pending behind the SDK loading
            // dialog, load the requested ad, then continue only after dismissal
            // or a genuine load failure.
            loadAndShow(presenter, placementName: placementName, placement: placement, loading: loading, onComplete: onComplete)
            return
        }

        loading.dismiss {
            self.activePlacementName = placementName
            self.pendingCompletion = onComplete
            let host = ITWingUI.presentationHost(fallback: presenter)
            self.pendingPresenter = host
            ad.present(from: host)
            AnalyticsClient.shared.track("ad_impression", properties: ["placement": placementName, "format": "interstitial", "network": "admob"])
            self.frequency.markShown(placement)
        }
    }

    public func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let completedPlacement = activePlacementName
        if let completedPlacement {
            AnalyticsClient.shared.track("ad_dismissed", properties: ["placement": completedPlacement, "format": "interstitial", "network": "admob"])
        }
        activePlacementName = nil
        pendingPresenter = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
        if let completedPlacement {
            load(completedPlacement)
        }
    }

    public func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let failedPlacement = activePlacementName
        if let failedPlacement {
            AnalyticsClient.shared.track("ad_show_failed", properties: ["placement": failedPlacement, "format": "interstitial", "network": "admob", "message": error.localizedDescription])
        }
        activePlacementName = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        if let failedPlacement,
           let placement = placement(named: failedPlacement),
           let fallback = placement.fallbackCustomAd(in: configProvider()),
           let presenter = pendingPresenter {
            pendingPresenter = nil
            presentCustomFallback(fallback, placement: placement, from: presenter, onComplete: completion ?? {})
            return
        }
        pendingPresenter = nil
        completion?()
        if let failedPlacement {
            load(failedPlacement)
        }
    }

    private func loadAndShow(_ viewController: UIViewController, placementName: String, placement: AdPlacementConfig, loading: ITWingLoadingHandle, onComplete: @escaping () -> Void) {
        guard let unit = placement.units.first(where: { $0.network == "admob" }) else {
            loading.dismiss { self.presentFallbackIfAvailable(placement, from: viewController, onComplete: onComplete) }
            return
        }
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "interstitial", "network": "admob"])
        Task { @MainActor in
            do {
                let ad = try await InterstitialAd.load(with: unit.adUnitId, request: Request())
                ad.fullScreenContentDelegate = self
                ad.paidEventHandler = { adValue in
                    AnalyticsClient.shared.track("ad_paid", properties: [
                        "placement": placementName,
                        "format": "interstitial",
                        "network": "admob",
                        "revenue_micros": Int((adValue.value.doubleValue * 1_000_000).rounded()),
                        "currency": adValue.currencyCode,
                        "precision": adValue.precision.rawValue,
                        "ad_unit_id": unit.adUnitId,
                    ])
                }
                loading.dismiss {
                    self.activePlacementName = placementName
                    self.pendingCompletion = onComplete
                    let host = ITWingUI.presentationHost(fallback: viewController)
                    self.pendingPresenter = host
                    ad.present(from: host)
                    AnalyticsClient.shared.track("ad_impression", properties: ["placement": placementName, "format": "interstitial", "network": "admob"])
                    self.frequency.markShown(placement)
                }
            } catch {
                AnalyticsClient.shared.track("interstitial_load_failed", properties: ["placement": placementName])
                loading.dismiss { self.presentFallbackIfAvailable(placement, from: viewController, onComplete: onComplete) }
            }
        }
    }

    private func presentFallbackIfAvailable(_ placement: AdPlacementConfig, from presenter: UIViewController, onComplete: @escaping () -> Void) {
        guard let fallback = placement.fallbackCustomAd(in: configProvider()) else {
            onComplete()
            return
        }
        presentCustomFallback(fallback, placement: placement, from: presenter, onComplete: onComplete)
    }

    private func presentCustomFallback(_ ad: ITWingCustomAd, placement: AdPlacementConfig, from presenter: UIViewController, onComplete: @escaping () -> Void) {
        let controller = ITWingCustomFullScreenAdController(ad: ad, placement: placement) {
            self.frequency.markShown(placement)
            onComplete()
        }
        ITWingUI.presentationHost(fallback: presenter).present(controller, animated: true)
        AnalyticsClient.shared.track("ad_impression", properties: ["placement": placement.name, "format": "interstitial", "network": "custom_fallback"])
    }

    private func placement(named name: String) -> AdPlacementConfig? {
        configProvider().ads.placements.first { $0.name == name && $0.format == "interstitial" && $0.enabled }
    }
}

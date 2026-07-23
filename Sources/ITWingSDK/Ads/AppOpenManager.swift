import Foundation
import GoogleMobileAds
import UIKit

public final class AppOpenManager: NSObject, FullScreenContentDelegate {
    private let configProvider: () -> ITWingConfig
    private let frequency = FrequencyController()
    private var ad: AppOpenAd?
    private var activePlacementName: String?
    private var isShowing = false
    private var pendingCompletion: (() -> Void)?
    private var isLoading = false
    private var lastLoadAttemptAt: [String: Date] = [:]
    private let minimumLoadInterval: TimeInterval = 20
    private var observer: NSObjectProtocol?
    private var fullScreenToken: UUID?

    init(configProvider: @escaping () -> ITWingConfig) {
        self.configProvider = configProvider
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func startAutomaticPresentation() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showIfAvailable()
        }
        load()
    }

    public func load() {
        guard ITWingSDK.canRequestAds(),
              let placement = automaticPlacement(),
              let unit = placement.units.first(where: { $0.network == "admob" }),
              !isLoading,
              canStartPreload(placement.name) else { return }

        isLoading = true
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placement.name, "format": "app_open", "network": "admob"])
        Task { @MainActor in
            do {
                let loaded = try await AppOpenAd.load(with: unit.adUnitId, request: Request())
                loaded.fullScreenContentDelegate = self
                loaded.paidEventHandler = { adValue in
                    AnalyticsClient.shared.track("ad_paid", properties: [
                        "placement": placement.name,
                        "format": "app_open",
                        "network": "admob",
                        "revenue_micros": Int((adValue.value.doubleValue * 1_000_000).rounded()),
                        "currency": adValue.currencyCode,
                        "precision": adValue.precision.rawValue,
                        "ad_unit_id": unit.adUnitId,
                    ])
                }
                self.ad = loaded
                AnalyticsClient.shared.track("ad_loaded", properties: ["placement": placement.name, "format": "app_open", "network": "admob"])
            } catch {
                AnalyticsClient.shared.track("app_open_load_failed", properties: ["placement": placement.name])
            }
            self.isLoading = false
        }
    }

    public func showIfAvailable(from viewController: UIViewController? = nil, onComplete: (() -> Void)? = nil) {
        guard ITWingSDK.canRequestAds(),
              !ITWingSDK.rewarded.hasActiveFullScreenRequest,
              let placement = automaticPlacement(),
              frequency.canShow(placement, countTrigger: true),
              !isShowing else {
            onComplete?()
            return
        }

        guard let ad else {
            frequency.refundTrigger(placement)
            load()
            onComplete?()
            return
        }

        guard let root = viewController ?? UIApplication.shared.itwingTopViewController() else {
            frequency.refundTrigger(placement)
            onComplete?()
            return
        }
        // Automatic app-open ads must never stack over another modal. This is
        // the iOS equivalent of Android's global FullscreenAdState gate.
        guard root.presentedViewController == nil,
              !root.isBeingPresented,
              !root.isBeingDismissed,
              root.transitionCoordinator == nil else {
            frequency.refundTrigger(placement)
            onComplete?()
            return
        }
        guard let token = FullScreenAdCoordinator.shared.tryBegin() else {
            frequency.refundTrigger(placement)
            onComplete?()
            return
        }
        fullScreenToken = token
        isShowing = true
        pendingCompletion = onComplete
        activePlacementName = placement.name
        self.ad = nil
        ad.present(from: root)
        AnalyticsClient.shared.track("ad_impression", properties: ["placement": placement.name, "format": "app_open", "network": "admob"])
        frequency.markShown(placement)
    }

    public func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if let activePlacementName {
            AnalyticsClient.shared.track("ad_dismissed", properties: ["placement": activePlacementName, "format": "app_open", "network": "admob"])
        }
        activePlacementName = nil
        isShowing = false
        FullScreenAdCoordinator.shared.end(fullScreenToken)
        fullScreenToken = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
        load()
    }

    public func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let activePlacementName {
            AnalyticsClient.shared.track("ad_show_failed", properties: ["placement": activePlacementName, "format": "app_open", "network": "admob", "message": error.localizedDescription])
        }
        activePlacementName = nil
        isShowing = false
        FullScreenAdCoordinator.shared.end(fullScreenToken)
        fullScreenToken = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
        load()
    }

    private func automaticPlacement() -> AdPlacementConfig? {
        configProvider().ads.placements.first {
            $0.format == "app_open" &&
            $0.enabled &&
            (($0.metadata?["show_automatically"] ?? "true") ?? "true") != "false"
        }
    }

    private func canStartPreload(_ placementName: String) -> Bool {
        let now = Date()
        if let previous = lastLoadAttemptAt[placementName],
           now.timeIntervalSince(previous) < minimumLoadInterval { return false }
        lastLoadAttemptAt[placementName] = now
        return true
    }
}

private extension UIApplication {
    func itwingTopViewController(base: UIViewController? = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return itwingTopViewController(base: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return itwingTopViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return itwingTopViewController(base: presented)
        }
        return base
    }
}

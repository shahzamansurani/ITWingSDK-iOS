import Foundation
import GoogleMobileAds
import UIKit

public final class AppOpenManager: NSObject, FullScreenContentDelegate {
    private let configProvider: () -> ITWingConfig
    private let frequency = FrequencyController()
    private var ad: AppOpenAd?
    private var adLoadedAt: Date?
    private var activePlacementName: String?
    private var isShowing = false
    private var pendingCompletion: (() -> Void)?
    private var isLoading = false
    private var lastLoadAttemptAt: [String: Date] = [:]
    private let minimumLoadInterval: TimeInterval = 20
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var fullScreenToken: UUID?
    private var processForeground = false
    private var hasObservedForeground = false
    private var enteredBackgroundAt: Date?
    private var foregroundSessionID: UInt64 = 0

    init(configProvider: @escaping () -> ITWingConfig) {
        self.configProvider = configProvider
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public func startAutomaticPresentation() {
        guard lifecycleObservers.isEmpty else { return }
        processForeground = UIApplication.shared.applicationState == .active
        hasObservedForeground = processForeground
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.processForeground = false
            self.foregroundSessionID &+= 1
            self.debug("SKIP_INACTIVE")
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.processForeground = false
            self.enteredBackgroundAt = Date()
            UserDefaults.standard.set(true, forKey: Self.firstRunCompletedKey)
            self.foregroundSessionID &+= 1
            self.debug("SKIP_BACKGROUND")
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.didBecomeActive()
        })
        load()
    }

    private func didBecomeActive() {
        let returnedFromBackground = enteredBackgroundAt.map { Date().timeIntervalSince($0) >= Self.minimumResumeDuration } ?? false
        enteredBackgroundAt = nil
        processForeground = UIApplication.shared.applicationState == .active
        hasObservedForeground = true
        foregroundSessionID &+= 1
        let session = foregroundSessionID
        guard returnedFromBackground else {
            debug("SKIP_COLD_OR_SHORT_FOREGROUND")
            load()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeSettleDelay) { [weak self] in
            guard let self else { return }
            guard self.canPresent(session: session, from: nil) == nil else {
                self.debug(self.canPresent(session: session, from: nil) ?? "SKIP_POLICY")
                return
            }
            self.showIfAvailable(expectedSession: session)
        }
    }

    public func load() {
        guard ITWingSDK.canRequestAds(),
              let placement = automaticPlacement(),
              let unit = placement.units.first(where: { $0.network == "admob" }),
              !isLoading,
              !hasFreshAd,
              canStartPreload(placement.name) else { return }

        isLoading = true
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placement.name, "format": "app_open", "network": "admob"])
        Task { @MainActor in
            do {
                let loaded = try await AppOpenAd.load(with: unit.adUnitId, request: Request())
                guard ITWingSDK.canRequestAds() else {
                    self.isLoading = false
                    return
                }
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
                self.adLoadedAt = Date()
                AnalyticsClient.shared.track("ad_loaded", properties: ["placement": placement.name, "format": "app_open", "network": "admob"])
            } catch {
                AnalyticsClient.shared.track("app_open_load_failed", properties: ["placement": placement.name])
            }
            self.isLoading = false
        }
    }

    func clearCachedAds() {
        ad = nil
        adLoadedAt = nil
        isLoading = false
        lastLoadAttemptAt.removeAll()
    }

    /// Explicit callers (normally an SDK loading/splash flow) and the automatic
    /// resume observer converge on the same main-thread foreground policy gate.
    public func showIfAvailable(from viewController: UIViewController? = nil, onComplete: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self, weak viewController] in
            guard let self else { onComplete?(); return }
            self.showIfAvailable(from: viewController, expectedSession: self.foregroundSessionID, onComplete: onComplete)
        }
    }

    private func showIfAvailable(
        from viewController: UIViewController? = nil,
        expectedSession: UInt64,
        onComplete: (() -> Void)? = nil
    ) {
        if let reason = canPresent(session: expectedSession, from: viewController) {
            debug(reason)
            onComplete?()
            return
        }
        guard ITWingSDK.canRequestAds(),
              let placement = automaticPlacement(),
              frequency.canShow(placement, countTrigger: true),
              !isShowing else {
            onComplete?()
            return
        }
        guard hasFreshAd else {
            frequency.refundTrigger(placement)
            ad = nil
            adLoadedAt = nil
            load()
            onComplete?()
            return
        }
        guard let root = viewController ?? UIApplication.shared.itwingTopViewController() else {
            frequency.refundTrigger(placement)
            onComplete?()
            return
        }
        // Re-run immediately before reserving/presenting; a queued request
        // from a prior foreground session is never allowed to survive Home.
        guard canPresent(session: expectedSession, from: root) == nil,
              let token = FullScreenAdCoordinator.shared.tryBegin() else {
            frequency.refundTrigger(placement)
            debug("SKIP_FULLSCREEN_CONFLICT")
            onComplete?()
            return
        }
        guard let ad else {
            FullScreenAdCoordinator.shared.end(token)
            frequency.refundTrigger(placement)
            load()
            onComplete?()
            return
        }
        fullScreenToken = token
        isShowing = true
        pendingCompletion = onComplete
        activePlacementName = placement.name
        self.ad = nil
        ad.present(from: root)
    }

    public func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard let name = activePlacementName,
              let placement = configProvider().ads.placements.first(where: { $0.name == name }) else { return }
        frequency.markShown(placement)
        AnalyticsClient.shared.track("ad_impression", properties: ["placement": name, "format": "app_open", "network": "admob"])
        debug("SHOW")
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

    private func canPresent(session: UInt64, from viewController: UIViewController?) -> String? {
        let root = viewController ?? UIApplication.shared.itwingTopViewController()
        if let reason = AppOpenLifecycleGate.rejectionReason(
            applicationActive: UIApplication.shared.applicationState == .active,
            processForeground: processForeground,
            resumedActivityAvailable: root?.viewIfLoaded?.window != nil && root?.isBeingPresented == false && root?.isBeingDismissed == false,
            sessionMatches: session == foregroundSessionID,
            fullscreenConflict: FullScreenAdCoordinator.shared.wasRecentlyActive(within: Self.fullscreenSuppressionDuration),
            firstEverLaunch: !UserDefaults.standard.bool(forKey: Self.firstRunCompletedKey)
        ) { return reason }
        guard !isShowing else { return "SKIP_ALREADY_SHOWING" }
        guard !ITWingSDK.rewarded.hasActiveFullScreenRequest else { return "SKIP_FULLSCREEN_CONFLICT" }
        guard let root,
              root.transitionCoordinator == nil,
              root.presentedViewController == nil else { return "SKIP_NO_ACTIVE_PRESENTATION_CONTEXT" }
        guard automaticPlacement() != nil else { return "SKIP_PLACEMENT_DISABLED" }
        return nil
    }

    private var hasFreshAd: Bool {
        guard ad != nil, let adLoadedAt else { return false }
        return Date().timeIntervalSince(adLoadedAt) >= 0 && Date().timeIntervalSince(adLoadedAt) < Self.maximumAdAge
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
        if let previous = lastLoadAttemptAt[placementName], now.timeIntervalSince(previous) < minimumLoadInterval { return false }
        lastLoadAttemptAt[placementName] = now
        return true
    }

    private func debug(_ decision: String) {
        #if DEBUG
        let activity = UIApplication.shared.itwingTopViewController()
        let isResumed = UIApplication.shared.applicationState == .active && activity?.viewIfLoaded?.window != nil
        NSLog("[ITWingSDK][AppOpen] process_foreground=%@ activity_resumed=%@ session=%llu ad_ready=%@ decision=%@",
              String(processForeground), String(isResumed), foregroundSessionID, String(hasFreshAd), decision)
        #endif
    }

    private static let minimumResumeDuration: TimeInterval = 2
    private static let resumeSettleDelay: TimeInterval = 0.15
    private static let fullscreenSuppressionDuration: TimeInterval = 3
    private static let firstRunCompletedKey = "itwing_sdk_app_open_first_run_completed"
    private static let maximumAdAge: TimeInterval = 4 * 60 * 60
}

enum AppOpenLifecycleGate {
    static func rejectionReason(
        applicationActive: Bool,
        processForeground: Bool,
        resumedActivityAvailable: Bool,
        sessionMatches: Bool,
        fullscreenConflict: Bool,
        firstEverLaunch: Bool = false
    ) -> String? {
        guard !firstEverLaunch else { return "SKIP_FIRST_EVER_LAUNCH" }
        guard applicationActive, processForeground else { return "SKIP_BACKGROUND" }
        guard sessionMatches else { return "SKIP_STALE_FOREGROUND_SESSION" }
        guard resumedActivityAvailable else { return "SKIP_NO_RESUMED_ACTIVITY" }
        guard !fullscreenConflict else { return "SKIP_FULLSCREEN_CONFLICT" }
        return nil
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

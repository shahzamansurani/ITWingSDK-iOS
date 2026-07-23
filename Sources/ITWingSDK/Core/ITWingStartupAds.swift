import SwiftUI
import UIKit

public extension ITWingSDK {
    /// Runs the admin-configured splash delay and splash ad. Host apps only
    /// report whether first-run screens are still pending; placement selection,
    /// format selection, loading and fallback remain SDK-owned.
    static func runConfiguredSplash(
        startupScreensPending: Bool,
        from presenter: UIViewController? = nil,
        onComplete: @escaping () -> Void
    ) {
        Task {
            let deadline = Date().addingTimeInterval(15)
            while !isReady(), Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let seconds = min(15, max(0, config.app.splash.seconds))
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            await MainActor.run {
                guard !startupScreensPending else {
                    onComplete()
                    return
                }
                showConfiguredSplashAd(from: presenter, onComplete: onComplete)
            }
        }
    }

    /// Presents the configured splash placement immediately. `startAppFlow`
    /// uses this after its own splash delay; custom host-owned splash screens
    /// normally use `runConfiguredSplash` instead.
    @MainActor
    static func showConfiguredSplashAd(
        from presenter: UIViewController?,
        onComplete: @escaping () -> Void
    ) {
        let format = config.app.splash.adFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !["", "none", "no_ad", "disabled"].contains(format) else {
            onComplete()
            return
        }
        let matches = config.ads.placements.filter { $0.enabled && $0.format.lowercased() == format }
        let placement = matches.first {
            (($0.metadata?["splash"] ?? nil) ?? "false").itwingStartupBool ||
            (($0.metadata?["usage"] ?? nil) ?? "").lowercased() == "splash"
        } ?? matches.first { $0.name.lowercased().contains("splash") } ?? matches.first

        guard let placement,
              let host = presenter ?? UIApplication.shared.itwingStartupTopViewController else {
            onComplete()
            return
        }
        switch format {
        case "interstitial":
            interstitial.show(from: host, placement: placement.name, onComplete: onComplete)
        case "app_open":
            appOpen.showIfAvailable(from: host, onComplete: onComplete)
        default:
            onComplete()
        }
    }
}

/// Admin-driven onboarding ad used by any SwiftUI host. It mirrors Android's
/// activity/page/off scope behavior and creates the configured banner or native
/// renderer without requiring placement logic in the host app.
public struct ITWingOnboardingAd: View {
    public let pageIndex: Int
    @State private var configRevision = 0

    public init(pageIndex: Int) {
        self.pageIndex = pageIndex
    }

    public var body: some View {
        Group {
            if let resolved {
                if resolved.format == "banner" {
                    StartupBannerRepresentable(placement: resolved.placement)
                        .frame(height: 60)
                } else {
                    StartupNativeRepresentable(placement: resolved.placement)
                        .frame(height: resolved.isSmallNative ? 150 : 280)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .itwingConfigDidChange)) { _ in
            configRevision &+= 1
        }
    }

    private var resolved: (placement: String, format: String, isSmallNative: Bool)? {
        _ = configRevision
        let flow = ITWingSDK.config.startupFlow
        let scope = flow.onboardingAdScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard scope != "off", scope != "none" else { return nil }

        let pagePlacement = flow.onboardingPages.indices.contains(pageIndex)
            ? flow.onboardingPages[pageIndex].nativePlacement?.itwingStartupNonEmpty
            : nil
        let placement = scope == "page"
            ? pagePlacement
            : flow.onboardingActivityAdPlacement?.itwingStartupNonEmpty ?? pagePlacement
        guard let placement else { return nil }

        let configured = ITWingSDK.config.ads.placements.first { $0.enabled && $0.name == placement }
        guard configured != nil else { return nil }
        let format = configured?.format.lowercased()
            ?? flow.onboardingActivityAdFormat.lowercased()
        guard format == "banner" || format == "native" else { return nil }
        let template = ((configured?.metadata?["native_type"] ?? nil)
            ?? (configured?.metadata?["native_template"] ?? nil)
            ?? "large").lowercased()
        return (placement, format, template == "small")
    }
}

private struct StartupNativeRepresentable: UIViewRepresentable {
    let placement: String
    func makeUIView(context: Context) -> ITWingNativeAdView {
        let view = ITWingNativeAdView()
        view.placementName = placement
        return view
    }
    func updateUIView(_ view: ITWingNativeAdView, context: Context) {
        view.placementName = placement
    }
}

private struct StartupBannerRepresentable: UIViewRepresentable {
    let placement: String
    func makeUIView(context: Context) -> ITWingBannerView {
        let view = ITWingBannerView()
        view.placementName = placement
        return view
    }
    func updateUIView(_ view: ITWingBannerView, context: Context) {
        view.placementName = placement
    }
}

private extension UIApplication {
    var itwingStartupTopViewController: UIViewController? {
        func top(_ base: UIViewController?) -> UIViewController? {
            if let navigation = base as? UINavigationController { return top(navigation.visibleViewController) }
            if let tabs = base as? UITabBarController { return top(tabs.selectedViewController) }
            if let presented = base?.presentedViewController { return top(presented) }
            return base
        }
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return top(window?.rootViewController)
    }
}

private extension String {
    var itwingStartupNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var itwingStartupBool: Bool {
        ["1", "true", "yes", "on"].contains(trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

# ITWingSDK for iOS

`ITWingSDK` is the reusable iOS SDK for the IT Wing administration platform. It mirrors the Android SDK’s host-app model: initialize with one SDK key, then control ads, startup flow, legal content, UI colors, dialogs, media libraries, VPN server data, analytics, notifications, and subscriptions from the admin panel.

An executable SwiftUI demonstration is included in
[`Examples/ITWingSDKExample`](Examples/ITWingSDKExample). It links this package
locally and exercises the public APIs without adding example code to the SDK
library product.

## Requirements

- iOS 13 or newer
- Swift 5.9 or newer
- Xcode 15 or newer
- An iOS SDK key created in the IT Wing admin panel
- A valid AdMob iOS App ID in the host app when AdMob is enabled

## Swift Package Manager

In Xcode, open **File → Add Package Dependencies** and enter:

```text
https://github.com/shahzamansurani/ITWingSDK-iOS.git
```

Select a tagged version and add the `ITWingSDK` product to the app target.
The repository must have a semantic version tag such as `1.0.0` before Xcode
can resolve a version-based dependency.

For a `Package.swift` host:

```swift
dependencies: [
    .package(
        url: "https://github.com/shahzamansurani/ITWingSDK-iOS.git",
        from: "1.0.0"
    )
]
```

Then add `.product(name: "ITWingSDK", package: "ITWingSDK-iOS")` to the target dependencies.

## CocoaPods

```ruby
pod 'ITWingSDK', '~> 1.0'
```

## Required host configuration

When AdMob is enabled, add the platform-specific iOS App ID to the host app’s `Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

Use the iOS AdMob App ID, not an Android App ID. Add Google’s current SKAdNetwork identifiers as required by the Google Mobile Ads documentation and configure the host app’s App Privacy answers for the SDK features it enables.

## Minimal initialization

```swift
import ITWingSDK

ITWingSDK.initialize(apiKey: "YOUR_ITWING_IOS_SDK_KEY")
```

With a custom backend endpoint:

```swift
let options = ITWingOptions(
    endpoint: URL(string: "https://sdk.itwingtech.com/api/sdk/v1")!,
    bootstrapTimeout: 15
)
ITWingSDK.initialize(
    apiKey: "YOUR_ITWING_IOS_SDK_KEY",
    options: options
)
```

## Admin-managed startup flow

For UIKit apps, the SDK can own splash timing and ads, onboarding, terms, legal content, and the transition to the main screen:

```swift
import ITWingSDK
import UIKit

final class SplashViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        ITWingSDK.startAppFlow(
            apiKey: "YOUR_ITWING_IOS_SDK_KEY",
            from: self,
            config: ITWingStartAppFlowConfig(
                splashBackgroundView: view,
                mainFactory: { MainViewController() }
            )
        )
    }
}
```

SwiftUI hosts with their own splash screen can delegate the admin-controlled delay and splash ad:

```swift
ITWingSDK.runConfiguredSplash(
    startupScreensPending: false,
    onComplete: {
        // Open the main app UI.
    }
)
```

Use `ITWingOnboardingAd(pageIndex:)` inside a custom SwiftUI onboarding screen. The SDK resolves activity/page/off scope, placement, banner/native format, and native size from the admin panel.

## Ads

```swift
let banner = ITWingBannerView()
banner.placementName = "banner_adaptive"

let native = ITWingNativeAdView()
native.placementName = "native_large"

ITWingSDK.interstitial.show(
    from: viewController,
    placement: "interstitial"
) {
    // Called after dismissal or a genuine load/show failure.
}

ITWingSDK.rewarded.showWithOptIn(
    from: viewController,
    placement: "rewarded"
) {
    // Called only after the reward is earned and the ad is dismissed.
}
```

Real AdMob delivery has priority. Compatible custom campaigns are used only for explicitly custom placements or after the real ad fails to load or present.

VPN hosts should block SDK ad requests while a tunnel is active:

```swift
ITWingSDK.setAdsBlocked(true)   // connected
ITWingSDK.setAdsBlocked(false)  // disconnected
```

## Admin-managed data and features

The package includes:

- Banner, native, interstitial, rewarded, and app-open ads
- Custom campaign fallback for supported ad formats
- Splash/onboarding/terms startup flow
- Reusable dialogs and loading UI
- Legal documents and remote app colors
- StoreKit subscription products and purchase verification
- APNs token registration and in-app notifications
- Analytics and media event tracking
- Wallpapers, ringtones, and video libraries
- VPN server and country/category libraries
- Remote API keys and feature flags

Examples:

```swift
let response = try await ITWingSDK.fetchVpnServers(
    placement: "vpn_servers",
    limit: 100,
    sort: "trending"
)

let privacy = ITWingSDK.legalContent("privacy")
let primary = ITWingSDK.getColor("primary")
let enabled = ITWingSDK.isFeatureEnabled("my_feature")
```

Forward the APNs token when notifications are enabled:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    ITWingSDK.registerPushToken(deviceToken)
}
```

## StoreKit subscriptions and in-app purchases

Create products in the app workspace under **iOS Purchases** using the exact
product IDs from App Store Connect. The SDK loads localized StoreKit pricing,
handles purchases and restores, listens for transaction updates, and sends
Apple's signed StoreKit 2 transaction to the IT Wing backend for certificate,
signature, bundle-ID, product-ID, expiry, and revocation verification.

Add the reusable admin-managed purchase view:

```swift
let premiumView = ITWingPremiumView()
```

Or start a purchase and restore directly:

```swift
ITWingSubscriptionManager.shared.showPurchaseDialog(from: viewController) { purchased in
    // Called after a completed purchase, restore, or dialog dismissal.
}

let restored = await ITWingSubscriptionManager.shared.restore(from: viewController)
```

If App Store Connect products are not appearing in a development, StoreKit
configuration, or TestFlight build, print diagnostics after initialization:

```swift
print(ITWingSDK.billingDiagnostics())
```

The output includes configured product IDs, loaded StoreKit product IDs,
missing product IDs, the app bundle ID, and the last StoreKit loading message.
The purchase dialog keeps actions enabled and shows the same StoreKit diagnostic
instead of disabling a product card.

Products marked **Removes ads** suppress SDK ads while their verified
subscription or non-consumable entitlement is active. Mark an in-app product
with `{"consumable": true}` in its admin metadata when it must be delivered
once rather than restored as a permanent entitlement.

## VPN limitation on iOS

The SDK supplies admin-managed VPN server data, categories, premium gating, ads, dialogs, and analytics. Apple requires each VPN host app to contain its own Network Extension target and entitlements, so the packet-tunnel provider cannot be shipped as a universally reusable normal app-library implementation.

## Versioning and release

The package follows semantic versioning. To publish a release:

```bash
git tag 1.0.0
git push origin 1.0.0
```

Host apps can then select `1.0.0` or use the `from: "1.0.0"` dependency rule.

See [MIGRATION.md](MIGRATION.md) when moving an existing host from the old
local `ITWingAds` module. The old local SDK can remain in place for projects
that have not migrated.

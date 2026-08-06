# Changelog

All notable changes to ITWingSDK are documented here.

## 1.0.2

- Matched the iOS purchase dialog to Android billing behavior with plan, billing, and price rows.
- Kept purchase actions enabled when StoreKit product details are temporarily missing and surfaced StoreKit diagnostics.
- Added public iOS billing diagnostics for configured, loaded, and missing App Store product IDs.

## 1.0.1

- Fixed App Store product config decoding when admin omits Android-only billing period fields.
- Added App Store subscription group metadata and stable original-transaction verification payloads.

## 1.0.0

- First standalone `ITWingSDK` Swift Package and CocoaPods release.
- Admin-managed configuration, startup flow, legal content, UI, analytics,
  notifications, subscriptions, media libraries, and VPN server data.
- AdMob banner, native, interstitial, rewarded, and app-open formats.
- Platform-aware custom campaign fallback.
- iOS privacy manifest.

# Changelog

All notable changes to ITWingSDK are documented here.

## 1.0.4

- Fixed `ITWingPremiumView` active-plan content being compressed or cropped in compact host layouts.
- Added an intrinsic premium-card height and internal scrolling so plan details and buttons remain accessible on small screens.

## 1.0.3

- Removed already-rendered inline ads and cleared cached full-screen ads immediately when a verified premium purchase disables ads.
- Blocked SDK ads during the App Store checkout and verification flow so app-open ads cannot appear before entitlement activation finishes.
- Added Android-parity active plan rows to the iOS premium view: plan, billing, price, and expiry.
- Added `ITWingSDK.isAdFree()` and `ITWingSDK.currentSubscription()` helpers for iOS host apps.

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

# Changelog

All notable changes to ITWingSDK are documented here.

## 1.6.6 — IT Wing SDK v1.49 companion release candidate

- Normalize supported ad component colors using the existing admin `app.colors` keys, including dedicated native and banner CTA colors and text colors.
- Align the safe default CTA/accent color with Android when admin colors are absent or malformed.
- Apply native and banner background/border presentation consistently to custom creatives where those fields are configured.
- Use the existing admin `media_shimmer_base_color` and `media_shimmer_highlight_color` values for ad shimmer, with generic/fallback colors when unset.
- Use the same normalized theme contract for fullscreen custom-ad text, badge, CTA, and background styling.
- Resolve custom native advertiser/meta text through the same `native_meta_text_color` / `native_secondary_text_color` app-color path as real native ads.
- Use one shared native card surface for real and custom creatives so their default gradient and configured solid background behavior cannot drift independently.
- Cancel pending custom-ad fetches when their views leave the window; invalidate old requests on placement changes and ignore stale banner/native callbacks from replaced or detached views.
- Ignore stale custom image/video readiness callbacks after a media view is reconfigured, preventing replaced creatives from becoming visible or recording readiness/impressions.
- Register the reusable inline creative CTA handler once, preventing repeated renders from multiplying click events; validate all custom-ad click/video and SDK media URLs as HTTP(S).
- Replace force-casts in media-library collection cell dequeue paths with graceful fallback cells.
- Validate custom creative, SDK media-player, and cached-image URLs through one HTTP(S) validator; release replaced media players and avoid cache-directory force unwraps.
- Load custom-ad images asynchronously with request/resource timeouts, a 12 MiB response cap, and ImageIO downsampling to a bounded pixel size; media fallback cache reads and JSON decoding also stay off the UI thread.
- Keep existing Swift Package Manager product, deployment target, public API, and v1.48 host integration unchanged.

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

# ITWingSDK iOS example

This app mirrors the Android SDK example module and links the package from the
repository root. It demonstrates:

- Minimal SDK initialization and remote configuration refresh
- Complete SDK-owned splash, onboarding, terms, and main-screen startup flow
- Admin-managed app title, colors, legal links, and subscriptions
- Analytics and notification APIs
- SDK dialogs, loading UI, and premium view
- Banner, native-small, and native-large containers
- Interstitial, rewarded, app-open, splash, and onboarding ads
- Wallpaper, ringtone, video, and VPN-server SDK views

The package's automated unit tests remain in `../../Tests/ITWingSDKTests`.

## Run it

1. Open `ITWingSDKExample.xcodeproj`.
2. Select the `ITWingSDKExample` scheme.
3. In **Product → Scheme → Edit Scheme → Run → Arguments → Environment
   Variables**, add `ITWING_SDK_KEY` with an iOS SDK key from the admin panel.
4. Select an iPhone simulator or development device and run.

The committed `Info.plist` uses Google's iOS demo AdMob App ID. Admin-managed
test placements must use Google's iOS demo ad-unit IDs. Replace the App ID only
when testing a real iOS AdMob application.

No key or signing team is committed. Select your own development team when
running on a physical device.

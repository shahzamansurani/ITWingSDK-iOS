# Migrating from the local ITWingAds package

The standalone package intentionally uses the new module and API name:

```swift
import ITWingSDK

ITWingSDK.initialize(apiKey: "YOUR_IOS_SDK_KEY")
```

For a host app that previously imported the local package:

1. Remove only that host target's local `ITWingAds` package reference.
2. Add `https://github.com/itwingtechnologies/ITWingSDK-iOS.git`.
3. Link the `ITWingSDK` product to the host target.
4. Replace `import ITWingAds` with `import ITWingSDK`.
5. Replace calls beginning with `ITWingAds.` with `ITWingSDK.`.
6. Keep the host app's AdMob App ID, notification capabilities, and any
   Network Extension entitlements in the host app.

The original local `ios-sdk` project is independent and does not need to be
renamed, deleted, or published.


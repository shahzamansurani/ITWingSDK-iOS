import XCTest
import UIKit
@testable import ITWingSDK

final class ITWingSDKTests: XCTestCase {
    func testEmptyConfigurationIsSafe() {
        XCTAssertEqual(ITWingConfig.empty.configVersion, 0)
        XCTAssertFalse(ITWingConfig.empty.ads.globalEnabled)
        XCTAssertTrue(ITWingConfig.empty.ads.placements.isEmpty)
    }

    func testDefaultEndpointUsesHTTPS() {
        XCTAssertEqual(ITWingOptions.default.endpoint.scheme, "https")
    }

    func testInlineAdSizesProtectNativeMediaAndOverlays() {
        XCTAssertEqual(ITWingAdLayout.bannerHeight, 64)
        XCTAssertGreaterThanOrEqual(ITWingAdLayout.nativeSmallHeight, 190)
        XCTAssertGreaterThanOrEqual(ITWingAdLayout.nativeLargeHeight, 280)
        XCTAssertEqual(ITWingAdLayout.nativeSmallMediaHeight, 130)
        XCTAssertEqual(ITWingAdLayout.nativeLargeMediaHeight, 120)
        XCTAssertEqual(ITWingAdLayout.nativeSmallCTAHeight, 40)
        XCTAssertEqual(ITWingAdLayout.nativeLargeCTAHeight, 35)
    }

    func testAdCardRadiusPresetsAndMalformedValuesAreSafe() {
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("none"), 0)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("small"), 8)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("medium"), 12)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("large"), 16)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("extra_large"), 24)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("-4"), 0)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("junk"), 0)
        XCTAssertEqual(ITWingAdTheme.normalizedCardRadius("999"), 0)
    }

    func testAdCardSurfaceElevationAndBordersAreOptionalAndFormatAware() {
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("none"), 0)
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("subtle"), 2)
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("medium"), 6)
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("strong"), 10)
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("-1"), 0)
        XCTAssertEqual(ITWingAdTheme.normalizedCardElevation("junk"), 0)

        let values = [
            "native_card_elevation": "medium",
            "ad_card_elevation": "strong",
            "native_card_border_color": "#123456",
            "native_card_border_width": "thin",
            "native_card_padding": "comfortable",
        ]
        let provider: (String) -> String = { values[$0] ?? "" }
        let native = ITWingAdTheme.cardStyle(format: "native", appColorProvider: provider)
        let defaults = ITWingAdTheme.cardStyle(format: "banner", appColorProvider: { _ in "" })
        XCTAssertEqual(native.elevation, 6)
        XCTAssertEqual(native.borderWidth, 1)
        XCTAssertEqual(native.innerPadding, 12)
        XCTAssertEqual(defaults.elevation, 0)
        XCTAssertEqual(defaults.cornerRadius, 0)
        XCTAssertEqual(defaults.borderWidth, 0)
        XCTAssertEqual(defaults.innerPadding, 0)
        let invalidSpecific = ITWingAdTheme.cardStyle(
            format: "banner",
            appColorProvider: { $0 == "banner_card_elevation" ? "junk" : ($0 == "ad_card_elevation" ? "strong" : "") }
        )
        XCTAssertEqual(invalidSpecific.elevation, 10)
    }

    func testAppOpenPolicyRejectsBackgroundStaleAndConflictingPresentation() {
        XCTAssertEqual(AppOpenLifecycleGate.rejectionReason(
            applicationActive: true, processForeground: true, resumedActivityAvailable: true,
            sessionMatches: true, fullscreenConflict: false, firstEverLaunch: true
        ), "SKIP_FIRST_EVER_LAUNCH")
        XCTAssertNil(AppOpenLifecycleGate.rejectionReason(
            applicationActive: true, processForeground: true, resumedActivityAvailable: true,
            sessionMatches: true, fullscreenConflict: false
        ))
        XCTAssertEqual(AppOpenLifecycleGate.rejectionReason(
            applicationActive: false, processForeground: false, resumedActivityAvailable: true,
            sessionMatches: true, fullscreenConflict: false
        ), "SKIP_BACKGROUND")
        XCTAssertEqual(AppOpenLifecycleGate.rejectionReason(
            applicationActive: true, processForeground: true, resumedActivityAvailable: false,
            sessionMatches: true, fullscreenConflict: false
        ), "SKIP_NO_RESUMED_ACTIVITY")
        XCTAssertEqual(AppOpenLifecycleGate.rejectionReason(
            applicationActive: true, processForeground: true, resumedActivityAvailable: true,
            sessionMatches: false, fullscreenConflict: false
        ), "SKIP_STALE_FOREGROUND_SESSION")
        XCTAssertEqual(AppOpenLifecycleGate.rejectionReason(
            applicationActive: true, processForeground: true, resumedActivityAvailable: true,
            sessionMatches: true, fullscreenConflict: true
        ), "SKIP_FULLSCREEN_CONFLICT")
    }

    func testAdThemeParsesAndroidCompatibleHexFormats() {
        assertColor(ITWingAdTheme.parsed("#abc"), red: 170.0 / 255, green: 187.0 / 255, blue: 204.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.parsed("#8AbC"), red: 170.0 / 255, green: 187.0 / 255, blue: 204.0 / 255, alpha: 136.0 / 255)
        assertColor(ITWingAdTheme.parsed("#80112233"), red: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 128.0 / 255)
    }

    func testAdThemeRejectsMalformedColors() {
        for value in ["", "red", "#12", "#GGGGGG", "#123456789"] {
            XCTAssertNil(ITWingAdTheme.parsed(value), "Expected malformed color to be rejected: \(value)")
        }
    }

    func testAdThemeMetadataOverridesAppColorAndInvalidMetadataFallsThrough() {
        let metadataWins = ITWingAdTheme.color(
            metadata: ["native_cta_color": "#123456"],
            metadataKeys: ["native_cta_color"],
            appKeys: ["primary"],
            fallback: .black,
            appColorProvider: { _ in "#abcdef" }
        )
        assertColor(metadataWins, red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1)

        let invalidMetadataFallsThrough = ITWingAdTheme.color(
            metadata: ["native_cta_color": "not-a-color"],
            metadataKeys: ["native_cta_color"],
            appKeys: ["primary"],
            fallback: .black,
            appColorProvider: { _ in "#abcdef" }
        )
        assertColor(invalidMetadataFallsThrough, red: 171.0 / 255, green: 205.0 / 255, blue: 239.0 / 255, alpha: 1)
    }

    func testAdThemeUsesFallbackWhenConfiguredColorIsMalformed() {
        let fallback = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let resolved = ITWingAdTheme.color(
            appKeys: ["primary"],
            fallback: fallback,
            appColorProvider: { _ in "invalid" }
        )
        assertColor(resolved, red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    }

    func testWronglyTypedAdminColorDoesNotInvalidateAppConfiguration() throws {
        let json = ##"{"colors":{"primary":"#123456","native_cta_color":123,"banner_text_color":true}}"##.data(using: .utf8)!
        let app = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(app.colors["primary"], "#123456")
        XCTAssertEqual(app.colors["native_cta_color"], "123")
        XCTAssertEqual(app.colors["banner_text_color"], "true")

        let resolved = ITWingAdTheme.nativeCTA(appColorProvider: { app.colors[$0] ?? "" })
        assertColor(resolved, red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1)
    }

    func testCustomMediaImageDecodeIsDownsampledAndRejectsOversizedPayloads() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2300, height: 1700), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2300, height: 1700))
        }
        let encoded = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let decoded = try XCTUnwrap(MediaDiskCache.decodeImage(encoded))
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 2048)

        let oversized = Data(repeating: 0, count: (12 * 1024 * 1024) + 1)
        XCTAssertNil(MediaDiskCache.decodeImage(oversized))
    }

    func testCustomAdClickURLOnlyAllowsSafeWebTargetsAndFallsBack() {
        XCTAssertEqual(
            ITWingURLSafety.firstHTTPURL(["javascript:alert(1)", "https://example.com/path"])?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertNil(ITWingURLSafety.firstHTTPURL(["file:///etc/passwd", "https:example.com", "https://user:pass@example.com"]))
    }

    func testNativeMetaPrefersDedicatedAdminColorAndUsesSecondaryAlias() {
        let dedicated = ITWingAdTheme.nativeMeta(
            fallback: .black,
            appColorProvider: { $0 == "native_meta_text_color" ? "#112233" : "" }
        )
        assertColor(dedicated, red: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 1)

        let secondary = ITWingAdTheme.nativeMeta(
            fallback: .black,
            appColorProvider: { $0 == "native_secondary_text_color" ? "#445566" : "" }
        )
        assertColor(secondary, red: 68.0 / 255, green: 85.0 / 255, blue: 102.0 / 255, alpha: 1)
    }

    func testNativeAndBannerCTAUseDedicatedAdminColors() {
        let nativeCTA = ITWingAdTheme.nativeCTA(
            appColorProvider: { $0 == "native_cta_color" ? "#112233" : "#000000" }
        )
        let nativeText = ITWingAdTheme.nativeCTAText(
            appColorProvider: { $0 == "native_cta_text_color" ? "#223344" : "#000000" }
        )
        let bannerCTA = ITWingAdTheme.bannerCTA(
            appColorProvider: { $0 == "banner_cta_color" ? "#334455" : "#000000" }
        )
        let bannerText = ITWingAdTheme.bannerCTAText(
            appColorProvider: { $0 == "banner_cta_text_color" ? "#445566" : "#000000" }
        )

        assertColor(nativeCTA, red: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 1)
        assertColor(nativeText, red: 34.0 / 255, green: 51.0 / 255, blue: 68.0 / 255, alpha: 1)
        assertColor(bannerCTA, red: 51.0 / 255, green: 68.0 / 255, blue: 85.0 / 255, alpha: 1)
        assertColor(bannerText, red: 68.0 / 255, green: 85.0 / 255, blue: 102.0 / 255, alpha: 1)
    }

    func testEveryBackendDefinedAdColorRoleResolvesFromAppColors() {
        let colors = [
            "native_text_color": "#010101",
            "native_secondary_text_color": "#020202",
            "native_meta_text_color": "#030303",
            "native_background_color": "#040404",
            "native_stroke_color": "#050505",
            "native_ad_label_text_color": "#060606",
            "native_ad_label_background_color": "#070707",
            "native_cta_color": "#080808",
            "native_cta_text_color": "#090909",
            "banner_text_color": "#0A0A0A",
            "banner_background_color": "#0B0B0B",
            "banner_stroke_color": "#0C0C0C",
            "banner_cta_color": "#0D0D0D",
            "banner_cta_text_color": "#0E0E0E",
            "cta_text_color": "#0F0F0F",
            "ad_label_text_color": "#101010",
        ]
        let appColor: (String) -> String = { colors[$0] ?? "" }

        assertColor(ITWingAdTheme.nativeHeadline(fallback: .black, appColorProvider: appColor), red: 1.0 / 255, green: 1.0 / 255, blue: 1.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeBody(fallback: .black, appColorProvider: appColor), red: 2.0 / 255, green: 2.0 / 255, blue: 2.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeMeta(fallback: .black, appColorProvider: appColor), red: 3.0 / 255, green: 3.0 / 255, blue: 3.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeBackground(appColorProvider: appColor), red: 4.0 / 255, green: 4.0 / 255, blue: 4.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeBorder(appColorProvider: appColor), red: 5.0 / 255, green: 5.0 / 255, blue: 5.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeLabelText(appColorProvider: appColor), red: 6.0 / 255, green: 6.0 / 255, blue: 6.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeLabel(appColorProvider: appColor), red: 7.0 / 255, green: 7.0 / 255, blue: 7.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.nativeCTA(appColorProvider: appColor), red: 8.0 / 255, green: 8.0 / 255, blue: 8.0 / 255, alpha: 1)
        assertColor(
            ITWingAdTheme.nativeCTA(appColorProvider: { $0 == "primary" ? "#171717" : "" }),
            red: 23.0 / 255,
            green: 23.0 / 255,
            blue: 23.0 / 255,
            alpha: 1
        )
        assertColor(ITWingAdTheme.nativeCTAText(appColorProvider: appColor), red: 9.0 / 255, green: 9.0 / 255, blue: 9.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerText(fallback: .black, appColorProvider: appColor), red: 10.0 / 255, green: 10.0 / 255, blue: 10.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerSecondary(fallback: .black, appColorProvider: appColor), red: 10.0 / 255, green: 10.0 / 255, blue: 10.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerBackground(appColorProvider: appColor), red: 11.0 / 255, green: 11.0 / 255, blue: 11.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerBorder(appColorProvider: appColor), red: 12.0 / 255, green: 12.0 / 255, blue: 12.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerCTA(appColorProvider: appColor), red: 13.0 / 255, green: 13.0 / 255, blue: 13.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.bannerCTAText(appColorProvider: appColor), red: 14.0 / 255, green: 14.0 / 255, blue: 14.0 / 255, alpha: 1)
        assertColor(
            ITWingAdTheme.nativeCTAText(appColorProvider: { $0 == "cta_text_color" ? colors["cta_text_color"]! : "" }),
            red: 15.0 / 255,
            green: 15.0 / 255,
            blue: 15.0 / 255,
            alpha: 1
        )
        assertColor(
            ITWingAdTheme.nativeLabelText(appColorProvider: { $0 == "ad_label_text_color" ? colors["ad_label_text_color"]! : "" }),
            red: 16.0 / 255,
            green: 16.0 / 255,
            blue: 16.0 / 255,
            alpha: 1
        )
    }

    func testCardBackgroundUsesAdminFallbackWhenSpecificCardColorIsMissing() {
        let colors = [
            "native_background_color": "#040404",
            "banner_background_color": "#0B0B0B",
        ]
        let provider: (String) -> String = { colors[$0] ?? "" }

        assertColor(
            ITWingAdTheme.cardBackground(format: "native", metadata: ["native_transparent_background": "false"], appColorProvider: provider),
            red: 4.0 / 255, green: 4.0 / 255, blue: 4.0 / 255, alpha: 1
        )
        assertColor(
            ITWingAdTheme.cardBackground(format: "banner", metadata: ["banner_transparent_background": "false"], appColorProvider: provider),
            red: 11.0 / 255, green: 11.0 / 255, blue: 11.0 / 255, alpha: 1
        )
        assertColor(
            ITWingAdTheme.cardBackground(format: "native", metadata: ["native_transparent_background": "true"], appColorProvider: provider),
            red: 4.0 / 255, green: 4.0 / 255, blue: 4.0 / 255, alpha: 1
        )
        assertColor(
            ITWingAdTheme.cardBackground(
                format: "native",
                metadata: ["native_transparent_background": "false"],
                appColorProvider: { $0 == "native_card_background_color" ? "#ABCDEF" : "" }
            ),
            red: 171.0 / 255, green: 205.0 / 255, blue: 239.0 / 255, alpha: 1
        )
        assertColor(
            ITWingAdTheme.cardBackground(format: "native", appColorProvider: { _ in "" }),
            red: 0, green: 0, blue: 0, alpha: 0
        )

        assertColor(
            ITWingAdTheme.cardBackground(
                format: "native",
                appColorProvider: { $0 == "ad_background_color" ? "#123456" : "" }
            ),
            red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1
        )
        assertColor(
            ITWingAdTheme.cardBackground(
                format: "banner",
                appColorProvider: { $0 == "ad_background_color" ? "#123456" : "" }
            ),
            red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1
        )
    }

    func testShimmerUsesAdminMediaShimmerColorsBeforePrimary() {
        let colors = [
            "media_shimmer_base_color": "#102030",
            "media_shimmer_highlight_color": "#A0B0C0",
            "primary": "#010203",
        ]
        assertColor(ITWingAdTheme.shimmerBase(appColorProvider: { colors[$0] ?? "" }), red: 16.0 / 255, green: 32.0 / 255, blue: 48.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.shimmerHighlight(appColorProvider: { colors[$0] ?? "" }), red: 160.0 / 255, green: 176.0 / 255, blue: 192.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.shimmerBase(appColorProvider: { _ in "" }), red: 64.0 / 255, green: 64.0 / 255, blue: 64.0 / 255, alpha: 1)
        assertColor(ITWingAdTheme.shimmerHighlight(appColorProvider: { _ in "" }), red: 1, green: 1, blue: 1, alpha: 1)
    }

    func testSubscriptionProductDecodesWeeklyBillingPeriod() throws {
        let json = """
        {
          "id": "product-1",
          "name": "Premium",
          "store": "app_store",
          "product_type": "subscription",
          "product_id": "celebrity_look_alike",
          "subscription_group_id": "123456",
          "billing_period": "weekly",
          "removes_ads": true,
          "entitlements": { "premium": true }
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(SubscriptionProductConfig.self, from: json)

        XCTAssertEqual(product.productId, "celebrity_look_alike")
        XCTAssertEqual(product.subscriptionGroupId, "123456")
        XCTAssertEqual(product.billingPeriod, "weekly")
        XCTAssertTrue(product.removesAds)
    }

    func testSubscriptionProductDefaultsMissingBillingPeriod() throws {
        let json = """
        {
          "id": "product-1",
          "name": "Premium",
          "store": "app_store",
          "product_type": "subscription",
          "product_id": "celebrity_look_alike",
          "removes_ads": true
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(SubscriptionProductConfig.self, from: json)

        XCTAssertEqual(product.billingPeriod, "monthly")
    }

    private func assertColor(
        _ color: UIColor?,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color else {
            XCTFail("Expected a resolved color", file: file, line: line)
            return
        }
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertEqual(actualRed, red, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualGreen, green, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualBlue, blue, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualAlpha, alpha, accuracy: 0.002, file: file, line: line)
    }
}

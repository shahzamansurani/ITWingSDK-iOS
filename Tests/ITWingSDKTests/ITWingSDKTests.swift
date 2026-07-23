import XCTest
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
    }
}

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
}

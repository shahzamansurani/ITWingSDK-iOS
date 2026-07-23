import Foundation

public struct ITWingOptions: Sendable {
    public let endpoint: URL
    public let bootstrapTimeout: TimeInterval
    public let analyticsEnabled: Bool

    public static let `default` = ITWingOptions(
        endpoint: URL(string: "https://sdk.itwingtech.com/api/sdk/v1")!,
        bootstrapTimeout: 4,
        analyticsEnabled: true
    )

    public init(endpoint: URL, bootstrapTimeout: TimeInterval = 4, analyticsEnabled: Bool = true) {
        self.endpoint = endpoint
        self.bootstrapTimeout = bootstrapTimeout
        self.analyticsEnabled = analyticsEnabled
    }
}

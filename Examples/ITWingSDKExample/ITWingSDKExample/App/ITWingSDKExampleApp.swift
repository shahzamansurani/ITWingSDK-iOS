import SwiftUI
import ITWingSDK

@main
struct ITWingSDKExampleApp: App {
    init() {
        if !ExampleEnvironment.sdkKey.isEmpty {
            ITWingSDK.initialize(apiKey: ExampleEnvironment.sdkKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

enum ExampleEnvironment {
    /// Same example application ID used by the Android SDK example.
    static let defaultSDKKey = "itw_live_94kbqo2nFjs3nNhLpOOm3jHWv80k0JQIkHEzHLBD94Banchm"

    static var sdkKey: String {
        let environment = ProcessInfo.processInfo.environment["ITWING_SDK_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environment, !environment.isEmpty {
            return environment
        }
        let plist = (Bundle.main.object(forInfoDictionaryKey: "ITWingSDKKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plist, !plist.isEmpty, !plist.contains("$(") else {
            return defaultSDKKey
        }
        return plist
    }
}

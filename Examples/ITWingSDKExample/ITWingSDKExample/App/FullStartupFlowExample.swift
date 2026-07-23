import SwiftUI
import UIKit
import ITWingSDK

/// UIKit-style full startup integration, equivalent to the Android example's
/// SplashActivity. The SDK owns splash timing, onboarding, terms, splash ads,
/// and navigation to the host application's main controller.
enum FullStartupFlowExample {
    static func start(from presenter: UIViewController) {
        guard !ExampleEnvironment.sdkKey.isEmpty else { return }
        let splashBackground = UIView()
        splashBackground.backgroundColor = ITWingSDK.uiColor(
            "splash_background",
            defaultValue: .systemIndigo
        )
        ITWingStartAppFlow.start(
            apiKey: ExampleEnvironment.sdkKey,
            from: presenter,
            config: ITWingStartAppFlowConfig(
                splashBackgroundView: splashBackground,
                mainFactory: {
                    UIHostingController(rootView: ContentView())
                }
            )
        )
    }
}


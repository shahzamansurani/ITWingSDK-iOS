import SwiftUI
import ITWingSDK
import StoreKit

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("SDK", systemImage: "shippingbox") }

            NavigationStack {
                AdsExampleView()
            }
            .tabItem { Label("Ads", systemImage: "rectangle.on.rectangle") }

            NavigationStack {
                LibrariesExampleView()
            }
            .tabItem { Label("Libraries", systemImage: "square.grid.2x2") }
        }
    }
}

private struct DashboardView: View {
    @State private var message = "Waiting for configuration"

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("SDK version", value: ITWingSDK.version)
                LabeledContent("SDK key") {
                    Text(ExampleEnvironment.sdkKey.isEmpty ? "Not configured" : "Configured")
                        .foregroundStyle(ExampleEnvironment.sdkKey.isEmpty ? .red : .green)
                }
                LabeledContent("Ready", value: ITWingSDK.isReady() ? "Yes" : "No")
                Text(message).font(.footnote).foregroundStyle(.secondary)

                Button("Refresh remote configuration") {
                    Task {
                        do {
                            try await ITWingSDK.refreshConfig()
                            await MainActor.run {
                                message = "Loaded configuration version \(ITWingSDK.config.configVersion)"
                            }
                        } catch {
                            await MainActor.run { message = error.localizedDescription }
                        }
                    }
                }
                .disabled(ExampleEnvironment.sdkKey.isEmpty)
            }

            Section("Admin-managed values") {
                LabeledContent("App title", value: ITWingSDK.appTitle(defaultValue: "ITWing SDK Example"))
                LabeledContent("Logo", value: ITWingSDK.logoUrl()?.absoluteString ?? "Not configured")
                LabeledContent("Primary color", value: ITWingSDK.getColor("primary", defaultValue: "Not configured"))
                LabeledContent("Privacy URL", value: ITWingSDK.appUrl("privacy") ?? "Not configured")
                LabeledContent("Terms URL", value: ITWingSDK.appUrl("terms") ?? "Not configured")
                LabeledContent("Privacy content", value: ITWingSDK.legalContent("privacy") == nil ? "Not configured" : "Configured")
                LabeledContent("Terms content", value: ITWingSDK.legalContent("terms") == nil ? "Not configured" : "Configured")
                LabeledContent("Subscriptions", value: "\(ITWingSDK.subscriptionProducts().count)")
                LabeledContent("Example feature flag", value: ITWingSDK.isFeatureEnabled("example_feature") ? "Enabled" : "Disabled")
                LabeledContent("API base URL", value: ITWingSDK.apiBaseUrl("exchange_rates", defaultValue: "Not configured"))
                LabeledContent(
                    "API proxy endpoint",
                    value: ITWingSDK.config.apiKeys["exchange_rates"]?.proxyEndpoint ?? "Not configured"
                )
            }

            Section("Host actions") {
                Button("Track example analytics event") {
                    AnalyticsClient.shared.track(
                        "example_manual_event",
                        properties: ["screen": "dashboard", "source": "ios_example"]
                    )
                    message = "Analytics event queued"
                }
                Button("Request notification permission") {
                    ITWingSDK.requestNotificationPermission()
                }
                Button("Sync example notification token") {
                    ITWingSDK.registerPushToken("example-local-token")
                    message = "Example notification token synced"
                }
                Button("Show pending in-app notifications") {
                    ITWingNotificationManager.shared.showPendingInAppNotifications()
                }
                Button("Show SDK action dialog") {
                    guard let presenter = ExamplePresenter.current else { return }
                    ITWingSDK.showActionDialog(
                        from: presenter,
                        title: "ITWingSDK dialog",
                        message: "Text, buttons, colors, and reusable behavior can come from the admin panel."
                    ) { result in
                        message = "Dialog result: \(String(describing: result))"
                    }
                }
                Button("Show SDK loading dialog") {
                    guard let presenter = ExamplePresenter.current else { return }
                    let handle = ITWingSDK.showLoadingDialog(from: presenter)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        handle.dismiss()
                    }
                }
                Button("Run complete SDK startup flow") {
                    guard let presenter = ExamplePresenter.current else { return }
                    FullStartupFlowExample.start(from: presenter)
                }
                .disabled(ExampleEnvironment.sdkKey.isEmpty)
                Button("Request App Store review") {
                    guard let presenter = ExamplePresenter.current else { return }
                    ITWingReviewHelper.showReviewPrompt(from: presenter)
                }
                Button("Show admin-managed purchase dialog") {
                    guard let presenter = ExamplePresenter.current else { return }
                    ITWingSubscriptionManager.shared.showPurchaseDialog(from: presenter) { purchased in
                        message = purchased ? "Purchase completed" : "Purchase dialog closed"
                    }
                }
                Button("Restore App Store purchases") {
                    Task {
                        guard let presenter = ExamplePresenter.current else { return }
                        let restored = await ITWingSubscriptionManager.shared.restore(from: presenter)
                        await MainActor.run {
                            message = restored ? "Purchases restored" : "No active purchase found"
                        }
                    }
                }
            }

            Section("Reusable SDK views") {
                PremiumRepresentable()
                    .frame(minHeight: 150)
            }
        }
        .navigationTitle("ITWingSDK Example")
    }
}

private struct PremiumRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ITWingPremiumView {
        ITWingPremiumView()
    }

    func updateUIView(_ uiView: ITWingPremiumView, context: Context) {
        uiView.refresh()
    }
}

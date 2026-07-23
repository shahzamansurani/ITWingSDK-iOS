import SwiftUI
import ITWingSDK

struct AdsExampleView: View {
    @State private var status = "Use placement names configured in the admin panel."

    var body: some View {
        List {
            Section("Inline banner") {
                BannerRepresentable(placement: "banner_adaptive")
                    .frame(height: 60)
            }

            Section("Native small") {
                NativeRepresentable(placement: "native_small")
                    .frame(height: 160)
            }

            Section("Native large") {
                NativeRepresentable(placement: "native_large")
                    .frame(height: 300)
            }

            Section("Fullscreen ads") {
                Button("Preload interstitial") {
                    ITWingSDK.interstitial.load("interstitial")
                    status = "Interstitial preload requested"
                }
                Button("Show interstitial") {
                    guard let presenter = ExamplePresenter.current else { return }
                    ITWingSDK.interstitial.show(from: presenter, placement: "interstitial") {
                        status = "Interstitial flow completed"
                    }
                }
                Button("Preload rewarded") {
                    ITWingSDK.rewarded.load("rewarded")
                    status = "Rewarded preload requested"
                }
                Button("Show rewarded with opt-in") {
                    guard let presenter = ExamplePresenter.current else { return }
                    ITWingSDK.rewarded.showWithOptIn(from: presenter, placement: "rewarded") {
                        status = "Reward earned and ad dismissed"
                    }
                }
                Button("Show app-open if available") {
                    ITWingSDK.appOpen.showIfAvailable(from: ExamplePresenter.current) {
                        status = "App-open flow completed"
                    }
                }
            }

            Section("Startup placements") {
                ITWingOnboardingAd(pageIndex: 0)
                Button("Run configured splash delay and ad") {
                    ITWingSDK.runConfiguredSplash(
                        startupScreensPending: false,
                        from: ExamplePresenter.current
                    ) {
                        status = "Configured splash flow completed"
                    }
                }
            }

            Section("Result") {
                Text(status).font(.footnote)
            }
        }
        .navigationTitle("Ads")
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let placement: String

    func makeUIView(context: Context) -> ITWingBannerView {
        let view = ITWingBannerView()
        view.placementName = placement
        return view
    }

    func updateUIView(_ uiView: ITWingBannerView, context: Context) {
        uiView.placementName = placement
        uiView.loadAdIfNeeded()
    }
}

private struct NativeRepresentable: UIViewRepresentable {
    let placement: String

    func makeUIView(context: Context) -> ITWingNativeAdView {
        let view = ITWingNativeAdView()
        view.placementName = placement
        return view
    }

    func updateUIView(_ uiView: ITWingNativeAdView, context: Context) {
        uiView.placementName = placement
        uiView.loadAdIfNeeded()
    }
}


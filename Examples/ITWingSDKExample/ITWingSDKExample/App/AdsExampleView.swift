import SwiftUI
import ITWingSDK

struct AdsExampleView: View {
    @State private var status = "Use placement names configured in the admin panel."

    var body: some View {
        List {
            Section("Top banner") {
                BannerRepresentable(placement: "banner_top")
                    .frame(height: ITWingAdLayout.bannerHeight)
            }

            Section("Real AdMob banners") {
                BannerRepresentable(placement: "banner_adaptive")
                    .frame(height: ITWingAdLayout.bannerHeight)
            }

            Section("Custom banners") {
                BannerRepresentable(placement: "custom_adaptive_banner")
                    .frame(height: ITWingAdLayout.bannerHeight)
            }

            Section("Real native ads") {
                NativeRepresentable(placement: "native_small")
                    .frame(height: ITWingAdLayout.nativeSmallHeight)
                NativeRepresentable(placement: "native_large")
                    .frame(height: ITWingAdLayout.nativeLargeHeight)
            }

            Section("Custom native ads") {
                NativeRepresentable(placement: "custom_native_small")
                    .frame(height: ITWingAdLayout.nativeSmallHeight)
                NativeRepresentable(placement: "custom_native_large")
                    .frame(height: ITWingAdLayout.nativeLargeHeight)
            }

            Section("Preloading") {
                Button("Preload all fullscreen ads") {
                    ["interstitial", "splash_interstitial", "custom_interstitial"].forEach {
                        ITWingSDK.interstitial.load($0)
                    }
                    ["rewarded", "rewarded_interstitial", "custom_rewarded"].forEach {
                        ITWingSDK.rewarded.load($0)
                    }
                    ITWingSDK.appOpen.load()
                    status = "Fullscreen ad preload requested"
                }
            }

            Section("Interstitials") {
                Button("Show interstitial") {
                    showInterstitial("interstitial")
                }
                Button("Show splash interstitial") {
                    showInterstitial("splash_interstitial")
                }
                Button("Show custom interstitial") {
                    showInterstitial("custom_interstitial")
                }
            }

            Section("Rewarded") {
                Button("Show rewarded video") {
                    showRewarded("rewarded")
                }
                Button("Show rewarded again") {
                    showRewarded("rewarded")
                }
                Button("Show custom rewarded") {
                    showRewarded("custom_rewarded")
                }
                Button("Show rewarded interstitial") {
                    showRewarded("rewarded_interstitial")
                }
                Button("Show custom rewarded with callback") {
                    showRewarded("custom_rewarded")
                }
            }

            Section("App open ads") {
                Button("Show app open: app_open_auto") {
                    showAppOpen()
                }
                Button("Show app open again") {
                    showAppOpen()
                }
                Button("Show custom interstitial as app-open") {
                    showInterstitial("custom_interstitial")
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

    private func showInterstitial(_ placement: String) {
        guard let presenter = ExamplePresenter.current else { return }
        ITWingSDK.interstitial.show(from: presenter, placement: placement) {
            status = "Interstitial completed: \(placement)"
        }
    }

    private func showRewarded(_ placement: String) {
        guard let presenter = ExamplePresenter.current else { return }
        ITWingSDK.rewarded.showWithOptIn(from: presenter, placement: placement) {
            status = "Reward granted and ad dismissed: \(placement)"
        }
    }

    private func showAppOpen() {
        ITWingSDK.appOpen.showIfAvailable(from: ExamplePresenter.current) {
            status = "App-open flow completed"
        }
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

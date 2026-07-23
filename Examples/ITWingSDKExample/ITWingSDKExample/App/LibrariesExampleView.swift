import SwiftUI
import ITWingSDK

struct LibrariesExampleView: View {
    var body: some View {
        List {
            NavigationLink("Wallpapers") {
                LibraryScreen(title: "Wallpapers", kind: .wallpapers)
            }
            NavigationLink("Trending wallpapers") {
                LibraryScreen(title: "Trending wallpapers", kind: .trendingWallpapers)
            }
            NavigationLink("Ringtones") {
                LibraryScreen(title: "Ringtones", kind: .ringtones)
            }
            NavigationLink("Videos") {
                LibraryScreen(title: "Videos", kind: .videos)
            }
            NavigationLink("VPN servers") {
                LibraryScreen(title: "VPN servers", kind: .vpnServers)
            }
        }
        .navigationTitle("Content libraries")
    }
}

private struct LibraryScreen: View {
    let title: String
    let kind: ExampleLibraryKind

    var body: some View {
        LibraryRepresentable(kind: kind)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
    }
}

private enum ExampleLibraryKind {
    case wallpapers
    case trendingWallpapers
    case ringtones
    case videos
    case vpnServers
}

private struct LibraryRepresentable: UIViewRepresentable {
    let kind: ExampleLibraryKind

    func makeUIView(context: Context) -> ITWingMediaCollectionView {
        let view: ITWingMediaCollectionView
        switch kind {
        case .wallpapers:
            view = ITWingWallpapersView()
        case .trendingWallpapers:
            view = ITWingTopTrendsWallpaperView()
        case .ringtones:
            view = ITWingRingtonesView()
        case .videos:
            view = ITWingVideosView()
        case .vpnServers:
            view = ITWingVpnServersView()
        }
        view.onItemSelected = { item in
            guard let presenter = ExamplePresenter.current else { return }
            ITWingUI.showActionDialog(
                from: presenter,
                title: item.title,
                message: item.mediaUrl,
                positive: "OK",
                negative: "Cancel",
                onResult: { _ in }
            )
        }
        return view
    }

    func updateUIView(_ uiView: ITWingMediaCollectionView, context: Context) {}
}


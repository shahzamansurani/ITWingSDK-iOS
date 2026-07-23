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
            NavigationLink("Wallpaper categories + grid") {
                CategoriesLibraryScreen()
            }
            NavigationLink("Ringtones") {
                LibraryScreen(title: "Ringtones", kind: .ringtones)
            }
            NavigationLink("Trending ringtones") {
                LibraryScreen(title: "Trending ringtones", kind: .trendingRingtones)
            }
            NavigationLink("Videos") {
                LibraryScreen(title: "Videos", kind: .videos)
            }
            NavigationLink("Trending videos") {
                LibraryScreen(title: "Trending videos", kind: .trendingVideos)
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
    case trendingRingtones
    case videos
    case trendingVideos
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
        case .trendingRingtones:
            view = ITWingMediaCollectionView()
            view.kind = "ringtones"
            view.placementName = "ringtones_trending"
        case .videos:
            view = ITWingVideosView()
        case .trendingVideos:
            view = ITWingMediaCollectionView()
            view.kind = "videos"
            view.placementName = "videos_trending"
        case .vpnServers:
            view = ITWingVpnServersView()
        }
        view.onItemSelected = { item in
            ExampleMediaPreview.show(item)
        }
        return view
    }

    func updateUIView(_ uiView: ITWingMediaCollectionView, context: Context) {}
}

private struct CategoriesLibraryScreen: View {
    var body: some View {
        CategoriesLibraryRepresentable()
            .navigationTitle("Wallpaper categories")
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct CategoriesLibraryRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let categories = ITWingCategoriesView()
        categories.kind = "wallpapers"
        categories.placementName = "wallpaper_categories"
        categories.displayMode = "text"
        categories.translatesAutoresizingMaskIntoConstraints = false

        let wallpapers = ITWingWallpapersView()
        wallpapers.translatesAutoresizingMaskIntoConstraints = false
        wallpapers.onItemSelected = ExampleMediaPreview.show
        categories.onCategorySelected = { category in
            wallpapers.setCategory(category)
        }

        container.addSubview(categories)
        container.addSubview(wallpapers)
        NSLayoutConstraint.activate([
            categories.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            categories.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            categories.topAnchor.constraint(equalTo: container.topAnchor),
            categories.heightAnchor.constraint(equalToConstant: 64),
            wallpapers.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wallpapers.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wallpapers.topAnchor.constraint(equalTo: categories.bottomAnchor, constant: 8),
            wallpapers.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private enum ExampleMediaPreview {
    static func show(_ item: ITWingMediaItem) {
        guard let presenter = ExamplePresenter.current else { return }
        let controller = UIViewController()
        controller.title = item.title
        controller.view.backgroundColor = .systemBackground

        let player = ITWingMediaPlayerView()
        player.translatesAutoresizingMaskIntoConstraints = false
        player.setMedia(item)
        controller.view.addSubview(player)
        NSLayoutConstraint.activate([
            player.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            player.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            player.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            player.heightAnchor.constraint(equalToConstant: 280),
        ])

        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) }
        )
        presenter.present(navigation, animated: true)
    }
}

import UIKit

public typealias ITWingMediaSelectionHandler = (ITWingMediaItem) -> Void
public typealias ITWingCategorySelectionHandler = (ITWingMediaCategory?) -> Void

open class ITWingMediaCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public var kind: String = "wallpapers"
    public var placementName: String = "wallpapers"
    public var onItemSelected: ITWingMediaSelectionHandler?

    public var itemSize: CGSize = CGSize(width: 145, height: 210)
    public var itemSpacing: CGFloat = 8
    public var showTitle: Bool = true

    private var items: [ITWingMediaItem] = []
    private var shimmer: UIActivityIndicatorView = {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .medium)
        }
        return UIActivityIndicatorView(style: .gray)
    }()
    private var categoryId: String?

    public init(kind: String, placementName: String) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        super.init(frame: .zero, collectionViewLayout: layout)
        self.kind = kind
        self.placementName = placementName
        commonInit()
    }

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        dataSource = self
        delegate = self
        register(ITWingMediaCell.self, forCellWithReuseIdentifier: "ITWingMediaCell")
        shimmer.translatesAutoresizingMaskIntoConstraints = false
        shimmer.hidesWhenStopped = true
        addSubview(shimmer)
        NSLayoutConstraint.activate([
            shimmer.centerXAnchor.constraint(equalTo: centerXAnchor),
            shimmer.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            reloadContent()
        }
    }

    public func setCategory(_ category: ITWingMediaCategory?) {
        categoryId = category?.id
        reloadContent()
    }

    public func reloadContent() {
        guard window != nil else { return }
        shimmer.startAnimating()
        let placement = placementConfig()
        apply(placement)
        Task {
            do {
                let response = try await ITWingSDK.repo?.fetchMedia(
                    kind: kind,
                    placement: placementName,
                    categoryId: categoryId ?? placement?.categoryId,
                    limit: placement?.limit,
                    sort: placement?.sort,
                    selectedItemIds: placement?.selectedItemIds ?? []
                )
                let source = placement?.viewType == "top_trends" ? response?.trending : response?.items
                let next = source ?? []
                MediaDiskCache.shared.prefetch(next.map(\.displayImageUrl))
                await MainActor.run {
                    self.items = next
                    self.shimmer.stopAnimating()
                    self.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.shimmer.stopAnimating()
                    if self.items.isEmpty, let presenter = UIApplication.shared.itwingVisibleViewController {
                        ITWingUI.showError(from: presenter, message: "Internet is not available. Cached content will be shown when available.")
                    }
                }
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = dequeueReusableCell(withReuseIdentifier: "ITWingMediaCell", for: indexPath) as! ITWingMediaCell
        cell.bind(items[indexPath.item], showTitle: showTitle)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        if item.isPremium, !ITWingSubscriptionManager.shared.hasPremiumAccess {
            guard let presenter = UIApplication.shared.itwingVisibleViewController else { return }
            ITWingUI.showActionDialog(
                from: presenter,
                title: "Unlock premium",
                message: "Watch a rewarded ad or buy premium to unlock this item.",
                positive: "Watch Ad",
                negative: "Cancel"
            ) { [weak self] result in
                guard result == .positive, let presenter = UIApplication.shared.itwingVisibleViewController else { return }
                let rewardedPlacement = self?.placementConfig()?.rewardedPlacement ?? "rewarded"
                ITWingSDK.rewarded.show(from: presenter, placement: rewardedPlacement) {
                    self?.open(item)
                }
            }
            return
        }
        open(item)
    }

    private func open(_ item: ITWingMediaItem) {
        ITWingSDK.trackMediaEvent(kind: kind, itemId: item.id, eventType: kind == "vpn_servers" ? "click" : "click")
        onItemSelected?(item)
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        itemSize
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        itemSpacing
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        itemSpacing
    }

    private func placementConfig() -> MediaPlacementConfig? {
        let library: MediaLibraryConfig
        switch kind {
        case "ringtones": library = ITWingSDK.config.ringtones
        case "videos": library = ITWingSDK.config.videos
        case "vpn_servers": library = ITWingSDK.config.vpnServers
        default: library = ITWingSDK.config.wallpapers
        }
        return library.placements[placementName]
    }

    private func apply(_ placement: MediaPlacementConfig?) {
        guard let placement else { return }
        showTitle = placement.showTitle
        if let layout = collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = placement.horizontal ? .horizontal : .vertical
        }
    }
}

open class ITWingCategoriesView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public var kind: String = "wallpapers"
    public var placementName: String = "categories"
    public weak var linkedMediaView: ITWingMediaCollectionView?
    public var onCategorySelected: ITWingCategorySelectionHandler?
    public var displayMode: String = "text"

    private var categories: [ITWingMediaCategory] = [ITWingMediaCategory(id: "", name: "All", slug: nil, description: nil, imageUrl: nil, sortOrder: 0)]
    private var selectedIndex = 0

    public init(kind: String, placementName: String) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        super.init(frame: .zero, collectionViewLayout: layout)
        self.kind = kind
        self.placementName = placementName
        commonInit()
    }

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        dataSource = self
        delegate = self
        register(ITWingCategoryCell.self, forCellWithReuseIdentifier: "ITWingCategoryCell")
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            reloadContent()
        }
    }

    public func reloadContent() {
        Task {
            do {
                let response = try await ITWingSDK.repo?.fetchMedia(kind: kind, placement: placementName, categoryId: nil, limit: 1, sort: nil)
                await MainActor.run {
                    self.displayMode = self.placementConfig()?.categoryMode ?? self.displayMode
                    self.categories = [ITWingMediaCategory(id: "", name: "All", slug: nil, description: nil, imageUrl: nil, sortOrder: 0)] + (response?.categories ?? [])
                    self.reloadData()
                }
            } catch {
                await MainActor.run { self.reloadData() }
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = dequeueReusableCell(withReuseIdentifier: "ITWingCategoryCell", for: indexPath) as! ITWingCategoryCell
        cell.bind(categories[indexPath.item], selected: selectedIndex == indexPath.item, displayMode: displayMode)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedIndex = indexPath.item
        reloadData()
        let category = categories[indexPath.item].id.isEmpty ? nil : categories[indexPath.item]
        linkedMediaView?.setCategory(category)
        onCategorySelected?(category)
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: max(92, categories[indexPath.item].name.count * 9 + 28), height: 42)
    }

    private func placementConfig() -> MediaPlacementConfig? {
        let library: MediaLibraryConfig
        switch kind {
        case "ringtones": library = ITWingSDK.config.ringtones
        case "videos": library = ITWingSDK.config.videos
        case "vpn_servers": library = ITWingSDK.config.vpnServers
        default: library = ITWingSDK.config.wallpapers
        }
        return library.placements[placementName]
    }
}

public final class ITWingWallpapersView: ITWingMediaCollectionView {
    public init() { super.init(kind: "wallpapers", placementName: "wallpapers") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "wallpapers" }
}

public final class ITWingTopTrendsWallpaperView: ITWingMediaCollectionView {
    public init() { super.init(kind: "wallpapers", placementName: "top_trends") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "wallpapers"; placementName = "top_trends" }
}

public final class ITWingWallpaperCategoriesView: ITWingCategoriesView {
    public init() { super.init(kind: "wallpapers", placementName: "categories") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "wallpapers" }
}

public final class ITWingRingtonesView: ITWingMediaCollectionView {
    public init() { super.init(kind: "ringtones", placementName: "ringtones") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "ringtones" }
}

public final class ITWingTopTrendsRingtoneView: ITWingMediaCollectionView {
    public init() { super.init(kind: "ringtones", placementName: "top_trends") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "ringtones"; placementName = "top_trends" }
}

public final class ITWingRingtoneCategoriesView: ITWingCategoriesView {
    public init() { super.init(kind: "ringtones", placementName: "categories") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "ringtones" }
}

public final class ITWingVideosView: ITWingMediaCollectionView {
    public init() { super.init(kind: "videos", placementName: "videos") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "videos" }
}

public final class ITWingTopTrendsVideoView: ITWingMediaCollectionView {
    public init() { super.init(kind: "videos", placementName: "top_trends") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "videos"; placementName = "top_trends" }
}

public final class ITWingVideoCategoriesView: ITWingCategoriesView {
    public init() { super.init(kind: "videos", placementName: "categories") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "videos" }
}

public final class ITWingVpnServersView: ITWingMediaCollectionView {
    public init() { super.init(kind: "vpn_servers", placementName: "vpn_servers") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "vpn_servers" }
}

public final class ITWingTopTrendsVpnServerView: ITWingMediaCollectionView {
    public init() { super.init(kind: "vpn_servers", placementName: "top_trends") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "vpn_servers"; placementName = "top_trends" }
}

public final class ITWingVpnCountriesView: ITWingCategoriesView {
    public init() { super.init(kind: "vpn_servers", placementName: "countries") }
    public required init?(coder: NSCoder) { super.init(coder: coder); kind = "vpn_servers"; placementName = "countries" }
}

final class ITWingMediaCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let premiumLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        contentView.backgroundColor = UIColor.secondarySystemFill
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        premiumLabel.translatesAutoresizingMaskIntoConstraints = false
        premiumLabel.text = "Premium"
        premiumLabel.font = .systemFont(ofSize: 11, weight: .bold)
        premiumLabel.textColor = .white
        premiumLabel.backgroundColor = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        premiumLabel.layer.cornerRadius = 9
        premiumLabel.clipsToBounds = true
        premiumLabel.textAlignment = .center
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(premiumLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            premiumLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            premiumLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            premiumLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            premiumLabel.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(_ item: ITWingMediaItem, showTitle: Bool) {
        titleLabel.text = showTitle ? item.title : nil
        titleLabel.isHidden = !showTitle
        premiumLabel.isHidden = !item.isPremium
        imageView.image = nil
        MediaDiskCache.shared.loadImage(item.displayImageUrl) { [weak self] image in
            self?.imageView.image = image
        }
    }
}

final class ITWingCategoryCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        contentView.backgroundColor = UIColor.secondarySystemFill
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(_ category: ITWingMediaCategory, selected: Bool, displayMode: String) {
        titleLabel.text = category.name
        titleLabel.isHidden = displayMode == "image"
        imageView.isHidden = displayMode == "text"
        titleLabel.textColor = selected ? .white : .label
        contentView.backgroundColor = selected ? ITWingSDK.uiColor("primary", defaultValue: .systemBlue) : UIColor.secondarySystemFill
        imageView.image = nil
        if let imageUrl = category.imageUrl {
            MediaDiskCache.shared.loadImage(imageUrl) { [weak self] image in
                self?.imageView.image = image
                self?.imageView.alpha = image == nil ? 0 : 0.28
            }
        }
    }
}

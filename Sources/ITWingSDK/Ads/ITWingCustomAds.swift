import AVFoundation
import UIKit

public struct ITWingCustomAd: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let format: String
    public let priority: Int
    public let headline: String?
    public let body: String?
    public let cta: String?
    public let targetUrl: String?
    public let androidTargetUrl: String?
    public let iosTargetUrl: String?
    public let imageUrl: String?
    public let videoUrl: String?
    public let mediaUrl: String?
    public let html: String?
    public let metadata: [String: String]
    public let brandName: String?
    public let brandLogoUrl: String?
    public let primaryColor: String?
    public let brandRating: Double
    public let adIcon: String
    public let mediaType: String?
    public let placementNames: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case format
        case priority
        case headline
        case body
        case cta
        case targetUrl = "target_url"
        case androidTargetUrl = "android_target_url"
        case iosTargetUrl = "ios_target_url"
        case imageUrl = "image_url"
        case videoUrl = "video_url"
        case mediaUrl = "media_url"
        case html
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? ""
        priority = try values.decodeIfPresent(Int.self, forKey: .priority) ?? 100
        headline = try values.decodeIfPresent(String.self, forKey: .headline)
        body = try values.decodeIfPresent(String.self, forKey: .body)
        cta = try values.decodeIfPresent(String.self, forKey: .cta)
        targetUrl = try values.decodeIfPresent(String.self, forKey: .targetUrl)
        androidTargetUrl = try values.decodeIfPresent(String.self, forKey: .androidTargetUrl)
        iosTargetUrl = try values.decodeIfPresent(String.self, forKey: .iosTargetUrl)
        imageUrl = try values.decodeIfPresent(String.self, forKey: .imageUrl)
        videoUrl = try values.decodeIfPresent(String.self, forKey: .videoUrl)
        mediaUrl = try values.decodeIfPresent(String.self, forKey: .mediaUrl)
        html = try values.decodeIfPresent(String.self, forKey: .html)
        metadata = (try? values.decodeIfPresent([String: String].self, forKey: .metadata)) ?? [:]
        let rich = (try? values.decodeIfPresent(CustomAdMetadata.self, forKey: .metadata)) ?? CustomAdMetadata()
        brandName = rich.brand?.name
        brandLogoUrl = rich.brand?.logoUrl
        primaryColor = rich.brand?.primaryColor ?? rich.adPrimaryColor
        brandRating = rich.brand?.rating?.value ?? rich.brandRating?.value ?? 4.5
        adIcon = rich.adIcon ?? "AD"
        mediaType = rich.mediaType
        placementNames = rich.placementNames ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(format, forKey: .format)
        try values.encode(priority, forKey: .priority)
        try values.encodeIfPresent(headline, forKey: .headline)
        try values.encodeIfPresent(body, forKey: .body)
        try values.encodeIfPresent(cta, forKey: .cta)
        try values.encodeIfPresent(targetUrl, forKey: .targetUrl)
        try values.encodeIfPresent(androidTargetUrl, forKey: .androidTargetUrl)
        try values.encodeIfPresent(iosTargetUrl, forKey: .iosTargetUrl)
        try values.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try values.encodeIfPresent(videoUrl, forKey: .videoUrl)
        try values.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try values.encodeIfPresent(html, forKey: .html)
        try values.encode(metadata, forKey: .metadata)
    }
}

private struct CustomAdMetadata: Decodable {
    struct Brand: Decodable {
        let name: String?
        let logoUrl: String?
        let primaryColor: String?
        let rating: FlexibleDouble?

        enum CodingKeys: String, CodingKey {
            case name
            case logoUrl = "logo_url"
            case primaryColor = "primary_color"
            case rating
        }
    }

    var brand: Brand?
    var brandRating: FlexibleDouble?
    var adPrimaryColor: String?
    var adIcon: String?
    var mediaType: String?
    var placementNames: [String]?

    enum CodingKeys: String, CodingKey {
        case brand
        case brandRating = "brand_rating"
        case adPrimaryColor = "ad_primary_color"
        case adIcon = "ad_icon"
        case mediaType = "media_type"
        case placementNames = "placement_names"
    }
}

extension AdPlacementConfig {
    func selectedCustomAd(in config: ITWingConfig) -> ITWingCustomAd? {
        let source = (metadata?["source"] ?? nil)?.lowercased() ?? ""
        let explicitlyCustom = source.contains("custom")
        let hasAdMobUnit = units.contains {
            $0.network.lowercased() == "admob" && !$0.adUnitId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // An attached campaign may be a fallback supplied by the control plane.
        // It must never bypass a real AdMob unit unless delivery is explicitly
        // configured as custom.
        guard explicitlyCustom || (!hasAdMobUnit && customAd != nil) else { return nil }
        if let customAd { return customAd }

        return config.ads.customAds
            .filter { ad in
                let formatMatches = ad.format == format
                    || (format == "rewarded_interstitial" && ad.format == "interstitial")
                    || ["image", "video"].contains(ad.format)
                let placementMatches = ad.placementNames.isEmpty || ad.placementNames.contains(name)
                return formatMatches && placementMatches
            }
            .sorted { $0.priority < $1.priority }
            .first
    }

    /// A compatible campaign used only after the configured AdMob unit fails
    /// to load or present. Explicit placement targeting wins; otherwise the
    /// highest-priority global campaign of the same full-screen/inline format
    /// is used.
    func fallbackCustomAd(in config: ITWingConfig) -> ITWingCustomAd? {
        let compatible = config.ads.customAds.filter { ad in
            [ad.mediaUrl, ad.videoUrl, ad.imageUrl].contains(where: { !($0 ?? "").isEmpty })
        }
        return compatible
            .sorted {
                let lhsTargeted = !$0.placementNames.isEmpty && $0.placementNames.contains(name)
                let rhsTargeted = !$1.placementNames.isEmpty && $1.placementNames.contains(name)
                let lhsFormat = $0.format == format
                let rhsFormat = $1.format == format
                if lhsTargeted != rhsTargeted { return lhsTargeted }
                if lhsFormat != rhsFormat { return lhsFormat }
                return $0.priority < $1.priority
            }
            .first { $0.placementNames.isEmpty || $0.placementNames.contains(name) }
    }
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self), let number = Double(text) {
            value = number
        } else {
            value = 0
        }
    }
}

struct CustomAdsEnvelope: Decodable {
    struct DataPayload: Decodable {
        let ads: [ITWingCustomAd]
    }

    let data: DataPayload
}

final class ITWingCustomFullScreenAdController: UIViewController {
    private let ad: ITWingCustomAd
    private let placement: AdPlacementConfig
    private let onDismiss: () -> Void
    private let onReward: (() -> Void)?
    private var rewardGranted = false

    init(ad: ITWingCustomAd, placement: AdPlacementConfig, onReward: (() -> Void)? = nil, onDismiss: @escaping () -> Void) {
        self.ad = ad
        self.placement = placement
        self.onDismiss = onDismiss
        self.onReward = onReward
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let appPrimary = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        let fullscreenBackground = ITWingSDK.uiColor("native_background_color", defaultValue: .black)
        let primary = UIColor.itwingHex(ad.primaryColor, fallback: appPrimary)
        view.backgroundColor = fullscreenBackground
        let isRewarded = placement.format.lowercased().contains("rewarded")
        let isVideo = ad.mediaType?.lowercased() == "video" || !(ad.videoUrl ?? "").isEmpty
        // Full-screen formats intentionally share one admin theme. Do not read
        // placement-specific native metadata here, otherwise rewarded and
        // interstitial campaigns render differently.
        let badgeText = ITWingSDK.uiColor("ad_label_text_color", defaultValue: .white)
        let headlineText = ITWingSDK.uiColor("native_headline_text_color", defaultValue: ITWingSDK.uiColor("native_text_color", defaultValue: .white))
        let bodyText = ITWingSDK.uiColor("native_body_text_color", defaultValue: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(white: 0.86, alpha: 1)))
        let metaText = ITWingSDK.uiColor("native_meta_text_color", defaultValue: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(white: 0.82, alpha: 1)))
        let ctaText = ITWingSDK.uiColor("cta_text_color", defaultValue: .white)

        let media = ITWingCustomMediaView()
        media.translatesAutoresizingMaskIntoConstraints = false
        media.layer.cornerRadius = 0
        media.backgroundColor = fullscreenBackground
        view.addSubview(media)

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.backgroundColor = .white
        icon.layer.cornerRadius = 6
        icon.clipsToBounds = true
        if let logo = ad.brandLogoUrl { MediaDiskCache.shared.loadImage(logo) { icon.image = $0 } }

        let badge = UILabel()
        badge.text = ad.adIcon
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = badgeText
        badge.textAlignment = .center
        badge.backgroundColor = primary
        badge.layer.cornerRadius = 6
        badge.clipsToBounds = true
        badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let brand = UILabel()
        brand.text = ad.brandName ?? "Sponsored"
        brand.textColor = metaText
        brand.font = .systemFont(ofSize: 13, weight: .bold)

        let brandRow = UIStackView(arrangedSubviews: [badge, brand, UIView()])
        brandRow.axis = .horizontal
        brandRow.alignment = .center
        brandRow.spacing = 6
        let headline = UILabel()
        headline.text = ad.headline ?? ad.name
        headline.textColor = headlineText
        headline.font = .systemFont(ofSize: 18, weight: .bold)
        headline.numberOfLines = 1
        let labels = UIStackView(arrangedSubviews: [brandRow, headline])
        labels.axis = .vertical
        labels.spacing = 4
        let top = UIStackView(arrangedSubviews: [icon, labels])
        top.translatesAutoresizingMaskIntoConstraints = false
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 10
        view.addSubview(top)

        let body = UILabel()
        body.text = ad.body ?? ""
        body.textColor = bodyText
        body.font = .systemFont(ofSize: 14)
        body.numberOfLines = 3
        let rating = ITWingRatingView(rating: ad.brandRating)
        let sponsored = UILabel()
        sponsored.text = "Sponsored"
        sponsored.textColor = metaText
        sponsored.font = .systemFont(ofSize: 12)
        let ratingRow = UIStackView(arrangedSubviews: [rating, sponsored, UIView()])
        ratingRow.axis = .horizontal
        ratingRow.alignment = .center
        ratingRow.spacing = 8
        let cta = UIButton(type: .system)
        cta.setTitle(ad.cta ?? "Open", for: .normal)
        cta.setTitleColor(ctaText, for: .normal)
        cta.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        cta.backgroundColor = primary
        cta.layer.cornerRadius = 20
        cta.heightAnchor.constraint(equalToConstant: 40).isActive = true
        cta.addTarget(self, action: #selector(openAd), for: .touchUpInside)
        let bottom = UIStackView(arrangedSubviews: [body, ratingRow, cta])
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.axis = .vertical
        bottom.spacing = 10
        bottom.isLayoutMarginsRelativeArrangement = true
        bottom.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        bottom.backgroundColor = fullscreenBackground
        view.addSubview(bottom)

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = ITWingSDK.uiColor("dialog_close_icon_color", defaultValue: .white)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        close.layer.cornerRadius = 22
        close.accessibilityLabel = "Close ad"
        close.addTarget(self, action: #selector(closeAd), for: .touchUpInside)

        view.addSubview(close)
        NSLayoutConstraint.activate([
            media.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            media.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            media.topAnchor.constraint(equalTo: view.topAnchor),
            media.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            top.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
            top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        close.alpha = 0
        close.isEnabled = false
        media.configure(with: ad, loop: !isRewarded) { [weak self] in self?.grantRewardIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (isRewarded ? 5 : 3)) { [weak self] in
            guard let self else { return }
            if isRewarded && !isVideo { self.grantRewardIfNeeded() }
            close.isEnabled = true
            UIView.animate(withDuration: 0.25) { close.alpha = 1 }
        }
    }

    @objc private func openAd() {
        ITWingSDK.trackCustomAdClick(ad.id, metadata: ["placement": placement.name])
        guard let value = ad.iosTargetUrl ?? ad.targetUrl, let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }

    private func grantRewardIfNeeded() {
        guard !rewardGranted, placement.format.lowercased().contains("rewarded") else { return }
        rewardGranted = true
    }

    @objc private func closeAd() {
        let shouldDeliverReward = rewardGranted && placement.format.lowercased().contains("rewarded")
        dismiss(animated: true) {
            if shouldDeliverReward { self.onReward?() }
            self.onDismiss()
        }
    }
}

open class ITWingCustomNativeAdView: UIView {
    public var placementName: String = "custom_native_large" {
        didSet { load() }
    }
    public var format: String = "native"
    public var nativeType: String = "large"
    public var placementMetadata: [String: String?] = [:]
    public var configuredAd: ITWingCustomAd? {
        didSet {
            if let configuredAd, window != nil {
                render(configuredAd)
            }
        }
    }

    private var currentAd: ITWingCustomAd?
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let imageView = UIImageView()
    private var mediaView: ITWingCustomMediaView?
    private let ctaButton = UIButton(type: .system)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        layer.cornerRadius = 0
        clipsToBounds = true
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            load()
        }
    }

    public func load() {
        guard window != nil, ITWingSDK.canRequestAds() else { return }
        if let configuredAd {
            render(configuredAd)
            return
        }
        Task {
            let ads = (try? await ITWingSDK.fetchCustomAds(format: format, placement: placementName)) ?? []
            guard let ad = ads.first else { return }
            await MainActor.run { self.render(ad) }
        }
    }

    private func render(_ ad: ITWingCustomAd) {
        currentAd = ad
        subviews.forEach { $0.removeFromSuperview() }
        let card = CustomNativeCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        let isBanner = format.lowercased() == "banner"
        card.layer.cornerRadius = isBanner ? 0 : 28
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.33).cgColor
        card.clipsToBounds = true
        if !placementMetadata.bool("native_transparent_background", defaultValue: true) {
            card.useSolidColor(placementMetadata.color("native_background_color", fallback: .clear))
        }
        addSubview(card)

        let content: UIView
        if isBanner {
            content = buildBanner(ad)
        } else if nativeType.lowercased() == "small" {
            content = buildSmall(ad)
        } else {
            content = buildLarge(ad)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: isBanner ? 1 : 12),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: isBanner ? -1 : -12),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: isBanner ? 1 : 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: isBanner ? -1 : -12),
        ])
        if !isBanner {
            let badgeBackground = CustomAdBadgeBackground()
            badgeBackground.color = primaryColor(for: ad)
            badgeBackground.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(badgeBackground)
            let badge = makeBadge(ad, fontSize: 11)
            card.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 25),
                badge.heightAnchor.constraint(equalToConstant: 20),
                badgeBackground.leadingAnchor.constraint(equalTo: badge.leadingAnchor),
                badgeBackground.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
                badgeBackground.topAnchor.constraint(equalTo: badge.topAnchor),
                badgeBackground.bottomAnchor.constraint(equalTo: badge.bottomAnchor),
            ])
            card.bringSubviewToFront(badge)
        }
        mediaView?.configure(with: ad)
        ITWingSDK.trackCustomAdEvent(adId: ad.id, eventType: "impression", metadata: ["placement": placementName])
    }

    private func buildLarge(_ ad: ITWingCustomAd) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 10)
        configureIcon(ad)
        header.addArrangedSubview(imageView)
        let titles = UIStackView()
        titles.axis = .vertical
        titles.spacing = 2
        configureLabels(ad)
        titles.addArrangedSubview(titleLabel)
        titles.addArrangedSubview(metaRow(ad))
        header.addArrangedSubview(titles)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(bodyLabel)
        let media = ITWingCustomMediaView()
        media.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        mediaView = media
        stack.addArrangedSubview(media)
        configureCTA(ad, height: 35)
        stack.addArrangedSubview(ctaButton)
        return stack
    }

    private func buildSmall(_ ad: ITWingCustomAd) -> UIView {
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 4
        configureLabels(ad)
        titleLabel.numberOfLines = 2
        bodyLabel.numberOfLines = 3

        // Mirrors custom_native_small.xml: the AD tag occupies the leading
        // portion of this row and the body begins immediately to its right.
        let bodyRow = UIStackView(arrangedSubviews: [bodyLabel])
        bodyRow.isLayoutMarginsRelativeArrangement = true
        bodyRow.layoutMargins = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 0)
        outer.addArrangedSubview(bodyRow)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 0
        row.alignment = .fill

        // Android weight=2 column.
        let info = UIStackView()
        info.axis = .vertical
        info.spacing = 3
        info.alignment = .fill
        info.addArrangedSubview(titleLabel)

        configureIcon(ad, size: 40)
        let store = UILabel()
        store.text = ""
        store.font = .systemFont(ofSize: 12, weight: .bold)
        store.textColor = metaColor
        store.textAlignment = .center
        let rating = ITWingRatingView(rating: ad.brandRating)
        let storeAndRating = UIStackView(arrangedSubviews: [store, rating])
        storeAndRating.axis = .vertical
        storeAndRating.alignment = .center
        storeAndRating.spacing = 0
        let iconRow = UIStackView(arrangedSubviews: [imageView, storeAndRating])
        iconRow.axis = .horizontal
        iconRow.alignment = .center
        iconRow.spacing = 3
        info.addArrangedSubview(iconRow)

        let price = UILabel()
        price.text = ""
        price.font = .systemFont(ofSize: 12)
        price.textColor = metaColor
        let advertiser = UILabel()
        advertiser.text = ad.brandName ?? "Sponsored"
        advertiser.font = .systemFont(ofSize: 12)
        advertiser.textColor = metaColor
        advertiser.numberOfLines = 1
        titleLabel.isHidden = duplicatesBrandHeadline(ad)
        advertiser.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let advertiserRow = UIStackView(arrangedSubviews: [price, advertiser, UIView()])
        advertiserRow.axis = .horizontal
        advertiserRow.spacing = 3
        info.addArrangedSubview(advertiserRow)

        configureCTA(ad, height: 40)
        ctaButton.layer.cornerRadius = 20
        info.addArrangedSubview(ctaButton)
        row.addArrangedSubview(info)

        // Android weight=4 column: exactly twice the width of the info column.
        let media = ITWingCustomMediaView()
        media.heightAnchor.constraint(equalToConstant: 130).isActive = true
        mediaView = media
        row.addArrangedSubview(media)
        media.widthAnchor.constraint(equalTo: info.widthAnchor, multiplier: 2).isActive = true
        outer.addArrangedSubview(row)
        return outer
    }

    private var metaColor: UIColor {
        placementMetadata.color(
            "native_meta_text_color",
            fallback: ITWingSDK.uiColor(
                "native_text_color",
                defaultValue: UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1)
            )
        )
    }

    private func buildBanner(_ ad: ITWingCustomAd) -> UIView {
        configureLabels(ad)
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.numberOfLines = 1
        bodyLabel.font = .systemFont(ofSize: 10)
        bodyLabel.numberOfLines = 2

        let media = ITWingCustomMediaView()
        media.translatesAutoresizingMaskIntoConstraints = false
        media.widthAnchor.constraint(equalToConstant: 84).isActive = true
        // The host banner is 60pt tall and the custom card has 1pt top/bottom
        // inset, so media must fit the remaining 58pt without breaking layout.
        media.heightAnchor.constraint(equalToConstant: 58).isActive = true
        mediaView = media

        let advertiser = UILabel()
        advertiser.text = ad.brandName ?? "Sponsored"
        advertiser.font = .systemFont(ofSize: 9, weight: .bold)
        advertiser.textColor = placementMetadata.color(
            "native_meta_text_color",
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1))
        )
        advertiser.numberOfLines = 1
        let normalizedAdvertiser = advertiser.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHeadline = titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        titleLabel.isHidden = normalizedHeadline?.isEmpty != false || normalizedHeadline == normalizedAdvertiser

        let rating = ITWingRatingView(rating: ad.brandRating, fontSize: 8)
        configureCTA(ad, height: 18)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 8, weight: .bold)
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)

        let bottom = UIStackView(arrangedSubviews: [rating, ctaButton, UIView()])
        bottom.axis = .horizontal
        bottom.alignment = .center
        bottom.spacing = 5

        let content = UIStackView(arrangedSubviews: [advertiser, titleLabel, bodyLabel, bottom])
        content.axis = .vertical
        content.spacing = 1
        content.alignment = .fill

        let badge = makeBadge(ad, fontSize: 9)
        badge.backgroundColor = primaryColor(for: ad)
        badge.layer.cornerRadius = 5
        badge.clipsToBounds = true
        configureIcon(ad, size: 30)
        let trailing = UIStackView(arrangedSubviews: [badge, imageView])
        trailing.axis = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 3
        trailing.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let row = UIStackView(arrangedSubviews: [media, content, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 5
        return row
    }

    private func primaryColor(for ad: ITWingCustomAd) -> UIColor {
        UIColor.itwingHex(ad.primaryColor, fallback: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
    }

    private func makeBadge(_ ad: ITWingCustomAd, fontSize: CGFloat) -> UILabel {
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = ad.adIcon
        badge.font = .systemFont(ofSize: fontSize, weight: .bold)
        badge.textAlignment = .center
        badge.textColor = placementMetadata.color(
            "native_ad_label_text_color",
            fallback: ITWingSDK.uiColor("ad_label_text_color", defaultValue: .white)
        )
        return badge
    }

    private func configureLabels(_ ad: ITWingCustomAd) {
        titleLabel.text = ad.headline ?? ad.name
        titleLabel.isHidden = false
        titleLabel.font = .systemFont(ofSize: nativeType.lowercased() == "small" ? 12 : 16, weight: .bold)
        titleLabel.textColor = placementMetadata.color(
            ["native_headline_text_color", "headline_text_color"],
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1))
        )
        titleLabel.numberOfLines = 2
        bodyLabel.text = ad.body ?? "Promoted content"
        bodyLabel.font = .systemFont(ofSize: nativeType.lowercased() == "small" ? 12 : 13)
        bodyLabel.textColor = placementMetadata.color(
            ["native_body_text_color", "body_text_color"],
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1))
        )
        bodyLabel.numberOfLines = 3
    }

    private func configureIcon(_ ad: ITWingCustomAd, size: CGFloat = 35) {
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 7
        imageView.widthAnchor.constraint(equalToConstant: size).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: size).isActive = true
        if let logo = ad.brandLogoUrl {
            MediaDiskCache.shared.loadImage(logo) { [weak self] image in self?.imageView.image = image }
        }
    }

    private func metaRow(_ ad: ITWingCustomAd) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        let metaColor = placementMetadata.color(
            "native_meta_text_color",
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1))
        )
        let advertiser = UILabel()
        advertiser.text = ad.brandName ?? "Sponsored"
        advertiser.font = .systemFont(ofSize: nativeType.lowercased() == "small" ? 12 : 14, weight: .bold)
        advertiser.textColor = metaColor
        titleLabel.isHidden = duplicatesBrandHeadline(ad)
        row.addArrangedSubview(advertiser)
        row.addArrangedSubview(ITWingRatingView(rating: ad.brandRating))
        row.addArrangedSubview(UIView())
        return row
    }

    /// A campaign without a distinct headline falls back to its campaign name,
    /// which is commonly identical to the selected brand name. Keep the
    /// advertiser/brand and hide only that duplicate headline.
    private func duplicatesBrandHeadline(_ ad: ITWingCustomAd) -> Bool {
        guard let brand = ad.brandName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !brand.isEmpty else { return false }
        let headline = (ad.headline ?? ad.name).trimmingCharacters(in: .whitespacesAndNewlines)
        return headline.caseInsensitiveCompare(brand) == .orderedSame
    }

    private func configureCTA(_ ad: ITWingCustomAd, height: CGFloat) {
        ctaButton.setTitle(ad.cta ?? "Install", for: .normal)
        ctaButton.backgroundColor = UIColor.itwingHex(ad.primaryColor, fallback: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
        ctaButton.setTitleColor(
            placementMetadata.color("native_cta_text_color", fallback: ITWingSDK.uiColor("cta_text_color", defaultValue: .white)),
            for: .normal
        )
        ctaButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        ctaButton.layer.cornerRadius = height / 2
        ctaButton.heightAnchor.constraint(equalToConstant: height).isActive = true
        ctaButton.addTarget(self, action: #selector(openAd), for: .touchUpInside)
    }

    @objc private func openAd() {
        guard let ad = currentAd else { return }
        ITWingSDK.trackCustomAdEvent(adId: ad.id, eventType: "click", metadata: ["placement": placementName])
        if let target = ad.iosTargetUrl ?? ad.targetUrl, let url = URL(string: target) {
            UIApplication.shared.open(url)
        }
    }
}

private final class ITWingCustomMediaView: UIView {
    private let imageView = UIImageView()
    private let muteButton = UIButton(type: .system)
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var isMuted = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 12
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.35)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
        muteButton.tintColor = .white
        muteButton.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        muteButton.layer.cornerRadius = 15
        muteButton.accessibilityLabel = "Unmute"
        muteButton.isHidden = true
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        addSubview(muteButton)
        updateMuteButton()
    }

    required init?(coder: NSCoder) { nil }

    func configure(with ad: ITWingCustomAd, loop: Bool = true, onCompleted: @escaping () -> Void = {}) {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        imageView.image = nil
        muteButton.isHidden = true

        let source = [ad.mediaUrl, ad.videoUrl, ad.imageUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let source, let url = URL(string: source) else { return }
        let isVideo = ad.mediaType?.lowercased() == "video"
            || ad.videoUrl == source
            || ["mp4", "mov", "m4v", "webm"].contains(url.pathExtension.lowercased())

        if isVideo {
            let player = AVPlayer(url: url)
            isMuted = true
            player.isMuted = isMuted
            player.actionAtItemEnd = loop ? .none : .pause
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            self.player = player
            playerLayer = layer
            self.layer.addSublayer(layer)
            muteButton.isHidden = false
            bringSubviewToFront(muteButton)
            updateMuteButton()
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                onCompleted()
                if loop {
                    player?.seek(to: .zero)
                    player?.play()
                }
            }
            player.play()
        } else {
            MediaDiskCache.shared.loadImage(source) { [weak self] image in
                self?.imageView.image = image
            }
        }
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        updateMuteButton()
    }

    private func updateMuteButton() {
        muteButton.setImage(
            UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
            for: .normal
        )
        muteButton.accessibilityLabel = isMuted ? "Unmute" : "Mute"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
        let compact = min(bounds.width, bounds.height) < 90
        let buttonSize: CGFloat = compact ? 20 : 30
        muteButton.layer.cornerRadius = buttonSize / 2
        let inset: CGFloat = compact ? 2 : 4
        muteButton.frame = CGRect(
            x: max(inset, bounds.width - buttonSize - inset),
            y: max(inset, bounds.height - buttonSize - inset),
            width: buttonSize,
            height: buttonSize
        )
        muteButton.imageView?.contentMode = .scaleAspectFit
        muteButton.imageEdgeInsets = compact
            ? UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            : .zero
        bringSubviewToFront(muteButton)
    }

    deinit {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }
}

private final class ITWingRatingView: UIView {
    init(rating: Double, fontSize: CGFloat = 12) {
        super.init(frame: .zero)
        let value = max(0, min(5, rating))
        let background = UILabel()
        background.text = "☆☆☆☆☆"
        background.font = .systemFont(ofSize: fontSize, weight: .semibold)
        background.textColor = UIColor.systemGray3
        background.sizeToFit()
        addSubview(background)

        let foreground = UILabel()
        foreground.text = "★★★★★"
        foreground.font = background.font
        foreground.textColor = UIColor(red: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
        foreground.sizeToFit()
        let mask = UIView(frame: CGRect(x: 0, y: 0, width: foreground.bounds.width * value / 5, height: foreground.bounds.height))
        mask.backgroundColor = .black
        foreground.mask = mask
        addSubview(foreground)
        frame.size = background.bounds.size
        widthAnchor.constraint(equalToConstant: background.bounds.width).isActive = true
        heightAnchor.constraint(equalToConstant: background.bounds.height).isActive = true
        accessibilityLabel = "\(String(format: "%.1f", value)) out of 5 stars"
    }

    required init?(coder: NSCoder) { nil }
}

private final class CustomNativeCard: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [
            UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.87).cgColor,
            UIColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 0.69).cgColor,
            UIColor(red: 2 / 255, green: 6 / 255, blue: 23 / 255, alpha: 0.82).cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
    }

    required init?(coder: NSCoder) { nil }

    func useSolidColor(_ color: UIColor) {
        gradient.colors = [color.cgColor, color.cgColor]
        gradient.locations = [0, 1]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
    }
}

private final class CustomAdBadgeBackground: UIView {
    var color: UIColor = .systemBlue { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        color.setFill()
        UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .bottomRight],
            cornerRadii: CGSize(width: 11, height: 11)
        ).fill()
    }
}

private extension Dictionary where Key == String, Value == String? {
    func bool(_ key: String, defaultValue: Bool) -> Bool {
        guard let value = self[key] ?? nil else { return defaultValue }
        switch value.lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return defaultValue
        }
    }

    func color(_ key: String, fallback: UIColor) -> UIColor {
        UIColor.itwingHex(self[key] ?? nil, fallback: fallback)
    }

    func color(_ keys: [String], fallback: UIColor) -> UIColor {
        for key in keys {
            if let value = self[key] ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return UIColor.itwingHex(value, fallback: fallback)
            }
        }
        return fallback
    }
}

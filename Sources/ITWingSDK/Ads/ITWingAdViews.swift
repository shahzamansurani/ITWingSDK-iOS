import GoogleMobileAds
import UIKit

open class ITWingBannerView: UIView, BannerViewDelegate {
    public var placementName: String = "banner_adaptive" {
        didSet { loadAdIfNeeded() }
    }

    private var bannerView: BannerView?
    private var hasRequested = false
    private var observers: [NSObjectProtocol] = []

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
        layer.masksToBounds = true
        observers = [.itwingConfigDidChange, .itwingAdsAvailabilityDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.unloadAd()
                if ITWingSDK.canRequestAds() {
                    self.loadAdIfNeeded()
                }
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            loadAdIfNeeded()
        } else {
            unloadAd()
        }
    }

    private func unloadAd() {
        bannerView?.delegate = nil
        bannerView?.removeFromSuperview()
        bannerView = nil
        hasRequested = false
    }

    public func loadAdIfNeeded() {
        guard window != nil, !hasRequested, ITWingSDK.canRequestAds() else { return }
        let bannerPlacements = ITWingSDK.config.ads.placements.filter { $0.enabled && $0.format == "banner" }
        guard let placement = bannerPlacements.first(where: { $0.name == placementName }) ?? bannerPlacements.first else { return }
        guard AdLoadBackoff.canRequest(placement) else {
            if let fallback = placement.fallbackCustomAd(in: ITWingSDK.config) {
                let customView = ITWingCustomNativeAdView()
                customView.translatesAutoresizingMaskIntoConstraints = false
                customView.format = "banner"
                customView.nativeType = "small"
                customView.placementName = placement.name
                customView.placementMetadata = placement.metadata ?? [:]
                customView.configuredAd = fallback
                addSubview(customView)
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    customView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    customView.topAnchor.constraint(equalTo: topAnchor),
                    customView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                hasRequested = true
                isHidden = false
                return
            }
            isHidden = true
            return
        }
        isHidden = false
        if let customAd = placement.selectedCustomAd(in: ITWingSDK.config) {
            hasRequested = true
            let customView = ITWingCustomNativeAdView()
            customView.translatesAutoresizingMaskIntoConstraints = false
            customView.format = "banner"
            customView.nativeType = "small"
            customView.placementName = placement.name
            customView.placementMetadata = placement.metadata ?? [:]
            customView.configuredAd = customAd
            addSubview(customView)
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: trailingAnchor),
                customView.topAnchor.constraint(equalTo: topAnchor),
                customView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            return
        }
        guard let unit = placement.units.first(where: { $0.network == "admob" }) else { return }
        guard let root = UIApplication.shared.itwingVisibleViewController else { return }

        hasRequested = true
        showShimmer(kind: .banner)
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let size = currentOrientationAnchoredAdaptiveBanner(width: width)
        let banner = BannerView(adSize: size)
        banner.adUnitID = unit.adUnitId
        banner.rootViewController = root
        banner.delegate = self
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.topAnchor.constraint(equalTo: topAnchor),
            banner.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bannerView = banner
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "banner", "network": "admob"])
        banner.load(Request())
    }

    public func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        removeShimmer()
        if let placement = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }) {
            AdLoadBackoff.recordSuccess(placement)
        }
        AnalyticsClient.shared.track("ad_impression", properties: ["placement": placementName, "format": "banner", "network": "admob"])
    }

    public func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        removeShimmer()
        hasRequested = false
        bannerView.removeFromSuperview()
        self.bannerView = nil
        isHidden = true
        if let placement = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }) {
            AdLoadBackoff.recordFailure(placement, error: error)
            if let fallback = placement.fallbackCustomAd(in: ITWingSDK.config) {
                let customView = ITWingCustomNativeAdView()
                customView.translatesAutoresizingMaskIntoConstraints = false
                customView.format = "banner"
                customView.nativeType = "small"
                customView.placementName = placement.name
                customView.placementMetadata = placement.metadata ?? [:]
                customView.configuredAd = fallback
                addSubview(customView)
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    customView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    customView.topAnchor.constraint(equalTo: topAnchor),
                    customView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                hasRequested = true
                isHidden = false
                return
            }
        }
        AnalyticsClient.shared.track("ad_load_failed", properties: ["placement": placementName, "format": "banner", "network": "admob"])
    }

    private func showShimmer(kind: ITWingAdShimmerView.Kind) {
        removeShimmer()
        let shimmer = ITWingAdShimmerView(kind: kind)
        shimmer.tag = ITWingAdShimmerView.viewTag
        shimmer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shimmer)
        NSLayoutConstraint.activate([
            shimmer.leadingAnchor.constraint(equalTo: leadingAnchor),
            shimmer.trailingAnchor.constraint(equalTo: trailingAnchor),
            shimmer.topAnchor.constraint(equalTo: topAnchor),
            shimmer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func removeShimmer() {
        viewWithTag(ITWingAdShimmerView.viewTag)?.removeFromSuperview()
    }

}

open class ITWingNativeAdView: UIView, NativeAdLoaderDelegate, NativeAdDelegate {
    public var placementName: String = "native_large" {
        didSet { loadAdIfNeeded() }
    }

    private var adLoader: AdLoader?
    private var hasRequested = false
    private var observers: [NSObjectProtocol] = []

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
        observers = [.itwingConfigDidChange, .itwingAdsAvailabilityDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.unloadAd()
                if ITWingSDK.canRequestAds() {
                    self.loadAdIfNeeded()
                }
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            loadAdIfNeeded()
        } else {
            unloadAd()
        }
    }

    private func unloadAd() {
        adLoader?.delegate = nil
        adLoader = nil
        subviews.forEach { $0.removeFromSuperview() }
        hasRequested = false
    }

    public func loadAdIfNeeded() {
        guard window != nil, !hasRequested, ITWingSDK.canRequestAds() else { return }
        let enabledPlacements = ITWingSDK.config.ads.placements.filter(\.enabled)
        let nativePlacements = enabledPlacements.filter { $0.format == "native" }
        guard let placement = enabledPlacements.first(where: { $0.name == placementName })
                ?? nativePlacements.first else {
            return
        }
        guard AdLoadBackoff.canRequest(placement) else {
            if let fallback = placement.fallbackCustomAd(in: ITWingSDK.config) {
                renderCustomAd(fallback, placement: placement)
                isHidden = false
                return
            }
            isHidden = true
            return
        }
        isHidden = false

        if placement.format == "banner" {
            hasRequested = true
            let banner = ITWingBannerView()
            banner.translatesAutoresizingMaskIntoConstraints = false
            banner.placementName = placement.name
            addSubview(banner)
            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: trailingAnchor),
                banner.topAnchor.constraint(equalTo: topAnchor),
                banner.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            return
        }

        guard placement.format == "native" else { return }
        if placement.selectedCustomAd(in: ITWingSDK.config) != nil {
            renderCustom(placement)
            return
        }

        guard let unit = placement.units.first(where: { $0.network == "admob" }),
              let root = UIApplication.shared.itwingVisibleViewController else { return }

        hasRequested = true
        showShimmer()
        let options = NativeAdMediaAdLoaderOptions()
        let loader = AdLoader(adUnitID: unit.adUnitId, rootViewController: root, adTypes: [.native], options: [options])
        loader.delegate = self
        adLoader = loader
        AnalyticsClient.shared.track("ad_requested", properties: ["placement": placementName, "format": "native", "network": "admob"])
        loader.load(Request())
    }

    public func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        NSLog("[ITWingSDK] native ad loaded placement=%@", placementName)
        nativeAd.delegate = self
        guard let placement = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }) else { return }
        AdLoadBackoff.recordSuccess(placement)
        render(nativeAd, placement: placement)
        AnalyticsClient.shared.track("ad_impression", properties: ["placement": placementName, "format": "native", "network": "admob"])
    }

    public func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        NSLog("[ITWingSDK] native ad failed placement=%@ error=%@", placementName, String(describing: error))
        removeShimmer()
        AnalyticsClient.shared.track("ad_load_failed", properties: ["placement": placementName, "format": "native", "network": "admob"])
        if let placement = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }) {
            AdLoadBackoff.recordFailure(placement, error: error)
        }
        if let fallback = customFallbackPlacement() {
            NSLog("[ITWingSDK] using custom native fallback requested=%@ fallback=%@", placementName, fallback.name)
            if let requested = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }),
               let fallbackAd = fallback.selectedCustomAd(in: ITWingSDK.config) {
                // The fallback supplies campaign content; the requested real
                // placement continues to own colors, template and sizing.
                renderCustomAd(fallbackAd, placement: requested)
            } else {
                renderCustom(fallback)
            }
            return
        }
        if let placement = ITWingSDK.config.ads.placements.first(where: { $0.name == placementName }) {
            if let fallbackAd = placement.fallbackCustomAd(in: ITWingSDK.config) {
                renderCustomAd(fallbackAd, placement: placement)
                return
            }
        }
        hasRequested = false
        adLoader.delegate = nil
        self.adLoader = nil
        isHidden = true
    }

    private func renderCustom(_ placement: AdPlacementConfig) {
        adLoader?.delegate = nil
        adLoader = nil
        subviews.forEach { $0.removeFromSuperview() }
        hasRequested = true
        let customView = ITWingCustomNativeAdView()
        customView.translatesAutoresizingMaskIntoConstraints = false
        customView.format = "native"
        customView.configuredAd = placement.selectedCustomAd(in: ITWingSDK.config)
        customView.placementMetadata = placement.metadata ?? [:]
        customView.nativeType = ((placement.metadata?["native_type"] ?? nil)
            ?? (placement.metadata?["native_template"] ?? nil)) ?? "large"
        customView.placementName = placement.name
        addSubview(customView)
        NSLayoutConstraint.activate([
            customView.leadingAnchor.constraint(equalTo: leadingAnchor),
            customView.trailingAnchor.constraint(equalTo: trailingAnchor),
            customView.topAnchor.constraint(equalTo: topAnchor),
            customView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func renderCustomAd(_ ad: ITWingCustomAd, placement: AdPlacementConfig) {
        adLoader?.delegate = nil
        adLoader = nil
        subviews.forEach { $0.removeFromSuperview() }
        hasRequested = true
        let customView = ITWingCustomNativeAdView()
        customView.translatesAutoresizingMaskIntoConstraints = false
        customView.format = "native"
        customView.configuredAd = ad
        customView.placementMetadata = placement.metadata ?? [:]
        customView.nativeType = ((placement.metadata?["native_type"] ?? nil)
            ?? (placement.metadata?["native_template"] ?? nil)) ?? "large"
        customView.placementName = placement.name
        addSubview(customView)
        NSLayoutConstraint.activate([
            customView.leadingAnchor.constraint(equalTo: leadingAnchor),
            customView.trailingAnchor.constraint(equalTo: trailingAnchor),
            customView.topAnchor.constraint(equalTo: topAnchor),
            customView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func customFallbackPlacement() -> AdPlacementConfig? {
        let requested = ITWingSDK.config.ads.placements.first { $0.name == placementName }
        let requestedType = ((requested?.metadata?["native_type"] ?? nil)
            ?? (requested?.metadata?["native_template"] ?? nil)
            ?? (placementName.contains("small") ? "small" : "large")).lowercased()
        return ITWingSDK.config.ads.placements.first { candidate in
            guard candidate.enabled, candidate.format == "native",
                  candidate.selectedCustomAd(in: ITWingSDK.config) != nil else { return false }
            let candidateType = ((candidate.metadata?["native_type"] ?? nil)
                ?? (candidate.metadata?["native_template"] ?? nil)
                ?? (candidate.name.contains("small") ? "small" : "large")).lowercased()
            return candidateType == requestedType
        }
    }

    private func render(_ ad: NativeAd, placement: AdPlacementConfig) {
        let template = ((placement.metadata?["native_type"] ?? nil)
            ?? (placement.metadata?["native_template"] ?? nil)
            ?? "large").lowercased()
        if template == "small" {
            renderSmall(ad, placement: placement)
            return
        }
        subviews.forEach { $0.removeFromSuperview() }

        let nativeView = NativeAdView()
        nativeView.translatesAutoresizingMaskIntoConstraints = false
        nativeView.clipsToBounds = false
        addSubview(nativeView)
        let adChoices = AdChoicesView()
        adChoices.translatesAutoresizingMaskIntoConstraints = false
        adChoices.clipsToBounds = false
        adChoices.accessibilityIdentifier = "ad_choices"
        nativeView.addSubview(adChoices)
        nativeView.adChoicesView = adChoices

        let metadata = placement.metadata ?? [:]
        let card = ITWingNativeGradientCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 28
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.33).cgColor
        card.clipsToBounds = true
        if !metadata.itwingBool("native_transparent_background", defaultValue: true) {
            card.useSolidColor(metadata.itwingColor("native_background_color", fallback: .clear))
        }
        nativeView.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 10)
        stack.addArrangedSubview(header)

        let icon = UIImageView()
        icon.image = ad.icon?.image
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 7
        icon.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 35),
            icon.heightAnchor.constraint(equalToConstant: 35),
        ])
        header.addArrangedSubview(icon)
        nativeView.iconView = icon

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.spacing = 2
        header.addArrangedSubview(titleStack)

        let headline = UILabel()
        headline.text = ad.headline
        headline.font = .systemFont(ofSize: 16, weight: .bold)
        headline.textColor = metadata.itwingColor(
            ["native_headline_text_color", "headline_text_color"],
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1))
        )
        headline.numberOfLines = 2
        titleStack.addArrangedSubview(headline)
        nativeView.headlineView = headline

        let details = UIStackView()
        details.axis = .horizontal
        details.spacing = 5
        details.alignment = .center
        titleStack.addArrangedSubview(details)

        let metaColor = metadata.itwingColor(
            "native_meta_text_color",
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1))
        )
        let advertiser = nativeDetailLabel(text: ad.advertiser, size: 14, bold: true, color: metaColor)
        details.addArrangedSubview(advertiser)
        nativeView.advertiserView = advertiser

        let price = nativeDetailLabel(text: ad.price, size: 12, color: metaColor)
        details.addArrangedSubview(price)
        nativeView.priceView = price

        let rating = UILabel()
        let ratingValue = ad.starRating?.doubleValue ?? 0
        rating.text = ratingValue > 0 ? starText(ratingValue) : nil
        rating.font = .systemFont(ofSize: 11, weight: .semibold)
        rating.textColor = UIColor(red: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
        rating.setContentCompressionResistancePriority(.required, for: .horizontal)
        details.addArrangedSubview(rating)
        nativeView.starRatingView = rating

        let store = nativeDetailLabel(text: ad.store, size: 12, color: metaColor)
        details.addArrangedSubview(store)
        nativeView.storeView = store
        details.addArrangedSubview(UIView())

        if let body = ad.body {
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
            bodyLabel.textColor = metadata.itwingColor(
                ["native_body_text_color", "body_text_color"],
                fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1))
            )
            bodyLabel.numberOfLines = 3
            stack.addArrangedSubview(bodyLabel)
            nativeView.bodyView = bodyLabel
        }

        let mediaView = MediaView()
        mediaView.mediaContent = ad.mediaContent
        mediaView.clipsToBounds = true
        mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        mediaView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.addArrangedSubview(mediaView)
        nativeView.mediaView = mediaView

        let cta = UIButton(type: .system)
        cta.setTitle(ad.callToAction ?? "Open", for: .normal)
        cta.backgroundColor = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        cta.setTitleColor(metadata.itwingColor("native_cta_text_color", fallback: ITWingSDK.uiColor("cta_text_color", defaultValue: .white)), for: .normal)
        cta.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        cta.layer.cornerRadius = 17.5
        cta.heightAnchor.constraint(equalToConstant: 35).isActive = true
        stack.addArrangedSubview(cta)
        nativeView.callToActionView = cta
        cta.isUserInteractionEnabled = false

        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = "Ad"
        badge.accessibilityIdentifier = "ad_attribution"
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .clear
        badge.textColor = metadata.itwingColor("native_ad_label_text_color", fallback: ITWingSDK.uiColor("ad_label_text_color", defaultValue: .white))
        let badgeBackground = ITWingAdBadgeBackground()
        badgeBackground.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.color = ITWingSDK.uiColor("primary", defaultValue: .systemGreen)
        card.addSubview(badgeBackground)
        card.addSubview(badge)
        NSLayoutConstraint.activate([
            nativeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeView.topAnchor.constraint(equalTo: topAnchor),
            nativeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor),
            card.topAnchor.constraint(equalTo: nativeView.topAnchor),
            card.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            badge.widthAnchor.constraint(equalToConstant: 25),
            badge.heightAnchor.constraint(equalToConstant: 20),
            badgeBackground.leadingAnchor.constraint(equalTo: badge.leadingAnchor),
            badgeBackground.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
            badgeBackground.topAnchor.constraint(equalTo: badge.topAnchor),
            badgeBackground.bottomAnchor.constraint(equalTo: badge.bottomAnchor),
            adChoices.topAnchor.constraint(equalTo: nativeView.topAnchor, constant: 6),
            adChoices.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -6),
            adChoices.widthAnchor.constraint(equalToConstant: 30),
            adChoices.heightAnchor.constraint(equalToConstant: 30),
        ])
        card.bringSubviewToFront(badge)
        nativeView.bringSubviewToFront(adChoices)
        nativeView.layoutIfNeeded()
        nativeView.nativeAd = ad
        nativeView.alpha = 0
        UIView.animate(withDuration: 0.25) {
            nativeView.alpha = 1
        }
    }

    private func renderSmall(_ ad: NativeAd, placement: AdPlacementConfig) {
        subviews.forEach { $0.removeFromSuperview() }
        let metadata = placement.metadata ?? [:]
        let nativeView = NativeAdView()
        nativeView.translatesAutoresizingMaskIntoConstraints = false
        nativeView.clipsToBounds = false
        let adChoices = AdChoicesView()
        adChoices.translatesAutoresizingMaskIntoConstraints = false
        adChoices.clipsToBounds = false
        adChoices.accessibilityIdentifier = "ad_choices"
        let card = ITWingNativeGradientCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 28
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.33).cgColor
        card.clipsToBounds = true
        if !metadata.itwingBool("native_transparent_background", defaultValue: true) {
            card.useSolidColor(metadata.itwingColor("native_background_color", fallback: .clear))
        }
        addSubview(nativeView)
        nativeView.addSubview(card)
        nativeView.addSubview(adChoices)
        nativeView.adChoicesView = adChoices

        let headlineColor = metadata.itwingColor(
            ["native_headline_text_color", "headline_text_color"],
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 248/255, green: 250/255, blue: 252/255, alpha: 1))
        )
        let bodyColor = metadata.itwingColor(
            ["native_body_text_color", "body_text_color"],
            fallback: ITWingSDK.uiColor("native_text_color", defaultValue: UIColor(red: 203/255, green: 213/255, blue: 225/255, alpha: 1))
        )
        let metaColor = metadata.itwingColor("native_meta_text_color", fallback: bodyColor)

        let body = UILabel()
        body.text = ad.body
        body.font = .systemFont(ofSize: 12)
        body.textColor = bodyColor
        body.numberOfLines = 3
        nativeView.bodyView = body
        let bodyRow = UIStackView(arrangedSubviews: [body])
        bodyRow.isLayoutMarginsRelativeArrangement = true
        bodyRow.layoutMargins = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 0)

        let headline = UILabel()
        headline.text = ad.headline
        headline.font = .systemFont(ofSize: 12, weight: .bold)
        headline.textColor = headlineColor
        headline.numberOfLines = 2
        nativeView.headlineView = headline

        let icon = UIImageView(image: ad.icon?.image)
        icon.contentMode = .scaleAspectFit
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        nativeView.iconView = icon

        let store = nativeDetailLabel(text: ad.store, size: 12, bold: true, color: metaColor)
        store.textAlignment = .center
        nativeView.storeView = store
        let rating = UILabel()
        let ratingValue = ad.starRating?.doubleValue ?? 0
        rating.text = ratingValue > 0 ? starText(ratingValue) : nil
        rating.font = .systemFont(ofSize: 11, weight: .semibold)
        rating.textColor = UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
        nativeView.starRatingView = rating
        let storeRating = UIStackView(arrangedSubviews: [store, rating])
        storeRating.axis = .vertical
        storeRating.alignment = .center
        let iconRow = UIStackView(arrangedSubviews: [icon, storeRating])
        iconRow.axis = .horizontal
        iconRow.alignment = .center
        iconRow.spacing = 3

        let price = nativeDetailLabel(text: ad.price, size: 12, color: metaColor)
        let advertiser = nativeDetailLabel(text: ad.advertiser, size: 12, color: metaColor)
        nativeView.priceView = price
        nativeView.advertiserView = advertiser
        let advertiserRow = UIStackView(arrangedSubviews: [price, advertiser, UIView()])
        advertiserRow.axis = .horizontal
        advertiserRow.spacing = 3

        let cta = UIButton(type: .system)
        cta.setTitle(ad.callToAction ?? "Install", for: .normal)
        cta.backgroundColor = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        cta.setTitleColor(metadata.itwingColor("native_cta_text_color", fallback: .white), for: .normal)
        cta.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        cta.layer.cornerRadius = 20
        cta.heightAnchor.constraint(equalToConstant: 40).isActive = true
        cta.isUserInteractionEnabled = false
        nativeView.callToActionView = cta

        let info = UIStackView(arrangedSubviews: [headline, iconRow, advertiserRow, cta])
        info.axis = .vertical
        info.spacing = 3

        let media = MediaView()
        media.mediaContent = ad.mediaContent
        media.clipsToBounds = true
        media.heightAnchor.constraint(equalToConstant: 130).isActive = true
        media.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        nativeView.mediaView = media
        let columns = UIStackView(arrangedSubviews: [info, media])
        columns.axis = .horizontal
        columns.spacing = 0
        media.widthAnchor.constraint(equalTo: info.widthAnchor, multiplier: 2).isActive = true

        let content = UIStackView(arrangedSubviews: [bodyRow, columns])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 4
        card.addSubview(content)

        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = "Ad"
        badge.accessibilityIdentifier = "ad_attribution"
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textAlignment = .center
        badge.textColor = metadata.itwingColor("native_ad_label_text_color", fallback: .white)
        let badgeBackground = ITWingAdBadgeBackground()
        badgeBackground.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.color = ITWingSDK.uiColor("primary", defaultValue: .systemGreen)
        card.addSubview(badgeBackground)
        card.addSubview(badge)
        NSLayoutConstraint.activate([
            nativeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nativeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nativeView.topAnchor.constraint(equalTo: topAnchor),
            nativeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor),
            card.topAnchor.constraint(equalTo: nativeView.topAnchor),
            card.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 25),
            badge.heightAnchor.constraint(equalToConstant: 20),
            badgeBackground.leadingAnchor.constraint(equalTo: badge.leadingAnchor),
            badgeBackground.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
            badgeBackground.topAnchor.constraint(equalTo: badge.topAnchor),
            badgeBackground.bottomAnchor.constraint(equalTo: badge.bottomAnchor),
            adChoices.topAnchor.constraint(equalTo: nativeView.topAnchor, constant: 6),
            adChoices.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -6),
            adChoices.widthAnchor.constraint(equalToConstant: 30),
            adChoices.heightAnchor.constraint(equalToConstant: 30),
        ])
        nativeView.bringSubviewToFront(adChoices)
        nativeView.layoutIfNeeded()
        nativeView.nativeAd = ad
    }

    private func nativeDetailLabel(text: String?, size: CGFloat, bold: Bool = false, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        label.textColor = color
        label.numberOfLines = 1
        label.isHidden = text?.isEmpty ?? true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func starText(_ rating: Double) -> String {
        let rounded = Int(rating.rounded())
        return String(repeating: "★", count: max(0, min(5, rounded)))
            + String(repeating: "☆", count: max(0, 5 - min(5, rounded)))
    }

    private func showShimmer() {
        subviews.forEach { $0.removeFromSuperview() }
        let shimmer = ITWingAdShimmerView(kind: .nativeLarge)
        shimmer.tag = ITWingAdShimmerView.viewTag
        shimmer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shimmer)
        NSLayoutConstraint.activate([
            shimmer.leadingAnchor.constraint(equalTo: leadingAnchor),
            shimmer.trailingAnchor.constraint(equalTo: trailingAnchor),
            shimmer.topAnchor.constraint(equalTo: topAnchor),
            shimmer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func removeShimmer() {
        viewWithTag(ITWingAdShimmerView.viewTag)?.removeFromSuperview()
    }
}

private final class ITWingNativeGradientCard: UIView {
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

private final class ITWingAdBadgeBackground: UIView {
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
    func itwingBool(_ key: String, defaultValue: Bool) -> Bool {
        guard let raw = self[key] ?? nil else { return defaultValue }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return defaultValue
        }
    }

    func itwingColor(_ key: String, fallback: UIColor) -> UIColor {
        UIColor.itwingHex(self[key] ?? nil, fallback: fallback)
    }

    func itwingColor(_ keys: [String], fallback: UIColor) -> UIColor {
        for key in keys {
            if let value = self[key] ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return UIColor.itwingHex(value, fallback: fallback)
            }
        }
        return fallback
    }
}

private final class ITWingAdShimmerView: UIView {
    enum Kind { case banner, nativeLarge }
    static let viewTag = 918_204
    private let gradient = CAGradientLayer()

    init(kind: Kind) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.72)
        layer.cornerRadius = kind == .banner ? 8 : 18
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        if kind == .nativeLarge {
            let header = UIStackView()
            header.axis = .horizontal
            header.alignment = .center
            header.spacing = 10
            header.addArrangedSubview(block(width: 35, height: 35))
            let titles = UIStackView()
            titles.axis = .vertical
            titles.alignment = .leading
            titles.spacing = 6
            titles.addArrangedSubview(block(height: 15))
            titles.addArrangedSubview(block(width: 150, height: 12))
            header.addArrangedSubview(titles)
            stack.addArrangedSubview(header)
            stack.addArrangedSubview(block(height: 12))
            stack.addArrangedSubview(block(height: 120))
            stack.addArrangedSubview(block(height: 35))
        } else {
            stack.addArrangedSubview(block(height: 14))
            stack.addArrangedSubview(block(width: 180, height: 11))
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        gradient.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.20).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -UIScreen.main.bounds.width
        animation.toValue = UIScreen.main.bounds.width
        animation.duration = 1.15
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "itwing.shimmer")
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func block(width: CGFloat? = nil, height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        if let width {
            let constraint = view.widthAnchor.constraint(equalToConstant: width)
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }
        return view
    }
}

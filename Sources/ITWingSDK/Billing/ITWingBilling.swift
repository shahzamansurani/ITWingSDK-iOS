import StoreKit
import UIKit
import WebKit

public struct ITWingActiveSubscription: Sendable {
    public let productId: String
    public let name: String
    public let displayPrice: String
    public let productType: String
    public let billingPeriod: String
    public let removesAds: Bool
    public let expiryDate: Date?
}

public final class ITWingSubscriptionManager {
    public static let shared = ITWingSubscriptionManager()

    public private(set) var hasPremiumAccess = false
    public private(set) var activeSubscription: ITWingActiveSubscription?
    public private(set) var lastStoreKitMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var loadedStoreProductIds: Set<String> = []

    private init() {
        if #available(iOS 15.0, *) {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else { continue }
                    _ = await self?.verifyWithBackend(transaction: transaction, signedTransaction: result.jwsRepresentation)
                    await transaction.finish()
                    await self?.sync()
                }
            }
        }
    }

    @available(iOS 15.0, *)
    public func sync() async {
        let configs = Dictionary(uniqueKeysWithValues: ITWingSDK.subscriptionProducts()
            .filter { $0.store == "app_store" }
            .map { ($0.productId, $0) })
        let productsById = await loadStoreProducts(configs: Array(configs.values))
        var latest: ITWingActiveSubscription?
        var removesAds = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let productConfig = configs[transaction.productID],
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            _ = await verifyWithBackend(
                transaction: transaction,
                signedTransaction: result.jwsRepresentation,
                storeProduct: productsById[transaction.productID]
            )
            let candidate = ITWingActiveSubscription(
                productId: transaction.productID,
                name: productConfig.name,
                displayPrice: productsById[transaction.productID]?.displayPrice ?? formattedPrice(productConfig),
                productType: productConfig.productType,
                billingPeriod: productsById[transaction.productID]?.subscription?.subscriptionPeriod.displayLabel ?? productConfig.billingPeriod,
                removesAds: productConfig.removesAds,
                expiryDate: transaction.expirationDate
            )
            if latest == nil || (candidate.expiryDate ?? .distantFuture) > (latest?.expiryDate ?? .distantPast) {
                latest = candidate
            }
            removesAds = removesAds || productConfig.removesAds
        }
        let resolvedSubscription = latest
        let shouldRemoveAds = removesAds
        await MainActor.run {
            self.hasPremiumAccess = resolvedSubscription != nil
            self.activeSubscription = resolvedSubscription
            ITWingSDK.setPremiumAdsBlocked(shouldRemoveAds)
        }
    }

    @available(iOS 15.0, *)
    public func purchase(_ config: SubscriptionProductConfig, from presenter: UIViewController) async -> Bool {
        do {
            guard let product = try await Product.products(for: [config.productId]).first else {
                await MainActor.run {
                    let message = self.storeKitUnavailableMessage(for: config)
                    self.lastStoreKitMessage = message
                    ITWingUI.showError(from: presenter, title: "Purchase unavailable", message: message)
                }
                return false
            }
            ITWingSDK.setPurchaseFlowAdsBlocked(true)
            defer { ITWingSDK.setPurchaseFlowAdsBlocked(false) }
            let result = try await product.purchase()
            guard case .success(let verification) = result,
                  case .verified(let transaction) = verification else {
                return false
            }
            // StoreKit's `.verified` result is the cryptographic purchase
            // authority on-device. Backend verification records and syncs the
            // entitlement across IT Wing services, but a temporary backend or
            // network failure must not turn a completed App Store purchase into
            // an app-visible failure. `sync()` retries this acknowledgement on
            // launch and restore.
            let backendVerified = await verifyWithBackend(
                transaction: transaction,
                signedTransaction: verification.jwsRepresentation,
                storeProduct: product
            )
            if !backendVerified {
                AnalyticsClient.shared.track("app_store_verification_deferred", properties: [
                    "product_id": transaction.productID,
                    "transaction_id": String(transaction.id),
                ])
            }
            await transaction.finish()
            if config.consumable {
                return true
            }
            let active = ITWingActiveSubscription(
                productId: transaction.productID,
                name: config.name,
                displayPrice: product.displayPrice,
                productType: config.productType,
                billingPeriod: product.subscription?.subscriptionPeriod.displayLabel ?? config.billingPeriod,
                removesAds: config.removesAds,
                expiryDate: transaction.expirationDate
            )
            await MainActor.run {
                self.hasPremiumAccess = true
                self.activeSubscription = active
                ITWingSDK.setPremiumAdsBlocked(config.removesAds)
            }
            return true
        } catch {
            await MainActor.run {
                ITWingUI.showError(from: presenter, title: "Purchase failed", message: "The purchase could not be completed. Please try again.")
            }
            return false
        }
    }

    @available(iOS 15.0, *)
    public func restore(from presenter: UIViewController? = nil) async -> Bool {
        do {
            try await AppStore.sync()
            await sync()
            if !hasPremiumAccess, let presenter {
                await MainActor.run {
                    ITWingUI.showError(from: presenter, title: "No purchases found", message: "No active subscription or non-consumable purchase was found for this Apple ID.")
                }
            }
            return hasPremiumAccess
        } catch {
            if let presenter {
                await MainActor.run {
                    ITWingUI.showError(from: presenter, title: "Restore failed", message: error.localizedDescription)
                }
            }
            return false
        }
    }

    @available(iOS 15.0, *)
    @MainActor
    public func showPurchaseDialog(
        from presenter: UIViewController,
        completion: ((Bool) -> Void)? = nil
    ) {
        let configs = ITWingSDK.subscriptionProducts().filter { $0.store == "app_store" }
        guard !configs.isEmpty else {
            ITWingUI.showError(from: presenter, title: "No products", message: "No App Store subscriptions or purchases are enabled for this app in IT Wing admin.")
            completion?(false)
            return
        }

        Task {
            let productsById = await self.loadStoreProducts(configs: configs)
            // Never turn a transient StoreKit/App Store catalog failure into an
            // empty paywall. Admin configuration remains the source of which
            // plans are offered; StoreKit supplies the authoritative localized
            // price and is still required before a purchase can complete.
            let unavailableProductIds = configs
                .map(\.productId)
                .filter { productsById[$0] == nil }
            let dialog = ITWingPurchaseViewController(
                configs: configs,
                storeProducts: productsById,
                storeKitMessage: unavailableProductIds.isEmpty
                    ? nil
                    : self.missingStoreKitProductsMessage(unavailableProductIds),
                activeSubscription: activeSubscription,
                purchase: { [weak self] config, controller in
                    guard let self else { return false }
                    return await self.purchase(config, from: controller)
                },
                restore: { [weak self] controller in
                    guard let self else { return false }
                    return await self.restore(from: controller)
                },
                completion: completion
            )
            dialog.modalPresentationStyle = .formSheet
            dialog.preferredContentSize = CGSize(width: 620, height: 760)
            if let sheet = dialog.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
            presenter.present(dialog, animated: true)
        }
    }

    @available(iOS 15.0, *)
    public func diagnostics() -> [String: Any] {
        let configured = ITWingSDK.subscriptionProducts()
            .filter { $0.store == "app_store" }
            .map(\.productId)
        return [
            "configured_products": configured,
            "loaded_store_products": Array(loadedStoreProductIds).sorted(),
            "missing_store_products": configured.filter { !loadedStoreProductIds.contains($0) },
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "last_storekit_message": lastStoreKitMessage ?? "",
        ]
    }

    @available(iOS 15.0, *)
    private func verifyWithBackend(transaction: Transaction, signedTransaction: String, storeProduct: Product? = nil) async -> Bool {
        let config = ITWingSDK.subscriptionProducts().first { $0.store == "app_store" && $0.productId == transaction.productID }
        var payload: [String: Any] = [
            "store": "app_store",
            "product_type": config?.productType ?? (transaction.productType == .autoRenewable ? "subscription" : "inapp"),
            "product_id": transaction.productID,
            "signed_transaction_info": signedTransaction,
            "original_transaction_id": "\(transaction.originalID)",
            "order_id": String(transaction.id)
        ]
        if let webOrderLineItemID = transaction.webOrderLineItemID {
            payload["web_order_line_item_id"] = "\(webOrderLineItemID)"
        }
        if let subscriptionGroupID = storeProduct?.subscription?.subscriptionGroupID ?? config?.subscriptionGroupId, !subscriptionGroupID.isEmpty {
            payload["subscription_group_id"] = subscriptionGroupID
        }
        if let price = transaction.price {
            payload["charged_price"] = NSDecimalNumber(decimal: price).doubleValue
        }
        if #available(iOS 16.0, *), let currency = transaction.currency?.identifier {
            payload["charged_currency"] = currency
        }
        do {
            return try await ITWingSDK.repo?.verifyPurchase(payload: payload) ?? false
        } catch {
            return false
        }
    }

    private func formattedPrice(_ config: SubscriptionProductConfig?) -> String {
        guard let price = config?.price else { return "See price in App Store" }
        return "\(config?.currency ?? "") \(price)"
    }

    @available(iOS 15.0, *)
    private func loadStoreProducts(configs: [SubscriptionProductConfig]) async -> [String: Product] {
        let productIds = Array(Set(configs.map(\.productId).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !productIds.isEmpty else {
            await MainActor.run {
                self.loadedStoreProductIds = []
                self.lastStoreKitMessage = "No App Store product IDs are configured in ITWing admin."
            }
            return [:]
        }

        var lastError: Error?
        for attempt in 1...3 {
            do {
                let products = try await Product.products(for: productIds)
                let productsById = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
                if !productsById.isEmpty || attempt == 3 {
                    let loadedIds = Set(productsById.keys)
                    let missingIds = productIds.filter { !loadedIds.contains($0) }
                    await MainActor.run {
                        self.loadedStoreProductIds = loadedIds
                        self.lastStoreKitMessage = missingIds.isEmpty ? nil : self.missingStoreKitProductsMessage(missingIds)
                    }
                    return productsById
                }
            } catch {
                lastError = error
                if attempt == 3 { break }
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
        }
        await MainActor.run {
            self.loadedStoreProductIds = []
            self.lastStoreKitMessage = "StoreKit could not load App Store products: \(lastError?.localizedDescription ?? "Unknown App Store error")"
        }
        return [:]
    }

    private func storeKitUnavailableMessage(for config: SubscriptionProductConfig) -> String {
        lastStoreKitMessage?.nonEmpty
            ?? missingStoreKitProductsMessage([config.productId])
    }

    private func missingStoreKitProductsMessage(_ productIds: [String]) -> String {
        let ids = productIds.joined(separator: ", ")
        return "The App Store did not return product details for \(ids). Confirm the bundle ID, App Store Connect app record, product status, signed build/TestFlight or StoreKit configuration file, Paid Apps agreements, and exact product ID."
    }
}

@available(iOS 15.0, *)
private final class ITWingPurchaseViewController: UIViewController {
    private let configs: [SubscriptionProductConfig]
    private let storeProducts: [String: Product]
    private let storeKitMessage: String?
    private let activeSubscription: ITWingActiveSubscription?
    private let purchase: (SubscriptionProductConfig, UIViewController) async -> Bool
    private let restore: (UIViewController) async -> Bool
    private let completion: ((Bool) -> Void)?
    private let statusLabel = UILabel()
    private var deliveredResult = false

    init(
        configs: [SubscriptionProductConfig],
        storeProducts: [String: Product],
        storeKitMessage: String?,
        activeSubscription: ITWingActiveSubscription?,
        purchase: @escaping (SubscriptionProductConfig, UIViewController) async -> Bool,
        restore: @escaping (UIViewController) async -> Bool,
        completion: ((Bool) -> Void)?
    ) {
        self.configs = configs
        self.storeProducts = storeProducts
        self.storeKitMessage = storeKitMessage
        self.activeSubscription = activeSubscription
        self.purchase = purchase
        self.restore = restore
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let primary = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        view.backgroundColor = ITWingSDK.uiColor("dialog_background_color", defaultValue: .systemBackground)

        let scroll = UIScrollView()
        let content = UIStackView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 12
        view.addSubview(scroll)
        scroll.addSubview(content)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        let heading = UILabel()
        heading.text = "Choose your premium plan"
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        heading.textColor = ITWingSDK.uiColor("premium_title_color", defaultValue: .label)
        heading.numberOfLines = 2
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = ITWingSDK.uiColor("secondary_text_color", defaultValue: .secondaryLabel)
        close.accessibilityLabel = "Close"
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true
        close.addAction(UIAction { [weak self] _ in self?.dismissResult(false) }, for: .touchUpInside)
        header.addArrangedSubview(heading)
        header.addArrangedSubview(close)
        content.addArrangedSubview(header)

        let subtitle = UILabel()
        subtitle.numberOfLines = 0
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = ITWingSDK.uiColor("premium_text_color", defaultValue: .secondaryLabel)
        subtitle.text = activeSubscription == nil
            ? "Secure App Store checkout. Products, display settings, and entitlements come from this app's IT Wing admin configuration; localized prices come directly from the App Store."
            : "Your active purchase is shown below. App Store purchases are restored automatically for this Apple ID."
        content.addArrangedSubview(subtitle)

        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = primary
        statusLabel.isHidden = activeSubscription == nil && storeKitMessage?.nonEmpty == nil
        statusLabel.text = activeSubscription == nil
            ? storeKitMessage?.nonEmpty
            : activeDescription()
        content.addArrangedSubview(statusLabel)

        configs.forEach { content.addArrangedSubview(productCard(config: $0, primary: primary)) }

        let restoreButton = outlinedButton(title: "Restore purchases", color: primary)
        restoreButton.addAction(UIAction { [weak self, weak restoreButton] _ in
            guard let self else { return }
            restoreButton?.isEnabled = false
            restoreButton?.setTitle("Checking purchases...", for: .normal)
            Task {
                let restored = await self.restore(self)
                await MainActor.run {
                    restoreButton?.isEnabled = true
                    restoreButton?.setTitle(restored ? "Purchase restored" : "Restore purchases", for: .normal)
                    self.statusLabel.isHidden = false
                    self.statusLabel.text = restored ? "Your active App Store purchase was restored." : "No active purchase was found."
                    if restored { self.deliver(true) }
                }
            }
        }, for: .touchUpInside)
        content.addArrangedSubview(restoreButton)

        let legalLinks = UIStackView()
        legalLinks.axis = .horizontal
        legalLinks.alignment = .center
        legalLinks.distribution = .fillEqually
        legalLinks.spacing = 12
        let privacy = legalButton(title: "Privacy Policy", primary: primary)
        privacy.addAction(UIAction { [weak self] _ in
            self?.presentLegal(kind: "privacy", title: "Privacy Policy")
        }, for: .touchUpInside)
        let terms = legalButton(title: "Terms of Use (EULA)", primary: primary)
        terms.addAction(UIAction { [weak self] _ in
            self?.presentLegal(kind: "terms", title: "Terms of Use (EULA)")
        }, for: .touchUpInside)
        legalLinks.addArrangedSubview(privacy)
        legalLinks.addArrangedSubview(terms)
        content.addArrangedSubview(legalLinks)

        let renewal = label(
            "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel subscriptions in your App Store account settings.",
            size: 12,
            weight: .regular,
            color: .secondaryLabel
        )
        renewal.numberOfLines = 0
        renewal.textAlignment = .center
        content.addArrangedSubview(renewal)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        deliver(false)
    }

    private func productCard(config: SubscriptionProductConfig, primary: UIColor) -> UIView {
        let product = storeProducts[config.productId]
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 7
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.backgroundColor = ITWingSDK.uiColor("premium_card_background_color", defaultValue: .secondarySystemBackground)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = ITWingSDK.uiColor("premium_card_border_color", defaultValue: .separator).cgColor

        let name = label(config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (product?.displayName ?? config.productId) : config.name, size: 16, weight: .bold, color: .label)
        name.numberOfLines = 2
        name.textAlignment = .center
        card.addArrangedSubview(name)
        let billing = config.productType == "inapp" || config.billingPeriod == "lifetime"
            ? "Lifetime"
            : periodLabel(config: config, product: product)
        let price = label("\(product?.displayPrice ?? configuredPrice(config)) billed \(billing.lowercased())", size: 28, weight: .heavy, color: primary)
        price.numberOfLines = 2
        price.textAlignment = .center
        price.adjustsFontSizeToFitWidth = true
        price.minimumScaleFactor = 0.75
        price.setContentCompressionResistancePriority(.required, for: .vertical)
        card.addArrangedSubview(price)

        if let offer = offerText(config: config, product: product) {
            card.addArrangedSubview(label(offer, size: 13, weight: .semibold, color: primary))
        }
        let oneTime = config.productType == "inapp" || config.billingPeriod == "lifetime"
        let productType = oneTime ? "One-time purchase" : "Subscription"
        card.addArrangedSubview(label("Plan: \(config.name.nonEmpty ?? product?.displayName ?? config.productId)", size: 13, weight: .semibold, color: .secondaryLabel))
        card.addArrangedSubview(label("Billing: \(productType) | \(billing)", size: 13, weight: .semibold, color: .secondaryLabel))
        let description = config.productDescription?.nonEmpty
            ?? product?.description.nonEmpty
            ?? config.entitlements?.keys.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ").nonEmpty
            ?? "Secure App Store checkout. Active purchases are restored automatically."
        let descriptionLabel = label(description, size: 13, weight: .regular, color: .secondaryLabel)
        descriptionLabel.numberOfLines = 0
        card.addArrangedSubview(descriptionLabel)

        let owned = activeSubscription?.productId == config.productId
        let button = filledButton(title: owned ? "Active purchase" : (activeSubscription == nil || oneTime ? "Continue" : "Change plan"), color: primary)
        button.isEnabled = !owned
        button.alpha = button.isEnabled ? 1 : 0.65
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self else { return }
            button?.isEnabled = false
            button?.setTitle("Opening App Store...", for: .normal)
            self.statusLabel.isHidden = false
            self.statusLabel.text = "Opening secure App Store checkout..."
            Task {
                let success = await self.purchase(config, self)
                await MainActor.run {
                    if success {
                        self.statusLabel.text = "Purchase completed successfully."
                        self.dismissResult(true)
                    } else {
                        button?.isEnabled = true
                        button?.setTitle(self.activeSubscription == nil || oneTime ? "Continue" : "Change plan", for: .normal)
                        self.statusLabel.text = "The purchase was not completed. You can retry or restore an existing purchase."
                    }
                }
            }
        }, for: .touchUpInside)
        card.addArrangedSubview(button)
        return card
    }

    private func periodLabel(config: SubscriptionProductConfig, product: Product?) -> String {
        guard let period = product?.subscription?.subscriptionPeriod else {
            return config.billingPeriod.replacingOccurrences(of: "_", with: " ").capitalized
        }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit.capitalized : "\(period.value) \(unit)"
    }

    private func activeDescription() -> String {
        guard let activeSubscription else { return "" }
        let expiry = activeSubscription.expiryText
        return "Premium is active\nPlan: \(activeSubscription.name)\nBilling: \(activeSubscription.billingDisplay)\n\(expiry)"
    }

    private func offerText(config: SubscriptionProductConfig, product: Product?) -> String? {
        if let original = config.formattedOriginalPrice?.nonEmpty {
            return "\(config.offerLabel?.nonEmpty ?? "Limited offer"): was \(original)"
        }
        if product?.subscription?.introductoryOffer != nil {
            return config.offerLabel?.nonEmpty ?? "Introductory offer available"
        }
        return config.offerLabel?.nonEmpty
    }

    private func configuredPrice(_ config: SubscriptionProductConfig) -> String {
        guard let price = config.price else { return "See price in App Store" }
        return "\(config.currency ?? "") \(String(format: "%.2f", price))".trimmingCharacters(in: .whitespaces)
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let result = UILabel()
        result.text = text
        result.font = .systemFont(ofSize: size, weight: weight)
        result.textColor = color
        return result
    }

    private func filledButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }

    private func outlinedButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = color.cgColor
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }

    private func legalButton(title: String, primary: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(primary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    private func presentLegal(kind: String, title: String) {
        let urlString = ITWingSDK.appUrl(kind)
            ?? (kind == "terms" ? "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" : nil)
        let controller = ITWingLegalViewController(
            title: title,
            urlString: urlString,
            content: ITWingSDK.legalContent(kind)
        )
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    private func dismissResult(_ result: Bool) {
        deliver(result)
        dismiss(animated: true)
    }

    private func deliver(_ result: Bool) {
        guard !deliveredResult else { return }
        deliveredResult = true
        completion?(result)
    }
}

@available(iOS 15.0, *)
private final class ITWingLegalViewController: UIViewController {
    private let legalTitle: String
    private let urlString: String?
    private let content: String?

    init(title: String, urlString: String?, content: String?) {
        legalTitle = title
        self.urlString = urlString
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = legalTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if let urlString, let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        } else if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            webView.loadHTMLString(content, baseURL: nil)
        } else {
            webView.loadHTMLString("<html><body><p>This document is temporarily unavailable.</p></body></html>", baseURL: nil)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

open class ITWingPremiumView: UIView {
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsStack = UIStackView()
    private let planLabel = UILabel()
    private let billingLabel = UILabel()
    private let priceLabel = UILabel()
    private let expiryLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
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
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 20
        blur.clipsToBounds = true
        addSubview(blur)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.clipsToBounds = true
        blur.contentView.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        badgeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.clipsToBounds = true
        badgeLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = ITWingSDK.uiColor("premium_title_color", defaultValue: ITWingSDK.uiColor("text_color", defaultValue: .label))
        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = ITWingSDK.uiColor("premium_text_color", defaultValue: ITWingSDK.uiColor("secondary_text_color", defaultValue: .secondaryLabel))
        subtitleLabel.numberOfLines = 0
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        detailsStack.axis = .vertical
        detailsStack.spacing = 5
        [planLabel, billingLabel, priceLabel, expiryLabel].forEach {
            $0.font = .systemFont(ofSize: 13, weight: .semibold)
            $0.textColor = ITWingSDK.uiColor("premium_text_color", defaultValue: ITWingSDK.uiColor("secondary_text_color", defaultValue: .secondaryLabel))
            $0.numberOfLines = 0
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
            detailsStack.addArrangedSubview($0)
        }

        messageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        messageLabel.textColor = ITWingSDK.uiColor("primary", defaultValue: .systemBlue)
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        actionButton.layer.cornerRadius = 13
        actionButton.backgroundColor = ITWingSDK.uiColor("premium_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
        actionButton.setTitleColor(ITWingSDK.uiColor("premium_button_text_color", defaultValue: .white), for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        actionButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        actionButton.setContentCompressionResistancePriority(.required, for: .vertical)
        actionButton.addTarget(self, action: #selector(openPurchaseDialog), for: .touchUpInside)

        restoreButton.layer.cornerRadius = 13
        restoreButton.layer.borderWidth = 1
        restoreButton.layer.borderColor = ITWingSDK.uiColor("premium_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue)).cgColor
        restoreButton.setTitleColor(ITWingSDK.uiColor("premium_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue)), for: .normal)
        restoreButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        restoreButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        restoreButton.setContentCompressionResistancePriority(.required, for: .vertical)
        restoreButton.addTarget(self, action: #selector(restorePurchases), for: .touchUpInside)

        stack.addArrangedSubview(badgeLabel)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(detailsStack)
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(actionButton)
        stack.addArrangedSubview(restoreButton)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -14),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])
        observers = [.itwingPremiumEntitlementDidChange, .itwingAdsAvailabilityDidChange, .itwingConfigDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    open override var intrinsicContentSize: CGSize {
        let compactHeight: CGFloat = ITWingSubscriptionManager.shared.activeSubscription == nil ? 206 : 286
        return CGSize(width: UIView.noIntrinsicMetric, height: compactHeight)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let contentHeight = stack.systemLayoutSizeFitting(
            CGSize(width: max(0, bounds.width - 28), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + 28
        scrollView.isScrollEnabled = contentHeight > bounds.height + 1
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
        if #available(iOS 15.0, *) {
            Task {
                await ITWingSubscriptionManager.shared.sync()
                await MainActor.run { self.refresh() }
            }
        }
    }

    public func refresh() {
        applyColors()
        if let active = ITWingSubscriptionManager.shared.activeSubscription {
            badgeLabel.text = "ACTIVE"
            titleLabel.text = "Premium active"
            subtitleLabel.text = "Ads are disabled while this purchase remains active."
            detailsStack.isHidden = false
            planLabel.text = "Plan: \(active.name)"
            billingLabel.text = "Billing: \(active.productTypeDisplay) | \(active.billingDisplay)"
            priceLabel.text = "Price: \(active.displayPrice)"
            expiryLabel.text = active.expiryText
            actionButton.setTitle("Change plan", for: .normal)
            actionButton.isEnabled = !active.isOneTimePurchase
            actionButton.alpha = actionButton.isEnabled ? 1 : 0.72
            restoreButton.setTitle("Manage subscription", for: .normal)
            restoreButton.isHidden = active.isOneTimePurchase
        } else {
            badgeLabel.text = "AVAILABLE"
            titleLabel.text = "Remove ads"
            subtitleLabel.text = "Unlock premium and remove ads while your plan is active."
            detailsStack.isHidden = true
            actionButton.setTitle("View plans", for: .normal)
            actionButton.isEnabled = true
            actionButton.alpha = 1
            restoreButton.setTitle("Restore purchases", for: .normal)
            restoreButton.isHidden = false
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func applyColors() {
        let primary = ITWingSDK.uiColor("premium_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
        actionButton.backgroundColor = primary
        actionButton.setTitleColor(ITWingSDK.uiColor("premium_button_text_color", defaultValue: .white), for: .normal)
        restoreButton.layer.borderColor = primary.cgColor
        restoreButton.setTitleColor(primary, for: .normal)
        badgeLabel.textColor = primary
        badgeLabel.backgroundColor = primary.withAlphaComponent(0.12)
    }

    @objc private func openPurchaseDialog() {
        guard let presenter = UIApplication.shared.itwingVisibleViewController else { return }
        if #available(iOS 15.0, *) {
            ITWingSubscriptionManager.shared.showPurchaseDialog(from: presenter) { [weak self] _ in
                self?.refresh()
            }
        } else {
            ITWingUI.showError(from: presenter, title: "iOS update needed", message: "Purchases require iOS 15 or later.")
        }
    }

    @objc private func restorePurchases() {
        guard let presenter = UIApplication.shared.itwingVisibleViewController else { return }
        if let active = ITWingSubscriptionManager.shared.activeSubscription,
           !active.isOneTimePurchase,
           let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
            return
        }
        if #available(iOS 15.0, *) {
            restoreButton.isEnabled = false
            restoreButton.setTitle("Checking purchases...", for: .normal)
            Task {
                let restored = await ITWingSubscriptionManager.shared.restore(from: presenter)
                await MainActor.run {
                    self.restoreButton.isEnabled = true
                    self.messageLabel.isHidden = false
                    self.messageLabel.text = restored ? "Purchase restored." : "No active purchase was found."
                    self.refresh()
                }
            }
        } else {
            ITWingUI.showError(from: presenter, title: "iOS update needed", message: "Purchases require iOS 15 or later.")
        }
    }
}

private extension ITWingActiveSubscription {
    var productTypeDisplay: String {
        isOneTimePurchase ? "One-time purchase" : "Subscription"
    }

    var isOneTimePurchase: Bool {
        productType == "inapp" || billingPeriod == "lifetime"
    }

    var billingDisplay: String {
        billingPeriod.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var expiryText: String {
        if let expiryDate {
            return "Expires: \(DateFormatter.localizedString(from: expiryDate, dateStyle: .medium, timeStyle: .short))"
        }
        return isOneTimePurchase ? "Expiry: Lifetime" : "Expiry: Managed by App Store"
    }
}

@available(iOS 15.0, *)
private extension Product.SubscriptionPeriod {
    var displayLabel: String {
        let unitName: String
        switch unit {
        case .day: unitName = value == 1 ? "day" : "days"
        case .week: unitName = value == 1 ? "week" : "weeks"
        case .month: unitName = value == 1 ? "month" : "months"
        case .year: unitName = value == 1 ? "year" : "years"
        @unknown default: unitName = "period"
        }
        return value == 1 ? unitName : "\(value) \(unitName)"
    }
}

import StoreKit
import UIKit

public struct ITWingActiveSubscription: Sendable {
    public let productId: String
    public let name: String
    public let displayPrice: String
    public let expiryDate: Date?
}

public final class ITWingSubscriptionManager {
    public static let shared = ITWingSubscriptionManager()

    public private(set) var hasPremiumAccess = false
    public private(set) var activeSubscription: ITWingActiveSubscription?

    private init() {}

    @available(iOS 15.0, *)
    public func sync() async {
        var latest: ITWingActiveSubscription?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable || transaction.productType == .nonConsumable else { continue }
            let productConfig = ITWingSDK.subscriptionProducts().first { $0.productId == transaction.productID }
            let products = try? await Product.products(for: [transaction.productID])
            latest = ITWingActiveSubscription(
                productId: transaction.productID,
                name: productConfig?.name ?? products?.first?.displayName ?? "Premium",
                displayPrice: products?.first?.displayPrice ?? formattedPrice(productConfig),
                expiryDate: transaction.expirationDate
            )
        }
        await MainActor.run {
            self.hasPremiumAccess = latest != nil
            self.activeSubscription = latest
        }
    }

    @available(iOS 15.0, *)
    public func purchase(_ config: SubscriptionProductConfig, from presenter: UIViewController) async -> Bool {
        do {
            guard let product = try await Product.products(for: [config.productId]).first else {
                await MainActor.run {
                    ITWingUI.showError(from: presenter, title: "Purchase unavailable", message: "This plan is not available from the App Store right now.")
                }
                return false
            }
            let result = try await product.purchase()
            guard case .success(let verification) = result, case .verified(let transaction) = verification else {
                return false
            }
            await transaction.finish()
            let active = ITWingActiveSubscription(
                productId: transaction.productID,
                name: config.name,
                displayPrice: product.displayPrice,
                expiryDate: transaction.expirationDate
            )
            await MainActor.run {
                self.hasPremiumAccess = true
                self.activeSubscription = active
            }
            var payload: [String: Any] = [
                "store": "app_store",
                "product_id": transaction.productID,
                "transaction_id": String(transaction.id),
            ]
            if let expiration = transaction.expirationDate {
                payload["expires_at"] = expiration.timeIntervalSince1970
            }
            try? await ITWingSDK.repo?.verifyPurchase(payload: payload)
            return true
        } catch {
            await MainActor.run {
                ITWingUI.showError(from: presenter, title: "Purchase failed", message: "The purchase could not be completed. Please try again.")
            }
            return false
        }
    }

    private func formattedPrice(_ config: SubscriptionProductConfig?) -> String {
        guard let price = config?.price else { return "Price unavailable" }
        return "\(config?.currency ?? "") \(price)"
    }
}

open class ITWingPremiumView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stack = UIStackView()

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

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = ITWingSDK.uiColor("premium_title_color", defaultValue: ITWingSDK.uiColor("text_color", defaultValue: .label))
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = ITWingSDK.uiColor("premium_text_color", defaultValue: ITWingSDK.uiColor("secondary_text_color", defaultValue: .secondaryLabel))
        subtitleLabel.numberOfLines = 0
        actionButton.layer.cornerRadius = 13
        actionButton.backgroundColor = ITWingSDK.uiColor("premium_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
        actionButton.setTitleColor(ITWingSDK.uiColor("premium_button_text_color", defaultValue: .white), for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        actionButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        actionButton.addTarget(self, action: #selector(openPurchaseDialog), for: .touchUpInside)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(actionButton)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -16),
        ])
        refresh()
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
        if let active = ITWingSubscriptionManager.shared.activeSubscription {
            titleLabel.text = "Premium active"
            let expiry = active.expiryDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "Managed by App Store"
            subtitleLabel.text = "\(active.name)\nExpires: \(expiry)"
            actionButton.setTitle("Change plan", for: .normal)
        } else {
            titleLabel.text = "Remove ads"
            subtitleLabel.text = "Unlock premium and remove ads while your plan is active."
            actionButton.setTitle("View plans", for: .normal)
        }
    }

    @objc private func openPurchaseDialog() {
        guard let presenter = UIApplication.shared.itwingVisibleViewController else { return }
        let products = ITWingSDK.subscriptionProducts().filter { $0.store.lowercased().contains("apple") || $0.store.lowercased().contains("app") || $0.store.isEmpty }
        guard !products.isEmpty else {
            ITWingUI.showError(from: presenter, title: "No plans", message: "No App Store subscription plans are configured for this app.")
            return
        }
        let sheet = UIAlertController(title: "Choose premium plan", message: nil, preferredStyle: .actionSheet)
        products.forEach { config in
            sheet.addAction(UIAlertAction(title: config.name, style: .default) { _ in
                if #available(iOS 15.0, *) {
                    Task {
                        let success = await ITWingSubscriptionManager.shared.purchase(config, from: presenter)
                        if success {
                            await MainActor.run { self.refresh() }
                        }
                    }
                } else {
                    ITWingUI.showError(from: presenter, title: "iOS update needed", message: "Purchases require iOS 15 or later.")
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presenter.present(sheet, animated: true)
    }
}

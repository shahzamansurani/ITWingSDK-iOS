import Lottie
import StoreKit
import UIKit

public enum ITWingDialogResult {
    case positive
    case negative
    case cancelled
}

public final class ITWingLoadingHandle {
    private var controller: UIViewController?
    private var dismissed = false

    init(controller: UIViewController?) {
        self.controller = controller
        // Final SDK-level safety net. Even if an ad manager loses ownership of
        // its request, a modal loading controller can never remain indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.dismiss()
        }
    }

    public func dismiss(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard !self.dismissed else {
                completion?()
                return
            }
            self.dismissed = true
            guard let controller = self.controller, controller.presentingViewController != nil else {
                self.controller = nil
                completion?()
                return
            }
            controller.dismiss(animated: true) {
                self.controller = nil
                completion?()
            }
        }
    }
}

public enum ITWingUI {
    static func presentationHost(fallback: UIViewController) -> UIViewController {
        var candidate = UIApplication.shared.itwingVisibleViewController ?? fallback
        while candidate.isBeingDismissed || candidate.navigationController?.isBeingDismissed == true {
            guard let presenting = candidate.presentingViewController else { break }
            candidate = presenting
        }
        return candidate
    }

    @discardableResult
    public static func showLoading(from presenter: UIViewController, title: String = "Loading") -> ITWingLoadingHandle {
        let controller = GlassDialogController(title: title, message: nil, positive: nil, negative: nil)
        controller.isModalInPresentation = true
        presenter.present(controller, animated: true)
        return ITWingLoadingHandle(controller: controller)
    }

    public static func showError(from presenter: UIViewController, title: String = "Connection issue", message: String, retry: (() -> Void)? = nil) {
        let controller = GlassDialogController(title: title, message: message, positive: retry == nil ? "OK" : "Retry", negative: retry == nil ? nil : "Cancel")
        controller.onResult = { result in
            if result == .positive {
                retry?()
            }
        }
        presenter.present(controller, animated: true)
    }

    public static func showActionDialog(
        from presenter: UIViewController,
        title: String? = nil,
        message: String? = nil,
        positive: String? = nil,
        negative: String? = nil,
        onResult: @escaping (ITWingDialogResult) -> Void
    ) {
        let config = ITWingSDK.config.dialogs
        guard config.enabled else {
            onResult(.negative)
            return
        }
        let controller = GlassDialogController(
            title: title ?? config.title,
            message: message ?? config.description,
            positive: positive ?? config.positiveButton,
            negative: negative ?? config.negativeButton
        )
        controller.onResult = onResult
        presenter.present(controller, animated: true)
    }

    public static func requestReview(from presenter: UIViewController) {
        if #available(iOS 14.0, *) {
            if let scene = presenter.view.window?.windowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        } else {
            SKStoreReviewController.requestReview()
        }
    }
}

final class GlassDialogController: UIViewController {
    var onResult: ((ITWingDialogResult) -> Void)?

    private let dialogTitle: String
    private let message: String?
    private let positive: String?
    private let negative: String?

    init(title: String, message: String?, positive: String?, negative: String?) {
        self.dialogTitle = title
        self.message = message
        self.positive = positive
        self.negative = negative
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        if positive == nil && negative == nil {
            buildLoadingPresentation()
            return
        }

        let blur = UIVisualEffectView(effect: nil)
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.backgroundColor = ITWingSDK.uiColor("dialog_background_color", defaultValue: UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.96))
        blur.layer.cornerRadius = 28
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.33).cgColor
        blur.clipsToBounds = true
        view.addSubview(blur)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = dialogTitle
        titleLabel.textColor = ITWingSDK.uiColor("dialog_title_color", defaultValue: .label)
        titleLabel.textAlignment = .left
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)

        if let message {
            let messageLabel = UILabel()
            messageLabel.text = message
            messageLabel.textColor = ITWingSDK.uiColor("dialog_description_color", defaultValue: .secondaryLabel)
            messageLabel.textAlignment = .left
            messageLabel.font = .systemFont(ofSize: 13, weight: .regular)
            messageLabel.numberOfLines = 0
            stack.addArrangedSubview(messageLabel)
        }

        let buttons = UIStackView()
        buttons.axis = .horizontal
        buttons.spacing = 16
        buttons.distribution = .fillEqually
        if let negative {
            buttons.addArrangedSubview(button(title: negative, filled: false, result: .negative))
        }
        if let positive {
            buttons.addArrangedSubview(button(title: positive, filled: true, result: .positive))
        }
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            blur.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            blur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blur.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            blur.widthAnchor.constraint(lessThanOrEqualToConstant: 430),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -18),
        ])
    }

    private func buildLoadingPresentation() {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = ITWingSDK.uiColor("loading_dialog_background_color", defaultValue: UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.96))
        card.layer.cornerRadius = 45
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.33).cgColor
        view.addSubview(card)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = ITWingSDK.uiColor("primary", defaultValue: .white)
        spinner.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        spinner.startAnimating()
        card.addSubview(spinner)

        if let source = ITWingSDK.config.app.loadingLottieUrl,
           let url = URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines)),
           !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let didLoad: (LottieAnimationView, Error?) -> Void = { view, error in
                DispatchQueue.main.async {
                    guard error == nil, view.animation != nil else { return }
                    spinner.stopAnimating()
                    spinner.isHidden = true
                    view.loopMode = .loop
                    view.play()
                }
            }
            let lottieView: LottieAnimationView
            if url.pathExtension.lowercased() == "lottie" {
                lottieView = LottieAnimationView(dotLottieUrl: url, completion: didLoad)
            } else {
                var jsonView: LottieAnimationView!
                jsonView = LottieAnimationView(url: url) { error in
                    didLoad(jsonView, error)
                }
                lottieView = jsonView
            }
            lottieView.translatesAutoresizingMaskIntoConstraints = false
            lottieView.backgroundBehavior = .pauseAndRestore
            lottieView.contentMode = .scaleAspectFit
            card.addSubview(lottieView)
            NSLayoutConstraint.activate([
                lottieView.widthAnchor.constraint(equalToConstant: 78),
                lottieView.heightAnchor.constraint(equalToConstant: 78),
                lottieView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                lottieView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 90),
            card.heightAnchor.constraint(equalToConstant: 90),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
    }

    private func button(title: String, filled: Bool, result: ITWingDialogResult) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        if filled {
            button.backgroundColor = ITWingSDK.uiColor("dialog_positive_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
            button.setTitleColor(ITWingSDK.uiColor("dialog_positive_text_color", defaultValue: .white), for: .normal)
        } else {
            button.backgroundColor = ITWingSDK.uiColor("dialog_negative_button_color", defaultValue: .clear)
            button.layer.borderWidth = 1
            let negative = ITWingSDK.uiColor("dialog_negative_text_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
            button.layer.borderColor = ITWingSDK.uiColor("dialog_negative_stroke_color", defaultValue: negative.withAlphaComponent(0.47)).cgColor
            button.setTitleColor(negative, for: .normal)
        }
        button.tag = result == .positive ? 1 : -1
        button.addTarget(self, action: #selector(handleButton(_:)), for: .touchUpInside)
        return button
    }

    @objc private func handleButton(_ sender: UIButton) {
        let result: ITWingDialogResult = sender.tag == 1 ? .positive : .negative
        dismiss(animated: true) {
            self.onResult?(result)
        }
    }
}

extension UIApplication {
    var itwingVisibleViewController: UIViewController? {
        let window: UIWindow?
        if #available(iOS 13.0, *) {
            window = connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            window = windows.first { $0.isKeyWindow }
        }
        return topViewController(from: window?.rootViewController)
    }

    private func topViewController(from base: UIViewController?) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        if let presented = base?.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        return base
    }
}

extension UIColor {
    static func itwingHex(_ value: String?, fallback: UIColor) -> UIColor {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard let int = UInt64(value, radix: 16) else { return fallback }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if value.count == 6 {
            red = CGFloat((int >> 16) & 0xff) / 255
            green = CGFloat((int >> 8) & 0xff) / 255
            blue = CGFloat(int & 0xff) / 255
        } else {
            return fallback
        }
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

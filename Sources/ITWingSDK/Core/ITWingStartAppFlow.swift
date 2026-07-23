import Lottie
import UIKit
import WebKit

public struct ITWingStartAppFlowConfig {
    public var options: ITWingOptions
    public var showOnboarding: Bool
    public var requireTerms: Bool
    public var autoStartAppOpenAds: Bool
    public var showSplashAdAfterFirstRun: Bool
    public var splashTitleLabel: UILabel?
    public var splashSubtitleLabel: UILabel?
    public var splashLogoView: UIImageView?
    public var splashBackgroundView: UIView?
    public var splashLottieView: LottieAnimationView?
    public var onboardingViewControllers: [UIViewController]
    public var mainFactory: () -> UIViewController

    public init(
        options: ITWingOptions = .default,
        showOnboarding: Bool = true,
        requireTerms: Bool = true,
        autoStartAppOpenAds: Bool = true,
        showSplashAdAfterFirstRun: Bool = true,
        splashTitleLabel: UILabel? = nil,
        splashSubtitleLabel: UILabel? = nil,
        splashLogoView: UIImageView? = nil,
        splashBackgroundView: UIView? = nil,
        splashLottieView: LottieAnimationView? = nil,
        onboardingViewControllers: [UIViewController] = [],
        mainFactory: @escaping () -> UIViewController
    ) {
        self.options = options
        self.showOnboarding = showOnboarding
        self.requireTerms = requireTerms
        self.autoStartAppOpenAds = autoStartAppOpenAds
        self.showSplashAdAfterFirstRun = showSplashAdAfterFirstRun
        self.splashTitleLabel = splashTitleLabel
        self.splashSubtitleLabel = splashSubtitleLabel
        self.splashLogoView = splashLogoView
        self.splashBackgroundView = splashBackgroundView
        self.splashLottieView = splashLottieView
        self.onboardingViewControllers = onboardingViewControllers
        self.mainFactory = mainFactory
    }
}

public enum ITWingStartAppFlow {
    private static let acceptedTermsKey = "itwing_start_flow_terms_accepted"

    public static func start(apiKey: String, from activity: UIViewController, config: ITWingStartAppFlowConfig) {
        ITWingSDK.initialize(apiKey: apiKey, options: config.options)
        renderCachedSplash(config)
        Task {
            let deadline = Date().addingTimeInterval(config.options.bootstrapTimeout)
            while !ITWingSDK.isReady(), Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !ITWingSDK.isReady() { try? await ITWingSDK.refreshConfig() }
            await MainActor.run {
                renderCachedSplash(config)
            }
            let delay = min(15, max(0, ITWingSDK.config.app.splash.seconds))
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            await MainActor.run {
                continueFlow(from: activity, config: config)
            }
        }
    }

    @MainActor
    private static func continueFlow(from activity: UIViewController, config: ITWingStartAppFlowConfig) {
        let remote = ITWingSDK.config.startupFlow
        let shouldShowOnboarding = config.showOnboarding && remote.flowOnboarding && !UserDefaults.standard.bool(forKey: acceptedTermsKey)
        let shouldShowTerms = config.requireTerms && remote.flowTerms && !UserDefaults.standard.bool(forKey: acceptedTermsKey)

        if shouldShowOnboarding {
            var controllerRef: OnboardingController?
            let controller = OnboardingController(pages: pages(config), config: config) {
                controllerRef?.dismiss(animated: true) {
                    if shouldShowTerms {
                        showTerms(from: activity, config: config)
                    } else {
                        UserDefaults.standard.set(true, forKey: acceptedTermsKey)
                        openMain(from: activity, config: config)
                    }
                }
            }
            controllerRef = controller
            activity.present(controller, animated: true)
            return
        }

        if shouldShowTerms {
            showTerms(from: activity, config: config)
            return
        }

        if config.showSplashAdAfterFirstRun {
            ITWingSDK.showConfiguredSplashAd(from: activity) {
                openMain(from: activity, config: config)
            }
        } else {
            openMain(from: activity, config: config)
        }
    }

    private static func showTerms(from activity: UIViewController, config: ITWingStartAppFlowConfig) {
        let controller = TermsController {
            activity.presentedViewController?.dismiss(animated: true) {
                UserDefaults.standard.set(true, forKey: acceptedTermsKey)
                if ITWingSDK.config.startupFlow.termsInterstitialEnabled {
                    ITWingSDK.interstitial.show(from: activity, placement: ITWingSDK.config.startupFlow.termsInterstitialPlacement ?? "interstitial") {
                        openMain(from: activity, config: config)
                    }
                } else {
                    openMain(from: activity, config: config)
                }
            }
        }
        activity.present(controller, animated: true)
    }

    private static func openMain(from activity: UIViewController, config: ITWingStartAppFlowConfig) {
        let main = config.mainFactory()
        main.modalPresentationStyle = .fullScreen
        activity.present(main, animated: true) {
            ITWingNotificationManager.shared.showPendingInAppNotifications(from: main)
        }
    }

    private static func renderCachedSplash(_ config: ITWingStartAppFlowConfig) {
        let app = ITWingSDK.config.app
        let splash = app.splash
        let title = splash.title ?? app.splashTitle ?? ITWingSDK.appTitle(defaultValue: config.splashTitleLabel?.text ?? "")
        config.splashTitleLabel?.text = title
        config.splashSubtitleLabel?.text = splash.subtitle ?? app.splashSubtitle ?? config.splashSubtitleLabel?.text
        config.splashTitleLabel?.textColor = UIColor.itwingHex(splash.titleTextColor ?? app.splashTitleTextColor, fallback: config.splashTitleLabel?.textColor ?? .label)
        config.splashSubtitleLabel?.textColor = UIColor.itwingHex(splash.subtitleTextColor ?? app.splashSubtitleTextColor, fallback: config.splashSubtitleLabel?.textColor ?? .secondaryLabel)
        if let size = splash.titleTextSize { config.splashTitleLabel?.font = config.splashTitleLabel?.font.withSize(CGFloat(size)) }
        if let size = splash.subtitleTextSize { config.splashSubtitleLabel?.font = config.splashSubtitleLabel?.font.withSize(CGFloat(size)) }
        let backgroundColor = splash.backgroundColor ?? app.splashBackgroundColor
        config.splashBackgroundView?.backgroundColor = UIColor.itwingHex(backgroundColor, fallback: ITWingSDK.uiColor("primary", defaultValue: config.splashBackgroundView?.backgroundColor ?? .systemBackground))

        let backgroundUrl = splash.backgroundUrl ?? app.splashBackgroundUrl
        if let imageView = config.splashBackgroundView as? UIImageView, let backgroundUrl {
            MediaDiskCache.shared.loadImage(backgroundUrl) { image in
                if let image { imageView.image = image }
            }
        }
        let logo = splash.centerImageUrl ?? app.splashCenterImageUrl ?? ITWingSDK.logoUrl()?.absoluteString
        if let logo, let imageView = config.splashLogoView {
            MediaDiskCache.shared.loadImage(logo) { image in
                if let image { imageView.image = image }
            }
        }
        if let lottieView = config.splashLottieView,
           let source = splash.lottieUrl ?? app.splashLottieUrl ?? app.loadingLottieUrl,
           let url = URL(string: source) {
            LottieAnimation.loadedFrom(url: url, closure: { animation in
                lottieView.animation = animation
                lottieView.loopMode = .loop
                lottieView.play()
            }, animationCache: DefaultAnimationCache.sharedCache)
        }
    }

    private static func pages(_ config: ITWingStartAppFlowConfig) -> [UIViewController] {
        if !config.onboardingViewControllers.isEmpty {
            return config.onboardingViewControllers
        }
        let remote = ITWingSDK.config.startupFlow.onboardingPages
        if !remote.isEmpty {
            return remote.map { RemoteOnboardingPage(page: $0) }
        }
        return [
            RemoteOnboardingPage(page: OnboardingPageConfig(title: "Powered by IT Wing Technologies", description: "Manage ads, premium, notifications, and content from one panel.", imageUrl: nil, nativePlacement: nil)),
            RemoteOnboardingPage(page: OnboardingPageConfig(title: "Dynamic experiences", description: "Update app content and settings without publishing a new build.", imageUrl: nil, nativePlacement: nil)),
            RemoteOnboardingPage(page: OnboardingPageConfig(title: "Ready to start", description: "Continue to accept terms and open the app.", imageUrl: nil, nativePlacement: nil)),
        ]
    }
}

public extension ITWingSDK {
    static func startAppFlow(apiKey: String, from viewController: UIViewController, mainFactory: @escaping () -> UIViewController) {
        let config = ITWingStartAppFlowConfig(mainFactory: mainFactory)
        ITWingStartAppFlow.start(apiKey: apiKey, from: viewController, config: config)
    }

    static func startAppFlow(apiKey: String, from viewController: UIViewController, config: ITWingStartAppFlowConfig) {
        ITWingStartAppFlow.start(apiKey: apiKey, from: viewController, config: config)
    }
}

final class OnboardingController: UIViewController, UIPageViewControllerDataSource {
    private let pages: [UIViewController]
    private let completion: () -> Void
    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let nextButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private var index = 0
    private var activityAd: UIView?

    init(pages: [UIViewController], config: ITWingStartAppFlowConfig, completion: @escaping () -> Void) {
        self.pages = pages
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ITWingSDK.uiColor("onboarding_background_color", defaultValue: .systemBackground)
        addChild(pageController)
        pageController.view.frame = view.bounds
        pageController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        pageController.dataSource = self
        pageController.setViewControllers([pages[0]], direction: .forward, animated: false)

        [backButton, nextButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            $0.backgroundColor = ITWingSDK.uiColor("onboarding_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
            $0.setTitleColor(ITWingSDK.uiColor("onboarding_button_text_color", defaultValue: .white), for: .normal)
            $0.layer.cornerRadius = 14
            view.addSubview($0)
        }
        backButton.setTitle("Back", for: .normal)
        backButton.tintColor = ITWingSDK.uiColor("onboarding_back_tint_color", defaultValue: .white)
        nextButton.setTitle("Next", for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(goNext), for: .touchUpInside)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            backButton.widthAnchor.constraint(equalToConstant: 90),
            backButton.heightAnchor.constraint(equalToConstant: 46),
            nextButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            nextButton.widthAnchor.constraint(equalToConstant: 104),
            nextButton.heightAnchor.constraint(equalToConstant: 46),
        ])
        installActivityAdIfNeeded()
        updateButtons()
    }

    private func installActivityAdIfNeeded() {
        let flow = ITWingSDK.config.startupFlow
        guard flow.onboardingAdScope.lowercased() == "activity",
              let placement = flow.onboardingActivityAdPlacement, !placement.isEmpty else { return }
        let ad: UIView
        let height: CGFloat
        if flow.onboardingActivityAdFormat.lowercased() == "banner" {
            let banner = ITWingBannerView()
            banner.placementName = placement
            ad = banner
            height = 60
        } else {
            let native = ITWingNativeAdView()
            native.placementName = placement
            ad = native
            height = placement.lowercased().contains("large") ? 300 : 120
        }
        ad.translatesAutoresizingMaskIntoConstraints = false
        ad.backgroundColor = .clear
        view.addSubview(ad)
        NSLayoutConstraint.activate([
            ad.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            ad.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            ad.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -12),
            ad.heightAnchor.constraint(equalToConstant: height),
        ])
        activityAd = ad
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = pages.firstIndex(where: { $0 === viewController }), current > 0 else { return nil }
        return pages[current - 1]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = pages.firstIndex(where: { $0 === viewController }), current < pages.count - 1 else { return nil }
        return pages[current + 1]
    }

    @objc private func goBack() {
        guard index > 0 else { return }
        index -= 1
        pageController.setViewControllers([pages[index]], direction: .reverse, animated: true)
        updateButtons()
    }

    @objc private func goNext() {
        guard index < pages.count - 1 else {
            completion()
            return
        }
        index += 1
        pageController.setViewControllers([pages[index]], direction: .forward, animated: true)
        updateButtons()
    }

    private func updateButtons() {
        backButton.isHidden = index == 0
        nextButton.setTitle(index == pages.count - 1 ? "Finish" : "Next", for: .normal)
    }
}

final class RemoteOnboardingPage: UIViewController {
    private let page: OnboardingPageConfig

    init(page: OnboardingPageConfig) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ITWingSDK.uiColor("onboarding_background_color", defaultValue: .systemBackground)
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = page.title
        title.textColor = ITWingSDK.uiColor("onboarding_title_color", defaultValue: .label)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false
        let description = UILabel()
        description.text = page.description
        description.font = .systemFont(ofSize: 15)
        description.textAlignment = .center
        description.textColor = ITWingSDK.uiColor("onboarding_description_color", defaultValue: .secondaryLabel)
        description.numberOfLines = 0
        description.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(image)
        view.addSubview(title)
        view.addSubview(description)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            image.topAnchor.constraint(equalTo: view.topAnchor),
            image.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.58),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            title.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 22),
            description.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            description.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            description.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
        ])
        if let url = page.imageUrl {
            MediaDiskCache.shared.loadImage(url) { image.image = $0 }
        }
    }
}

final class TermsController: UIViewController {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ITWingSDK.uiColor("terms_background_color", defaultValue: .systemBackground)
        let content: UIView
        if let rawUrl = ITWingSDK.config.startupFlow.termsUrl ?? ITWingSDK.appUrl("terms"),
           let url = URL(string: rawUrl) {
            let web = WKWebView()
            web.load(URLRequest(url: url))
            content = web
        } else {
            let text = UITextView()
            text.isEditable = false
            text.backgroundColor = .clear
            text.textColor = ITWingSDK.uiColor("terms_text_color", defaultValue: .label)
            text.font = .systemFont(ofSize: 15)
            text.text = ITWingSDK.config.startupFlow.termsContent
                ?? ITWingSDK.legalContent("terms")
                ?? "Please accept the terms of use to continue."
            content = text
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setTitle(ITWingSDK.string("terms_accept_button_text", defaultValue: "Accept"), for: .normal)
        button.backgroundColor = ITWingSDK.uiColor("terms_accept_button_color", defaultValue: ITWingSDK.uiColor("primary", defaultValue: .systemBlue))
        button.setTitleColor(ITWingSDK.uiColor("terms_accept_button_text_color", defaultValue: .white), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.layer.cornerRadius = 14
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(acceptTerms), for: .touchUpInside)
        view.addSubview(content)
        view.addSubview(button)
        var contentBottom = button.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 16)
        if ITWingSDK.config.startupFlow.termsAdFormat.lowercased() == "banner",
           let placement = ITWingSDK.config.startupFlow.termsBannerPlacement {
            let banner = ITWingBannerView()
            banner.placementName = placement
            banner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(banner)
            contentBottom = banner.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 8)
            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                banner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                banner.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -10),
                banner.heightAnchor.constraint(equalToConstant: 60),
            ])
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            contentBottom,
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
            button.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    @objc private func acceptTerms() {
        completion()
    }
}

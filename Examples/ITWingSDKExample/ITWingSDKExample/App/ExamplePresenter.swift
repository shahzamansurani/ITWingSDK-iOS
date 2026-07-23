import UIKit

enum ExamplePresenter {
    static var current: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return visible(from: root)
    }

    private static func visible(from controller: UIViewController?) -> UIViewController? {
        if let presented = controller?.presentedViewController {
            return visible(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return visible(from: navigation.visibleViewController)
        }
        if let tabs = controller as? UITabBarController {
            return visible(from: tabs.selectedViewController)
        }
        return controller
    }
}


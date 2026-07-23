import StoreKit
import UIKit

public enum ITWingAppStoreUpdateHelper {
    public static func checkForUpdate(appStoreId: String, presenter: UIViewController, force: Bool = false) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let latest = results.first?["version"] as? String,
                  let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  latest.compare(current, options: .numeric) == .orderedDescending else { return }
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Update available", message: "A newer version is available on the App Store.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Update", style: .default) { _ in
                    if let storeUrl = URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreId)") {
                        UIApplication.shared.open(storeUrl)
                    }
                })
                if !force {
                    alert.addAction(UIAlertAction(title: "Later", style: .cancel))
                }
                presenter.present(alert, animated: true)
            }
        }.resume()
    }
}

public enum ITWingReviewHelper {
    public static func showReviewPrompt(from presenter: UIViewController) {
        ITWingUI.requestReview(from: presenter)
    }
}

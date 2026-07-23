import UIKit
import UserNotifications

public struct ITWingInAppNotification: Codable, Sendable {
    public var id: String
    public var title: String
    public var body: String?
    public var imageUrl: String?
    public var primaryActionTitle: String?
    public var primaryActionUrl: String?
    public var secondaryActionTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case imageUrl = "image_url"
        case primaryActionTitle = "primary_action_title"
        case primaryActionUrl = "primary_action_url"
        case secondaryActionTitle = "secondary_action_title"
    }
}

struct InAppNotificationEnvelope: Decodable {
    let data: [ITWingInAppNotification]
}

public final class ITWingNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = ITWingNotificationManager()

    private let seenKey = "itwing_seen_in_app_notifications"

    private override init() {
        super.init()
    }

    public func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            AnalyticsClient.shared.track("notification_permission_result", properties: ["granted": granted])
        }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    public func showPendingInAppNotifications(from presenter: UIViewController? = nil) {
        guard let repository = ITWingSDK.repo else { return }
        Task {
            do {
                let pending = try await repository.pendingNotifications()
                let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
                guard let notification = pending.first(where: { !seen.contains($0.id) }) else { return }
                await MainActor.run {
                    self.present(notification, from: presenter ?? UIApplication.shared.itwingVisibleViewController)
                }
            } catch {
                AnalyticsClient.shared.track("in_app_notification_fetch_failed")
            }
        }
    }

    private func present(_ notification: ITWingInAppNotification, from presenter: UIViewController?) {
        guard let presenter else { return }
        let dialog = GlassDialogController(
            title: notification.title,
            message: notification.body,
            positive: notification.primaryActionTitle ?? "Open",
            negative: notification.secondaryActionTitle ?? "Close"
        )
        dialog.onResult = { result in
            self.markSeen(notification.id, event: result == .positive ? "clicked" : "dismissed")
            if result == .positive,
               let value = notification.primaryActionUrl,
               let url = URL(string: value) {
                UIApplication.shared.open(url)
            }
        }
        presenter.present(dialog, animated: true)
    }

    private func markSeen(_ id: String, event: String) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        seen.insert(id)
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
        Task {
            try? await ITWingSDK.repo?.submitNotificationEvent(campaignId: id, event: event)
        }
    }
}

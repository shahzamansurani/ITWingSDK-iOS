import Foundation

/// Matches the Android SDK's failed-load throttle. Inline ads make a single
/// request, remove their shimmer on failure, and wait before they can request
/// again instead of creating an AdMob request loop while the view is visible.
@MainActor
enum AdLoadBackoff {
    private static var retryAfter: [String: Date] = [:]

    static func canRequest(_ placement: AdPlacementConfig) -> Bool {
        guard let date = retryAfter[placement.name] else { return true }
        guard Date() >= date else { return false }
        retryAfter.removeValue(forKey: placement.name)
        return true
    }

    static func recordFailure(_ placement: AdPlacementConfig, error: Error) {
        let message = error.localizedDescription.lowercased()
        let seconds: TimeInterval
        if message.contains("no fill") || message.contains("no ad to show") {
            seconds = 120
        } else if message.contains("network") || message.contains("timeout") {
            seconds = 60
        } else {
            seconds = 45
        }
        retryAfter[placement.name] = Date().addingTimeInterval(seconds)
    }

    static func recordSuccess(_ placement: AdPlacementConfig) {
        retryAfter.removeValue(forKey: placement.name)
    }
}

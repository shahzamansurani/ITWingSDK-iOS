import Foundation

final class FrequencyController {
    private var sessionCounts: [String: Int] = [:]
    private var lastShown: [String: Date] = [:]
    private var triggerCounts: [String: Int] = [:]

    func canShow(_ placement: AdPlacementConfig, countTrigger: Bool = false) -> Bool {
        guard placement.enabled else { return false }
        let key = frequencyKey(placement)
        if countTrigger {
            let interval = max(1, placement.triggerInterval ?? 1)
            let current = triggerCounts[key] ?? 0
            let shouldShow = current == 0 || current % interval == 0
            triggerCounts[key] = current + 1
            guard shouldShow else { return false }
        }

        if let cooldown = placement.cooldownSeconds, cooldown > 0,
           let last = lastShown[key],
           Date().timeIntervalSince(last) < TimeInterval(cooldown) {
            return false
        }

        // The control plane and Android SDK define 0 as unlimited.
        if let cap = placement.sessionCap, cap > 0,
           (sessionCounts[key] ?? 0) >= cap {
            return false
        }

        return true
    }

    func markShown(_ placement: AdPlacementConfig) {
        let key = frequencyKey(placement)
        sessionCounts[key] = (sessionCounts[key] ?? 0) + 1
        lastShown[key] = Date()
    }

    func refundTrigger(_ placement: AdPlacementConfig) {
        let key = frequencyKey(placement)
        triggerCounts[key] = max(0, (triggerCounts[key] ?? 0) - 1)
    }

    private func frequencyKey(_ placement: AdPlacementConfig) -> String {
        placement.format.lowercased() == "interstitial"
            ? "format:interstitial"
            : "placement:\(placement.name)"
    }
}

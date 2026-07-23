import Foundation

final class FrequencyController {
    private var sessionCounts: [String: Int] = [:]
    private var lastShown: [String: Date] = [:]
    private var triggerCounts: [String: Int] = [:]

    func canShow(_ placement: AdPlacementConfig, countTrigger: Bool = false) -> Bool {
        guard placement.enabled else { return false }
        if countTrigger {
            let interval = placement.triggerInterval ?? 1
            let next = (triggerCounts[placement.name] ?? 0) + 1
            triggerCounts[placement.name] = next >= interval ? 0 : next
            guard next >= interval else { return false }
        }

        if let cooldown = placement.cooldownSeconds, cooldown > 0,
           let last = lastShown[placement.name],
           Date().timeIntervalSince(last) < TimeInterval(cooldown) {
            return false
        }

        // The control plane and Android SDK define 0 as unlimited.
        if let cap = placement.sessionCap, cap > 0,
           (sessionCounts[placement.name] ?? 0) >= cap {
            return false
        }

        return true
    }

    func markShown(_ placement: AdPlacementConfig) {
        sessionCounts[placement.name] = (sessionCounts[placement.name] ?? 0) + 1
        lastShown[placement.name] = Date()
    }
}


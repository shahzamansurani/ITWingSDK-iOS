import Foundation

public final class AnalyticsClient {
    public static let shared = AnalyticsClient()

    private let queue = DispatchQueue(label: "com.itwingtech.itwingsdk.analytics", qos: .utility)
    private var repository: ConfigRepository?
    private var events: [[String: Any]] = []
    private var flushScheduled = false

    private init() {}

    func configure(repository: ConfigRepository) {
        queue.async {
            self.repository = repository
        }
    }

    public func track(_ name: String, properties: [String: Any] = [:]) {
        let safeEvent: [String: Any] = [
            "name": String(name.prefix(80)),
            "event_at": ISO8601DateFormatter().string(from: Date()),
            "properties": properties.mapValues { Self.safeValue($0) }
        ]
        queue.async {
            self.events.append(safeEvent)
            if self.events.count > 500 {
                self.events.removeFirst(self.events.count - 500)
            }
            self.scheduleFlush()
        }
    }

    public func flush() {
        queue.async {
            self.flushNow()
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0) {
            self.flushNow()
        }
    }

    private func flushNow() {
        guard let repository, !events.isEmpty else {
            flushScheduled = false
            return
        }
        let batch = Array(events.prefix(50))
        Task {
            do {
                try await repository.submitAnalytics(events: batch)
                self.queue.async {
                    self.events.removeFirst(min(batch.count, self.events.count))
                    self.flushScheduled = false
                    if !self.events.isEmpty {
                        self.scheduleFlush()
                    }
                }
            } catch {
                self.queue.async {
                    self.flushScheduled = false
                }
            }
        }
    }

    private static func safeValue(_ value: Any) -> Any {
        switch value {
        case let value as String:
            return String(value.prefix(500))
        case let value as NSNumber:
            return value
        case let value as Bool:
            return value
        case let value as [String]:
            return String(value.joined(separator: ",").prefix(500))
        case let value as [String: Any]:
            return value.mapValues { safeValue($0) }
        default:
            return String(String(describing: value).prefix(500))
        }
    }
}

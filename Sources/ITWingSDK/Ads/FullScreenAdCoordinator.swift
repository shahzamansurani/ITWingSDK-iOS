import UIKit

/// Process-wide ownership gate shared by every real and custom full-screen ad.
/// A repeated tap can never stack a second ad over an active presentation.
final class FullScreenAdCoordinator {
    static let shared = FullScreenAdCoordinator()
    private let lock = NSLock()
    private var owner: UUID?

    func tryBegin() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard owner == nil else { return nil }
        let token = UUID()
        owner = token
        return token
    }

    func end(_ token: UUID?) {
        guard let token else { return }
        lock.lock()
        if owner == token { owner = nil }
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return owner != nil
    }
}

/// Mirrors Android's InlineAdSafetyGate. After a non-splash full-screen ad
/// dismisses, defer the next inline request until one user interaction or a
/// short automatic release, whichever comes first.
@MainActor
final class InlineAdSafetyGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = InlineAdSafetyGate()
    private var armed = false
    private var callbacks: [() -> Void] = []
    private weak var watchedWindow: UIWindow?
    private var watcher: UITapGestureRecognizer?
    private var releaseWork: DispatchWorkItem?

    func arm() {
        armed = true
        callbacks.removeAll()
        releaseWork?.cancel()
    }

    func suppressInline(reload: @escaping () -> Void) -> Bool {
        guard armed else { return false }
        callbacks.append(reload)
        installWatcher()
        scheduleRelease()
        return true
    }

    private func installWatcher() {
        guard watcher == nil,
              let window = UIApplication.shared.windows.first(where: \.isKeyWindow) else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(interacted))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        watchedWindow = window
        watcher = recognizer
    }

    private func scheduleRelease() {
        guard releaseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.release() }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    @objc private func interacted() {
        release()
    }

    private func release() {
        releaseWork?.cancel()
        releaseWork = nil
        if let watcher { watchedWindow?.removeGestureRecognizer(watcher) }
        watcher = nil
        watchedWindow = nil
        armed = false
        let pending = callbacks
        callbacks.removeAll()
        pending.forEach { $0() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

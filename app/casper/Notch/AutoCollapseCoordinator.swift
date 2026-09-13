//
//  AutoCollapseCoordinator.swift
//
//  A Space change can activate its destination's app without the user
//  dismissing Casper. Let the workspace notifications settle before treating
//  activation alone as an app switch. Explicit clicks and controls bypass this.
//

import Foundation

@MainActor
final class AutoCollapseCoordinator {
    private let settlingDelay: Duration
    private var lastSpaceChange: ContinuousClock.Instant?
    private var pendingCollapse: Task<Void, Never>?

    init(settlingDelay: Duration = .milliseconds(600)) {
        self.settlingDelay = settlingDelay
    }

    deinit {
        pendingCollapse?.cancel()
    }

    func otherAppDidActivate(collapse: @escaping @MainActor () -> Void) {
        cancel()
        // Space notifications may precede the destination's activation.
        if let lastSpaceChange, lastSpaceChange.duration(to: .now) < settlingDelay {
            return
        }
        let delay = settlingDelay
        pendingCollapse = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingCollapse = nil
            collapse()
        }
    }

    func spaceDidChange() {
        lastSpaceChange = .now
        // Or activation may arrive first, while the Space is still moving.
        cancel()
    }

    /// Returning to Casper, opening an alert, or explicitly changing the
    /// panel state makes any earlier activation-based collapse obsolete.
    func cancel() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }
}

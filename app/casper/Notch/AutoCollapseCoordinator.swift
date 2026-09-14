//
//  AutoCollapseCoordinator.swift
//
//  A recent Command release lets an app activation collapse the notch right
//  away. Activation alone (such as a Space switch) leaves it open. This is a
//  heuristic for keyboard app switching; it does not identify the Tab key.
//  Explicit clicks and controls bypass this check.
//

import Foundation

@MainActor
final class AutoCollapseCoordinator {
    private let commandReleaseWindow: Duration
    private var isCommandPressed = false
    private(set) var cmdRecentlyPressed = false
    private var commandReleaseDeadline: ContinuousClock.Instant?
    private var commandExpirationTask: Task<Void, Never>?

    init(commandReleaseWindow: Duration = .milliseconds(200)) {
        self.commandReleaseWindow = commandReleaseWindow
    }

    deinit {
        commandExpirationTask?.cancel()
    }

    /// Only actual modifier state belongs here. The panel's shortcut-hint
    /// callback also reports false on focus loss, which is not a key release.
    func commandKeyChanged(isPressed: Bool) {
        guard isPressed != isCommandPressed else { return }  // Ignore reports that haven't changed. true != false or viceversa
        isCommandPressed = isPressed // Remember the new command state: down (true) or up (false).
        cancel() // Clear any previous release window.
        guard isPressed == false else { return } // Only advance if isPressed is false ( meaning a release )

        cmdRecentlyPressed = true
        commandReleaseDeadline = .now.advanced(by: commandReleaseWindow)
        let window = commandReleaseWindow
        commandExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: window)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.cmdRecentlyPressed = false
            self.commandReleaseDeadline = nil
            self.commandExpirationTask = nil
        }
    }

    /// Runs synchronously. The timer only expires eligibility; it never
    /// schedules a collapse. Consume the release before invoking the callback.
    func otherAppDidActivate(collapse: () -> Void) {
        // A busy main actor may postpone the expiration task. Check the
        // deadline too, so delayed cleanup cannot extend the 200 ms window.
        let shouldCollapse = cmdRecentlyPressed
            && commandReleaseDeadline.map { ContinuousClock.now < $0 } == true
        cancel()
        guard shouldCollapse else { return }
        collapse()
    }

    /// Clear recent eligibility when panel state/focus changes or an alert
    /// interrupts. Keep the physical key state so only a real release can arm it.
    func cancel() {
        commandExpirationTask?.cancel()
        commandExpirationTask = nil
        cmdRecentlyPressed = false
        commandReleaseDeadline = nil
    }
}

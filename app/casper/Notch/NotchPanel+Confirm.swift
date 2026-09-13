//
//  NotchPanel+Confirm.swift
//
//  The one place a confirmation dialog is put in front of the panel. Every
//  yes/no question in the app comes through here, so the approach can be
//  swapped in one spot.
//
//  The panel is an unusual window: above the menu bar, on every Space, over
//  full-screen apps, and nonactivating. An ordinary alert window has nothing
//  tying it to the panel, so it can land behind it, stay on the Space it
//  opened on, or be refused on a full-screen Space. Attaching the alert as a
//  child window makes the window server carry it wherever the panel goes.
//  Its level still has to be raised by hand: AppKit sets the modal panel
//  level when the session starts and restores it when the app activates,
//  including activation after changing Spaces. Both put it under the notch.
//
//  The alert needs the app active for keyboard input, and the app must not
//  stay active afterwards. An active app keeps the keyboard when the panel
//  resigns key on collapse, AppKit loses track of which window is key, and
//  the next expand cannot take it back. From then on ⌘Q reaches the app
//  menu's Quit ahead of the panel. So activation goes back to the app that
//  had it, and the panel takes key status again the nonactivating way once
//  the app has resigned.
//

import AppKit

extension NotchPanel {
    /// Asks a yes/no question above the panel and waits for the answer.
    /// Returns true when the user chose `button`. The panel takes key status
    /// back afterwards; the caller decides which view gets focus.
    func confirm(_ message: String, detail: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")

        let window = alert.window
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // NSAlert only centers a window it has not shown yet, and attaching
        // the child shows it at once, so place it first. Moving it onto this
        // panel's screen makes center() use that screen: exact horizontally,
        // a little above the middle, the way AppKit places every alert.
        alert.layout()
        window.setFrameOrigin(frame.origin)
        window.center()

        addChildWindow(window, ordered: .above)

        let alertLevel = NSWindow.Level(rawValue: level.rawValue + 1)
        let raiseAlert: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                guard NSApp.modalWindow === window else { return }
                window.level = alertLevel
            }
        }

        // Activation can finish after the first modal-loop pass. AppKit
        // restores level 8 while handling that event, undoing our first
        // raise. Reapply after activation, synchronously: a main-queue
        // callback can be blocked by the caller's own modal session.
        let activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: nil
        ) { _ in
            raiseAlert()
        }
        let previousApp = NSWorkspace.shared.frontmostApplication
        defer {
            NotificationCenter.default.removeObserver(activationObserver)
            removeChildWindow(window)
            returnActivation(to: previousApp)
        }

        // The session also sets the initial modal level. A run-loop block
        // works even when confirm itself was called from the main queue.
        RunLoop.main.perform(inModes: [.modalPanel], block: raiseAlert)

        // Unlike the nonactivating notch, the alert needs an active app
        // for keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Gives activation back to `previousApp` and takes key status again
    /// once this app has resigned: the switch lands after this returns and
    /// takes key status with it. With nothing to hand back to (the app was
    /// active before the alert) the panel is simply made key again.
    private func returnActivation(to previousApp: NSRunningApplication?) {
        makeKeyAndOrderFront(nil)
        guard let previousApp,
              previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(takeKeyBackAfterResigningActive),
                                               name: NSApplication.didResignActiveNotification,
                                               object: NSApp)
        if !previousApp.activate(from: .current, options: []) {
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: NSApp)
        }
    }

    @objc private func takeKeyBackAfterResigningActive() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: NSApp)
        makeKeyAndOrderFront(nil)
    }
}

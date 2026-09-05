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
        defer {
            NotificationCenter.default.removeObserver(activationObserver)
            removeChildWindow(window)
            makeKeyAndOrderFront(nil)
        }

        // The session also sets the initial modal level. A run-loop block
        // works even when confirm itself was called from the main queue.
        RunLoop.main.perform(inModes: [.modalPanel], block: raiseAlert)

        // Unlike the nonactivating notch, the alert needs an active app
        // for keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

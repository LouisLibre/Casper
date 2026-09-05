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
//  Its level still has to be raised by hand: the window server orders by
//  level before it honors the child link, and the modal session lowers the
//  alert to the modal panel level, under the panel.
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

        // Starting the modal session drops the alert to the modal panel
        // level; raise it on the first pass of the modal run loop. This has
        // to be a run loop block, not a main-queue block: confirm may itself
        // be running inside a main-queue block, and libdispatch does not
        // drain the main queue again until that block returns, which is
        // after the alert is gone. A block that ran then would bring the
        // dismissed alert back as a dead window.
        let alertLevel = NSWindow.Level(rawValue: level.rawValue + 1)
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                guard NSApp.modalWindow === window else { return }
                window.level = alertLevel
            }
        }

        // The alert is a regular window: unlike this nonactivating panel it
        // only takes keyboard input while the app is active.
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        removeChildWindow(window)
        makeKeyAndOrderFront(nil)
        return confirmed
    }
}

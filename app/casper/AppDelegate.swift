//
//  AppDelegate.swift
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let rootController = AppRootController()

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        rootController.start()
        // Let AppKit finish its initial launch/activation before applying the
        // saved Dock policy. This is a lifecycle boundary, not a timed delay.
        DispatchQueue.main.async { [weak self] in
            self?.rootController.finishLaunch()
        }
        // Uncomment to restore menu bar item
        //installStatusItem()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Every way out ends here: ⌘Q and the quit button through `quit()`,
    /// the app menu's own ⌘Q, a quit Apple event. The question is asked
    /// once, in one place.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        rootController.shouldQuit() ? .terminateNow : .terminateCancel
    }

    /// A menu bar item with Quit, from before the app had a Dock icon.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(resource: .menuBarIcon)
        icon.accessibilityDescription = "Casper"
        item.button?.image = icon

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Casper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }
}

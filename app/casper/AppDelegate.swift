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
        // Uncomment to restore menu bar item
        //installStatusItem()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// LSUIElement hides the Dock icon and menu bar, so this is the only way to quit.
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

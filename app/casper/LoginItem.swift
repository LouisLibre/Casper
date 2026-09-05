//
//  LoginItem.swift
//
//  Whether Casper starts when the user logs in, through the system's login
//  items (SMAppService). macOS keeps the actual state, so it is always read
//  back from the service rather than stored by the app.
//

import ServiceManagement
import os

enum LoginItem {
    private static let logger = Logger(subsystem: "rs.unaligned.casper", category: "login-item")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Read `isEnabled` afterwards: macOS may refuse, or hold the item until
    /// the user approves it in System Settings, which is opened for them.
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            logger.error("could not \(enabled ? "register" : "unregister") login item: \(error)")
            return
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

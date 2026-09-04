//
//  CasperApp.swift
//

import SwiftUI

@main
struct CasperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup: the UI lives in the NSPanel owned by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}

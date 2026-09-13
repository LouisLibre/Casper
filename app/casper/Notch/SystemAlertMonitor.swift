//
//  SystemAlertMonitor.swift
//
//  Permission UI belongs to macOS helpers, not NSApp.windows. Window-list
//  metadata lets us yield below it without Accessibility or Screen Recording
//  access. Never inspect window titles or capture another window's contents.
//

import AppKit
import CoreGraphics

@MainActor
final class SystemAlertMonitor {
    private weak var panel: NotchPanel?
    private var timer: Timer?
    private var isExpanded = false
    private var confirmationCount = 0
    private var alertLevel: Int?

    var isYielding: Bool { alertLevel != nil }

    /// A child stays above its parent by ordering, but must stay below an
    /// external alert too. `confirm` also reapplies this after activation.
    var confirmationLevel: NSWindow.Level {
        isYielding ? panel?.level ?? .normal
            : NSWindow.Level(rawValue: NotchPanel.notchLevel.rawValue + 1)
    }

    init(panel: NotchPanel) {
        self.panel = panel
    }

    deinit {
        timer?.invalidate()
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        updateMonitoring()
    }

    func beginConfirmation() {
        confirmationCount += 1
        updateMonitoring()
    }

    func endConfirmation() {
        confirmationCount -= 1
        updateMonitoring()
    }

    private func updateMonitoring() {
        guard isExpanded || confirmationCount > 0 else {
            timer?.invalidate()
            timer = nil
            apply(alertLevel: nil)
            return
        }
        refresh()
        guard timer == nil else { return }
        // Helpers can stay running, keep activation, and replace one prompt
        // with the next. Launch/activation notifications alone miss these
        // transitions. Poll only while the expanded panel or a child alert
        // can cover them, including inside NSAlert's nested modal run loop.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        self.timer = timer
    }

    /// Also checked synchronously before activation/collapse handling, so
    /// handing the keyboard to a system alert isn't treated as switching apps.
    func refresh() {
        guard isExpanded || confirmationCount > 0, let panel,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return }

        let ownIDs = Set(([panel] + (panel.childWindows ?? [])).map { $0.windowNumber })
        let lowestAlert = Self.alertLevel(
            in: windows, covering: ownIDs, ownPID: ProcessInfo.processInfo.processIdentifier
        ) { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            return Self.isSystemDialogHost(app)
        }
        apply(alertLevel: lowestAlert)
    }

    static func alertLevel(in windows: [[String: Any]], covering ownIDs: Set<Int>,
                           ownPID: pid_t, isSystemDialogHost: (pid_t) -> Bool) -> Int? {
        // Use Window Server coordinates for both frames. They differ from
        // AppKit's on displays above/below the primary screen.
        let coveredFrames = windows.compactMap { window -> CGRect? in
            guard let id = window[kCGWindowNumber as String] as? Int,
                  ownIDs.contains(id) else { return nil }
            return Self.bounds(of: window)
        }
        return windows.compactMap { window -> Int? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let level = window[kCGWindowLayer as String] as? Int,
                  level >= NSWindow.Level.normal.rawValue,
                  level <= NotchPanel.notchLevel.rawValue,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = Self.bounds(of: window), !bounds.isEmpty,
                  coveredFrames.contains(where: { $0.intersects(bounds) }) else { return nil }

            // The standard modal level covers permission families we don't
            // enumerate, and modal dialogs from other apps. Some macOS helper
            // dialogs use normal/floating levels, so recognize their owners
            // too. Ordinary windows, palettes, menus, and banners don't match.
            if level == NSWindow.Level.modalPanel.rawValue { return level }
            guard isSystemDialogHost(pid) else { return nil }
            return level
        }.min()
    }

    static func isSystemDialogHost(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier,
              app.bundleURL?.path.hasPrefix("/System/Library/") == true else { return false }
        return [
            "com.apple.UserNotificationCenter",
            "com.apple.coreservices.uiagent",
            "com.apple.SecurityAgent",
            "com.apple.LocalAuthenticationRemoteService",
        ].contains(id)
    }

    private static func bounds(of window: [String: Any]) -> CGRect? {
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    private func apply(alertLevel: Int?) {
        self.alertLevel = alertLevel
        guard let panel else { return }
        // Compare to the normal notch level when detecting, not the lowered
        // level, or the next poll would miss the alert and oscillate.
        let level = alertLevel.map { NSWindow.Level(rawValue: $0 - 1) } ?? NotchPanel.notchLevel
        if panel.level != level { panel.level = level }
        for child in panel.childWindows ?? [] {
            if child.level != confirmationLevel { child.level = confirmationLevel }
        }
        // Changing level doesn't activate either app or steal keyboard focus.
    }
}

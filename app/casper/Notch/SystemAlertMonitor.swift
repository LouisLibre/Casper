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
    private var levels = AlertLevels()
    private var permissionFrames: [CGRect] = []

    /// Called after each successful snapshot, with previous/current visibility.
    /// Permission lifetime is independent of whether it overlaps the notch.
    var onPermissionWindowsUpdated: ((_ wereVisible: Bool, _ areVisible: Bool) -> Void)?
    var hasPermissionWindows: Bool { !permissionFrames.isEmpty }

    /// Uses the same WindowServer coordinates as NSEvent.cgEvent.location.
    func containsPermissionWindow(at point: CGPoint) -> Bool {
        permissionFrames.contains { $0.contains(point) }
    }

    struct AlertLevels: Equatable {
        var panel: Int?
        var band: Int?

        var lowest: Int? { [panel, band].compactMap { $0 }.min() }
    }

    var isYielding: Bool { levels.lowest != nil }
    var isConfirming: Bool { confirmationCount > 0 }

    /// A child stays above its parent by ordering, but must stay below an
    /// external alert too. `confirm` also reapplies this after activation.
    var confirmationLevel: NSWindow.Level {
        NSWindow.Level(rawValue: levels.lowest.map { $0 - 1 }
                       ?? NotchPanel.notchLevel.rawValue + 1)
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
            apply(levels: AlertLevels())
            return
        }
        refresh()
        guard timer == nil else { return }
        // Helpers can stay running, keep activation, and replace one prompt
        // with the next. Launch/activation notifications alone miss these
        // transitions. Poll only while the expanded panel or a child alert
        // can cover them, including inside NSAlert's nested modal run loop.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        self.timer = timer
    }

    /// Also checked synchronously before activation/collapse handling, so
    /// handing the keyboard to a system alert isn't treated as switching apps.
    @discardableResult
    func refresh() -> Bool {
        guard isExpanded || confirmationCount > 0, let panel,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return false }

        let ownIDs = Set(([panel] + panel.confirmationWindows).map { $0.windowNumber })
        var hosts: [pid_t: Bool] = [:]
        func isDialogHost(_ pid: pid_t) -> Bool {
            if let cached = hosts[pid] { return cached }
            let isHost = NSRunningApplication(processIdentifier: pid).map(Self.isSystemDialogHost) ?? false
            hosts[pid] = isHost
            return isHost
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let levels = Self.alertLevels(
            in: windows, panelIDs: ownIDs, bandID: panel.bandWindow?.windowNumber,
            ownPID: ownPID, isSystemDialogHost: isDialogHost
        )
        let frames = Self.permissionWindowFrames(
            in: windows, ownPID: ownPID, isSystemDialogHost: isDialogHost
        )
        apply(levels: levels, permissionFrames: frames)
        return true
    }

    /// Track visible permission-helper windows even when they are moved away
    /// from Casper or are already above it. Other apps' modal windows still
    /// affect occlusion, but must not trigger permission-focus restoration.
    static func permissionWindowFrames(in windows: [[String: Any]], ownPID: pid_t,
                                       isSystemDialogHost: (pid_t) -> Bool) -> [CGRect] {
        windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let level = window[kCGWindowLayer as String] as? Int, level >= 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = Self.bounds(of: window), !bounds.isEmpty,
                  isSystemDialogHost(pid) else { return nil }
            return bounds
        }
    }

    /// A centered prompt lowers the body alone. A prompt that reaches the
    /// top strip lowers that window too: the menu bar never takes priority
    /// over a permission dialog. Both decisions use the same snapshot.
    static func alertLevels(in windows: [[String: Any]], panelIDs: Set<Int>, bandID: Int?,
                            ownPID: pid_t, isSystemDialogHost: (pid_t) -> Bool) -> AlertLevels {
        AlertLevels(
            panel: alertLevel(in: windows, covering: panelIDs, ownPID: ownPID,
                              isSystemDialogHost: isSystemDialogHost),
            band: alertLevel(in: windows, covering: Set(bandID.map { [$0] } ?? []), ownPID: ownPID,
                             isSystemDialogHost: isSystemDialogHost)
        )
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

    private func apply(levels: AlertLevels, permissionFrames: [CGRect] = []) {
        let wereVisible = hasPermissionWindows
        self.permissionFrames = permissionFrames
        self.levels = levels
        guard let panel else { return }
        // flickers because it drops the private api overlay
        // let suspendOverlay = levels.lowest != nil || confirmationCount > 0
        // this one doesn't flicker:
        // let suspendOverlay = confirmationCount > 0
        // we still remove the suspend overlay to avoid flickering for confirm quit
        // if suspendOverlay { panel.suspendStationarySpace(true) }
        // Compare to the normal notch level when detecting, not the lowered
        // level, or the next poll would miss the alert and oscillate.
        let level = levels.panel.map { NSWindow.Level(rawValue: $0 - 1) } ?? NotchPanel.notchLevel
        let bandLevel = levels.band.map { NSWindow.Level(rawValue: $0 - 1) } ?? NotchPanel.notchLevel
        let band = panel.bandWindow
        // Attached windows form an ordering group. Separate the strip while
        // it needs an independent level; reattach above the body afterwards
        // so activating the terminal cannot cover its own controls.
        if let band, band.parent === panel, bandLevel != level {
            panel.removeChildWindow(band)
        }
        if panel.level != level { panel.level = level }
        if let band {
            if band.level != bandLevel { band.level = bandLevel }
            if band.parent == nil, bandLevel == level {
                panel.addChildWindow(band, ordered: .above)
            }
        }
        for child in panel.confirmationWindows {
            if child.level != confirmationLevel { child.level = confirmationLevel }
        }
        // if !suspendOverlay { panel.suspendStationarySpace(false) }
        // Finish ordering before the controller schedules any focus request.
        onPermissionWindowsUpdated?(wereVisible, hasPermissionWindows)
    }
}

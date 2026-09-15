// Runtime integration check on a logged-in Mac. Uses two clear, noninteractive
// windows and reads their WindowServer membership; it never switches desktops.
// xcrun swiftc -parse-as-library -default-isolation MainActor \
//   app/casper/Notch/NotchPanel.swift app/casper/Notch/SystemAlertMonitor.swift \
//   app/casper/Notch/NotchOverlaySpace.swift app/tests/NotchOverlaySpaceTests.swift \
//   -o /tmp/casper-overlay-tests
// /tmp/casper-overlay-tests

import AppKit
import Darwin

@main
struct NotchOverlaySpaceTests {
    private static var checks = 0
    private static var failures = 0

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
        let band = NSPanel(contentRect: panel.frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        band.collectionBehavior = panel.collectionBehavior
        band.level = panel.level
        for window in [panel, band] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
        }
        panel.bandWindow = band
        panel.addChildWindow(band, ordered: .above)
        panel.orderFrontRegardless()
        settle()
        let originalBehavior = panel.collectionBehavior
        let originalFrame = panel.frame
        let reader = SpaceReader()

        expect(!reader.spaces(panel, mask: 7).isEmpty, "Test panel starts on ordinary desktops")
        panel.enableStationarySpace()
        settle()
        let overlay = reader.spaces(panel, mask: 11)
        expect(overlay.count == 1, "Body joins one OS overlay Space")
        expect(reader.spaces(panel, mask: 15) == overlay, "Body leaves the moving desktops")
        expect(reader.spaces(band, mask: 15) == overlay, "Band joins only the same overlay")
        expect(panel.frame == originalFrame, "Anchoring preserves the panel's screen coordinates")
        expect(panel.level == NotchPanel.notchLevel, "Anchoring preserves the normal notch level")
        expect(panel.isVisible && band.isVisible, "Both windows remain ordered on screen")

        panel.orderFrontRegardless()
        panel.setFrameOrigin(NSPoint(x: 1, y: 0))
        settle()
        expect(reader.spaces(panel, mask: 15) == overlay, "Reordering and layout retain overlay membership")
        expect(reader.spaces(band, mask: 15) == overlay, "Child ordering retains the band's membership")

        panel.systemAlerts.beginConfirmation()
        settle()
        expect(reader.spaces(panel, mask: 11).isEmpty, "Confirmation removes body from overlay")
        expect(reader.spaces(band, mask: 11).isEmpty, "Confirmation removes band from overlay")
        expect(!reader.spaces(panel, mask: 7).isEmpty, "Confirmation restores ordinary desktop membership")
        expect(panel.collectionBehavior == originalBehavior, "Confirmation restores AppKit Space flags")
        panel.systemAlerts.beginConfirmation()
        panel.systemAlerts.endConfirmation()
        settle()
        expect(reader.spaces(panel, mask: 11).isEmpty, "Nested confirmation keeps the overlay suspended")
        panel.systemAlerts.endConfirmation()
        settle()
        expect(reader.spaces(panel, mask: 15) == overlay, "Last confirmation closing restores the overlay")
        expect(reader.spaces(band, mask: 15) == overlay, "Band rejoins after confirmation")

        panel.suspendStationarySpace(true)
        panel.removeChildWindow(band)
        panel.level = NSWindow.Level(rawValue: -1)
        settle()
        expect(reader.spaces(panel, mask: 11).isEmpty, "Yielding allows normal cross-app window ordering")
        expect(panel.level.rawValue == -1 && band.level == NotchPanel.notchLevel,
               "Body and band retain independent levels while yielding")
        panel.level = NotchPanel.notchLevel
        panel.addChildWindow(band, ordered: .above)
        panel.suspendStationarySpace(false)
        settle()
        expect(reader.spaces(panel, mask: 15) == overlay && reader.spaces(band, mask: 15) == overlay,
               "Reattaching the band and resuming restores both memberships")

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: app)
        settle()
        expect(reader.spaces(panel, mask: 11).isEmpty, "Termination removes the overlay")
        expect(!reader.spaces(panel, mask: 7).isEmpty, "Cleanup restores normal membership")
        expect(panel.collectionBehavior == originalBehavior, "Cleanup restores normal flags")
        setenv("CASPER_DISABLE_OVERLAY_SPACE", "1", 1)
        expect(NotchOverlaySpace(windows: [panel, band]) == nil, "Environment override uses the AppKit fallback")
        unsetenv("CASPER_DISABLE_OVERLAY_SPACE")
        band.orderOut(nil)
        panel.orderOut(nil)
        print("\(checks - failures)/\(checks) overlay Space checks passed")
        if failures > 0 { exit(1) }
    }

    private static func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    private static func expect(_ result: Bool, _ message: String) {
        checks += 1
        if !result {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private struct SpaceReader {
        typealias Connection = @convention(c) () -> Int32
        typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        let connection: Int32
        let copySpaces: CopySpaces

        init() {
            let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
            connection = unsafeBitCast(dlsym(library, "SLSMainConnectionID")!, to: Connection.self)()
            copySpaces = unsafeBitCast(dlsym(library, "SLSCopySpacesForWindows")!, to: CopySpaces.self)
        }

        func spaces(_ window: NSWindow, mask: Int32) -> [UInt64] {
            guard let result = copySpaces(connection, mask, [window.windowNumber] as CFArray)?.takeRetainedValue()
            else { return [] }
            return (result as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
        }
    }
}

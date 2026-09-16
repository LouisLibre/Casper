// Run from the repository root:
// xcrun swiftc -parse-as-library -default-isolation MainActor \
//   app/casper/Notch/NotchPanel.swift app/casper/Notch/SystemAlertMonitor.swift \
//   app/casper/Notch/NotchOverlaySpace.swift \
//   app/tests/SystemAlertMonitorTests.swift -o /tmp/casper-system-alert-tests
// /tmp/casper-system-alert-tests

import AppKit
import CoreGraphics

@main
struct SystemAlertMonitorTests {
    private static var checks = 0

    static func main() {
        let notchLevel = NotchPanel.notchLevel.rawValue
        let panel = window(1, pid: 100, level: notchLevel)
        let permission = window(2, pid: 200, level: 8)
        expect(8, [panel, permission], "A hidden modal permission alert must be detected")
        expect(8, [permission, window(1, pid: 100, level: 7)],
               "Lowering the panel must not oscillate its level on the next poll")
        expect(nil, [panel], "Closing an alert restores the panel even if its helper stays running")
        expect(8, [panel, window(3, pid: 200, level: 8)],
               "A consecutive prompt from the same process must still be detected")
        expect(8, [panel, window(2, pid: 300, level: 8)],
               "Modal dialogs from unlisted processes also need to be visible")
        expect(0, [panel, window(2, pid: 200, level: 0)],
               "A recognized system helper can present a normal-level alert")
        expect(0, [panel, permission, window(3, pid: 200, level: 0)],
               "Yield below the lowest of simultaneous alerts")
        expect(nil, [panel, window(2, pid: 100, level: 8)],
               "Casper's own modal windows must not trigger yielding")
        for level in [0, 3, 20, 24, 25, 26, 101] {
            expect(nil, [panel, window(2, pid: 300, level: level)],
                   "Ordinary windows, palettes, Dock, menus, and banners aren't alerts")
        }
        expect(nil, [panel, window(2, pid: 200, level: notchLevel + 1)],
               "An alert already above the notch needs no level change")
        expect(notchLevel, [panel, window(2, pid: 200, level: notchLevel)],
               "A system alert at the notch's level can still be covered")
        expect(nil, [panel, window(2, pid: 200, level: 8, alpha: 0)],
               "An invisible helper window must not keep the panel lowered")
        expect(nil, [panel, window(2, pid: 200, level: 8, frame: .zero)],
               "An empty helper window must not keep the panel lowered")
        expect(nil, [panel, window(2, pid: 200, level: 8,
                                  frame: CGRect(x: 2000, y: -800, width: 260, height: 200))],
               "A dialog on another display that Casper cannot cover is irrelevant")
        let upperDisplay = CGRect(x: -800, y: -1000, width: 752, height: 550)
        expect(8, [window(1, pid: 100, level: notchLevel, frame: upperDisplay),
                   window(2, pid: 200, level: 8, frame: upperDisplay.insetBy(dx: 100, dy: 100))],
               "Negative display coordinates use the same window-server coordinate space")
        expect(8, [panel, window(3, pid: 100, level: notchLevel + 1,
                                frame: CGRect(x: 800, y: 100, width: 260, height: 200)),
                   window(2, pid: 200, level: 8,
                          frame: CGRect(x: 800, y: 100, width: 260, height: 200))],
               "A permission alert overlapping only Casper's child must be detected",
               ownIDs: [1, 3])
        expect(nil, [permission], "No onscreen Casper window means no occlusion")
        expect(nil, [panel, [:]], "Incomplete metadata is ignored")

        let band = window(4, pid: 100, level: notchLevel,
                          frame: CGRect(x: 0, y: 0, width: 752, height: 33))
        let centered = window(2, pid: 200, level: 8,
                              frame: CGRect(x: 250, y: 150, width: 260, height: 200))
        let atTop = window(2, pid: 200, level: 8,
                           frame: CGRect(x: 250, y: 20, width: 260, height: 200))
        expectLevels(.init(panel: 8, band: nil), [panel, band, centered],
                     "A centered permission prompt lowers the body but preserves the band")
        expectLevels(.init(panel: 8, band: 8), [panel, band, atTop],
                     "A prompt touching the band takes priority over hiding the menu bar")
        expectLevels(.init(panel: 0, band: 8),
                     [panel, band, atTop, window(5, pid: 200, level: 0,
                                                frame: CGRect(x: 250, y: 300, width: 260, height: 200))],
                     "Each window yields to its own lowest overlapping alert")
        expectLevels(.init(panel: 8, band: nil),
                     [window(1, pid: 100, level: 7), band, centered],
                     "An independently raised band cannot make the body oscillate")
        expectLevels(.init(), [window(1, pid: 100, level: 7), band],
                     "Closing the prompt restores both windows")
        expectLevels(.init(panel: 8, band: nil), [panel, band, centered],
                     "Moving a prompt out of the band restores only the band")
        expectLevels(.init(), [panel, band, window(2, pid: 200, level: 8,
                          frame: CGRect(x: 2000, y: -800, width: 260, height: 200))],
                     "A prompt on another display cannot lower either window")
        expectLevels(.init(panel: 8, band: nil),
                     [panel, band, window(3, pid: 100, level: notchLevel + 1,
                                         frame: CGRect(x: 800, y: 100, width: 260, height: 200)),
                      window(2, pid: 200, level: 8,
                             frame: CGRect(x: 800, y: 100, width: 260, height: 200))],
                     "A child-only overlap leaves the band raised", panelIDs: [1, 3])
        expectLevels(.init(panel: 8, band: nil), [panel, centered],
                     "Monitoring still works before a band window is onscreen")
        expectLevels(.init(panel: nil, band: 8), [band, atTop],
                     "A band-only overlap is still a yielding state")
        let away = CGRect(x: 2000, y: -800, width: 260, height: 200)
        expectPermissionFrames([away], [window(2, pid: 200, level: 8, frame: away)],
                               "Moving a permission away from Casper does not finish the interruption")
        expectPermissionFrames([away], [window(2, pid: 200, level: notchLevel + 1, frame: away)],
                               "A permission already above Casper still owns focus")
        expectPermissionFrames([], [window(2, pid: 300, level: 8)],
                               "Another application's modal must not request permission-focus restoration")
        expectPermissionFrames([], [window(2, pid: 200, level: 8, alpha: 0)],
                               "An invisible permission window no longer owns focus")
        expectPermissionFrames([], [window(2, pid: 200, level: 8, frame: .zero)],
                               "An empty helper window is ignored")
        expectPermissionFrames([], [window(2, pid: 100, level: 8)],
                               "Casper's confirmations use their existing focus path")
        expectPermissionFrames([away], [window(2, pid: 200, level: 8, alpha: 0),
                                        window(3, pid: 200, level: 8, frame: away)],
                               "A replacement permission keeps the interruption active")
        expectPermissionFrames([], [], "No permission windows means the interruption ended")
        // No fixtures include a window title or sharing state: neither is
        // available without Screen Recording approval, nor needed here.
        print("Passed \(checks) system-alert window-ordering checks")
    }

    private static func window(_ id: Int, pid: Int32, level: Int, alpha: Double = 1,
                               frame: CGRect = CGRect(x: 0, y: 0, width: 752, height: 550)) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowLayer as String: NSNumber(value: level),
         kCGWindowAlpha as String: NSNumber(value: alpha),
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }

    private static func expectPermissionFrames(_ expected: [CGRect], _ windows: [[String: Any]],
                                               _ message: String) {
        let actual = SystemAlertMonitor.permissionWindowFrames(in: windows, ownPID: 100) { $0 == 200 }
        precondition(actual == expected, message)
        checks += 1
    }

    private static func expect(_ expected: Int?, _ windows: [[String: Any]], _ message: String,
                               ownIDs: Set<Int> = [1]) {
        let actual = SystemAlertMonitor.alertLevel(in: windows, covering: ownIDs, ownPID: 100) {
            $0 == 200
        }
        precondition(actual == expected, "\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
        checks += 1
    }

    private static func expectLevels(_ expected: SystemAlertMonitor.AlertLevels,
                                     _ windows: [[String: Any]], _ message: String,
                                     panelIDs: Set<Int> = [1]) {
        let actual = SystemAlertMonitor.alertLevels(in: windows, panelIDs: panelIDs, bandID: 4,
                                                    ownPID: 100) { $0 == 200 }
        precondition(actual == expected, "\(message): expected \(expected), got \(actual)")
        checks += 1
    }
}

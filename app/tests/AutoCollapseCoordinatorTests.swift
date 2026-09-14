// Run from the repository root:
// xcrun swiftc -parse-as-library -default-isolation MainActor \
//   app/casper/Notch/AutoCollapseCoordinator.swift \
//   app/tests/AutoCollapseCoordinatorTests.swift -o /tmp/casper-app-switch-tests
// /tmp/casper-app-switch-tests

import Foundation

@main
struct AutoCollapseCoordinatorTests {
    private static var checks = 0

    static func main() async throws {
        let coordinator = AutoCollapseCoordinator()
        var collapses = 0

        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 0, "Activation without Command use must leave the panel open")
        try await Task.sleep(for: .milliseconds(300))
        expect(collapses == 0, "A Space-related activation must not schedule a later collapse")

        // Control/Option/Shift changes can report Command as false too.
        coordinator.commandKeyChanged(isPressed: false)
        expect(!coordinator.cmdRecentlyPressed, "A release without a preceding press must not arm collapse")
        coordinator.commandKeyChanged(isPressed: true)
        expect(!coordinator.cmdRecentlyPressed, "Holding Command alone must not arm collapse")
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 0, "The eligibility window starts on release, not press")

        coordinator.commandKeyChanged(isPressed: false)
        expect(coordinator.cmdRecentlyPressed, "Releasing Command arms the window immediately")
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 1, "A qualifying activation must collapse synchronously, without a timer delay")
        expect(!coordinator.cmdRecentlyPressed, "The activation consumes the Command release")
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 1, "Duplicate activations must not reuse the same release")

        // Activation can sample the live key state before the release event is
        // delivered. The delayed duplicate must not open another window.
        coordinator.commandKeyChanged(isPressed: false)
        expect(!coordinator.cmdRecentlyPressed, "A delayed duplicate release must not rearm collapse")

        coordinator.commandKeyChanged(isPressed: true)
        coordinator.commandKeyChanged(isPressed: false)
        try await Task.sleep(for: .milliseconds(300))
        expect(!coordinator.cmdRecentlyPressed, "The default 200 ms window must expire")
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 1, "An activation after expiry must leave the panel open")

        coordinator.commandKeyChanged(isPressed: true)
        coordinator.commandKeyChanged(isPressed: false)
        coordinator.cancel() // Returning to Casper, an alert, or a panel-state request.
        coordinator.commandKeyChanged(isPressed: false)
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 1, "Cancelled eligibility must stay cancelled after duplicate modifier events")

        coordinator.commandKeyChanged(isPressed: true)
        coordinator.commandKeyChanged(isPressed: false)
        coordinator.commandKeyChanged(isPressed: true)
        expect(!coordinator.cmdRecentlyPressed, "A new Command press clears the previous release window")
        coordinator.commandKeyChanged(isPressed: false)
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 2, "A new release must work after earlier eligibility was consumed or cancelled")

        // Block this actor so the expiration task cannot run. The synchronous
        // deadline check still must reject an activation beyond 200 ms.
        coordinator.commandKeyChanged(isPressed: true)
        coordinator.commandKeyChanged(isPressed: false)
        blockMainActor(for: 0.3)
        expect(coordinator.cmdRecentlyPressed, "This scenario must exercise delayed timer cleanup")
        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 2, "A busy main actor must not extend eligibility past its deadline")

        // Use a wider window to leave ample scheduling margin on build machines.
        let restarted = AutoCollapseCoordinator(commandReleaseWindow: .milliseconds(400))
        restarted.commandKeyChanged(isPressed: true)
        restarted.commandKeyChanged(isPressed: false)
        try await Task.sleep(for: .milliseconds(300))
        restarted.commandKeyChanged(isPressed: true)
        restarted.commandKeyChanged(isPressed: false)
        try await Task.sleep(for: .milliseconds(200))
        expect(restarted.cmdRecentlyPressed, "An older expiration task must not clear a newer release window")
        restarted.otherAppDidActivate { collapses += 1 }
        expect(collapses == 3, "A restarted window must still allow immediate collapse")

        print("Passed \(checks) Command-release/activation checks")
    }

    private static func blockMainActor(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }
}

// Run from the repository root:
// xcrun swiftc -parse-as-library -default-isolation MainActor \
//   app/casper/Notch/AutoCollapseCoordinator.swift \
//   app/tests/AutoCollapseCoordinatorTests.swift -o /tmp/casper-app-switch-tests
// /tmp/casper-app-switch-tests

import Foundation

@main
struct AutoCollapseCoordinatorTests {
    private static var checks = 0
    private static let delay: Duration = .milliseconds(30)

    static func main() async throws {
        let coordinator = AutoCollapseCoordinator(settlingDelay: delay)
        var collapses = 0

        coordinator.otherAppDidActivate { collapses += 1 }
        expect(collapses == 0, "Activation must allow a Space notification to arrive first")
        try await settle()
        expect(collapses == 1, "An ordinary app switch must still collapse")

        collapses = 0
        coordinator.otherAppDidActivate { collapses += 1 }
        await Task.yield()
        coordinator.spaceDidChange()
        try await settle()
        expect(collapses == 0, "Activation followed by a Space change must leave the panel open")

        coordinator.spaceDidChange()
        coordinator.otherAppDidActivate { collapses += 1 }
        try await settle()
        expect(collapses == 0, "A Space change followed by activation must leave the panel open")

        for _ in 0..<3 {
            coordinator.otherAppDidActivate { collapses += 1 }
            coordinator.spaceDidChange()
            coordinator.otherAppDidActivate { collapses += 1 }
        }
        try await settle()
        expect(collapses == 0, "Repeated Space changes and activation callbacks must not collapse")

        coordinator.otherAppDidActivate { collapses += 1 }
        try await settle()
        expect(collapses == 1, "A later app switch must work after Space notifications settle")

        collapses = 0
        coordinator.otherAppDidActivate { collapses += 1 }
        await Task.yield()
        coordinator.cancel()
        try await settle()
        expect(collapses == 0, "Returning to Casper or yielding to an alert cancels pending collapse")

        coordinator.otherAppDidActivate { collapses += 1 }
        coordinator.cancel() // Explicit collapse, followed by reopening the panel.
        try await settle()
        expect(collapses == 0, "An earlier app switch must not collapse a newly reopened panel")

        var destinations: [String] = []
        coordinator.otherAppDidActivate { destinations.append("old app") }
        coordinator.otherAppDidActivate { destinations.append("new app") }
        try await settle()
        expect(destinations == ["new app"], "Only the latest activation can request collapse")

        var temporary: AutoCollapseCoordinator? = AutoCollapseCoordinator(settlingDelay: delay)
        temporary?.otherAppDidActivate { collapses += 1 }
        temporary = nil
        try await settle()
        expect(collapses == 0, "Releasing the coordinator must cancel its pending collapse")

        print("Passed \(checks) app-switch/Space-change checks")
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }
}

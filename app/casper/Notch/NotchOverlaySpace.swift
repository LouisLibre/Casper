//
//  NotchOverlaySpace.swift
//

import AppKit
import Darwin

/// An unmanaged WindowServer Space keeps the notch outside the desktop's
/// sliding transform. `.stationary` only controls Mission Control layout.
/// These APIs are private: resolve them at runtime and retain AppKit's
/// ordinary all-Spaces behavior if the overlay cannot be established.
@MainActor
final class NotchOverlaySpace {
    private struct Member {
        weak var window: NSWindow?
        let behavior: NSWindow.CollectionBehavior
    }

    private let api: WindowServer
    private let identifier: UInt64
    private let members: [Member]
    private var isAttached = false
    private var isInvalidated = false
    private var terminationObserver: NSObjectProtocol?

    init?(windows: [NSWindow]) {
        guard !windows.isEmpty,
              ProcessInfo.processInfo.environment["CASPER_DISABLE_OVERLAY_SPACE"] != "1",
              let api = WindowServer() else { return nil }
        let identifier = api.create(api.connection, 1, nil)
        guard identifier != 0 else { return nil }
        self.api = api
        self.identifier = identifier
        members = windows.map { Member(window: $0, behavior: $0.collectionBehavior) }

        // A normal overlay, with no lock-screen elevation. The windows keep
        // their existing levels; this changes Space membership, not level.
        api.setLevel(api.connection, identifier, 0)
        guard attach() else {
            invalidate()
            return nil
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if !isInvalidated {
            api.hide(api.connection, [identifier] as CFArray)
            api.destroy(api.connection, identifier)
        }
    }

    /// Dialogs need the ordinary, cross-application window ordering. Leave
    /// the overlay for their lifetime, then rejoin it after they close.
    func setSuspended(_ suspended: Bool) {
        guard !isInvalidated else { return }
        if suspended {
            detach()
        } else if !isAttached, !attach() {
            invalidate()
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        detach()
        api.hide(api.connection, [identifier] as CFArray)
        api.destroy(api.connection, identifier)
        isInvalidated = true
    }

    private func attach() -> Bool {
        let spaces = [identifier] as CFArray
        // Mark attached before editing, so a partial failure restores every
        // member, including windows processed earlier in this loop.
        isAttached = true
        for member in members {
            guard let window = member.window else { continue }
            let windows = [window.windowNumber] as CFArray
            window.collectionBehavior = member.behavior.subtracting(
                [.canJoinAllSpaces, .moveToActiveSpace, .fullScreenAuxiliary]
            )
            api.add(api.connection, windows, spaces)
            guard let membership = api.spaces(for: windows), membership.contains(identifier) else {
                return false
            }
            // Leaving the moving desktop is essential; adding a second
            // membership alone still leaves the window in its animation.
            let desktops = membership.filter { $0 != identifier }
            if !desktops.isEmpty { api.remove(api.connection, windows, desktops as CFArray) }
            guard api.spaces(for: windows) == [identifier] else { return false }
        }
        api.show(api.connection, spaces)
        return true
    }

    private func detach() {
        guard isAttached else { return }
        for member in members {
            guard let window = member.window else { continue }
            window.collectionBehavior = member.behavior
            api.remove(api.connection, [window.windowNumber] as CFArray, [identifier] as CFArray)
        }
        api.hide(api.connection, [identifier] as CFArray)
        isAttached = false
    }

    private nonisolated struct WindowServer {
        typealias Connection = @convention(c) () -> Int32
        typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
        typealias Destroy = @convention(c) (Int32, UInt64) -> Void
        typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
        typealias Membership = @convention(c) (Int32, CFArray, CFArray) -> Void
        typealias Visibility = @convention(c) (Int32, CFArray) -> Void
        typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

        let connection: Int32
        let create: Create
        let destroy: Destroy
        let setLevel: SetLevel
        let add: Membership
        let remove: Membership
        let show: Visibility
        let hide: Visibility
        let copySpaces: CopySpaces

        // Keep the framework loaded for the lifetime of its function pointers.
        private static let library = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
        )

        init?() {
            guard let library = Self.library else { return nil }
            func load<T>(_ name: String, _: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let connection = load("SLSMainConnectionID", Connection.self),
                  let create = load("SLSSpaceCreate", Create.self),
                  let destroy = load("SLSSpaceDestroy", Destroy.self),
                  let setLevel = load("SLSSpaceSetAbsoluteLevel", SetLevel.self),
                  let add = load("SLSAddWindowsToSpaces", Membership.self),
                  let remove = load("SLSRemoveWindowsFromSpaces", Membership.self),
                  let show = load("SLSShowSpaces", Visibility.self),
                  let hide = load("SLSHideSpaces", Visibility.self),
                  let copySpaces = load("SLSCopySpacesForWindows", CopySpaces.self) else { return nil }
            self.connection = connection()
            self.create = create
            self.destroy = destroy
            self.setLevel = setLevel
            self.add = add
            self.remove = remove
            self.show = show
            self.hide = hide
            self.copySpaces = copySpaces
        }

        func spaces(for windows: CFArray) -> [UInt64]? {
            // Include OS-owned Spaces (bit 3) as well as user desktops.
            // The usual user-only mask, 7, cannot see an unmanaged Space.
            guard let result = copySpaces(connection, 15, windows)?.takeRetainedValue() else { return nil }
            return (result as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
        }
    }
}

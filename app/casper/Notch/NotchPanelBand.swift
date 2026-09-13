//
//  NotchPanelBand.swift
//
//  Windows and hit targets for the top strip. Empty band space toggles
//  the notch; the pill and the corner buttons take their own clicks first.
//

import AppKit
import SwiftUI

/// Owns the band's drawing and controls, never the keyboard. Its frame is
/// only the menu-bar-height strip; shortcut badges below it stay in the
/// terminal window. Both windows use the controller's screen geometry.
final class NotchBandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        canHide = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = NotchPanel.notchLevel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class NotchPanelBand: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Drawing never claims a click. The band, pill and buttons above it own
/// interaction, including transparent space inside their hit rectangles.
final class NotchBandDrawingHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

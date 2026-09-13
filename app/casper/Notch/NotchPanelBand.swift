//
//  NotchPanelBand.swift
//
//  Click target for the band: the strip along the top of the expanded
//  shape that holds the corner buttons. A click anywhere in it collapses
//  the notch, as a click on the pill does while collapsed. It sits under
//  the pill and the corner controls, so those take their clicks first.
//  Hidden while collapsed, so it takes no clicks then.
//

import AppKit

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

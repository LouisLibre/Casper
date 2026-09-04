//
//  NotchPanel.swift
//

import AppKit

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Last on purpose: other NSPanel properties (isFloatingPanel is one) will
        // quietly overwrite `level` if you set them after this. statusBar + 1 puts
        // us above the menu bar, which is where the notch lives.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    // Borderless windows refuse key status unless we opt in — the terminal needs keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit constrains window frames to sit below the menu bar. The whole point of
    // this panel is to overlap the notch, so opt out entirely.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        // macOS separates "the active app" (the one named in the menu bar) from
        // "the key window" (the one window that receives typing). Because this
        // panel uses .nonactivatingPanel, it becomes the key window without
        // making this app active: the user types into the notch while, say,
        // Safari still counts as the active app. That combination defeats
        // AppKit's built-in ⌘-shortcut handling — the "ask every view whether
        // it wants this shortcut" pass (performKeyEquivalent) only runs for the
        // active app, and we usually aren't it. So for ⌘ keystrokes we run that
        // pass ourselves: calling performKeyEquivalent on the content view asks
        // it and, recursively, every subview (including the terminal screen)
        // until one returns true. If a view claims the shortcut we stop here;
        // otherwise the event goes through normal delivery.
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           contentView?.performKeyEquivalent(with: event) == true {
            return
        }
        super.sendEvent(event)
    }
}

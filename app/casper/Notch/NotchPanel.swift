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

    /// Receives +1 for ⌘⇧+ and -1 for ⌘⇧-. Both keys are matched by the
    /// character they produce with Shift ("+" or "=" up, "-" or "_" down) so
    /// layouts where plus lives on the equals key and ones where it doesn't
    /// both work.
    var onSizeStep: ((Int) -> Void)?

    /// ⌘Q. Taken here so it reaches the same confirmation from every pane:
    /// the terminal would otherwise swallow it as Ghostty's own quit
    /// binding, and the settings pane would hand it to the app menu, which
    /// quits without asking.
    var onQuit: (() -> Void)?

    /// ⌘M. Collapses the notch, the same as the collapse button in the
    /// corner. Taken here so it works from every pane.
    var onCollapse: (() -> Void)?

    /// ⌘S. Shows the settings pane, the same as the settings button in the
    /// dock. Taken here so it works from every pane.
    var onShowSettings: (() -> Void)?

    /// ⌘T, or ⌘1 to ⌘9 and ⌘0 for the tenth tab.
    enum TabShortcut {
        case newTab
        case tab(Int)
    }

    /// In a terminal the tab shortcuts are Ghostty's own bindings and reach
    /// it as keys, but the settings pane takes no keys, so from there the
    /// panel hands them over. Returns whether the shortcut was taken; false
    /// leaves the key to the views, as in a terminal.
    var onTabShortcut: ((TabShortcut) -> Bool)?

    /// Receives true when ⌘ goes down and false when it comes up. Also
    /// false whenever the panel stops being key: a release that lands in
    /// another app never reaches this window, so it must not stay stuck on.
    var onCommandKeyChange: ((Bool) -> Void)?

    // Borderless windows refuse key status unless we opt in — the terminal needs keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit constrains window frames to sit below the menu bar. The whole point of
    // this panel is to overlap the notch, so opt out entirely.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// AppKit's own key-equivalent pass runs from NSApplication before
    /// `sendEvent`, and if nobody claims a ⌘⇧ key it retries with Shift
    /// stripped. Ghostty claims that retry for minus (⌘- is its font
    /// binding), so the size shortcuts must be taken here, ahead of it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleOwnShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func becomeKey() {
        super.becomeKey()
        onCommandKeyChange?(NSEvent.modifierFlags.contains(.command))
    }

    override func resignKey() {
        super.resignKey()
        onCommandKeyChange?(false)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            onCommandKeyChange?(event.modifierFlags.contains(.command))
        }
        // As a .nonactivatingPanel this window takes key status without
        // making the app active, so the user types here while another app
        // owns the menu bar. AppKit only runs its ⌘-shortcut pass
        // (performKeyEquivalent down the view tree) for the active app, so
        // for ⌘ keys we run it ourselves and stop if a view claims the key.
        //
        // The panel's own shortcuts go first: Ghostty binds ⌘+ to font size,
        // and on a US layout ⌘⇧= produces that plus, so the terminal would
        // take it; it binds ⌘Q too.
        if handleOwnShortcut(event) { return }
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           contentView?.performKeyEquivalent(with: event) == true {
            return
        }
        super.sendEvent(event)
    }

    /// The panel's own shortcuts, taken ahead of every view: ⌘⇧+ / ⌘⇧- step
    /// the size, ⌘Q asks about quitting, ⌘M collapses and ⌘S shows
    /// settings; the tab shortcuts only when the pane on screen cannot take
    /// them. Whether `event` was one of them.
    private func handleOwnShortcut(_ event: NSEvent) -> Bool {
        if let delta = Self.sizeStep(for: event), let onSizeStep {
            onSizeStep(delta)
            return true
        }
        if Self.isCommandKey(event, "q"), let onQuit {
            onQuit()
            return true
        }
        if Self.isCommandKey(event, "m"), let onCollapse {
            onCollapse()
            return true
        }
        if Self.isCommandKey(event, "s"), let onShowSettings {
            onShowSettings()
            return true
        }
        if let shortcut = Self.tabShortcut(for: event), let onTabShortcut, onTabShortcut(shortcut) {
            return true
        }
        return false
    }

    /// ⌘T, or ⌘ with a digit: 1 to 9 for those tabs, 0 for the tenth. ⌘
    /// alone, as with Shift or Option these are other keys. Matched by the
    /// character first, then by the physical key for layouts whose digits
    /// need Shift: the US digit row and the keypad.
    private static func tabShortcut(for event: NSEvent) -> TabShortcut? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command]
        else { return nil }
        let character = event.charactersIgnoringModifiers ?? ""
        if character == "t" { return .newTab }
        if let digit = Int(character), (0...9).contains(digit) {
            return .tab(digit == 0 ? 10 : digit)
        }
        let digitRow: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10]
        let keypad: [UInt16: Int] = [83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10]
        if let number = digitRow[event.keyCode] ?? keypad[event.keyCode] {
            return .tab(number)
        }
        return nil
    }

    /// Whether `event` is `key` pressed with ⌘ alone.
    private static func isCommandKey(_ event: NSEvent, _ key: String) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command]
            && event.charactersIgnoringModifiers == key
    }

    private static func sizeStep(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
        else { return nil }
        // With ⌘ held AppKit reports the key inconsistently across layouts:
        // sometimes the shifted character, sometimes the base one, sometimes
        // the US-layout equivalent. Check every reading, then the physical
        // keys for the US positions and the keypad.
        let readings = [event.charactersIgnoringModifiers,
                        event.characters,
                        event.characters(byApplyingModifiers: []),
                        event.characters(byApplyingModifiers: .shift)].compactMap { $0 }
        if readings.contains(where: { ["+", "="].contains($0) }) { return 1 }
        if readings.contains(where: { ["-", "_"].contains($0) }) { return -1 }
        switch event.keyCode {
        case 24, 69: return 1   // ANSI equal, keypad plus
        case 27, 78: return -1  // ANSI minus, keypad minus
        default: return nil
        }
    }
}

//
//  ToggleChordMonitor.swift
//
//  The chord that expands or collapses the notch from any app: Control and
//  the left Option key pressed together. It fires the moment both are down.
//  No key is pressed, so this is not a hotkey but a watch on modifier
//  changes, which global monitors report without Accessibility or Input
//  Monitoring permission.
//

import AppKit

final class ToggleChordMonitor {
    /// Called once each time the chord goes down.
    var onTrigger: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var previousModifiers: NSEvent.ModifierFlags = []

    private static let chord: NSEvent.ModifierFlags = [.control, .option]
    /// The chord as a badge reads it.
    static let hint = "⌃⌥"
    /// The keys that make up a chord. Caps Lock is a state, not a key held.
    private static let modifierKeys: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]
    /// Device bits in the raw flags that tell the two Option keys apart (IOLLEvent.h).
    private static let leftOptionBit: UInt = 0x20
    private static let rightOptionBit: UInt = 0x40

    func start() {
        // Events other apps receive. Never called for Casper's own.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            DispatchQueue.main.async { self?.modifiersChanged(to: flags) }
        }
        // Casper's own events, while the panel is key and has the keyboard.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifiersChanged(to: event.modifierFlags)
            return event
        }
    }

    private func modifiersChanged(to flags: NSEvent.ModifierFlags) {
        let modifiers = flags.intersection(Self.modifierKeys)
        defer { previousModifiers = modifiers }

        guard modifiers == Self.chord, Self.isLeftOptionOnly(flags) else { return }
        // Only on the way in, from nothing or one of the two keys. Coming
        // down to it from a bigger chord (⌃⌥⌘8, then ⌘ up) does not count.
        guard previousModifiers.isStrictSubset(of: Self.chord) else { return }
        // VoiceOver's own modifier keys are ⌃⌥; its users press them constantly.
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }
        onTrigger?()
    }

    private static func isLeftOptionOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.rawValue & leftOptionBit != 0 && flags.rawValue & rightOptionBit == 0
    }
}

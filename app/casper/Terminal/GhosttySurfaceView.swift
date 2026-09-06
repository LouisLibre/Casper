//
//  GhosttySurfaceView.swift
//
//  One libghostty surface hosted in an NSView: the terminal emulator, its
//  Metal renderer and the shell behind it. Owns the ghostty_surface_t and
//  translates AppKit input into libghostty calls. Modeled on the Ghostty
//  app's SurfaceView_AppKit.swift, trimmed to what a single embedded terminal
//  needs: no splits, menus or services. Tabs are the app's business; the
//  view only reports the keybinds that ask for them.
//
//  libghostty replaces this view's layer with its own render layer and turns
//  on clipsToBounds while the surface is created, so anything that has to
//  survive that (corner radius, masks) belongs on a parent view.
//

import AppKit
import Carbon.HIToolbox
import GhosttyKit
import os

@MainActor
final class GhosttySurfaceView: NSView {
    /// nil once `close()` ran; every libghostty call checks it first.
    private(set) var surface: ghostty_surface_t?

    /// libghostty wants this surface gone: the shell exited, or a close
    /// keybind fired; `processExited` tells the two apart. Called from
    /// inside libghostty's own event processing, so tear down on a later
    /// runloop turn, never inline.
    var onCloseRequest: (() -> Void)?
    /// Ghostty's new_tab binding fired while this surface had focus. Called
    /// from inside libghostty's event processing, like `onCloseRequest`.
    var onNewTabRequest: (() -> Void)?
    /// One of Ghostty's goto_tab bindings (⌘1–⌘9, next and previous tab)
    /// fired while this surface had focus. Called like `onNewTabRequest`.
    var onGoToTabRequest: ((TabDestination) -> Void)?

    /// Whether a process is still running in the shell, by Ghostty's own
    /// close rules (its `confirm-close-surface` setting).
    var needsConfirmClose: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    /// Whether the shell itself has ended (exit, ⌃D).
    var processExited: Bool {
        guard let surface else { return false }
        return ghostty_surface_process_exited(surface)
    }

    private(set) var focused = false
    private var markedText = NSMutableAttributedString()
    /// Non-nil only while inside keyDown; collects what insertText produces.
    private var keyTextAccumulator: [String]?
    private var cursor: NSCursor = .iBeam
    private var keyUpMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, app: ghostty_app_t) {
        super.init(frame: frame)

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 1)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        // libghostty copies the strings it needs while creating the surface.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        surface = home.withCString { directory in
            config.working_directory = directory
            return ghostty_surface_new(app, &config)
        }
        guard let surface else {
            GhosttyRuntime.logger.critical("ghostty_surface_new failed")
            return
        }

        setBackgroundOpacity(GhosttyRuntime.shared.backgroundOpacity)
        // Nothing has focus until the panel expands and makes us first responder.
        ghostty_surface_set_focus(surface, false)
        syncSize()
        updateTrackingAreas()
        registerForDraggedTypes([.fileURL, .URL, .string])

        // AppKit never delivers keyUp for ⌘-modified keys through the
        // responder chain, so pick those up from the event stream instead.
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, self.focused, event.modifierFlags.contains(.command) else { return event }
            self.keyUp(with: event)
            return nil
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        if let surface { ghostty_surface_free(surface) }
    }

    /// Frees the surface, which also ends the shell process. The view is
    /// inert afterwards.
    func close() {
        guard let surface else { return }
        self.surface = nil
        ghostty_surface_free(surface)
    }

    /// libghostty installs its render layer marked opaque regardless of
    /// `background-opacity`, which makes the compositor drop the alpha it
    /// renders with. Mirror the config onto the layer.
    func setBackgroundOpacity(_ opacity: Double) {
        layer?.isOpaque = opacity >= 1
    }

    /// Lets the renderer idle while the notch is collapsed.
    func setVisible(_ visible: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, visible)
    }

    func setMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: cursor = .arrow
        case GHOSTTY_MOUSE_SHAPE_TEXT: cursor = .iBeam
        case GHOSTTY_MOUSE_SHAPE_POINTER: cursor = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_GRAB: cursor = .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: cursor = .closedHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursor = .crosshair
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: cursor = .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursor = .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: cursor = .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_W_RESIZE, GHOSTTY_MOUSE_SHAPE_E_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            cursor = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE, GHOSTTY_MOUSE_SHAPE_S_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            cursor = .resizeUpDown
        default: return
        }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Geometry

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        syncContentScale()
        syncDisplay()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncContentScale()
    }

    @objc private func windowDidChangeScreen(_ notification: Notification) {
        guard let window, notification.object as? NSWindow === window else { return }
        syncDisplay()
        syncContentScale()
    }

    /// libghostty renders at backing resolution; tell it the scale and keep
    /// the layer from being rescaled by the compositor.
    private func syncContentScale() {
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        CATransaction.commit()
        ghostty_surface_set_content_scale(surface, scale, scale)
        syncSize()
    }

    private func syncSize() {
        guard let surface else { return }
        let size = convertToBacking(bounds.size)
        ghostty_surface_set_size(surface, UInt32(max(0, size.width)), UInt32(max(0, size.height)))
    }

    /// Used by the renderer's vsync source to follow the right display.
    private func syncDisplay() {
        guard let surface, let screen = window?.screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }
        ghostty_surface_set_display_id(surface, displayID)
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { setFocused(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setFocused(false) }
        return resigned
    }

    private func setFocused(_ focused: Bool) {
        guard self.focused != focused else { return }
        self.focused = focused
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Self.mods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Self.mods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface,
              ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, Self.mods(event.modifierFlags))
        else { return super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface,
              ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, Self.mods(event.modifierFlags))
        else { return super.rightMouseUp(with: event) }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, Self.button(event.buttonNumber), Self.mods(event.modifierFlags))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, Self.button(event.buttonNumber), Self.mods(event.modifierFlags))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        reportMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Drags keep reporting through mouseDragged even outside the view.
        guard let surface, NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, Self.mods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) { reportMousePosition(event) }
    override func mouseDragged(with event: NSEvent) { reportMousePosition(event) }
    override func rightMouseDragged(with event: NSEvent) { reportMousePosition(event) }
    override func otherMouseDragged(with event: NSEvent) { reportMousePosition(event) }

    /// libghostty's origin is top-left; AppKit's is bottom-left.
    private func reportMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, Self.mods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise {
            // Same multiplier as Ghostty.app; trackpad deltas feel sluggish otherwise.
            x *= 2
            y *= 2
        }
        // Packed like ghostty's ScrollMods: bit 0 precision, bits 1-3 momentum phase.
        var mods: ghostty_input_scroll_mods_t = precise ? 1 : 0
        mods |= Int32(Self.momentum(event.momentumPhase)) << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    private static func momentum(_ phase: NSEvent.Phase) -> UInt8 {
        switch phase {
        case .began: return 1
        case .stationary: return 2
        case .changed: return 3
        case .ended: return 4
        case .cancelled: return 5
        case .mayBegin: return 6
        default: return 0
        }
    }

    private static func button(_ number: Int) -> ghostty_input_mouse_button_e {
        switch number {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        case 3: return GHOSTTY_MOUSE_EIGHT
        case 4: return GHOSTTY_MOUSE_NINE
        case 5: return GHOSTTY_MOUSE_SIX
        case 6: return GHOSTTY_MOUSE_SEVEN
        case 7: return GHOSTTY_MOUSE_FOUR
        case 8: return GHOSTTY_MOUSE_FIVE
        case 9: return GHOSTTY_MOUSE_TEN
        case 10: return GHOSTTY_MOUSE_ELEVEN
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    // MARK: - Keyboard

    /// ⌘ shortcuts arrive here first (NotchPanel runs the key-equivalent pass
    /// itself). Keys bound in the Ghostty config are performed; everything
    /// else falls through to keyDown, where libghostty decides whether the
    /// child gets it (kitty keyboard protocol) or it is dropped.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused, let surface else { return false }
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { text -> Bool in
            keyEvent.text = text
            var flags = ghostty_binding_flags_e(0)
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
        guard isBinding else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Translation modifiers differ from the event's when the config maps
        // option to alt: libghostty then wants the untranslated character.
        let translationFlags = Self.modifierFlags(
            ghostty_surface_key_translation_mods(surface, Self.mods(event.modifierFlags)))
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationFlags.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        // Reuse the original event whenever possible: input methods compare
        // event identity and Korean input breaks with a copy.
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Run the event through the input method first so dead keys and
        // composed input (Korean, Japanese) arrive via insertText.
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let markedTextBefore = markedText.length > 0
        let keyboardBefore: String? = markedTextBefore ? nil : Self.keyboardLayoutID
        interpretKeyEvents([translationEvent])

        // A key that switched the keyboard layout was for the input method.
        if !markedTextBefore && keyboardBefore != Self.keyboardLayoutID { return }

        syncPreedit(clearIfNeeded: markedTextBefore)

        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                sendKey(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            sendKey(action,
                    event: event,
                    translationEvent: translationEvent,
                    text: translationEvent.ghosttyCharacters,
                    // Still composing, or this key just cancelled a composition
                    // and must not be encoded (backspace during Japanese input).
                    composing: markedText.length > 0 || markedTextBefore)
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifier: UInt32
        switch event.keyCode {
        case 0x39: modifier = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: modifier = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: modifier = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: modifier = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: modifier = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        if hasMarkedText() { return }

        // Pressed if the modifier is set and it was this side's key; a release
        // of one side with the other still held reports as a release.
        var action = GHOSTTY_ACTION_RELEASE
        if Self.mods(event.modifierFlags).rawValue & modifier != 0 {
            let raw = event.modifierFlags.rawValue
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C: sidePressed = raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E: sidePressed = raw & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D: sidePressed = raw & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36: sidePressed = raw & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: sidePressed = true
            }
            if sidePressed { action = GHOSTTY_ACTION_PRESS }
        }
        sendKey(action, event: event)
    }

    @discardableResult
    private func sendKey(_ action: ghostty_input_action_e,
                         event: NSEvent,
                         translationEvent: NSEvent? = nil,
                         text: String? = nil,
                         composing: Bool = false) -> Bool {
        guard let surface else { return false }
        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing
        // Control characters are encoded by libghostty itself; sending them as
        // text would break ctrl+enter and friends.
        if let text, let first = text.utf8.first, first >= 0x20 {
            return text.withCString { pointer in
                keyEvent.text = pointer
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    /// Identifier of the active keyboard layout, to spot keys the input
    /// method consumed for switching layouts.
    private static var keyboardLayoutID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }

    // MARK: - Modifier translation

    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        let raw = flags.rawValue
        if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }

    private static func modifierFlags(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    // MARK: - Drag and drop

    /// Files land as shell-escaped paths and anything else as its text, typed
    /// into the terminal the way Ghostty.app does it. A TUI sees exactly what
    /// it would have if the user had typed the path.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard surface != nil, Self.droppedText(sender.draggingPasteboard) != nil else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let surface, let text = Self.droppedText(sender.draggingPasteboard) else { return false }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
        // Starting the drag in another app took key status away from the
        // panel; hand it back so the next keystroke reaches the terminal.
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self)
        }
        return true
    }

    private static func droppedText(_ pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.map { shellEscape($0.path) }.joined(separator: " ")
        }
        if let url = pasteboard.string(forType: .URL), !url.isEmpty { return url }
        if let string = pasteboard.string(forType: .string), !string.isEmpty { return string }
        return nil
    }

    /// Backslash-escapes every character a POSIX shell would otherwise interpret.
    private static func shellEscape(_ path: String) -> String {
        let special: Set<Character> = [
            " ", "\t", "\n", "\\", "\"", "'", "`", "$", "&", "|", ";", "(", ")",
            "<", ">", "*", "?", "[", "]", "#", "~", "{", "}", "!",
        ]
        var escaped = ""
        for character in path {
            if special.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    // MARK: - Preedit

    /// Pushes the marked (composing) text to libghostty so it draws at the cursor.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let text = markedText.string
            text.withCString { ghostty_surface_preedit(surface, $0, UInt(text.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - NSTextInputClient

extension GhosttySurfaceView: NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        guard let surface else { return NSRange() }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String:
            markedText = NSMutableAttributedString(string: plain)
        default:
            return
        }
        // Outside keyDown (layout switched mid-composition) sync right away.
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let surface, range.length > 0 else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSAttributedString(string: String(cString: text.text))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    /// Where the input method should draw its candidate window.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        // libghostty reports a top-left origin.
        let rect = NSRect(x: x, y: bounds.height - y, width: width, height: height)
        return window.convertToScreen(convert(rect, to: nil))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil, let surface else { return }
        let text: String
        switch string {
        case let attributed as NSAttributedString: text = attributed.string
        case let plain as String: text = plain
        default: return
        }
        // Text arriving means any composition is over.
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }

    /// Swallows the selectors interpretKeyEvents produces for unhandled keys
    /// (otherwise AppKit beeps); the key still reaches libghostty from keyDown.
    override func doCommand(by selector: Selector) {
        guard let surface else { return }
        let action: String
        switch selector {
        case #selector(NSResponder.moveToBeginningOfDocument(_:)): action = "scroll_to_top"
        case #selector(NSResponder.moveToEndOfDocument(_:)): action = "scroll_to_bottom"
        default: return
        }
        action.withCString { _ = ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
    }
}

// MARK: - NSEvent helpers

private extension NSEvent {
    /// Builds the libghostty key event for this NSEvent. `text` and
    /// `composing` are left for the caller, whose string outlives the call.
    func ghosttyKeyEvent(_ action: ghostty_input_action_e,
                         translationMods: NSEvent.ModifierFlags? = nil) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.mods = GhosttySurfaceView.mods(modifierFlags)
        // macOS doesn't say which modifiers produced the text. Ghostty's
        // long-standing heuristic: control and command never do.
        keyEvent.consumed_mods = GhosttySurfaceView.mods(
            (translationMods ?? modifierFlags).subtracting([.control, .command]))
        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
           let characters = characters(byApplyingModifiers: []),
           let scalar = characters.unicodeScalars.first {
            keyEvent.unshifted_codepoint = scalar.value
        }
        return keyEvent
    }

    /// The text libghostty should see for this key: control characters are
    /// encoded by libghostty itself, and function keys (private use area) have
    /// no text at all.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}

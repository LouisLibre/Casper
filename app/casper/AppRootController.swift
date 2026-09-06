//
//  AppRootController.swift
//
//  Owns the panel: creation, expand/collapse state, and repositioning on display changes.
//
//  Interaction model:
//    - click on the notch strip                  -> toggle
//    - left button released outside the panel    -> collapse. The press alone
//      does not, so a drag that starts in another app can end on the terminal.
//    - right button pressed outside the panel    -> collapse
//    - Moving the mouse away does NOT collapse.
//    - ⌘⇧+ / ⌘⇧- while expanded                 -> step the expanded size
//    - ⌘Q                                        -> quit (after confirming), from any pane
//    - ⌘M                                        -> same as the collapse button in the corner
//    - ⌘T or the plus in the dock                -> open another terminal tab, from settings too
//    - ⌘W                                        -> same as the close button in the corner
//    - ⌘1 to ⌘9, ⌘0 for the tenth                -> switch to that tab, from settings too
//    - ⌘[ / ⌘]                                   -> previous / next tab, wrapping around; terminal only
//    - ⌘ held                                    -> the dock and the corner controls show each control's key
//    - ⌘S or the settings button in the dock     -> settings pane in place of the terminal
//    - close button in the corner                -> close the active tab; quit when it is the
//                                                   only one or settings is up (after confirming)
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppRootController: ObservableObject {
    @Published private(set) var isExpanded = false
    /// Every open terminal, in dock order. Never empty once `start()` ran.
    @Published private(set) var terminals: [NotchTerminalScreen] = []
    /// The terminal on screen while expanded (unless settings is), highlighted in the dock.
    @Published private(set) var activeTerminal: NotchTerminalScreen?
    /// The settings pane is on screen in place of the active terminal.
    @Published private(set) var isShowingSettings = false
    /// ⌘ is down while the panel has the keyboard. The dock swaps its icons
    /// for the keys that go with ⌘ meanwhile.
    @Published private(set) var isCommandHeld = false
    /// Whether the shape shows the frosted backdrop (on) or flat black (off).
    @Published private(set) var isTerminalTransparent = true
    /// Whether Casper is registered to start at login, mirrored from macOS.
    @Published private(set) var opensAtLogin = LoginItem.isEnabled

    // human-note: (DRAFT) we should probably have a set preferred sizes based on the current user screen resolution
    /// Size of the expanded shape. A rung of `ExpandedSizeLadder`, picked by
    /// the saved step and clamped to the current screen. Every reader of this
    /// value (shape, gradients, dock offset, terminal frame) follows it.
    @Published private(set) var expandedSize = ExpandedSizeLadder.size(at: 0)

    /// The rung the user chose. Kept as chosen even while a smaller screen
    /// clamps it, so the preference comes back on the larger display.
    private var sizeStep: Int {
        get { UserDefaults.standard.integer(forKey: Self.sizeStepKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sizeStepKey) }
    }
    private static let sizeStepKey = "expandedSizeStep"

    /// What the last run had on screen, so the next launch picks up there:
    /// how many terminals were open, which one was active, and whether the
    /// settings pane was up over it. Written on every change.
    private static let terminalCountKey = "terminalCount"
    private static let activeTerminalIndexKey = "activeTerminalIndex"
    private static let showingSettingsKey = "showingSettings"
    private var savedTerminalCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.terminalCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.terminalCountKey) }
    }
    private var savedActiveTerminalIndex: Int {
        get { UserDefaults.standard.integer(forKey: Self.activeTerminalIndexKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.activeTerminalIndexKey) }
    }
    private var savedIsShowingSettings: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showingSettingsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showingSettingsKey) }
    }

    private var panel: NotchPanel?
    private var pill: NotchPanelPill?
    private var body: NotchPanelBody?
    private var settingsScreen: NotchSettingsScreen?
    private var cornerControls: NotchCornerControlsHost?

    /// What the expanded shape shows: the settings pane when selected,
    /// otherwise the active terminal.
    private var activePane: NotchPane? {
        if isShowingSettings { return settingsScreen }
        return activeTerminal
    }

    private var geometry: AppGeometryReader?
    private var globalClickMonitor: Any?
    /// Runs from an outside left press until the button comes up again.
    private var releaseWatcher: Timer?

    var collapsedSize: CGSize { geometry?.collapsedSize ?? AppGeometryReader.fallbackSize }

    private var panelSize: CGSize { AppGeometryReader.panelSize(forExpanded: expandedSize) }

    // MARK: - Expanded size

    /// Moves the expanded size one rung up or down the ladder. Stops at the
    /// ladder's floor and at the largest rung the current screen can hold.
    func adjustExpandedSize(by delta: Int) {
        let current = clampedSizeStep(sizeStep)
        let next = clampedSizeStep(current + delta)
        guard next != current else { return }
        sizeStep = next
        applyExpandedSize()
        layoutPanel()
    }

    private func clampedSizeStep(_ step: Int) -> Int {
        let ceiling = max(geometry?.maxExpandedStep ?? step, ExpandedSizeLadder.minStep)
        return min(max(step, ExpandedSizeLadder.minStep), ceiling)
    }

    private func applyExpandedSize() {
        let size = ExpandedSizeLadder.size(at: clampedSizeStep(sizeStep))
        if size != expandedSize { expandedSize = size }
    }

    // MARK: - Terminals

    /// ⌘T and the dock's plus: opens another terminal and switches to it.
    func newTerminal() {
        activate(addTerminal())
    }

    /// Shows a terminal, leaving the settings pane if it was up, and gives it
    /// the keyboard. Only the active pane is visible; the other terminals
    /// keep running hidden behind it.
    func activate(_ terminal: NotchTerminalScreen) {
        let previous = activePane
        activeTerminal = terminal
        isShowingSettings = false
        saveActivePane()
        switchPane(from: previous)
    }

    /// Remembers the active tab and whether settings is up for the next launch.
    private func saveActivePane() {
        if let active = activeTerminal, let index = terminals.firstIndex(where: { $0 === active }) {
            savedActiveTerminalIndex = index
        }
        savedIsShowingSettings = isShowingSettings
    }

    /// Ghostty's goto_tab bindings: ⌘1 to ⌘9 pick a tab by number and ⌘0
    /// the tenth; ⌘[ and ⌘] (⌃⇧Tab and ⌃Tab too) step along the row and
    /// wrap at its ends. A number past the last tab does nothing.
    func goToTab(_ destination: TabDestination) {
        guard let active = activeTerminal,
              let current = terminals.firstIndex(where: { $0 === active }) else { return }
        let index: Int
        switch destination {
        case .number(let number): index = number - 1
        case .previous: index = (current - 1 + terminals.count) % terminals.count
        case .next: index = (current + 1) % terminals.count
        case .last: index = terminals.count - 1
        }
        guard terminals.indices.contains(index) else { return }
        activate(terminals[index])
    }

    /// Swaps the pane on screen while expanded. While collapsed every pane
    /// is hidden anyway and the next expand reveals the active one.
    private func switchPane(from previous: NotchPane?) {
        guard isExpanded, let pane = activePane else { return }
        if previous !== pane {
            previous?.hide()
            pane.show()
        }
        focusActivePane()
    }

    /// Dock clicks land in the SwiftUI body, so the pane gets the keyboard
    /// back afterwards. Dock controls that don't switch panes call this
    /// themselves.
    func focusActivePane() {
        panel?.makeFirstResponder(activePane?.inputView)
    }

    @discardableResult
    private func addTerminal() -> NotchTerminalScreen {
        let terminal = NotchTerminalScreen()
        terminal.onNewTabRequest = { [weak self] in self?.newTerminal() }
        terminal.onGoToTabRequest = { [weak self] destination in self?.goToTab(destination) }
        terminal.onCloseRequest = { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            self.closeRequested(by: terminal)
        }
        if let panel, let container = panel.contentView {
            terminal.view.frame = paneFrame(in: panel.frame)
            // Above the SwiftUI body, below the pill.
            container.addSubview(terminal.view, positioned: .below, relativeTo: pill)
        }
        terminals.append(terminal)
        savedTerminalCount = terminals.count
        terminal.startShellIfNeeded()
        return terminal
    }

    /// libghostty wants this terminal gone. A shell that exited on its own
    /// takes its tab with it, or gets a fresh shell when it was the only
    /// one: the notch always keeps a live terminal. The close binding (⌘W)
    /// goes the same way as the corner close button.
    private func closeRequested(by terminal: NotchTerminalScreen) {
        // Requests arrive deferred, so this one may be for a tab already gone.
        guard terminals.contains(where: { $0 === terminal }) else { return }
        //The respawn branch is not a close request. processExited is true only when the shell itself ended on its own: the
        // user typed exit, pressed ⌃D, or the shell crashed. Nobody asked to close a tab or quit the app. libghostty just
        // reports "my child process is gone" through the same callback it uses for ⌘W.
        if terminal.processExited {
            if terminals.count < 2 {
                terminal.respawn()
            } else {
                removeTerminal(terminal)
            }
            return
        }
        close(terminal)
    }

    /// Closes a terminal when others remain to fall back on, asking first if
    /// a process is still running in it. When it is the only one, asks
    /// about quitting instead, whatever is running in it.
    private func close(_ terminal: NotchTerminalScreen) {
        if terminals.count < 2 {
            confirmQuit()
            return
        }
        if terminal.needsConfirmClose {
            let close = confirm("Close this terminal?",
                                detail: "A process is still running in it and will end.",
                                button: "Close")
            guard close else { return }
        }
        removeTerminal(terminal)
    }

    private func removeTerminal(_ terminal: NotchTerminalScreen) {
        guard let index = terminals.firstIndex(where: { $0 === terminal }) else { return }
        // The dock's capsule shrinks with the same animation it grows with,
        // but the tabs in it snap: the closed one goes, the ones after it
        // move up, the next tab's highlight is just there. The dock's row
        // reads the mark off the transaction.
        var transaction = Transaction()
        transaction.closesTab = true
        withTransaction(transaction) {
            terminals.remove(at: index)
            savedTerminalCount = terminals.count
            if terminal === activeTerminal {
                // The tab to its right takes over, or the new last tab when it was rightmost.
                let next = terminals[min(index, terminals.count - 1)]
                if isShowingSettings {
                    // The shell exited behind the settings pane; stay on it.
                    activeTerminal = next
                } else {
                    activate(next)
                }
            }
        }
        // Closing a tab to the left of the active one shifts its index too.
        saveActivePane()
        terminal.close()
    }

    // MARK: - Dock and settings

    /// Puts the settings pane where the active terminal was.
    func showSettings() {
        let previous = activePane
        isShowingSettings = true
        saveActivePane()
        // The user may have changed it in System Settings meanwhile.
        opensAtLogin = LoginItem.isEnabled
        switchPane(from: previous)
    }

    func toggleTerminalTransparency() {
        isTerminalTransparent.toggle()
        focusActivePane()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        opensAtLogin = LoginItem.isEnabled
    }

    // MARK: - Corner controls

    func collapse() {
        setExpanded(false)
    }

    /// The corner close button: closes the active terminal, or asks about
    /// quitting from the settings pane.
    func closeActivePane() {
        guard !isShowingSettings, let terminal = activeTerminal else {
            confirmQuit()
            return
        }
        close(terminal)
    }

    /// Asks before quitting: the shells and anything running in them die
    /// with the app.
    func confirmQuit() {
        let quit = confirm("Quit Casper?",
                           detail: "Every terminal session and anything running in it will end.",
                           button: "Quit")
        if quit { NSApp.terminate(nil) }
    }

    /// Every confirmation goes through the panel, which owns the one way
    /// dialogs are kept in front of it (see NotchPanel+Confirm). Afterwards
    /// the pane gets the keyboard back.
    private func confirm(_ message: String, detail: String, button: String) -> Bool {
        guard let panel else { return false }
        let confirmed = panel.confirm(message, detail: detail, button: button)
        focusActivePane()
        return confirmed
    }

    func start() {
        rebuildPanel()
        // Reopen as many tabs as the last run had, and at least one, and
        // start on the pane it ended on: its tab, with settings over it if
        // that was up. Nothing saved yet means the first tab.
        for _ in 0..<max(savedTerminalCount, 1) { addTerminal() }
        activeTerminal = terminals[min(max(savedActiveTerminalIndex, 0), terminals.count - 1)]
        isShowingSettings = savedIsShowingSettings

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Clicks delivered to *other* apps are by definition outside our panel
        // (the expanded shape fills the whole panel frame). Global click
        // monitors are reliable without Accessibility permission. A right
        // press collapses at once; a left press may be the start of a drag
        // headed for the terminal, so that decision waits for the release.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let isRightPress = event.type == .rightMouseDown
            DispatchQueue.main.async {
                guard let self else { return }
                if isRightPress {
                    self.setExpanded(false)
                } else {
                    self.collapseWhenReleasedOutside()
                }
            }
        }
    }

    /// Collapses once the left button is released, unless the pointer is then
    /// over the expanded shape (a drop onto the terminal). The hardware button
    /// state drives this rather than a mouse-up monitor: while another app
    /// runs a drag session the release is not reliably posted as an event we
    /// can observe, but `pressedMouseButtons` always reflects the hardware.
    private func collapseWhenReleasedOutside() {
        guard isExpanded, releaseWatcher == nil else { return }
        let watcher = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                guard let self else { return }
                self.releaseWatcher = nil
                if !self.expandedShapeScreenRect.contains(NSEvent.mouseLocation) {
                    self.setExpanded(false)
                }
            }
        }
        RunLoop.main.add(watcher, forMode: .common)
        releaseWatcher = watcher
    }

    /// The black shape's frame while expanded, in screen coordinates.
    private var expandedShapeScreenRect: NSRect {
        guard let panel else { return .zero }
        let frame = panel.frame
        return NSRect(x: frame.minX + (frame.width - expandedSize.width) / 2,
                      y: frame.maxY - expandedSize.height,
                      width: expandedSize.width,
                      height: expandedSize.height)
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded, let panel, let pane = activePane else { return }
        isExpanded = expanded

        let collapsedShape = shapeRectInPaneSpace(for: collapsedSize, of: pane)
        let expandedShape = shapeRectInPaneSpace(for: expandedSize, of: pane)

        pill?.setIconVisible(!expanded, animated: true)
        if expanded {
            pane.reveal(from: collapsedShape, to: expandedShape)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(pane.inputView)
        } else {
            pane.conceal(from: expandedShape, to: collapsedShape)
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
    }

    /// Frame of the black shape at a given size, converted into the pane
    /// view's coordinate space for its reveal mask. Inset a hair so the mask
    /// edge stays behind the shape's anti-aliased edge even if the two
    /// animation clocks drift within a frame.
    private func shapeRectInPaneSpace(for size: CGSize, of pane: NotchPane) -> CGRect {
        guard let container = pane.view.superview else { return .zero }
        let panelSize = container.bounds.size
        let shape = NSRect(x: (panelSize.width - size.width) / 2,
                           y: panelSize.height - size.height,
                           width: size.width,
                           height: size.height).insetBy(dx: 2, dy: 2)
        return pane.view.convert(shape, from: container)
    }

    // MARK: - Panel lifecycle

    private func rebuildPanel() {
        guard let screen = AppGeometryReader.preferredScreen() else { return }
        let geometry = AppGeometryReader(screen: screen)
        self.geometry = geometry
        // The new screen may hold fewer rungs than the saved step.
        applyExpandedSize()

        if panel != nil {
            layoutPanel()
            return
        }

        // Fixed frame, big enough for the expanded state and the dock below
        // it. Collapsed just means most of the panel is transparent and
        // doesn't hit-test. Slightly wider than the expanded shape so its top
        // "ears" aren't clipped by the window.
        let frame = geometry.frame(for: panelSize)
        let panel = NotchPanel(contentRect: frame)
        panel.onSizeStep = { [weak self] delta in self?.adjustExpandedSize(by: delta) }
        panel.onQuit = { [weak self] in self?.confirmQuit() }
        panel.onCollapse = { [weak self] in self?.collapse() }
        panel.onShowSettings = { [weak self] in self?.showSettings() }
        // In a terminal these keys reach Ghostty and come back through its
        // bindings; only the settings pane needs the panel to take them.
        panel.onTabShortcut = { [weak self] shortcut in
            guard let self, self.isShowingSettings else { return false }
            switch shortcut {
            case .newTab: self.newTerminal()
            case .tab(let number): self.goToTab(.number(number))
            }
            return true
        }
        panel.onCommandKeyChange = { [weak self] held in
            guard let self, held != self.isCommandHeld else { return }
            self.isCommandHeld = held
        }
        let panelBody = NotchPanelBody().environmentObject(self)

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))

        let hosting = NSHostingView(rootView: panelBody)
        // Don't let SwiftUI drive the window's size — the panel frame is ours.
        hosting.sizingOptions = []
        // Don't apply the screen's notch safe-area inside the panel either.
        hosting.safeAreaRegions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // Pill hit-target view pinned over the place where the physical hardware notch is supposed to be.
        let pill = NotchPanelPill(frame: pillFrame(in: frame))
        pill.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        
        // AGENTS: IGNORE AND SKIP THE NEXT MULTILINE COMMENT
        /*
        <HUMANS_ONLY_BLOCK>
          human-notes: onEnter should do a slight expansion or glow animation on the pill
          old-business-logic: pill.onEnter = { [weak self] in self?.setExpanded(true) }
        </HUMANS_ONLY_BLOCK>
        */
        
        pill.onClick = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
        container.addSubview(pill)
        self.pill = pill

        // In the panel from the start, hidden until its dock tab is selected.
        let settings = NotchSettingsScreen(controller: self)
        settings.view.frame = paneFrame(in: frame)
        container.addSubview(settings.view, positioned: .below, relativeTo: pill)
        settingsScreen = settings

        // Collapse and close, in the band at the top right of the expanded
        // shape. Their key hints hang under the band, over the pane, so
        // they live above every pane: last in, and the terminals come in
        // below the pill.
        let corner = NotchCornerControlsHost(rootView: AnyView(NotchCornerControls().environmentObject(self)))
        corner.sizingOptions = []
        corner.safeAreaRegions = []
        corner.bandHeight = collapsedSize.height
        corner.frame = cornerControlsFrame(in: frame)
        container.addSubview(corner)
        cornerControls = corner

        panel.contentView = container
        panel.acceptsMouseMovedEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Moves the panel and the views that don't autoresize to the frame the
    /// current screen and expanded size call for. Never animated: the SwiftUI
    /// body only animates on expand/collapse, so both snap together.
    private func layoutPanel() {
        guard let panel, let geometry else { return }
        let frame = geometry.frame(for: panelSize)
        panel.setFrame(frame, display: true)
        pill?.frame = pillFrame(in: frame)
        for terminal in terminals {
            terminal.view.frame = paneFrame(in: frame)
        }
        settingsScreen?.view.frame = paneFrame(in: frame)
        cornerControls?.bandHeight = collapsedSize.height
        cornerControls?.frame = cornerControlsFrame(in: frame)
    }

    private func pillFrame(in panelFrame: NSRect) -> NSRect {
        let size = collapsedSize
        return NSRect(x: (panelFrame.width - size.width) / 2,
                      y: panelFrame.height - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// Every pane (terminals and settings) shares this frame inside the shape.
    private func paneFrame(in panelFrame: NSRect) -> NSRect {
        /// inset to match the expanded shape's rounded corners.
        let topInset = collapsedSize.height
        /// The expanded shape is centered in the (wider) panel; keep the pane inside it.
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        /// The shape sits at the top of the panel; the band below it belongs to the dock.
        let shapeBottom = panelFrame.height - expandedSize.height
        return NSRect(x: sideMargin + 7,
                      y: shapeBottom + 7,
                      width: expandedSize.width - 14,
                      height: expandedSize.height - topInset - 7)
    }

    /// Top-right corner of the expanded shape: the band the corner controls
    /// sit in, plus the room under it for their key hints.
    private func cornerControlsFrame(in panelFrame: NSRect) -> NSRect {
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        let height = collapsedSize.height + NotchCornerControls.hintReserve
        return NSRect(x: sideMargin + expandedSize.width - NotchCornerControls.width,
                      y: panelFrame.height - height,
                      width: NotchCornerControls.width,
                      height: height)
    }

    // Display connected/disconnected or resolution changed — the notch may have moved or vanished.
    @objc private func screenParametersChanged() {
        rebuildPanel()
    }
}

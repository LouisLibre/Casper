//
//  AppRootController.swift
//
//  Owns the panel: creation, expand/collapse state, and repositioning on display changes.
//
//  Interaction model:
//    - click on the notch strip                  -> toggle
//    - pointer over the notch strip              -> the strip swells a little, to show it takes clicks
//    - click in the band, while expanded         -> collapse; the corner buttons take their clicks first
//    - ⌃ + left ⌥ pressed together              -> toggle, from any app; the pane takes the keyboard on expand
//    - left button released outside the panel    -> collapse. The press alone
//      does not, so a drag that starts in another app can end on the terminal.
//    - right button pressed outside the panel    -> collapse
//    - pin button in the corner                  -> clicks outside no longer collapse;
//                                                   the collapse button and ⌘M still do.
//                                                   A click outside or ⌘Tab away shakes and
//                                                   glows the pin capsule once instead: the
//                                                   answer to "why didn't it close"
//    - Moving the mouse away does NOT collapse.
//    - ⌘Tab or the Dock icon to Casper           -> expand, with the keyboard. Casper is the
//                                                   active app only while expanded: collapsing
//                                                   from inside hands activation back
//    - ⌘Tab (or a click) to another app          -> collapse, unless pinned, once the other
//                                                   app takes focus. Browsing or cancelling
//                                                   the switcher leaves the notch open
//    - switching Spaces                         -> preserve the expanded state, even if
//                                                   macOS activates an app on the new Space
//    - Show in Dock, in settings                  -> the Dock icon and, with it, the ⌘Tab entry
//    - ⌘⇧+ / ⌘⇧- while expanded                 -> step the expanded size
//    - drag the bottom edge or a bottom corner    -> step the expanded size along with the
//                                                   pointer: down or out for bigger, back
//                                                   for smaller
//    - ⌘Q                                        -> quit (after confirming), from any pane
//    - ⌘M                                        -> same as the collapse button in the corner
//    - ⌘P                                        -> same as the pin button in the corner
//    - ⌘T or the plus in the dock                -> open another terminal tab in the active
//                                                   tab's directory, from settings too
//    - ⌘W                                        -> close the active tab; quit when it is the
//                                                   only one (after confirming)
//    - right click on a tab in the dock          -> menu: Finder at that tab's directory,
//                                                   or close it, as ⌘W would
//    - drag a tab along the dock                 -> move it there; the ⌘ numbers follow
//    - ⌘1 to ⌘9, ⌘0 for the tenth                -> switch to that tab, from settings too
//    - ⌘[ / ⌘]                                   -> previous / next tab, wrapping around; terminal only
//    - ⌘ held                                    -> the dock and the corner controls show each control's key,
//                                                   and the shape's bottom-right corner its size keys
//    - ⌘S or the settings button in the dock     -> settings pane in place of the terminal
//    - quit button in the corner                 -> same as ⌘Q
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppRootController: ObservableObject {
    @Published private(set) var isExpanded = false
    /// While pinned, clicks outside the panel leave it expanded. The corner
    /// button and ⌘M still collapse it. Off at every launch.
    @Published private(set) var isPinned = false
    /// The pin capsule's answer to "why didn't it close". Every collapse
    /// refused because the notch is pinned (a click outside, ⌘Tab or the
    /// Dock) bumps this, and the capsule shakes and glows once per bump.
    @Published private(set) var pinRefusalCount = 0
    /// A click outside can also activate another app, reporting the same
    /// departure as both a press and a switch.
    /// Refusals while this runs are the same refusal and play nothing.
    private var pinRefusalCooldown: Task<Void, Never>?
    private static let pinRefusalCooldownDuration: Duration = .milliseconds(300)
    /// The pointer is over the collapsed strip. The shape swells a little
    /// while it is, to show the strip takes clicks.
    @Published private(set) var isPillHovered = false
    /// Every open terminal, in dock order. Never empty once `start()` ran.
    @Published private(set) var terminals: [NotchTerminalScreen] = []
    /// The terminal on screen while expanded (unless settings is), highlighted in the dock.
    @Published private(set) var activeTerminal: NotchTerminalScreen?
    /// The settings pane is on screen in place of the active terminal.
    @Published private(set) var isShowingSettings = false
    /// Revealed only after a deliberate hold of ⌘ with no key pressed. All
    /// badge groups share this state so quick shortcuts never flash their
    /// hints. Typing a shortcut during the hold cancels the reveal until ⌘
    /// is released and held again.
    @Published private(set) var showsShortcutHints = false
    private var isCommandHeld = false
    private var shortcutHintTask: Task<Void, Never>?
    private static let shortcutHintDelay: Duration = .milliseconds(800)
    /// Whether terminals use the frosted backdrop or the theme's solid background.
    @Published private(set) var isTerminalTransparent = true
    /// Whether Casper is registered to start at login, mirrored from macOS.
    @Published private(set) var opensAtLogin = LoginItem.isEnabled
    /// Whether Casper has a Dock icon. macOS ties the Dock icon to the
    /// ⌘Tab entry, so this is also whether ⌘Tab can switch to Casper.
    /// Saved; on until turned off. Changes apply once collapsed and inactive.
    @Published private(set) var showsInDock = true
    private static let showsInDockKey = "showsInDock"

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
    /// each open terminal's directory in dock order, which one was active,
    /// and whether the settings pane was up over it. Written on every
    /// change, including every `cd` the shell reports.
    private static let terminalDirectoriesKey = "terminalDirectories"
    private static let activeTerminalIndexKey = "activeTerminalIndex"
    private static let showingSettingsKey = "showingSettings"
    private var savedTerminalDirectories: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.terminalDirectoriesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.terminalDirectoriesKey) }
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
    private var band: NotchPanelBand?
    private var bandDrawing: NSHostingView<AnyView>?
    private var settingsScreen: NotchSettingsScreen?
    private var cornerControls: NotchCornerControlsHost?
    private var cornerHints: NotchCornerControlsHost?
    private var sizeHints: NotchSizeHintsHost?
    private var resizeHandle: NotchResizeHandle?

    /// What the expanded shape shows: the settings pane when selected,
    /// otherwise the active terminal.
    private var activePane: NotchPane? {
        if isShowingSettings { return settingsScreen }
        return activeTerminal
    }

    // A display change can alter band height without changing the size rung.
    // Both SwiftUI slices must redraw even when expandedSize stays the same.
    @Published private var geometry: AppGeometryReader?
    private var globalClickMonitor: Any?
    /// Activation notifications can arrive before the workspace's cached
    /// frontmost app changes, especially on the first activation after launch.
    private var frontmostAppObservation: NSKeyValueObservation?
    private let autoCollapseCoordinator = AutoCollapseCoordinator()
    /// The app the user was in before Casper became active, to hand
    /// activation back to when the notch collapses from inside.
    private var previousApp: NSRunningApplication?
    /// Initial AppKit activation must not open the notch. Cleared once the
    /// launch callback has returned, or by an explicit click/chord.
    private var isLaunching = true
    private let toggleChord = ToggleChordMonitor()
    /// Runs from an outside left press until the button comes up again.
    private var releaseWatcher: Timer?

    var collapsedSize: CGSize { geometry?.collapsedSize ?? AppGeometryReader.fallbackSize }

    private var panelSize: CGSize { AppGeometryReader.panelSize(forExpanded: expandedSize) }

    // MARK: - Expanded size

    /// The rung the shape is on: the saved step, clamped to the current screen.
    private var currentSizeStep: Int { clampedSizeStep(sizeStep) }

    /// Moves the expanded size one rung up or down the ladder. Stops at the
    /// ladder's floor and at the largest rung the current screen can hold.
    func adjustExpandedSize(by delta: Int) {
        setExpandedSizeStep(currentSizeStep + delta)
    }

    /// Puts the expanded size on `step`, or on the nearest rung between the
    /// ladder's floor and the largest the current screen can hold. Where a
    /// drag on the shape's bottom edge or a bottom corner lands (see
    /// NotchResizeHandle), and the size shortcuts too.
    func setExpandedSizeStep(_ step: Int) {
        let next = clampedSizeStep(step)
        guard next != currentSizeStep else { return }
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

    /// ⌘T and the dock's plus: opens another terminal in the active one's
    /// directory and switches to it.
    func newTerminal() {
        activate(addTerminal(in: activeTerminal?.inheritedWorkingDirectory))
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

    /// Remembers every terminal's directory, in dock order, for the next launch.
    private func saveTerminals() {
        savedTerminalDirectories = terminals.compactMap { $0.workingDirectory }
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

    /// Opens a terminal in `workingDirectory`, or the home directory when nil.
    @discardableResult
    private func addTerminal(in workingDirectory: String?) -> NotchTerminalScreen {
        let terminal = NotchTerminalScreen()
        terminal.onNewTabRequest = { [weak self] in self?.newTerminal() }
        terminal.onGoToTabRequest = { [weak self] destination in self?.goToTab(destination) }
        terminal.onWorkingDirectoryChange = { [weak self] in self?.saveTerminals() }
        terminal.onCloseRequest = { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            self.closeRequested(by: terminal)
        }
        if let panel, let container = panel.contentView {
            terminal.view.frame = paneFrame(in: panel.frame)
            // Above the SwiftUI body, below the resize handle and key hints.
            container.addSubview(terminal.view, positioned: .below, relativeTo: resizeHandle)
        }
        terminals.append(terminal)
        terminal.startShellIfNeeded(in: workingDirectory)
        saveTerminals()
        return terminal
    }

    /// libghostty wants this terminal gone. A shell that exited on its own
    /// takes its tab with it, or gets a fresh shell when it was the only
    /// one: the notch always keeps a live terminal. The close binding (⌘W)
    /// closes the tab, or asks about quitting when it is the only one.
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
    /// about quitting instead, whatever is running in it. ⌘W for the active
    /// tab, and the dock's context menu for any tab.
    func close(_ terminal: NotchTerminalScreen) {
        if terminals.count < 2 {
            quit()
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
        // Switch the live pane immediately. The dock keeps the outgoing
        // icon's presentation slot long enough to fade before closing the gap.
        terminals.remove(at: index)
        saveTerminals()
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
        // Closing a tab to the left of the active one shifts its index too.
        saveActivePane()
        terminal.close()
    }

    /// A tab dragged along the dock: puts `terminal` at `index` in the row.
    /// The ⌘ numbers follow the new order, and so does the saved one.
    func move(_ terminal: NotchTerminalScreen, to index: Int) {
        guard let from = terminals.firstIndex(where: { $0 === terminal }), from != index else { return }
        var reordered = terminals
        reordered.remove(at: from)
        reordered.insert(terminal, at: index)
        terminals = reordered
        saveTerminals()
        saveActivePane()
    }

    /// The dock's context menu: a Finder window at the terminal's directory,
    /// wherever its shell last reported being. Nothing while it has no shell.
    func revealInFinder(_ terminal: NotchTerminalScreen) {
        guard let directory = terminal.workingDirectory else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
        collapse()
    }

    // MARK: - Dock and settings

    /// Key release and loss of key status both cancel the pending reveal.
    /// Other modifier changes while ⌘ stays down do not restart the delay.
    private func setCommandHeld(_ held: Bool) {
        guard held != isCommandHeld else { return }
        isCommandHeld = held
        shortcutHintTask?.cancel()
        shortcutHintTask = nil

        guard held else {
            showsShortcutHints = false
            return
        }

        shortcutHintTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.shortcutHintDelay)
            } catch { return }
            guard !Task.isCancelled, let self, self.isCommandHeld else { return }
            self.showsShortcutHints = true
            self.shortcutHintTask = nil
        }
    }

    /// A ⌘ shortcut was typed: the user knows the key, so drop the pending
    /// reveal and keep any hints already on screen. Nothing restarts the delay
    /// until ⌘ comes back up and goes down again.
    private func dismissShortcutHintsForHold() {
        shortcutHintTask?.cancel()
        shortcutHintTask = nil
    }

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

    func setShowsInDock(_ shows: Bool) {
        showsInDock = shows
        UserDefaults.standard.set(shows, forKey: Self.showsInDockKey)
        applyActivationPolicy()
    }

    // MARK: - Corner controls

    func collapse() {
        setExpanded(false)
    }

    func togglePinned() {
        isPinned.toggle()
        focusActivePane()
    }

    /// The notch stayed open because it is pinned, so the pin capsule shows
    /// why. Nothing while collapsed, where no capsule is on screen.
    private func refuseCollapseWhilePinned() {
        guard isExpanded, pinRefusalCooldown == nil else { return }
        pinRefusalCount += 1
        pinRefusalCooldown = Task { [weak self] in
            try? await Task.sleep(for: Self.pinRefusalCooldownDuration)
            self?.pinRefusalCooldown = nil
        }
    }

    /// Quits, after asking. The question lives in `shouldQuit`, which the
    /// app delegate puts in front of every path that terminates the app.
    func quit() {
        NSApp.terminate(nil)
    }

    /// Whether the user is sure: the shells and anything running in them
    /// die with the app. With no panel to ask through, quitting goes ahead.
    func shouldQuit() -> Bool {
        guard panel != nil else { return true }
        return confirm("Quit Casper?",
                       detail: "Every terminal session and anything running in it will end.",
                       button: "Quit")
    }

    /// Every confirmation goes through the panel, which owns the one way
    /// dialogs are kept in front of it (see NotchPanel+Confirm). Afterwards
    /// the pane gets the keyboard back.
    private func confirm(_ message: String, detail: String, button: String) -> Bool {
        guard let panel else { return false }
        let confirmed = panel.confirm(message, detail: detail, button: button)
        if isExpanded {
            focusActivePane()
        } else {
            // Asked while collapsed (Quit in the Dock menu): the alert made
            // Casper active, and nothing on screen needs it to stay so.
            yieldActivation()
        }
        return confirmed
    }

    func start() {
        rebuildPanel()
        // Reopen the last run's tabs, each in the directory its shell was
        // in, and start on the pane it ended on: its tab, with settings over
        // it if that was up. Nothing saved yet means one tab in the home
        // directory.
        let directories = savedTerminalDirectories
        if directories.isEmpty {
            addTerminal(in: nil)
        } else {
            for directory in directories { addTerminal(in: directory) }
        }
        activeTerminal = terminals[min(max(savedActiveTerminalIndex, 0), terminals.count - 1)]
        isShowingSettings = savedIsShowingSettings
        showsInDock = UserDefaults.standard.object(forKey: Self.showsInDockKey) as? Bool ?? true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // ⌘Tab and the Dock make Casper the active app; being active means
        // being expanded. Which app to hand activation back to afterwards
        // is tracked from launch, before the user first switches apps.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        // Message A: “Another application became active.”
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Message B: “The user changed Spaces.”
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // If both activation callbacks see the old frontmost app, neither
        // can open Casper. Observe the actual change as well, then recheck
        // on the main queue so a newer switch away cannot steal focus back.
        frontmostAppObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, change in
            guard let app = change.newValue ?? nil,
                  app.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            DispatchQueue.main.async { [weak self] in
                self?.appDidBecomeActive()
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication, !Self.isCasper(frontmost),
           !SystemAlertMonitor.isSystemDialogHost(frontmost) {
            previousApp = frontmost
        }

        // Clicks delivered to *other* apps are by definition outside our panel
        // (the expanded shape fills the whole panel frame). Global click
        // monitors are reliable without Accessibility permission. A right
        // press collapses at once; a left press may be the start of a drag
        // headed for the terminal, so that decision waits for the release.
        // While pinned neither collapses; the pin capsule shakes instead.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let isRightPress = event.type == .rightMouseDown
            // A button can dismiss the alert before our queued callback
            // runs. Keep the state at the press as well as the fresh check
            // below, so that same click cannot collapse an unpinned panel.
            let wasYieldingToAlert = self?.panel?.systemAlerts.isYielding == true
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel?.systemAlerts.refresh()
                guard !wasYieldingToAlert, self.panel?.systemAlerts.isYielding != true else { return }
                if self.isPinned {
                    self.refuseCollapseWhilePinned()
                    return
                }
                if isRightPress {
                    self.setExpanded(false)
                } else {
                    self.collapseWhenReleasedOutside()
                }
            }
        }

        // ⌃ + left ⌥ pressed together, whichever app has the keyboard.
        toggleChord.onTrigger = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
        toggleChord.start()
    }

    /// Called on the first main-queue turn after AppKit's launch callback.
    /// LSUIElement keeps launch itself inactive; joining the Dock afterwards
    /// does not turn that launch into a request to expand the notch.
    func finishLaunch() {
        isLaunching = false
        applyActivationPolicy()
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
                self.panel?.systemAlerts.refresh()
                guard self.panel?.systemAlerts.isYielding != true else { return }
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
        autoCollapseCoordinator.cancel()
        guard expanded != isExpanded, let panel, let pane = activePane else { return }
        isExpanded = expanded
        panel.systemAlerts.setExpanded(expanded)

        let collapsedShape = shapeRectInPaneSpace(for: collapsedSize, of: pane)
        let expandedShape = shapeRectInPaneSpace(for: expandedSize, of: pane)

        pill?.setIconVisible(!expanded, animated: true)
        if let bandWindow = panel.bandWindow {
            band?.frame = bandFrame(in: bandWindow.frame)
        }
        cornerControls?.takesClicks = expanded
        resizeHandle?.isHidden = !expanded
        if expanded {
            // An explicit click or chord takes precedence over startup.
            // A later activation callback must not hand this request back.
            isLaunching = false
            pane.reveal(from: collapsedShape, to: expandedShape)
            focusExpandedPanel()
        } else {
            pane.conceal(from: expandedShape, to: collapsedShape)
            panel.makeFirstResponder(nil)
            panel.resignKey()
            yieldActivation()
            applyActivationPolicy()
        }
    }

    // MARK: - Activation

    /// ⌘Tab or the Dock icon brought Casper forward: open the notch, or
    /// give it the keyboard again if it was already open (pinned, say).
    /// Not while an alert is up: it needs the app active and keeps the
    /// keyboard until answered.
    @objc private func appDidBecomeActive() {
        panel?.systemAlerts.refresh()
        // AppKit can report a nonactivating panel as active while another
        // app is still frontmost. A click/chord opens it through setExpanded;
        // only real app activation (⌘Tab/Dock) opens it through this path.
        // The frontmost-app observation retries once that state catches up.
        guard NSApp.modalWindow == nil, panel?.systemAlerts.isYielding != true,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              Self.isCasper(frontmost) else { return }
        autoCollapseCoordinator.cancel()
        if isLaunching {
            yieldActivation()
            return
        }
        if isExpanded {
            focusExpandedPanel()
        } else {
            setExpanded(true)
        }
    }

    /// Taking key status on a nonactivating panel alone leaves the previous
    /// app frontmost. Selecting that app in ⌘Tab then changes no activation
    /// or key status. Make Casper the actual active app on every explicit
    /// expansion, including with an accessory (Dock-hidden) policy, so the
    /// completed switch away always deactivates it.
    private func focusExpandedPanel() {
        autoCollapseCoordinator.cancel()
        panel?.systemAlerts.refresh()
        guard panel?.systemAlerts.isYielding != true else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication, !Self.isCasper(frontmost),
           !SystemAlertMonitor.isSystemDialogHost(frontmost) {
            previousApp = frontmost
        }
        if NSWorkspace.shared.frontmostApplication.map(Self.isCasper) != true {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel?.makeKeyAndOrderFront(nil)
        focusActivePane()
    }

    /// Resigning alone doesn't identify where activation is going. macOS
    /// sends this before a permission helper's window is in the window list,
    /// so collapsing here would stop the alert monitor before it can yield.
    /// `appDidActivate` handles collapse once the destination is known.
    @objc private func appDidResignActive() {
        applyActivationPolicy()
    }

    /// Remember the destination before collapsing, so yielding activation
    /// cannot bring an older app back over the one the user just selected.
    /// The workspace also confirms activation when Casper already held
    /// nonactivating key focus and AppKit may not report becoming active again.
    ///
    /// Handles:
    /// A CMD+Tab into another app or into Casper.
    /// Clicking another app or into casper.
    /// Switching Spaces when that activates an app there.
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // cancel any previous scheduled collapss
        autoCollapseCoordinator.cancel()
        
        // Case 1: IT IS CASPER
        if Self.isCasper(app) {
            appDidBecomeActive()
            return
        }
        
        // Case 2: IT IS PERMISSION ALERTS
        // Permission helpers are a temporary interruption, not the app to
        // activate when the user later collapses Casper.
        if SystemAlertMonitor.isSystemDialogHost(app) {
            panel?.systemAlerts.refresh()
            return
        }
        
        previousApp = app
        
        // Case 3: Casper may receive this notifications of other apps becoming active from mac os
        // even when its collapsed, nothing for us to do here so just better ignore
        guard isExpanded else { return }
        
        // Case 3: OTHER APP ACTIVATED ( VIA CMD+TAB OR CLICK OR SPACE SWITCHING )
        autoCollapseCoordinator.otherAppDidActivate { [weak self] in
            guard let self, self.isExpanded,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            self.collapseForAppSwitch()
        }
    }

    @objc private func spaceDidChange() {
        autoCollapseCoordinator.spaceDidChange()
    }

    /// A completed switch away, with no accompanying Space change, collapses
    /// unless pinned or an alert holds the app active.
    private func collapseForAppSwitch() {
        panel?.systemAlerts.refresh()
        guard NSApp.modalWindow == nil, panel?.systemAlerts.isYielding != true else { return }
        if isPinned {
            refuseCollapseWhilePinned()
            return
        }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            collapseWhenReleasedOutside()
            return
        }
        setExpanded(false)
    }

    private static func isCasper(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Collapsed from inside while Casper was the active app (after ⌘Tab
    /// in, or an alert): activation goes back to the app the user came
    /// from, so the keyboard and the menu bar do not stay with an empty
    /// screen. Nothing to do once another app has already taken activation.
    private func yieldActivation() {
        guard NSApp.isActive, let previousApp, !previousApp.isTerminated else { return }
        _ = previousApp.activate(from: .current, options: [])
    }

    /// Changing Dock policy while active can deactivate the app later. Apply
    /// it only while collapsed and inactive, so no focus-restoration task can
    /// mistake the user's next switch away for part of the policy change.
    /// A preference changed while open is applied on collapse/deactivation.
    private func applyActivationPolicy() {
        guard !isLaunching, !isExpanded, !NSApp.isActive else { return }
        let policy: NSApplication.ActivationPolicy = showsInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
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
        // doesn't hit-test. Wider than the expanded shape so its top "ears"
        // and the grow hint past its bottom-right corner aren't clipped by
        // the window.
        let frame = geometry.frame(for: panelSize)
        let panel = NotchPanel(contentRect: frame)
        panel.onSizeStep = { [weak self] delta in self?.adjustExpandedSize(by: delta) }
        panel.onQuit = { [weak self] in self?.quit() }
        panel.onCollapse = { [weak self] in self?.collapse() }
        panel.onTogglePin = { [weak self] in self?.togglePinned() }
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
            self?.setCommandHeld(held)
        }
        panel.onCommandShortcut = { [weak self] in
            self?.dismissShortcutHintsForHold()
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

        // The strip is a separate, non-key window. It keeps covering the
        // menu bar when the body yields to a centered permission prompt.
        // Its drawing uses the full body's coordinates, clipped to this
        // thin frame, so both slices follow exactly the same shape spring.
        let bandWindow = NotchBandPanel(contentRect: bandWindowFrame(in: frame))
        let bandContainer = NSView(frame: NSRect(origin: .zero, size: bandWindow.frame.size))
        let bandDrawing = NotchBandDrawingHost(rootView: AnyView(
            NotchPanelBody(region: .band).environmentObject(self)
        ))
        bandDrawing.sizingOptions = []
        bandDrawing.safeAreaRegions = []
        bandDrawing.frame = bandDrawingFrame(in: frame)
        bandContainer.addSubview(bandDrawing)
        self.bandDrawing = bandDrawing

        // Empty band space toggles either state. Its hit rectangle follows
        // the visible strip's width, below the pill and the real buttons.
        let band = NotchPanelBand(frame: bandFrame(in: bandWindow.frame))
        band.onClick = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
        bandContainer.addSubview(band)
        self.band = band

        // Pill hit-target view pinned over the place where the physical hardware notch is supposed to be.
        let pill = NotchPanelPill(frame: pillFrame(in: bandWindow.frame))
        pill.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        pill.onEnter = { [weak self] in self?.isPillHovered = true }
        pill.onExit = { [weak self] in self?.isPillHovered = false }
        pill.onClick = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
        bandContainer.addSubview(pill)
        self.pill = pill

        // In the panel from the start, hidden until its dock tab is selected.
        let settings = NotchSettingsScreen(controller: self)
        settings.view.frame = paneFrame(in: frame)
        container.addSubview(settings.view)
        settingsScreen = settings

        // Drag target for resizing by hand, along the bottom of the
        // expanded shape in the margin outside the pane. Above the panes
        // (the terminals come in below this handle), though its zones never
        // reach them. Hidden while collapsed.
        let handle = NotchResizeHandle(frame: resizeHandleFrame(in: frame))
        handle.isHidden = true
        handle.currentStep = { [weak self] in self?.currentSizeStep ?? 0 }
        handle.onDrag = { [weak self] step in self?.setExpandedSizeStep(step) }
        container.addSubview(handle)
        resizeHandle = handle

        // Real controls in the band window. Their badges use the same
        // layout in a noninteractive host in the body, clipped below the
        // band, so they don't require a taller high-level window.
        let corner = NotchCornerControlsHost(rootView: AnyView(NotchCornerControls().environmentObject(self)))
        corner.sizingOptions = []
        corner.safeAreaRegions = []
        corner.bandHeight = collapsedSize.height
        corner.takesClicks = isExpanded
        corner.frame = cornerControlsFrame(in: bandWindow.frame)
        bandContainer.addSubview(corner)
        cornerControls = corner

        let cornerHints = NotchCornerControlsHost(rootView: AnyView(NotchCornerControls(region: .hints).environmentObject(self)))
        cornerHints.sizingOptions = []
        cornerHints.safeAreaRegions = []
        cornerHints.takesClicks = false
        cornerHints.frame = cornerControlsFrame(in: frame)
        container.addSubview(cornerHints)
        self.cornerHints = cornerHints

        // The size shortcuts' hints, on the bottom-right corner of the
        // expanded shape. The shrink hint lies over the pane, so this host
        // goes above every pane too.
        let hints = NotchSizeHintsHost(rootView: AnyView(NotchSizeHints().environmentObject(self)))
        hints.sizingOptions = []
        hints.safeAreaRegions = []
        hints.frame = sizeHintsFrame(in: frame)
        container.addSubview(hints)
        sizeHints = hints

        panel.contentView = container
        panel.acceptsMouseMovedEvents = true
        bandWindow.contentView = bandContainer
        panel.bandWindow = bandWindow
        panel.addChildWindow(bandWindow, ordered: .above)
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
        let bandFrame = bandWindowFrame(in: frame)
        panel.bandWindow?.setFrame(bandFrame, display: true)
        bandDrawing?.frame = bandDrawingFrame(in: frame)
        pill?.frame = pillFrame(in: bandFrame)
        band?.frame = self.bandFrame(in: bandFrame)
        for terminal in terminals {
            terminal.view.frame = paneFrame(in: frame)
        }
        settingsScreen?.view.frame = paneFrame(in: frame)
        cornerControls?.bandHeight = collapsedSize.height
        cornerControls?.frame = cornerControlsFrame(in: bandFrame)
        cornerHints?.frame = cornerControlsFrame(in: frame)
        sizeHints?.frame = sizeHintsFrame(in: frame)
        resizeHandle?.frame = resizeHandleFrame(in: frame)
        panel.systemAlerts.refresh()
    }

    private func bandWindowFrame(in panelFrame: NSRect) -> NSRect {
        NSRect(x: panelFrame.minX, y: panelFrame.maxY - collapsedSize.height,
               width: panelFrame.width, height: collapsedSize.height)
    }

    /// A full-size drawing whose top aligns with the thin window's top.
    private func bandDrawingFrame(in panelFrame: NSRect) -> NSRect {
        NSRect(x: 0, y: collapsedSize.height - panelFrame.height,
               width: panelFrame.width, height: panelFrame.height)
    }

    private func pillFrame(in panelFrame: NSRect) -> NSRect {
        let size = collapsedSize
        return NSRect(x: (panelFrame.width - size.width) / 2,
                      y: panelFrame.height - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// Empty space in the current strip toggles it. While collapsed the
    /// invisible space either side must remain available to the menu bar.
    private func bandFrame(in panelFrame: NSRect) -> NSRect {
        let width = isExpanded ? expandedSize.width : collapsedSize.width
        let sideMargin = (panelFrame.width - width) / 2
        return NSRect(x: sideMargin,
                      y: panelFrame.height - collapsedSize.height,
                      width: width,
                      height: collapsedSize.height)
    }

    /// Margin between the expanded shape's sides and bottom and the pane,
    /// clear of the shape's rounded corners. The resize handle lives in it
    /// (see NotchResizeHandle).
    static let paneInset: CGFloat = 7

    /// Every pane (terminals and settings) shares this frame inside the shape.
    private func paneFrame(in panelFrame: NSRect) -> NSRect {
        /// inset to match the expanded shape's rounded corners.
        let topInset = collapsedSize.height
        /// The expanded shape is centered in the (wider) panel; keep the pane inside it.
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        /// The shape sits at the top of the panel; the band below it belongs to the dock.
        let shapeBottom = panelFrame.height - expandedSize.height
        let inset = Self.paneInset
        return NSRect(x: sideMargin + inset,
                      y: shapeBottom + inset,
                      width: expandedSize.width - inset * 2,
                      height: expandedSize.height - topInset - inset)
    }

    /// Along the bottom of the expanded shape, as wide as the shape and as
    /// tall as the corner zones reach up its sides.
    private func resizeHandleFrame(in panelFrame: NSRect) -> NSRect {
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        let shapeBottom = panelFrame.height - expandedSize.height
        return NSRect(x: sideMargin,
                      y: shapeBottom,
                      width: expandedSize.width,
                      height: NotchResizeHandle.cornerReach)
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

    /// A square centered on the bottom-right corner of the expanded shape:
    /// the shrink hint in the quarter inside the shape, the grow hint in
    /// the quarter outside it, past the corner.
    private func sizeHintsFrame(in panelFrame: NSRect) -> NSRect {
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        let shapeBottom = panelFrame.height - expandedSize.height
        return NSRect(x: sideMargin + expandedSize.width - NotchSizeHints.reach,
                      y: shapeBottom - NotchSizeHints.reach,
                      width: NotchSizeHints.reach * 2,
                      height: NotchSizeHints.reach * 2)
    }

    // Display connected/disconnected or resolution changed — the notch may have moved or vanished.
    @objc private func screenParametersChanged() {
        rebuildPanel()
    }
}

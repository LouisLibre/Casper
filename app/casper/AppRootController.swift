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
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppRootController: ObservableObject {
    @Published private(set) var isExpanded = false
    /// Tab highlighted in the dock. Settings has no pane yet, so it never
    /// becomes selected; see `select(_:)`.
    @Published private(set) var selectedTab: NotchTab = .terminal
    /// Whether the shape shows the frosted backdrop (on) or flat black (off).
    @Published private(set) var isTerminalTransparent = true

    // human-note: (DRAFT) we should probably have a set preferred sizes based on the current user screen resolution
    let expandedSize = CGSize(width: 640, height: 480)


    private var panel: NotchPanel?
    private var pill: NotchPanelPill?
    private var body: NotchPanelBody?

    let terminal = NotchTerminalScreen()
    
    private var geometry: AppGeometryReader?
    private var globalClickMonitor: Any?
    /// Runs from an outside left press until the button comes up again.
    private var releaseWatcher: Timer?

    var collapsedSize: CGSize { geometry?.collapsedSize ?? AppGeometryReader.fallbackSize }

    /// The panel is the expanded shape plus the band under it that holds the dock.
    private var panelSize: CGSize {
        CGSize(width: expandedSize.width + NotchShape.maxTopCornerRadius * 2,
               height: expandedSize.height + NotchDock.reserve)
    }

    // MARK: - Dock

    func select(_ tab: NotchTab) {
        switch tab {
        case .terminal:
            selectedTab = .terminal
        case .settings:
            // No settings pane yet: behaves like ⌘, and leaves the terminal selected.
            GhosttyRuntime.openUserConfig()
        }
        panel?.makeFirstResponder(terminal.inputView)
    }

    func toggleTerminalTransparency() {
        isTerminalTransparent.toggle()
        panel?.makeFirstResponder(terminal.inputView)
    }

    func start() {
        rebuildPanel()
        terminal.startShellIfNeeded()

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
        guard expanded != isExpanded, let panel else { return }
        isExpanded = expanded

        let collapsedShape = shapeRectInTerminalSpace(for: collapsedSize)
        let expandedShape = shapeRectInTerminalSpace(for: expandedSize)

        pill?.setIconVisible(!expanded, animated: true)
        if expanded {
            terminal.reveal(from: collapsedShape, to: expandedShape)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(terminal.inputView)
        } else {
            terminal.conceal(from: expandedShape, to: collapsedShape)
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
    }

    /// Frame of the black shape at a given size, converted into the terminal
    /// view's coordinate space for its reveal mask. Inset a hair so the mask
    /// edge stays behind the shape's anti-aliased edge even if the two
    /// animation clocks drift within a frame.
    private func shapeRectInTerminalSpace(for size: CGSize) -> CGRect {
        guard let container = terminal.view.superview else { return .zero }
        let panelSize = container.bounds.size
        let shape = NSRect(x: (panelSize.width - size.width) / 2,
                           y: panelSize.height - size.height,
                           width: size.width,
                           height: size.height).insetBy(dx: 2, dy: 2)
        return terminal.view.convert(shape, from: container)
    }

    // MARK: - Panel lifecycle

    private func rebuildPanel() {
        guard let screen = AppGeometryReader.preferredScreen() else { return }
        let geometry = AppGeometryReader(screen: screen)
        self.geometry = geometry

        // Fixed frame, big enough for the expanded state and the dock below
        // it. Collapsed just means most of the panel is transparent and
        // doesn't hit-test. Slightly wider than the expanded shape so its top
        // "ears" aren't clipped by the window.
        let frame = geometry.frame(for: panelSize)

        if let panel {
            panel.setFrame(frame, display: true)
            pill?.frame = pillFrame(in: frame)
            terminal.view.frame = terminalFrame(in: frame)
            return
        }

        let panel = NotchPanel(contentRect: frame)
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

        terminal.view.frame = terminalFrame(in: frame)
        container.addSubview(terminal.view)

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

        panel.contentView = container
        panel.acceptsMouseMovedEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func pillFrame(in panelFrame: NSRect) -> NSRect {
        let size = collapsedSize
        return NSRect(x: (panelFrame.width - size.width) / 2,
                      y: panelFrame.height - size.height,
                      width: size.width,
                      height: size.height)
    }

    private func terminalFrame(in panelFrame: NSRect) -> NSRect {
        /// inset to match the expanded shape's rounded corners.
        let topInset = collapsedSize.height
        /// The expanded shape is centered in the (wider) panel; keep the terminal inside it.
        let sideMargin = (panelFrame.width - expandedSize.width) / 2
        /// The shape sits at the top of the panel; the band below it belongs to the dock.
        let shapeBottom = panelFrame.height - expandedSize.height
        return NSRect(x: sideMargin + 7,
                      y: shapeBottom + 7,
                      width: expandedSize.width - 14,
                      height: expandedSize.height - topInset - 7)
    }

    // Display connected/disconnected or resolution changed — the notch may have moved or vanished.
    @objc private func screenParametersChanged() {
        rebuildPanel()
    }
}

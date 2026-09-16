//
//  NotchPane.swift
//
//  What the expanded shape shows: one of the terminals, or the settings
//  screen. Every pane shares the same frame inside the shape and stays in
//  the panel's view hierarchy for as long as it exists; only the active one
//  is visible. The panes live in `NotchPaneHost`, which the SwiftUI body
//  places inside the shape and clips with the very same animated shape it
//  draws, so the terminal can never show outside the black.
//

import AppKit
import SwiftUI

@MainActor
protocol NotchPane: AnyObject {
    /// Created once and never resized on expand/collapse; the body's mask
    /// does the revealing.
    var view: NotchPaneView { get }
    /// What should be first responder while this pane is on screen. nil for
    /// panes that take no keyboard input.
    var inputView: NSView? { get }

    /// Puts the pane on screen. The active pane stays shown while the notch
    /// is collapsed, masked out entirely by the body: a pane that carries
    /// the terminal's Metal layer must not be hidden and unhidden around
    /// the animation. Unhiding it stalls SwiftUI's animation frames in the
    /// panel for about 200 ms (measured), which showed the terminal well
    /// ahead of the black shape. The host keeps its layers out of the
    /// window server's hit testing instead (see `NotchPaneHost`).
    func show()
    /// Takes the pane off screen; another pane took its place.
    func hide()
    /// The notch is expanding with this pane in it.
    func reveal()
    /// The notch is collapsing; nothing of the pane will show once it has.
    func conceal()
}

/// Rounded container for a pane's content.
final class NotchPaneView: NSView {
    init() {
        // The host sizes it; see NotchPaneHost.
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

/// Holds every pane, each filling it. Laid out by the SwiftUI body at the
/// pane frame inside the expanded shape (see NotchPanelBody), and clipped
/// there by the animated shape. Both the black shape and this clip are
/// then SwiftUI animations in one transaction, on one clock; a separate
/// Core Animation mask could not be kept in step with the shape, whose
/// spring starts on a display frame of SwiftUI's choosing up to a frame
/// after the commit.
///
/// The host also stays out of the window server's hit testing. Which
/// window takes a click is decided there, layer by layer, before AppKit
/// sees the event, and neither the body's SwiftUI mask nor
/// `allowsHitTesting(false)` reaches it for a hosted AppKit view: the
/// terminal's opaque layer kept every click on the pane's frame, the
/// whole terminal area under the pill while collapsed (measured with
/// `NSWindow.windowNumber(at:)`), and AppKit then lost them. The shape's
/// fills and the backdrop keep the shape itself hit-testable, and they
/// follow the animation, so with the panes' layers out of the way the
/// hit region is the shape on every frame and clicks beside it, or under
/// the pill, reach the app beneath at once. Clicks that do land on the
/// shape are routed inside the window by AppKit's own `hitTest`, which
/// ignores the layer flag, so the terminal still gets them.
///
/// The flag is Core Animation's private `allowsHitTesting`, the one
/// SwiftUI's own modifier sets on its layers, resolved at runtime. Should
/// it go away, the controller falls back to parking the host at zero
/// alpha once the collapsing shape has hidden it, which the window server
/// also skips (measured, as it does hidden and Core Animation-masked
/// layers); the panes stay drawn for the animation and only a short
/// window of swallowed clicks remains.
final class NotchPaneHost: NSView {
    private static let allowsHitTestingSetter = Selector(("setAllowsHitTesting:"))

    /// Whether this host's layers are left out of the window server's hit
    /// testing for good. False only where the layer flag is missing; then
    /// `setParked` is the controller's fallback.
    let isOutOfHitTesting = CALayer.instancesRespond(to: allowsHitTestingSetter)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Any backing layer AppKit makes for the host carries the flag; it
    /// applies to the panes' layers below it too (measured).
    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        if isOutOfHitTesting { layer.setValue(false, forKey: "allowsHitTesting") }
        return layer
    }

    func add(_ pane: NotchPane) {
        pane.view.frame = bounds
        addSubview(pane.view)
    }

    /// Fallback while `isOutOfHitTesting` is false: parked, the host is at
    /// zero alpha, which the window server skips. Parked only once the
    /// collapse has hidden the panes and unparked before the expand
    /// starts, so they are always drawn while any of them could show.
    /// Alpha leaves the view and its Metal layer alone, so nothing is
    /// hidden or unhidden around the animation (see `NotchPane.show`).
    func setParked(_ parked: Bool) {
        alphaValue = parked ? 0 : 1
    }
}

struct NotchPaneHostView: NSViewRepresentable {
    @EnvironmentObject private var controller: AppRootController

    func makeNSView(context: Context) -> NotchPaneHost {
        controller.paneHost
    }

    func updateNSView(_ view: NotchPaneHost, context: Context) {}
}

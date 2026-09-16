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
    /// ahead of the black shape. Once collapsed, the host is parked out of
    /// hit testing instead (see `NotchPaneHost.setParked`).
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
final class NotchPaneHost: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func add(_ pane: NotchPane) {
        pane.view.frame = bounds
        addSubview(pane.view)
    }

    /// Takes the panes out of the window server's hit testing while the
    /// notch is collapsed, and puts them back for the expand.
    ///
    /// The body masks the panes out entirely while collapsed, but that is
    /// SwiftUI's mask on a hosted AppKit view: neither it nor
    /// `allowsHitTesting(false)` reaches the window server, which kept
    /// routing every click on the pane's frame (the whole terminal area
    /// under the pill, measured with `NSWindow.windowNumber(at:)`) to this
    /// window instead of to the app beneath, where AppKit then dropped or
    /// fed it to the terminal. The window server does skip hidden,
    /// zero-opacity and Core Animation-masked layers (all three measured).
    /// Opacity is used: it leaves the view and its Metal layer alone, so
    /// nothing is hidden or unhidden around the animation (see
    /// `NotchPane.show`), and the body's own mask still does the clipping
    /// while the shape moves. Parked only once the collapse has settled,
    /// unparked before the expand starts, so the panes are always drawn
    /// while any of them could show.
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

//
//  NotchSizeHints.swift
//
//  Two badges on the bottom-right corner of the expanded shape, shown
//  while ⌘ is held, for the shortcuts that step its size: ⌘⇧- inside the
//  corner, with an arrow drawing the corner in, and ⌘⇧+ outside it, past
//  the corner, with an arrow pushing it out. Both shortcuts work from
//  every pane (the panel takes them itself), so the hints show from the
//  settings pane too.
//
//  The shrink hint lies over the pane, so like the corner controls these
//  live in a host of their own above every pane (NotchSizeHintsHost).
//  The grow hint lies past the shape, in slack the panel reserves for it
//  (see AppGeometryReader.sideSlack).
//

import AppKit
import SwiftUI

struct NotchSizeHints: View {
    @EnvironmentObject private var controller: AppRootController

    /// How far the host reaches from the shape's corner, in every
    /// direction: room for a badge and its distance from the corner. A
    /// badge is about 41 tall and 36 wide (measured); plus the inset below
    /// that is 53, rounded up to leave some room. The part past the shape's
    /// bottom must fit in the dock's band under it (NotchDock.reserve).
    static let reach: CGFloat = 56
    /// From the shape's edges to the shrink hint inside them. The knob for
    /// how close the shrink hint sits to the corner: smaller is closer.
    static let inset: CGFloat = 12
    /// From the shape's edges to the grow hint outside them. The knob for
    /// how close the grow hint sits to the corner: smaller is closer, and
    /// negative pulls it in over the shape's square corner, where its own
    /// rounded corner keeps it clear of the curve.
    ///
    /// The curve recedes from the square corner, so a hint outside must
    /// come nearer that corner than one inside to look as close. With a
    /// corner radius r the two distances differ by r(2 - √2), about 13 at
    /// the shape's 22 (NotchPanelBody.expandedBottomCornerRadius). So with
    /// the inset at 12, -1 here would put both hints the same distance
    /// from the curve; this sits a little nearer than that.
    static let outset: CGFloat = -4

    var body: some View {
        let showsHints = controller.isExpanded && controller.showsShortcutHints
        // A square centered on the shape's corner. The top-left quarter is
        // inside the shape and the bottom-right quarter is outside it.
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: Self.reach, height: Self.reach)
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        if showsHints {
                            SizeKeyBadge(symbol: "arrow.up.left", key: "-")
                        }
                    }
                    .offset(x: -Self.inset, y: -Self.inset)
                }
            Color.clear
                .frame(width: Self.reach, height: Self.reach)
                .overlay(alignment: .topLeading) {
                    ZStack {
                        if showsHints {
                            SizeKeyBadge(symbol: "arrow.down.right", key: "+")
                        }
                    }
                    .offset(x: Self.outset, y: Self.outset)
                }
                .offset(x: Self.reach, y: Self.reach)
        }
        .frame(width: Self.reach * 2, height: Self.reach * 2, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: showsHints)
        .allowsHitTesting(false)
    }
}

/// Hosts the size hints above the panes, on the bottom-right corner of
/// the expanded shape. Nothing in it takes clicks: what is under the
/// shrink hint is the pane, and under the grow hint nothing of ours.
final class NotchSizeHintsHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

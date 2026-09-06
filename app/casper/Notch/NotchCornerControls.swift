//
//  NotchCornerControls.swift
//
//  Three small buttons in the top-right corner of the expanded shape: pin
//  the notch open so clicks outside stop collapsing it, collapse the notch,
//  and close: the active tab, or the app (after confirming) when that tab is
//  the only one or the settings pane is up. They sit in the band above the
//  terminal. After ⌘ is held briefly each wears a badge with the key that
//  does the same: ⌘P for pin, ⌘M for collapse, ⌘W or ⌘Q for close,
//  whichever the button would do right now.
//
//  The band is not tall enough to hold a badge under an icon, so the
//  collapse and close badges hang out under it, over the top of the pane.
//  The pin badge sits beside its icon instead, on the left, where the band
//  has room. The panes sit above the panel's SwiftUI body, so the controls
//  live in a host of their own above them (NotchCornerControlsHost), sized
//  to this corner alone.
//

import AppKit
import SwiftUI

struct NotchCornerControls: View {
    @EnvironmentObject private var controller: AppRootController

    /// Distance from the shape's right edge.
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 8
    /// Same point size and weight as the pill's chevron so the three read as one set.
    static let symbolSize: CGFloat = 16
    static let symbolWeight: Font.Weight = .regular
    static let restingOpacity = 0.44
    static let hoverOpacity = 1.0
    
    /// How wide the rectangle that holds these controls is, measured from
    /// the right edge of the expanded notch.
    ///
    /// A SwiftUI view like this one is always drawn inside an AppKit view.
    /// Here that AppKit view is `NotchCornerControlsHost`, a plain
    /// rectangle placed at the top-right corner of the expanded notch. It
    /// sits on top of the terminal so the badges can be seen. macOS gives
    /// a click to the topmost view whose rectangle contains it, and this
    /// rectangle is on top, so it would take every click inside it, even
    /// where nothing is drawn. So the host only claims clicks in the part
    /// of the band that holds the icons (`buttonsWidth`), and that part
    /// has to stay small: much wider, at the smallest notch size it would
    /// reach the pill (the clickable strip around the physical notch) and
    /// the pill would stop reacting to clicks.
    ///
    /// The value is not computed because two of the sizes involved come
    /// from font rendering, not from constants in this file. They were
    /// measured from a test render: an icon is 19 wide and a badge is 30.
    /// From the right edge: 18 of padding, the close icon (19), a gap (8),
    /// the collapse icon (19), a gap (8), and the pin icon (19) add up to
    /// 91. The collapse badge is wider than its icon and nudged left, but
    /// it stays over the pin icon, so it adds nothing. The pin badge sits
    /// beside its icon, so past the icons come the gap to it (6) and the
    /// badge (30), for 127. Rounded up to 136 to leave some room.
    static let width: CGFloat = 136
    /// The right part of the band that holds the three icons, the only
    /// part of the rectangle that takes clicks: 91 (see `width`), rounded
    /// up to leave some room.
    static let buttonsWidth: CGFloat = 100
    
    /// How far the rectangle that holds these controls extends below the
    /// band.
    ///
    /// The band is the dark strip along the top of the expanded notch. It
    /// is as tall as the collapsed notch, and the icons sit centered
    /// in it. The terminal starts right under it. A badge does not fit in
    /// the band under an icon, so it hangs out below the band, over the
    /// top of the terminal, and the rectangle must reach down far enough
    /// to show it.
    ///
    /// How far depends on the band's height, which changes with the
    /// screen. On a band 29 tall, the icon's bottom is 9.5 below the
    /// middle of the band, then comes the 3 gap, then a badge 16.5 tall.
    /// That puts the badge's bottom 14.5 below the band. Taller bands
    /// need less. Rounded up to 24 to leave some room. The extra room
    /// costs nothing: clicks in the part below the band are passed on to
    /// the terminal (see `NotchCornerControlsHost`).
    static let hintReserve: CGFloat = 24
    /// Gap between an icon and its badge, under or beside it.
    private static let hintGap: CGFloat = 6
    /// The badges are wider than the icons and would touch if each sat
    /// centered under its icon, so each is nudged this far outward: the
    /// collapse badge left, the close badge right.
    private static let hintShift: CGFloat = 6

    var body: some View {
        HStack(spacing: Self.spacing) {
            CornerButton(symbol: controller.isPinned ? "pin.circle.fill" : "pin.circle",
                         label: controller.isPinned ? "Unpin to set auto-collapse on" : "Pin to set auto-collapse off",
                         keyHint: showsKeyHints ? "P" : nil, hintShift: 0,
                         hintPlacement: .leading, isLit: controller.isPinned) {
                controller.togglePinned()
            }
            CornerButton(symbol: "chevron.up.circle.fill", label: "Collapse",
                         keyHint: showsKeyHints ? "M" : nil, hintShift: -Self.hintShift) {
                controller.collapse()
            }
            CornerButton(symbol: "x.circle.fill", label: closeLabel,
                         keyHint: showsKeyHints ? closeKeyHint : nil, hintShift: Self.hintShift) {
                controller.closeActivePane()
            }
        }
        // The icons are centered in the band; the badges hang out under it.
        .frame(height: controller.collapsedSize.height)
        .padding(.trailing, Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // Hidden and click-through while collapsed so the pill keeps the
        // strip to itself. Fades on the same spring as the shape.
        .opacity(controller.isExpanded ? 1 : 0)
        .allowsHitTesting(controller.isExpanded)
        .animation(NotchSpring.swiftUI(expanding: controller.isExpanded), value: controller.isExpanded)
    }

    /// ⌘P, ⌘M and ⌘Q are the panel's own shortcuts and work from every
    /// pane, so unlike the dock's badges these show from the settings pane
    /// too.
    private var showsKeyHints: Bool { controller.showsShortcutHints }

    /// Whether the close button quits rather than closes a tab: from the
    /// settings pane, or when the active terminal is the only one.
    private var closeQuits: Bool { controller.isShowingSettings || controller.terminals.count < 2 }

    /// What the close button does right now, for accessibility.
    private var closeLabel: String { closeQuits ? "Quit Casper" : "Close Tab" }

    /// ⌘W closes the tab (a Ghostty binding, routed to the same place as
    /// the button); ⌘Q asks about quitting.
    private var closeKeyHint: String { closeQuits ? "Q" : "W" }

    private struct CornerButton: View {
        let symbol: String
        let label: String
        /// The key that, with ⌘, does what a click does, shown in a badge
        /// under the icon. Set only while ⌘ is held.
        let keyHint: String?
        /// How far the badge sits off center under the icon, positive to the right.
        let hintShift: CGFloat
        /// Where the badge goes: under the icon, or beside it on the left.
        var hintPlacement: HintPlacement = .below
        /// Keeps the icon at full opacity whether hovered or not, to show a
        /// state that is switched on. Off for buttons that only do something.
        var isLit = false
        let action: () -> Void

        @State private var hovering = false

        enum HintPlacement {
            case below
            case leading
        }

        private var opacity: Double {
            if isLit || hovering { return NotchCornerControls.hoverOpacity }
            return NotchCornerControls.restingOpacity
        }

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: NotchCornerControls.symbolSize, weight: NotchCornerControls.symbolWeight))
                    .foregroundStyle(.white.opacity(opacity))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .toolTip(label)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            // The badge hangs under the icon, or sits beside it. As an
            // overlay it takes no part in layout, so the icons never shift
            // when it comes and goes; nor in clicks, so what is under it
            // keeps them. The guides that move it out from under the icon
            // sit on the stack, not the badge: set inside the `if` they
            // would not reach the overlay. Only the guide for the placement
            // in use is consulted.
            .overlay(alignment: hintPlacement == .below ? .bottom : .leading) {
                ZStack {
                    if let keyHint {
                        KeyBadge(key: keyHint).fixedSize()
                    }
                }
                .alignmentGuide(.bottom) { $0[.top] - NotchCornerControls.hintGap }
                .alignmentGuide(.leading) { $0[.trailing] + NotchCornerControls.hintGap }
                .offset(x: hintShift)
                .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.12), value: keyHint)
        }
    }
}

/// Hosts the corner controls above the panes, in the top-right corner of
/// the expanded shape. Only the right part of the band at its top takes
/// clicks, where the buttons are; the rest of the view is the room for
/// the badges, beside the buttons and under them over the pane, and
/// clicks there fall through to whatever is below. Needed because a
/// hosting view otherwise claims every click in its frame, badge or not.
final class NotchCornerControlsHost: NSHostingView<AnyView> {
    /// Height of the band at the top of the view.
    var bandHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let distanceFromTop = isFlipped ? local.y : bounds.height - local.y
        let distanceFromRight = bounds.width - local.x
        guard distanceFromTop <= bandHeight,
              distanceFromRight <= NotchCornerControls.buttonsWidth else { return nil }
        return super.hitTest(point)
    }
}

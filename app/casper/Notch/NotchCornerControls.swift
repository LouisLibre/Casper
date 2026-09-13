//
//  NotchCornerControls.swift
//
//  Three small buttons in the top-right corner of the expanded shape: pin
//  the notch open so clicks outside stop collapsing it, quit the app
//  (after confirming), and collapse the notch. They sit in the band above
//  the terminal. After ⌘ is held briefly each wears a badge with the key
//  that does the same: ⌘P for pin, ⌘Q for quit and ⌘M for collapse. Under
//  ⌘M hangs a second badge with the chord that toggles the notch from any
//  app (see ToggleChordMonitor).
//
//  The band is not tall enough to hold a badge under a button, so the
//  quit and collapse badges hang out under it, over the top of the pane.
//  The pin badge sits beside its capsule instead, on the left, where the
//  band has room. The panes sit above the panel's SwiftUI body, so the
//  controls live in a host of their own above them
//  (NotchCornerControlsHost), sized to this corner alone.
//

import AppKit
import SwiftUI

struct NotchCornerControls: View {
    @EnvironmentObject private var controller: AppRootController

    /// Distance from the shape's right edge.
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 8
    /// Height of the two capsules and the ghost, so the three read as one set.
    static let glyphHeight: CGFloat = 16
    /// The capsules rest dim and go full under the pointer. The mascot
    /// keeps its opacity and looks the other way instead.
    static let dimOpacity = 0.44
    static let fullOpacity = 1.0
    
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
    /// of the band that holds the buttons (`buttonsWidth`), and that part
    /// has to stay small: much wider, at the smallest notch size it would
    /// reach the pill (the clickable strip around the physical notch) and
    /// the pill would stop reacting to clicks.
    ///
    /// The value is not computed because the sizes involved come from
    /// font rendering, not from constants in this file. They were measured
    /// from a test render: the ghost is 16 wide, the pin capsule 44, the
    /// quit capsule 50 and a badge 30. From the right edge: 18 of padding,
    /// the ghost (16), a gap (8), the quit capsule (50), a gap (8), and
    /// the pin capsule (44) add up to 144. The quit and collapse badges
    /// stay over their own buttons, so they add nothing. The pin badge sits
    /// beside its capsule, so past the buttons come the gap to it (6) and
    /// the badge (30), for 180. Rounded up to 190 to leave some room.
    static let width: CGFloat = 190
    /// The right part of the band that holds the three buttons, the only
    /// part of the rectangle that takes clicks: 144 (see `width`), rounded
    /// up to leave some room.
    static let buttonsWidth: CGFloat = 152
    
    /// How far the rectangle that holds these controls extends below the
    /// band.
    ///
    /// The band is the dark strip along the top of the expanded notch. It
    /// is as tall as the collapsed notch, and the buttons sit centered
    /// in it. The terminal starts right under it. A badge does not fit in
    /// the band under a button, so it hangs out below the band, over the
    /// top of the terminal, and the rectangle must reach down far enough
    /// to show it.
    ///
    /// How far depends on the band's height, which changes with the
    /// screen. On a band 29 tall, the icon's bottom is 9.5 below the
    /// middle of the band, then comes the 3 gap, then a badge 16.5 tall.
    /// That puts the badge's bottom 14.5 below the band. The chord badge
    /// under it adds another gap and badge, 22.5 more, for 37. Taller
    /// bands need less. Rounded up to 48 to leave some room. The extra
    /// room costs nothing: clicks in the part below the band are passed
    /// on to the terminal (see `NotchCornerControlsHost`).
    static let hintReserve: CGFloat = 48
    /// Gap between a button and its badge, under or beside it.
    private static let hintGap: CGFloat = 6

    var body: some View {
        HStack(spacing: Self.spacing) {
            CornerButton(label: controller.isPinned ? "Unpin to set auto-collapse on" : "Pin to set auto-collapse off",
                         keyHint: showsKeyHints ? "P" : nil,
                         hintPlacement: .leading, isLit: controller.isPinned,
                         action: { controller.togglePinned() }) { _ in
                CornerCapsule(symbol: "pin.fill", text: "PIN", isOn: controller.isPinned)
            }
            CornerButton(label: "Quit Casper",
                         keyHint: showsKeyHints ? "Q" : nil,
                         action: { controller.confirmQuit() }) { _ in
                CornerCapsule(symbol: "command", text: "QUIT")
            }
            CornerButton(label: "Collapse",
                         keyHint: showsKeyHints ? "M" : nil,
                         chordHint: showsKeyHints ? ToggleChordMonitor.hint : nil,
                         dimsAtRest: false,
                         action: { controller.collapse() }) { hovering in
                CollapseMascot(hovering: hovering)
            }
        }
        // The buttons are centered in the band; the badges hang out under it.
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

    /// The mascot from the collapsed strip, where a click expands the notch;
    /// here it collapses it. The strip's purple, as tall as the capsules.
    /// Looks right at rest and glances left under the pointer, on the same
    /// spring as the strip's mascot. Its opacity never changes.
    private struct CollapseMascot: View {
        let hovering: Bool

        var body: some View {
            NotchGhostMascot(gaze: hovering ? -1 : 1)
                .fill(Color(nsColor: NotchPanelPill.glyphColor), style: FillStyle(eoFill: true))
                .frame(width: NotchCornerControls.glyphHeight, height: NotchCornerControls.glyphHeight)
                .animation(NotchSpring.hover, value: hovering)
        }
    }

    /// A capsule holding a small symbol and a short word, styled after the
    /// SF circle symbols: a white outline with white contents, like
    /// `pin.circle`. Switched on, a solid white capsule with the contents
    /// in the band's black, like `pin.circle.fill`.
    private struct CornerCapsule: View {
        let symbol: String
        let text: String
        var isOn = false

        private static let height = NotchCornerControls.glyphHeight
        /// As thick as the ring of an SF circle symbol at 16 points (measured).
        private static let lineWidth: CGFloat = 1.3

        var body: some View {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
                Text(text)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.75))
            .padding(.leading, 6)
            .padding(.trailing, 7)
            .frame(height: Self.height)
            .background {
                if isOn {
                    Capsule().fill(.white)
                } else {
                    Capsule().strokeBorder(.white.opacity(0.75), lineWidth: Self.lineWidth)
                }
            }
        }
    }

    private struct CornerButton<Face: View>: View {
        let label: String
        /// The key that, with ⌘, does what a click does, shown in a badge
        /// under the button. Set only while ⌘ is held.
        let keyHint: String?
        /// A modifier chord that does the same from any app, in a second
        /// badge under the first. Set only while ⌘ is held.
        var chordHint: String? = nil
        /// Where the badge goes: under the button, or beside it on the left.
        var hintPlacement: HintPlacement = .below
        /// Keeps the face at full opacity whether hovered or not, to show a
        /// state that is switched on. Off for buttons that only do something.
        var isLit = false
        /// Dim at rest and full under the pointer. Off for the mascot, which
        /// shows the pointer by looking the other way instead.
        var dimsAtRest = true
        let action: () -> Void
        /// What the button shows: a capsule, or the mascot. Told whether the
        /// pointer is over the button.
        @ViewBuilder let face: (_ hovering: Bool) -> Face

        @State private var hovering = false

        enum HintPlacement {
            case below
            case leading
        }

        private var opacity: Double {
            let dim = dimsAtRest && !isLit && !hovering
            return dim ? NotchCornerControls.dimOpacity : NotchCornerControls.fullOpacity
        }

        var body: some View {
            Button(action: action) {
                face(hovering)
                    .opacity(opacity)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .toolTip(label)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            // The badge hangs under the button, or sits beside it. As an
            // overlay it takes no part in layout, so the buttons never shift
            // when it comes and goes; nor in clicks, so what is under it
            // keeps them. The guides that move it out from under the button
            // sit on the stack, not the badge: set inside the `if` they
            // would not reach the overlay. Only the guide for the placement
            // in use is consulted.
            .overlay(alignment: hintPlacement == .below ? .bottom : .leading) {
                VStack(spacing: NotchCornerControls.hintGap) {
                    if let keyHint {
                        KeyBadge(key: keyHint).fixedSize()
                    }
                    if let chordHint {
                        KeyBadge(modifiers: "", key: chordHint).fixedSize()
                    }
                }
                .alignmentGuide(.bottom) { $0[.top] - NotchCornerControls.hintGap }
                .alignmentGuide(.leading) { $0[.trailing] + NotchCornerControls.hintGap }
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

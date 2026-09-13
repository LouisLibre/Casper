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
//  While pinned, the pin capsule also answers "why didn't it close": a
//  click outside or a switch to another app (⌘Tab) shakes and glows it
//  once. The controller counts those refusals and each count going up
//  plays the animation once.
//
//  The band is not tall enough to hold a badge under a button, so the
//  quit and collapse badges hang out under it, over the top of the pane.
//  The pin badge sits beside its capsule instead, on the left, where the
//  band has room. The buttons live in the thin band window; an identical,
//  noninteractive layout paints only the badges below it in the terminal
//  window. NotchCornerControlsHost keeps both sized to this corner alone.
//

import AppKit
import SwiftUI

struct NotchCornerControls: View {
    @EnvironmentObject private var controller: AppRootController

    /// Identical layout in both windows: real buttons in the band, only
    /// the portion of their badges below the band in the terminal window.
    enum Region { case band, hints }
    var region: Region = .band

    /// Distance from the shape's right edge.
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 8
    /// Height of the two capsules and the ghost's box, so the three read as
    /// one set. The ghost rests a little over its box (see CollapseMascot).
    static let glyphHeight: CGFloat = 16
    /// The capsules rest dim and go full under the pointer. The mascot
    /// keeps its opacity and looks the other way instead.
    static let dimOpacity = 0.44
    static let fullOpacity = 1.0
    
    /// How wide the rectangle that holds these controls is, measured from
    /// the right edge of the expanded notch.
    ///
    /// This reserves room for buttons and badges, not a click target.
    /// The host routes clicks only to the actual button rectangles; its
    /// padding and the gaps between controls belong to the band underneath.
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
                         showsFace: region == .band,
                         hintPlacement: .leading, isLit: controller.isPinned,
                         action: { controller.togglePinned() }) { _ in
                CornerCapsule(symbol: "pin.fill", text: "PIN", isOn: controller.isPinned)
                    .glows(on: controller.pinRefusalCount)
                    .shakes(on: controller.pinRefusalCount)
            }
            CornerButton(label: "Quit Casper",
                         keyHint: showsKeyHints ? "Q" : nil,
                         showsFace: region == .band,
                         action: { controller.quit() }) { _ in
                CornerCapsule(symbol: "command", text: "QUIT")
            }
            CornerButton(label: "Collapse",
                         keyHint: showsKeyHints ? "M" : nil,
                         showsFace: region == .band,
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
        .allowsHitTesting(controller.isExpanded && region == .band)
        .accessibilityHidden(region == .hints)
        .mask(alignment: .top) {
            if region == .hints {
                VStack(spacing: 0) {
                    Color.clear.frame(height: controller.collapsedSize.height)
                    Color.white
                }
            } else {
                Color.white
            }
        }
        .animation(NotchSpring.swiftUI(expanding: controller.isExpanded), value: controller.isExpanded)
    }

    /// ⌘P, ⌘M and ⌘Q are the panel's own shortcuts and work from every
    /// pane, so unlike the dock's badges these show from the settings pane
    /// too.
    private var showsKeyHints: Bool { controller.showsShortcutHints }

    /// The mascot from the collapsed strip, where a click expands the notch;
    /// here it collapses it. The strip's purple, boxed as tall as the
    /// capsules. The strip's mascot in reverse: looks right at rest and
    /// glances left under the pointer, and rests a little over its box and
    /// shrinks to it under the pointer, by the strip's hover scale and on
    /// the strip's spring. Its opacity never changes.
    private struct CollapseMascot: View {
        let hovering: Bool

        var body: some View {
            NotchGhostMascot(gaze: hovering ? -1 : 1)
                .fill(Color(nsColor: NotchPanelPill.glyphColor), style: FillStyle(eoFill: true))
                .frame(width: NotchCornerControls.glyphHeight, height: NotchCornerControls.glyphHeight)
                .scaleEffect(hovering ? 1 : PillGlyph.hoverScale)
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
        var showsFace = true
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
            face(hovering)
                .opacity(showsFace ? opacity : 0)
                .accessibilityHidden(true)
                .overlay {
                    if showsFace {
                        CornerButtonTarget(label: label, action: action,
                                           onHover: { hovering = $0 })
                    }
                }
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

/// SwiftUI supplies the face and its size; AppKit supplies a solid button
/// rectangle, independent of gaps in the lettering or the mascot's eyes.
private struct CornerButtonTarget: NSViewRepresentable {
    @EnvironmentObject private var controller: AppRootController
    let label: String
    let action: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NotchBandButton {
        NotchBandButton(frame: .zero)
    }

    func updateNSView(_ button: NotchBandButton, context: Context) {
        button.onClick = action
        button.onHover = onHover
        button.isEnabled = controller.isExpanded
        button.toolTip = controller.isExpanded ? label : nil
        button.setAccessibilityLabel(label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchBandButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class NotchBandButton: NSButton {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isTransparent = true
        refusesFirstResponder = true
        focusRingType = .none
        target = self
        action = #selector(activate)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func activate() { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

private extension View {
    /// A white halo along the edge that lights up and fades, once each time
    /// `trigger` changes. Drawn as an overlay, so it takes no part in
    /// layout or clicks.
    func glows(on trigger: Int) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, strength in
            view.overlay {
                Capsule()
                    .stroke(.white, lineWidth: 1.5)
                    .shadow(color: .white, radius: 5)
                    .opacity(strength)
            }
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.12)
                CubicKeyframe(1, duration: 0.15)
                CubicKeyframe(0, duration: 0.45)
            }
        }
    }

    /// A quick shake from side to side, dying out, once each time `trigger`
    /// changes. Moves only what is drawn: the button's click area stays put.
    func shakes(on trigger: Int) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-5, duration: 0.06)
                CubicKeyframe(5, duration: 0.08)
                CubicKeyframe(-3, duration: 0.08)
                CubicKeyframe(3, duration: 0.08)
                CubicKeyframe(0, duration: 0.1)
            }
        }
    }
}

/// Only native button rectangles take clicks. Empty space around them
/// falls through to the band's toggle target; the badges below the band
/// fall through to the terminal. No SwiftUI hosting surface swallows gaps.
final class NotchCornerControlsHost: NSHostingView<AnyView> {
    /// Height of the band at the top of the view.
    var bandHeight: CGFloat = 0
    var takesClicks = true

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClicks }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard takesClicks else { return nil }
        let local = convert(point, from: superview)
        let distanceFromTop = isFlipped ? local.y : bounds.height - local.y
        guard bounds.contains(local), distanceFromTop <= bandHeight else { return nil }
        return button(at: point, in: self)
    }

    private func button(at point: NSPoint, in view: NSView) -> NotchBandButton? {
        guard !view.isHidden, view.alphaValue > 0 else { return nil }
        if let button = view as? NotchBandButton, button.isEnabled,
           button.bounds.contains(button.convert(point, from: superview)) {
            return button
        }
        for child in view.subviews.reversed() {
            if let button = button(at: point, in: child) { return button }
        }
        return nil
    }
}

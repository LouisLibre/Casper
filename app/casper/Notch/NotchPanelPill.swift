//
//  NotchPanelPill.swift
//

import AppKit
import SwiftUI

final class NotchPanelPill: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    private let glyph = NSHostingView(rootView: PillGlyph(hovered: false))

    /// The ghost's purple: #9B83FF. The corner's collapse button wears the
    /// same ghost in the same purple.
    static let glyphColor = NSColor(srgbRed: 0x9B / 255, green: 0x83 / 255, blue: 0xFF / 255, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setIconVisible(_ visible: Bool, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                glyph.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            glyph.alphaValue = visible ? 1 : 0
        }
    }

    /// Icon is decorative — every click in the pill (including on the icon) expands/collapses.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self,
                                       userInfo: nil))
    }
    
    override func mouseEntered(with event: NSEvent) {
        glyph.rootView = PillGlyph(hovered: true)
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        glyph.rootView = PillGlyph(hovered: false)
        onExit?()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    private func configure() {
        // The pill's frame is set by AppRootController. The glyph's host
        // fills it and places the ghost itself.
        glyph.sizingOptions = []
        glyph.safeAreaRegions = []
        glyph.frame = bounds
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
    }
}

/// The ghost in the collapsed strip, in the pill's right ear. Looks left at
/// rest. Under the pointer it looks right and grows a little, on the same
/// spring as the strip's swell.
struct PillGlyph: View {
    var hovered: Bool

    /// The ghost's box, as the menu bar icon was sized.
    static let size: CGFloat = 15
    static let hoverScale: CGFloat = 1.05
    /// From the strip's right edge to the ghost.
    static let trailingPadding: CGFloat = 12
    /// How far above the strip's vertical center the ghost sits.
    static let lift: CGFloat = 2

    var body: some View {
        NotchGhostMascot(gaze: hovered ? 1 : -1)
            .fill(Color(nsColor: NotchPanelPill.glyphColor), style: FillStyle(eoFill: true))
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(hovered ? Self.hoverScale : 1)
            .animation(NotchSpring.hover, value: hovered)
            .offset(y: -Self.lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, Self.trailingPadding)
            .accessibilityHidden(true)
    }
}

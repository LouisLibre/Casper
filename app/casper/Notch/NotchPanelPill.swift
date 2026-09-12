//
//  NotchPanelPill.swift
//

import AppKit

final class NotchPanelPill: NSView {
    var onEnter: (() -> Void)?
    var onClick: (() -> Void)?

    private let iconView = NSImageView()

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
                iconView.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            iconView.alphaValue = visible ? 1 : 0
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
    
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseDown(with event: NSEvent) { onClick?() }

    private func configure() {
        let icon = NSImage(resource: .menuBarIcon).copy() as! NSImage
        icon.size = NSSize(width: 15, height: 15)
        icon.accessibilityDescription = "Casper"
        iconView.image = icon
        iconView.contentTintColor = Self.glyphColor
        iconView.imageScaling = .scaleNone
        iconView.imageAlignment = .alignRight
        iconView.setAccessibilityElement(false)
        let side = AppGeometryReader.collapsedSideInset
        let rightPadding: CGFloat = 12
        let bottomPadding: CGFloat = 2
        iconView.frame = NSRect(x: bounds.width - side - rightPadding, y: 0 + bottomPadding, width: side, height: bounds.height)
        iconView.autoresizingMask = [.height, .maxXMargin]
        addSubview(iconView)
    }
}

//
//  NotchPanelPill.swift
//

import AppKit

final class NotchPanelPill: NSView {
    var onEnter: (() -> Void)?
    var onClick: (() -> Void)?

    private let iconView = NSImageView()

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
        /*
         let icon = NSImage(resource: .menuBarIcon).copy() as! NSImage
         icon.size = NSSize(width: 13, height: 13)
         icon.accessibilityDescription = "Casper"
         iconView.image = icon
         iconView.contentTintColor = NSColor.magenta
         */
        iconView.image = NSImage(systemSymbolName: "chevron.down.circle.fill", accessibilityDescription: "Casper")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.92)
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

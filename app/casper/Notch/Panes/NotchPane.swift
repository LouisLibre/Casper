//
//  NotchPane.swift
//
//  What the expanded shape shows: one of the terminals, or the settings
//  screen. Every pane shares the same frame inside the shape and stays in
//  the panel's view hierarchy for as long as it exists; only the active one
//  is visible. The pane view carries the rounded corners and the reveal mask
//  that tracks the shape while the notch expands and collapses.
//

import AppKit

@MainActor
protocol NotchPane: AnyObject {
    /// Created once and never resized on expand/collapse; the mask does the revealing.
    var view: NotchPaneView { get }
    /// What should be first responder while this pane is on screen. nil for
    /// panes that take no keyboard input.
    var inputView: NSView? { get }

    /// Puts the pane on screen at once, without the reveal animation. For
    /// switching panes while the panel is already expanded.
    func show()
    /// Takes the pane off screen at once; another pane took its place.
    func hide()
    /// Rects are the black shape's frame in the pane view's coordinate space.
    /// The collapsed rect sits entirely above the pane, so masking to it
    /// hides everything; the expanded rect covers the whole view.
    func reveal(from collapsedShapeRect: CGRect, to expandedShapeRect: CGRect)
    func conceal(from expandedShapeRect: CGRect, to collapsedShapeRect: CGRect)
}

/// Rounded container with the reveal mask. Panes put their content inside it.
final class NotchPaneView: NSView {
    init() {
        // The actual frame gets set by AppRootController. Initialize it to
        // zero to avoid dual sources of truth.
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        cancelMaskAnimation()
        isHidden = false
    }

    func hide() {
        cancelMaskAnimation()
        isHidden = true
    }

    func reveal(from collapsedShapeRect: CGRect, to expandedShapeRect: CGRect) {
        isHidden = false
        animateMask(installingAt: collapsedShapeRect, to: expandedShapeRect, expanding: true,
                    startDelay: NotchSpring.revealStartDelay) { [weak self] in
            // Fully revealed — drop the mask so the layer isn't composited
            // offscreen while the panel just sits open.
            self?.removeMask()
        }
    }

    /// `completion` runs once the view is hidden, unless another animation
    /// took over in the meantime.
    func conceal(from expandedShapeRect: CGRect, to collapsedShapeRect: CGRect,
                 completion: @escaping () -> Void = {}) {
        animateMask(installingAt: expandedShapeRect, to: collapsedShapeRect, expanding: false) { [weak self] in
            self?.isHidden = true
            self?.removeMask()
            completion()
        }
    }

    // MARK: - Reveal mask

    private var maskLayer: CALayer?
    /// Invalidates stale completion blocks when an animation is retargeted.
    private var maskGeneration = 0

    /// Drops the mask and disowns any completion still pending on it.
    private func cancelMaskAnimation() {
        maskGeneration += 1
        removeMask()
    }

    private func removeMask() {
        maskLayer?.removeAllAnimations()
        maskLayer = nil
        layer?.mask = nil
    }

    private func animateMask(installingAt startRect: CGRect, to endRect: CGRect,
                             expanding: Bool,
                             startDelay: CFTimeInterval = 0,
                             completion: @escaping () -> Void) {
        maskGeneration += 1
        let generation = maskGeneration

        let mask: CALayer
        if let existing = maskLayer {
            mask = existing
            // Retarget from wherever the in-flight animation actually is.
            if let presentation = existing.presentation() {
                existing.bounds = presentation.bounds
                existing.position = presentation.position
            }
            existing.removeAllAnimations()
        } else {
            mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            // The shape's expanded bottom radius; its top corners never reach
            // down into the pane, so rounding all four is harmless.
            mask.cornerRadius = 22
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = startRect
            CATransaction.commit()
            layer?.mask = mask
            maskLayer = mask
        }

        let endBounds = CGRect(origin: .zero, size: endRect.size)
        let endPosition = CGPoint(x: endRect.midX, y: endRect.midY)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.maskGeneration == generation else { return }
            completion()
        }
        // Width and height ride separate springs, matching the shape. The
        // shape is top-centered so only position.y moves; it follows the
        // height's clock.
        let width = NotchSpring.caSpring(keyPath: "bounds.size.width",
                                         from: NSNumber(value: Double(mask.bounds.width)),
                                         to: NSNumber(value: Double(endBounds.width)),
                                         axis: .horizontal, expanding: expanding)
        let height = NotchSpring.caSpring(keyPath: "bounds.size.height",
                                          from: NSNumber(value: Double(mask.bounds.height)),
                                          to: NSNumber(value: Double(endBounds.height)),
                                          axis: .vertical, expanding: expanding)
        let position = NotchSpring.caSpring(keyPath: "position",
                                            from: NSValue(point: mask.position),
                                            to: NSValue(point: endPosition),
                                            axis: .vertical, expanding: expanding)
        let springs = [width, height, position]
        if startDelay > 0 {
            let begin = CACurrentMediaTime() + startDelay
            for spring in springs {
                spring.beginTime = begin
                // Hold the from-value during the delay; the model values below
                // are already at the end state, so without this the mask would
                // show the pane fully revealed for the gap frame.
                spring.fillMode = .backwards
            }
        }
        mask.bounds = endBounds
        mask.position = endPosition
        for spring in springs { mask.add(spring, forKey: spring.keyPath) }
        CATransaction.commit()
    }
}

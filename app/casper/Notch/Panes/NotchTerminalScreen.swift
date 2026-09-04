//
//  NotchTerminalScreen.swift
//
//  Owns the one libghostty terminal for the app's lifetime. The container
//  view is created once, stays in the panel's view hierarchy forever, and
//  never resizes on expand/collapse — so scrollback, running programs and the
//  shell itself all survive collapsing the notch, and TUIs never see SIGWINCH.
//  Expanding animates a layer mask that tracks the black shape, revealing the
//  full-size terminal underneath.
//
//  The libghostty surface view sits inside the container rather than being
//  the container: libghostty installs its own render layer on the view it is
//  given, which would discard the corner radius and mask, and the surface is
//  replaced with a fresh one whenever the shell exits.
//

import AppKit

@MainActor
final class NotchTerminalScreen {
    /// Carries the rounded corners and the reveal mask; the surface fills it.
    let view: NSView

    /// The live terminal. nil until the shell starts and briefly while a new
    /// shell replaces one that exited.
    private(set) var surfaceView: GhosttySurfaceView?

    /// What should be first responder while the panel is expanded.
    var inputView: NSView? { surfaceView }

    private var started = false
    private var revealed = false

    init() {
        // The actual terminal frame gets set by AppRootController. Initialize it to zero to avoid dual sources of truth
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.cornerRadius = 15
        view.layer?.masksToBounds = true
        view.isHidden = true
    }

    /// Launches the user's login shell. Called once at app start, after the
    /// container has its frame and lives in the panel; the process keeps
    /// running regardless of the notch's expanded state.
    func startShellIfNeeded() {
        guard !started else { return }
        started = true
        spawnSurface()
    }

    /// libghostty spawns the login shell itself (via `login`, as Ghostty.app
    /// does) in the home directory, with TERM=xterm-ghostty and
    /// TERM_PROGRAM=ghostty backed by the bundled terminfo and shell
    /// integration.
    private func spawnSurface() {
        guard let app = GhosttyRuntime.shared.app else { return }
        let surface = GhosttySurfaceView(frame: view.bounds, app: app)
        guard surface.surface != nil else { return }
        surface.autoresizingMask = [.width, .height]
        surface.onCloseRequest = { [weak self] processAlive in
            // A close keybind with a process still running has nothing to
            // confirm it here, so it is ignored. The shell exiting (`exit`,
            // or ⌘W on an idle shell) gets a fresh shell so the notch always
            // has a live terminal. Deferred: this arrives from inside
            // libghostty's own event processing.
            guard !processAlive else { return }
            DispatchQueue.main.async { self?.respawnSurface() }
        }
        view.addSubview(surface)
        surfaceView = surface
        surface.setVisible(revealed)
        if revealed { view.window?.makeFirstResponder(surface) }
    }

    private func respawnSurface() {
        guard let old = surfaceView else { return }
        old.close()
        old.removeFromSuperview()
        surfaceView = nil
        spawnSurface()
    }

    // MARK: - Reveal mask

    /// Rects are the black shape's frame in this view's coordinate space.
    /// The collapsed rect sits entirely above the terminal, so masking to it
    /// hides everything; the expanded rect covers the whole view.

    func reveal(from collapsedShapeRect: CGRect, to expandedShapeRect: CGRect) {
        revealed = true
        surfaceView?.setVisible(true)
        view.isHidden = false
        animateMask(installingAt: collapsedShapeRect, to: expandedShapeRect, expanding: true,
                    startDelay: NotchSpring.revealStartDelay) { [weak self] in
            // Fully revealed — drop the mask so the layer isn't composited
            // offscreen while the panel just sits open.
            self?.removeMask()
        }
    }

    func conceal(from expandedShapeRect: CGRect, to collapsedShapeRect: CGRect) {
        revealed = false
        animateMask(installingAt: expandedShapeRect, to: collapsedShapeRect, expanding: false) { [weak self] in
            self?.view.isHidden = true
            self?.removeMask()
            // Let the renderer idle now that nothing is on screen.
            self?.surfaceView?.setVisible(false)
        }
    }

    private var maskLayer: CALayer?
    /// Invalidates stale completion blocks when an animation is retargeted.
    private var maskGeneration = 0

    private func removeMask() {
        maskLayer?.removeAllAnimations()
        maskLayer = nil
        view.layer?.mask = nil
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
            // down into the terminal, so rounding all four is harmless.
            mask.cornerRadius = 22
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = startRect
            CATransaction.commit()
            view.layer?.mask = mask
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
                // show the terminal fully revealed for the gap frame.
                spring.fillMode = .backwards
            }
        }
        mask.bounds = endBounds
        mask.position = endPosition
        for spring in springs { mask.add(spring, forKey: spring.keyPath) }
        CATransaction.commit()
    }
}

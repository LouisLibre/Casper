//
//  NotchTerminalScreen.swift
//
//  One libghostty terminal, alive for as long as its tab is open. Its pane
//  view is created once, stays in the panel's view hierarchy and never
//  resizes on expand/collapse — so scrollback, running programs and the
//  shell itself all survive collapsing the notch, and TUIs never see
//  SIGWINCH. Every open terminal shares the same frame; only the active one
//  is visible, the rest keep running hidden behind it.
//
//  The libghostty surface view sits inside the pane view rather than being
//  the pane view: libghostty installs its own render layer on the view it is
//  given, which would discard the corner radius, and the surface is
//  replaced with a fresh one whenever the shell exits.
//

import AppKit

@MainActor
final class NotchTerminalScreen: NotchPane, Identifiable {
    nonisolated let id = UUID()

    let view = NotchPaneView()

    /// The live terminal. nil until the shell starts and briefly while a new
    /// shell replaces one that exited.
    private(set) var surfaceView: GhosttySurfaceView?

    var inputView: NSView? { surfaceView }

    /// Whether closing this terminal would end a running process.
    var needsConfirmClose: Bool { surfaceView?.needsConfirmClose ?? false }
    /// Whether the shell itself has ended.
    var processExited: Bool { surfaceView?.processExited ?? false }
    /// The shell's directory: where it started, then whatever it last
    /// reported through shell integration. nil while there is no shell.
    var workingDirectory: String? { surfaceView?.workingDirectory }
    /// Where a tab opened from this one should start, by Ghostty's
    /// `tab-inherit-working-directory` rule. nil means the default.
    var inheritedWorkingDirectory: String? { surfaceView?.inheritedWorkingDirectory }

    /// Ghostty's new_tab binding (⌘T) fired in this terminal.
    var onNewTabRequest: (() -> Void)?
    /// One of Ghostty's goto_tab bindings (⌘1–⌘9, next and previous tab)
    /// fired in this terminal.
    var onGoToTabRequest: ((TabDestination) -> Void)?
    /// The shell changed directory; see `workingDirectory`.
    var onWorkingDirectoryChange: (() -> Void)?
    /// libghostty wants this terminal gone: the shell exited, or the close
    /// binding (⌘W) fired; `processExited` tells the two apart. The owner
    /// decides between closing the tab, starting a fresh shell and quitting.
    var onCloseRequest: (() -> Void)?

    private var started = false
    /// Whether the terminal is on screen (or on its way there), so a surface
    /// spawned in the meantime starts out visible and focused.
    private var revealed = false

    /// Launches the user's login shell in `workingDirectory`, or the home
    /// directory when that is nil. Called once, after the pane view has its
    /// frame and lives in the panel; the process keeps running regardless of
    /// the notch's expanded state.
    func startShellIfNeeded(in workingDirectory: String?) {
        guard !started else { return }
        started = true
        spawnSurface(in: workingDirectory)
    }

    /// libghostty spawns the login shell itself (via `login`, as Ghostty.app
    /// does) in `workingDirectory` (home when nil or gone), with
    /// TERM=xterm-ghostty and TERM_PROGRAM=ghostty backed by the bundled
    /// terminfo and shell integration.
    private func spawnSurface(in workingDirectory: String?) {
        guard let app = GhosttyRuntime.shared.app else { return }
        let surface = GhosttySurfaceView(frame: view.bounds, app: app, workingDirectory: workingDirectory)
        guard surface.surface != nil else { return }
        surface.autoresizingMask = [.width, .height]
        // These requests arrive from inside libghostty's own event processing,
        // so they are passed on from a later runloop turn, never inline.
        surface.onNewTabRequest = { [weak self] in
            DispatchQueue.main.async { self?.onNewTabRequest?() }
        }
        surface.onGoToTabRequest = { [weak self] destination in
            DispatchQueue.main.async { self?.onGoToTabRequest?(destination) }
        }
        surface.onCloseRequest = { [weak self] in
            DispatchQueue.main.async { self?.onCloseRequest?() }
        }
        surface.onWorkingDirectoryChange = { [weak self] in
            DispatchQueue.main.async { self?.onWorkingDirectoryChange?() }
        }
        view.addSubview(surface)
        surfaceView = surface
        surface.setVisible(revealed)
        if revealed { view.window?.makeFirstResponder(surface) }
    }

    /// Replaces an exited shell with a fresh one in the same tab, back in
    /// the home directory.
    func respawn() {
        guard let old = surfaceView else { return }
        old.close()
        old.removeFromSuperview()
        surfaceView = nil
        spawnSurface(in: nil)
    }

    /// Ends the shell and takes the terminal out of the panel for good.
    func close() {
        surfaceView?.close()
        surfaceView?.removeFromSuperview()
        surfaceView = nil
        view.hide()
        view.removeFromSuperview()
    }

    // MARK: - NotchPane

    func show() {
        revealed = true
        view.show()
        surfaceView?.setVisible(true)
    }

    func hide() {
        revealed = false
        view.hide()
        surfaceView?.setVisible(false)
    }

    func reveal() {
        revealed = true
        surfaceView?.setVisible(true)
    }

    func conceal() {
        revealed = false
        // Let the renderer idle: what it last drew stays on its layer for
        // the collapse, and nothing shows once that ends.
        surfaceView?.setVisible(false)
    }
}

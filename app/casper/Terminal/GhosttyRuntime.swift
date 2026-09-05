//
//  GhosttyRuntime.swift
//
//  Process-wide libghostty state: one ghostty_app_t for the app's lifetime,
//  its configuration, and the C callbacks libghostty uses to talk back to
//  us. libghostty is single-threaded from our point of view: every API call
//  happens on the main thread, and every callback except `wakeup` arrives on
//  the main thread from inside one of our own calls or from `ghostty_app_tick`.
//

import AppKit
import GhosttyKit
import GhosttyTerminal
import UniformTypeIdentifiers
import os

@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    static let logger = Logger(subsystem: "rs.unaligned.casper", category: "ghostty")

    /// nil when libghostty failed to initialize; callers must cope.
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?

    /// `background-opacity` from the finalized config. libghostty clears its
    /// render layer with this alpha but leaves the layer marked opaque, so
    /// the surface view has to flip that itself for the alpha to reach the
    /// compositor.
    private(set) var backgroundOpacity: Double = 1

    private init() {
        Self.pinResourcesDirectory()
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            Self.logger.critical("ghostty_init failed")
            return
        }
        guard let config = Self.loadConfig() else { return }
        self.config = config
        backgroundOpacity = Self.backgroundOpacity(of: config)

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyRuntime.wakeup(userdata) },
            action_cb: { app, target, action in GhosttyRuntime.action(app, target: target, action: action) },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, request in
                GhosttyRuntime.confirmReadClipboard(userdata, string: string, state: state, request: request)
            },
            write_clipboard_cb: { userdata, location, content, count, confirm in
                GhosttyRuntime.writeClipboard(userdata, location: location, content: content, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyRuntime.closeSurface(userdata, processAlive: processAlive)
            })
        guard let app = ghostty_app_new(&runtime, config) else {
            Self.logger.critical("ghostty_app_new failed")
            return
        }
        self.app = app

        // Key bindings are only processed while libghostty believes the app
        // is focused. Our panel takes keyboard input without ever making this
        // app active, so the default (focused) is left in place on purpose.

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardSelectionDidChange),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil)
    }

    /// libghostty wants one resources directory that holds both
    /// `shell-integration` and `themes`, with the compiled terminfo database
    /// as its sibling. The libghostty-spm bundle provides shell integration
    /// and terminfo but no themes, so `theme = name` in any config layer
    /// would fail to resolve, and its shell scripts omit the `cl=line`
    /// prompt option, so clicking in the prompt never moves the cursor.
    /// Assemble the expected layout under Application Support out of
    /// symlinks: terminfo from the package, themes and the patched shell
    /// integration from this app's bundle (falling back to the package's
    /// scripts). Links are refreshed on every launch so a moved bundle
    /// cannot leave them dangling.
    ///
    /// Setting GHOSTTY_RESOURCES_DIR ourselves also matters because release
    /// builds of libghostty honor an inherited value first, so launching from
    /// inside another Ghostty-based terminal would otherwise pick up that
    /// app's files.
    private static func pinResourcesDirectory() {
        guard let packageResources = GhosttyRuntimeResources.directoryURL,
              let packageTerminfo = GhosttyRuntimeResources.terminfoDirectoryURL else {
            logger.error("libghostty resource bundle not found; shell integration and terminfo unavailable")
            return
        }
        let fileManager = FileManager.default
        do {
            let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "rs.unaligned.casper", isDirectory: true)
                .appendingPathComponent("ghostty-resources", isDirectory: true)
            let resources = root.appendingPathComponent("ghostty", isDirectory: true)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
            let bundledShellIntegration = Bundle.main.resourceURL?.appendingPathComponent("shell-integration")
            if let bundledShellIntegration, fileManager.fileExists(atPath: bundledShellIntegration.path) {
                try link(resources.appendingPathComponent("shell-integration"), to: bundledShellIntegration)
            } else {
                logger.error("shell-integration folder missing from the app bundle; using the package's scripts")
                try link(resources.appendingPathComponent("shell-integration"),
                         to: packageResources.appendingPathComponent("shell-integration"))
            }
            try link(root.appendingPathComponent("terminfo"), to: packageTerminfo)
            if let themes = Bundle.main.resourceURL?.appendingPathComponent("themes"),
               fileManager.fileExists(atPath: themes.path) {
                try link(resources.appendingPathComponent("themes"), to: themes)
            } else {
                logger.error("themes folder missing from the app bundle; theme names will not resolve")
            }
            setenv("GHOSTTY_RESOURCES_DIR", resources.path, 1)
        } catch {
            logger.error("could not assemble the libghostty resources directory: \(error); using the package bundle without themes")
            setenv("GHOSTTY_RESOURCES_DIR", packageResources.path, 1)
        }
    }

    /// Creates or repoints a symlink; leaves it alone when already correct.
    private static func link(_ location: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if let current = try? fileManager.destinationOfSymbolicLink(atPath: location.path),
           current == destination.path {
            return
        }
        try? fileManager.removeItem(at: location)
        try fileManager.createSymbolicLink(at: location, withDestinationURL: destination)
    }

    // MARK: - Configuration

    /// The configuration is a cascade of files. Later files win for
    /// single-value keys and append for repeatable ones such as `keybind`,
    /// `font-family` and `palette`. Lowest to highest precedence:
    ///
    ///   1. libghostty's built-in defaults, filled in by finalize.
    ///   2. `defaults.ghostty` in the app bundle: Casper's own opinions.
    ///   3. The user's Ghostty files: ~/.config/ghostty/config and
    ///      config.ghostty, then their Application Support copies. This is
    ///      what makes the notch match Ghostty.app.
    ///   4. ~/.config/casper/config.ghostty: overrides that apply to the
    ///      notch only. Created on first ⌘,.
    ///   5. `config-file` includes named by any of the above.
    private static func loadConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else {
            logger.critical("ghostty_config_new failed")
            return nil
        }
        if let defaults = bundledDefaultsURL {
            ghostty_config_load_file(config, defaults.path)
        } else {
            logger.error("defaults.ghostty missing from the app bundle")
        }
        ghostty_config_load_default_files(config)
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            ghostty_config_load_file(config, userConfigURL.path)
        }
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        let diagnostics = ghostty_config_diagnostics_count(config)
        for index in 0..<diagnostics {
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            logger.warning("config: \(String(cString: diagnostic.message))")
        }
        return config
    }

    private static var bundledDefaultsURL: URL? {
        Bundle.main.url(forResource: "defaults", withExtension: "ghostty")
    }

    /// Always ~/.config/casper/config.ghostty. Ghostty's own files honor
    /// XDG_CONFIG_HOME; this one deliberately does not, so the notch's
    /// settings live in one predictable place regardless of what launched
    /// the app.
    static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("casper", isDirectory: true)
            .appendingPathComponent("config.ghostty")
    }

    private static let userConfigTemplate = """
    # Casper terminal settings.
    #
    # Loaded after your Ghostty config (~/.config/ghostty/config), so anything
    # set here applies to the notch only and wins over Ghostty.app's settings.
    # Keys are Ghostty's: https://ghostty.org/docs/config/reference
    # Reload with ⌘⇧, while the notch has focus. Fonts and colors apply right
    # away; padding and other layout settings apply to the next shell (`exit`).
    #
    # font-size = 12
    # theme = catppuccin-mocha
    # window-padding-x = 4

    """

    /// Re-reads the configuration files and applies the result to the app and
    /// every surface. Bound to ⌘⇧, by default.
    func reloadConfig() {
        guard let app, let config = Self.loadConfig() else { return }
        ghostty_app_update_config(app, config)
        if let previous = self.config { ghostty_config_free(previous) }
        self.config = config
        backgroundOpacity = Self.backgroundOpacity(of: config)
    }

    private static func backgroundOpacity(of config: ghostty_config_t) -> Double {
        var opacity: Double = 1
        let key = "background-opacity"
        guard ghostty_config_get(config, &opacity, key, UInt(key.utf8.count)) else { return 1 }
        return opacity
    }

    /// ⌘, (and the dock's settings tab) opens Casper's override file in the
    /// user's editor, creating it with a commented template the first time.
    @discardableResult
    static func openUserConfig() -> Bool {
        let url = userConfigURL
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try userConfigTemplate.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                logger.error("could not create \(url.path): \(error)")
                return false
            }
        }
        // .ghostty files have no registered app on most Macs; fall back to
        // whatever handles plain text rather than letting the open fail.
        let editor = NSWorkspace.shared.urlForApplication(toOpen: url)
            ?? NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText)
        if let editor {
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    @objc private func keyboardSelectionDidChange(_ notification: Notification) {
        guard let app else { return }
        ghostty_app_keyboard_changed(app)
    }

    // MARK: - Callbacks

    /// May be called from any thread: schedule a tick on main.
    private nonisolated static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            guard let app = runtime.app else { return }
            ghostty_app_tick(app)
        }
    }

    /// Returns true when the action was performed. Anything the notch cannot
    /// do (windows, splits, quitting) reports false, which libghostty treats
    /// as a no-op.
    private nonisolated static func action(_ app: ghostty_app_t?,
                                           target: ghostty_target_s,
                                           action: ghostty_action_s) -> Bool {
        MainActor.assumeIsolated {
            switch action.tag {
            case GHOSTTY_ACTION_MOUSE_SHAPE:
                guard let view = surfaceView(for: target) else { return false }
                view.setMouseShape(action.action.mouse_shape)
                return true

            case GHOSTTY_ACTION_MOUSE_VISIBILITY:
                NSCursor.setHiddenUntilMouseMoves(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
                return true

            case GHOSTTY_ACTION_OPEN_URL:
                return openURL(action.action.open_url)

            case GHOSTTY_ACTION_RELOAD_CONFIG:
                shared.reloadConfig()
                return true

            case GHOSTTY_ACTION_CONFIG_CHANGE:
                // Sent per surface once a new config is in effect; the app
                // wide one carries the same config and needs nothing here.
                guard let view = surfaceView(for: target) else { return false }
                view.setBackgroundOpacity(backgroundOpacity(of: action.action.config_change.config))
                return true

            case GHOSTTY_ACTION_OPEN_CONFIG:
                return openUserConfig()

            case GHOSTTY_ACTION_NEW_TAB:
                guard let request = surfaceView(for: target)?.onNewTabRequest else { return false }
                request()
                return true

            case GHOSTTY_ACTION_RING_BELL:
                NSSound.beep()
                return true

            case GHOSTTY_ACTION_RENDERER_HEALTH:
                if action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY {
                    logger.error("renderer reported unhealthy")
                }
                return true

            default:
                return false
            }
        }
    }

    private static func openURL(_ value: ghostty_action_open_url_s) -> Bool {
        let text = String(decoding: UnsafeRawBufferPointer(start: value.url, count: Int(value.len)), as: UTF8.self)
        let url: URL
        if let candidate = URL(string: text), candidate.scheme != nil {
            url = candidate
        } else {
            url = URL(fileURLWithPath: NSString(string: text).standardizingPath)
        }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Paste: hand the pasteboard text to libghostty right away. Returning
    /// false (nothing to paste) lets the key that triggered it fall through.
    private nonisolated static func readClipboard(_ userdata: UnsafeMutableRawPointer?,
                                                  location: ghostty_clipboard_e,
                                                  state: UnsafeMutableRawPointer?) -> Bool {
        MainActor.assumeIsolated {
            guard location == GHOSTTY_CLIPBOARD_STANDARD,
                  let surface = surfaceView(from: userdata)?.surface,
                  let text = NSPasteboard.general.string(forType: .string) else { return false }
            text.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
            return true
        }
    }

    /// libghostty asks before pasting text it considers unsafe (control
    /// characters outside bracketed paste). There is no room for a dialog in
    /// the notch, so the paste goes through, as if `clipboard-paste-protection`
    /// were off.
    private nonisolated static func confirmReadClipboard(_ userdata: UnsafeMutableRawPointer?,
                                                         string: UnsafePointer<CChar>?,
                                                         state: UnsafeMutableRawPointer?,
                                                         request: ghostty_clipboard_request_e) {
        MainActor.assumeIsolated {
            guard let surface = surfaceView(from: userdata)?.surface, let string else { return }
            ghostty_surface_complete_clipboard_request(surface, string, state, true)
        }
    }

    private nonisolated static func writeClipboard(_ userdata: UnsafeMutableRawPointer?,
                                                   location: ghostty_clipboard_e,
                                                   content: UnsafePointer<ghostty_clipboard_content_s>?,
                                                   count: Int,
                                                   confirm: Bool) {
        MainActor.assumeIsolated {
            guard location == GHOSTTY_CLIPBOARD_STANDARD, let content, count > 0 else { return }
            for index in 0..<count {
                let entry = content[index]
                guard let mime = entry.mime, let data = entry.data,
                      String(cString: mime) == "text/plain" else { continue }
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(String(cString: data), forType: .string)
                return
            }
        }
    }

    private nonisolated static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        MainActor.assumeIsolated {
            surfaceView(from: userdata)?.onCloseRequest?(processAlive)
        }
    }

    // MARK: - Userdata

    private static func surfaceView(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func surfaceView(for target: ghostty_target_s) -> GhosttySurfaceView? {
        guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else { return nil }
        return surfaceView(from: ghostty_surface_userdata(surface))
    }
}

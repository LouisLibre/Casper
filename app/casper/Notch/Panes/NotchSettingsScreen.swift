//
//  NotchSettingsScreen.swift
//
//  The settings pane. Takes the terminal's place inside the expanded shape
//  while the dock's settings tab is selected. SwiftUI content inside a pane
//  view, so it expands and collapses with the same mask as a terminal.
//

import AppKit
import SwiftUI

@MainActor
final class NotchSettingsScreen: NotchPane {
    let view = NotchPaneView()
    /// Nothing here takes typed input.
    var inputView: NSView? { nil }

    init(controller: AppRootController) {
        let hosting = NSHostingView(rootView: NotchSettingsPane().environmentObject(controller))
        // The pane view owns the frame, and the notch overlaps the screen's
        // safe area on purpose.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)
    }

    func show() {
        view.show()
    }

    func hide() {
        view.hide()
    }

    func reveal(from collapsedShapeRect: CGRect, to expandedShapeRect: CGRect) {
        view.reveal(from: collapsedShapeRect, to: expandedShapeRect)
    }

    func conceal(from expandedShapeRect: CGRect, to collapsedShapeRect: CGRect) {
        view.conceal(from: expandedShapeRect, to: collapsedShapeRect)
    }
}

struct NotchSettingsPane: View {
    @EnvironmentObject private var controller: AppRootController

    static let rowFill = Color.white.opacity(0.06)
    static let rowRim = Color.white.opacity(0.08)
    static let detailColor = Color.white.opacity(0.55)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.bottom, 6)

                SettingsRow(title: "Open at login",
                            detail: "Start Casper when you log in to your Mac.") {
                    Toggle("Open at login", isOn: Binding(
                        get: { controller.opensAtLogin },
                        set: { controller.setOpensAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                SettingsRow(title: "Transparent background",
                            detail: "Frosted backdrop behind the terminal. Off makes the shape flat black.") {
                    Toggle("Transparent background", isOn: Binding(
                        get: { controller.isTerminalTransparent },
                        set: { _ in controller.toggleTerminalTransparency() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                SettingsRow(title: "Terminal configuration",
                            detail: "Ghostty settings for the notch, in \(Self.configPath).") {
                    Button("Open in Editor") {
                        GhosttyRuntime.openUserConfig()
                    }
                }

                SettingsRow(title: "Quit Casper",
                            detail: "Every terminal session and anything running in it will end.") {
                    Button("Quit…") {
                        controller.confirmQuit()
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    /// ~/.config/casper/config.ghostty, the way a shell prompt would show it.
    private static var configPath: String {
        (GhosttyRuntime.userConfigURL.path as NSString).abbreviatingWithTildeInPath
    }

    /// One setting: title and explanation on the left, its control on the right.
    private struct SettingsRow<Control: View>: View {
        let title: String
        let detail: String
        @ViewBuilder let control: Control

        var body: some View {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchSettingsPane.detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                control
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchSettingsPane.rowFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NotchSettingsPane.rowRim, lineWidth: 1)
            }
        }
    }
}

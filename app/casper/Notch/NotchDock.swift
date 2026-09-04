//
//  NotchDock.swift
//
//  Floating glass menu under the expanded shape. Two groups: controls for the
//  active pane on the left, and the pane tabs on the right. The groups are
//  Liquid Glass on macOS 26; older systems get the body's frosted backdrop
//  with a hand-drawn rim. The body itself stays on the frosted backdrop on
//  purpose (see NotchBackdrop): the dock is only visible while the panel is
//  expanded and key, so the glass flattening on key loss barely shows here.
//

import SwiftUI

/// Panes the dock can switch between. Only the terminal exists as a pane
/// today; settings opens the config file until it gets a pane of its own.
enum NotchTab: CaseIterable, Identifiable {
    case terminal
    case settings

    var id: Self { self }

    var symbol: String {
        switch self {
        case .terminal: "apple.terminal"
        case .settings: "line.3.horizontal"
        }
    }

    var label: String {
        switch self {
        case .terminal: "Terminal"
        case .settings: "Settings"
        }
    }
}

struct NotchDock: View {
    @EnvironmentObject private var controller: AppRootController

    static let height: CGFloat = 50
    /// Space between the shape's bottom edge and the dock.
    static let topGap: CGFloat = 22
    static let bottomMargin: CGFloat = 12
    /// Extra panel height below the expanded shape that the dock lives in.
    static var reserve: CGFloat { topGap + height + bottomMargin }

    /// Each control gets a square slot the height of the bar.
    private static let slot: CGFloat = height
    /// Highlight behind the selected tab: a hair wider than tall.
    private static let tabHighlightSize = CGSize(width: 46, height: 40)
    /// Hover highlight for a standalone control. Its capsule is a circle, so
    /// the highlight is a circle inset evenly from it to keep the two concentric.
    private static let controlHighlightSize = CGSize(width: 40, height: 40)
    private static let groupSpacing: CGFloat = 22
    private static let capsuleEndPadding: CGFloat = 6

    /// Dark fill under clear glass. A black *tint* on regular glass turns the
    /// lens edge into a thick dark band and leaves a lighter disc inside it;
    /// filling the interior and letting untinted clear glass refract on top
    /// keeps the fill even and the edge thin, like the references.
    static let fill = Color.black.opacity(0.7)
    /// Specular hairline: brighter along the top, fading toward the bottom.
    static let rim = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom)
    static let iconOn = Color.white
    static let iconOff = Color.white.opacity(0.55)

    var body: some View {
        DockGroups {
            HStack(spacing: Self.groupSpacing) {
                // Pane controls. Standalone buttons carry their state in the
                // symbol (filled when on) and never draw a highlight.
                DockGlass {
                    DockButton(symbol: controller.isTerminalTransparent ? "square.on.square" : "square.fill.on.square.fill",
                               label: "Transparency",
                               isOn: !controller.isTerminalTransparent,
                               highlighted: false,
                               highlightSize: Self.controlHighlightSize) {
                        controller.toggleTerminalTransparency()
                    }
                }

                DockGlass {
                    HStack(spacing: 0) {
                        ForEach(NotchTab.allCases) { tab in
                            DockButton(symbol: tab.symbol, label: tab.label,
                                       isOn: controller.selectedTab == tab,
                                       highlighted: controller.selectedTab == tab) {
                                controller.select(tab)
                            }
                        }
                    }
                    .padding(.horizontal, Self.capsuleEndPadding)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Lets the glass capsules render as one set without merging: the
    /// container spacing is kept below the gap between groups.
    private struct DockGroups<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 8) { content }
            } else {
                content
            }
        }
    }

    /// One capsule of the bar. Clear Liquid Glass over a dark fill where
    /// available, otherwise the body's frosted backdrop with the same fill.
    /// Both get the hairline rim.
    private struct DockGlass<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            if #available(macOS 26, *) {
                content
                    .frame(height: NotchDock.height)
                    .background { Capsule().fill(NotchDock.fill) }
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .overlay { Capsule().strokeBorder(NotchDock.rim, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            } else {
                content
                    .frame(height: NotchDock.height)
                    .background {
                        NotchBackdrop()
                            .clipShape(Capsule())
                            .overlay { Capsule().fill(NotchDock.fill) }
                            .overlay { Capsule().strokeBorder(NotchDock.rim, lineWidth: 1) }
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            }
        }
    }

    private struct DockButton: View {
        let symbol: String
        let label: String
        /// Drawn white; otherwise mid gray.
        let isOn: Bool
        /// Draws the pill behind the icon. Tabs only.
        let highlighted: Bool
        var highlightSize = NotchDock.tabHighlightSize
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn ? NotchDock.iconOn : NotchDock.iconOff)
                    .frame(width: NotchDock.slot, height: NotchDock.slot)
                    .background {
                        Capsule()
                            .fill(.white.opacity(highlighted ? 0.18 : hovering ? 0.07 : 0))
                            .frame(width: highlightSize.width, height: highlightSize.height)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isOn)
            .animation(.easeOut(duration: 0.15), value: highlighted)
        }
    }
}

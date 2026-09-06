//
//  NotchDock.swift
//
//  Floating glass menu under the expanded shape. Two groups: the tabs on the
//  left, one per open terminal, then a plus that opens another; and settings
//  on the right. The dock never grows wider than the expanded shape: the tab
//  capsule hugs its tabs until the row would push past that width, then the
//  row scrolls inside it, and each end with tabs scrolled out past it gets a
//  solid slot in the capsule's corner holding a chevron that points that way;
//  a click on the slot scrolls the row a step further that way. Stepping the
//  shape with ⌘⇧+ / ⌘⇧- widens or narrows the room for tabs along with it.
//  After ⌘ is held briefly every control with a shortcut gets a small ⌘ badge over
//  the corner of its icon: the first nine tabs their number (⌘1 to ⌘9), the
//  tenth a 0 (⌘0), the plus a T (⌘T) and settings an S (⌘S). ⌘[ and ⌘]
//  step through the tabs, and their badges sit on the ends of the tab
//  capsule. From the settings pane only the tabs and the plus wear theirs:
//  the brackets and ⌘S do nothing there.
//
//  The groups are Liquid Glass on macOS 26; older systems get the body's
//  frosted backdrop with a hand-drawn rim. The body itself stays on the
//  frosted backdrop on purpose (see NotchBackdrop): the dock is only visible
//  while the panel is expanded and key, so the glass flattening on key loss
//  barely shows here.
//

import SwiftUI

struct NotchDock: View {
    @EnvironmentObject private var controller: AppRootController

    static let height: CGFloat = 50
    /// Space between the shape's bottom edge and the dock.
    static let topGap: CGFloat = 8
    static let bottomMargin: CGFloat = 12
    /// Extra panel height below the expanded shape that the dock lives in.
    static var reserve: CGFloat { topGap + height + bottomMargin }

    /// Each control gets a square slot the height of the bar.
    private static let slot: CGFloat = height
    /// Highlight behind the selected tab: a hair wider than tall.
    private static let tabHighlightSize = CGSize(width: 46, height: 40)
    /// Highlight for a standalone control. Its capsule is a circle, so the
    /// highlight is a circle inset evenly from it to keep the two concentric.
    private static let controlHighlightSize = CGSize(width: 40, height: 40)
    private static let groupSpacing: CGFloat = 12
    private static let capsuleEndPadding: CGFloat = 6
    /// A tab opening or closing: the capsule grows or shrinks, the tabs
    /// after it slide, and the row view (see TabScroller) follows.
    private static let tabChange = Animation.easeInOut(duration: tabChangeDuration)
    private static let tabChangeDuration: TimeInterval = 0.24
    private static let tabFadeDuration: TimeInterval = 0.14

    /// Keep a closing tab's slot until its icon has faded. These are only
    /// presentation IDs; the controller closes the terminal immediately.
    @State private var presentedTabs: [UUID] = []
    @State private var closingTabs: Set<UUID> = []

    private var tabIDs: [UUID] {
        presentedTabs.isEmpty ? controller.terminals.map(\.id) : presentedTabs
    }

    /// Dark fill under clear glass. A black *tint* on regular glass turns the
    /// lens edge into a thick dark band and leaves a lighter disc inside it;
    /// filling the interior and letting untinted clear glass refract on top
    /// keeps the fill even and the edge thin, like the references.
    static let fill = Color.black.opacity(0.7)
    /// Chevron slots at the ends of the tab row. The gray that white at 0.18
    /// over `fill` comes to, made solid so tabs sliding under a slot are gone.
    static let slotFill = Color(red: 0.219, green: 0.219, blue: 0.219)
    /// Specular hairline: brighter along the top, fading toward the bottom.
    static let rim = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom)
    static let iconOn = Color.white
    static let iconOff = Color.white.opacity(0.55)

    var body: some View {
        DockGroups {
            HStack(spacing: Self.groupSpacing) {
                DockGlass {
                    // Spans the capsule end to end; the padding at both ends scrolls
                    // with the tabs, so the chevron slots can fill the capsule's corners.
                    TabStrip(tabIDs: tabIDs, closingTabs: closingTabs,
                             width: stripWidth, rowWidth: rowWidth, showsKeyHints: showsTabKeyHints)
                }
                // Settings, selected while its pane is up in place of the terminal. Same as ⌘S.
                DockGlass {
                    DockButton(symbol: controller.isShowingSettings ? "gearshape.fill" : "gearshape", label: "Settings",
                               keyHint: showsTerminalOnlyKeyHints ? "S" : nil,
                               isOn: controller.isShowingSettings,
                               highlighted: controller.isShowingSettings,
                               highlightSize: Self.controlHighlightSize) {
                        controller.showSettings()
                    }
                }
            }
            // The tab capsule grows and shrinks as terminals come and go. A
            // size step is not animated: the shape above snaps, so the dock does too.
            .animation(Self.tabChange, value: tabIDs)
        }
        // ⌘[ and ⌘] step through the tabs; their badges straddle the ends of
        // the tab capsule. Laid over the whole glass group, not inside it:
        // the group draws its glass above anything in it that is not glass
        // content, and the capsule clips what is. The badges' positions
        // follow the capsule's ends, so they ride along when it grows.
        .overlay {
            if showsTerminalOnlyKeyHints {
                EdgeKeyBadges(stripWidth: stripWidth)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsTerminalOnlyKeyHints)
        .animation(Self.tabChange, value: tabIDs)
        .onAppear { presentedTabs = controller.terminals.map(\.id) }
        .onChange(of: controller.terminals.map(\.id)) { _, ids in reconcileTabs(ids) }
        .environment(\.colorScheme, .dark)
    }

    private func reconcileTabs(_ ids: [UUID]) {
        // New tabs take the plus's previous slot. Keep existing identities,
        // including slots already fading out during rapid keyboard input.
        let additions = ids.filter { !presentedTabs.contains($0) }
        presentedTabs.append(contentsOf: additions)
        let removed = Set(presentedTabs).subtracting(ids).subtracting(closingTabs)
        guard !removed.isEmpty else { return }
        closingTabs.formUnion(removed)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tabFadeDuration) {
            // Only retire this batch. A later close has its own fade, and a
            // tab opened in the meantime must keep its new slot and identity.
            presentedTabs.removeAll { removed.contains($0) }
            closingTabs.subtract(removed)
        }
    }

    /// ⌘ has been held long enough. The tabs and the plus wear their badges from every pane:
    /// ⌘1 to ⌘9, ⌘0 and ⌘T reach a terminal as Ghostty's own bindings, and
    /// from the settings pane the panel takes them itself.
    private var showsTabKeyHints: Bool { controller.showsShortcutHints }

    /// ⌘[ and ⌘] step between terminals and ⌘S opens settings. Neither does
    /// anything while the settings pane is up, so their badges stay off there.
    private var showsTerminalOnlyKeyHints: Bool { controller.showsShortcutHints && !controller.isShowingSettings }

    /// Width of the tab capsule: the row, until it outgrows its room.
    private var stripWidth: CGFloat { min(rowWidth, rowWidthLimit) }

    /// Every tab and the plus side by side, with the capsule's end padding
    /// around them.
    private var rowWidth: CGFloat {
        Self.capsuleEndPadding * 2 + Self.slot * CGFloat(tabIDs.count + 1)
    }

    /// What is left of the expanded shape's width for the row once the
    /// settings capsule and the gap before it have taken their share.
    private var rowWidthLimit: CGFloat {
        let settings = Self.slot
        return controller.expandedSize.width - Self.groupSpacing - settings
    }

    /// One tab per open terminal and then the plus, scrolling sideways once
    /// they outgrow `width`. An end with more of the row scrolled out past it
    /// gets a solid slot holding a chevron that points that way; clicking it
    /// scrolls a step further. The active tab is kept clear of the slots:
    /// when it changes, and when the strip resizes.
    private struct TabStrip: View {
        @EnvironmentObject private var controller: AppRootController
        let tabIDs: [UUID]
        let closingTabs: Set<UUID>
        let width: CGFloat
        let rowWidth: CGFloat
        /// ⌘ is held: each tab and the plus wear their key's badge.
        let showsKeyHints: Bool

        /// Whether the row is wider than the strip. From the layout math, not
        /// the scroll geometry: the capsule animates its growth when a tab
        /// opens, so for a few frames the row is wider than the strip even
        /// when it is about to fit.
        private var scrollable: Bool { rowWidth > width }

        /// Width of a chevron slot.
        private static let edgeWidth: CGFloat = 28
        /// How far a click on a chevron slot moves the row.
        private static let clickStep = NotchDock.slot * 2
        /// The end padding may scroll off without counting as overflow, and a
        /// point of slack keeps rounding and rubber-banding from flickering
        /// the chevrons.
        private static let slack = NotchDock.capsuleEndPadding + 1

        /// The stretch of the row on screen, in row coordinates. Reported by
        /// the scroller after every scroll and resize.
        @State private var visible = CGRect.zero
        @State private var request: ScrollRequest?

        private var showsLeadingChevron: Bool { scrollable && visible.minX > Self.slack }
        private var showsTrailingChevron: Bool { scrollable && visible.maxX < rowWidth - Self.slack }

        /// The digit that, with ⌘, jumps to the tab at `number` (from one):
        /// 1 to 9 for the first nine, 0 for the tenth, none past that.
        private static func keyHint(forTab number: Int) -> String? {
            switch number {
            case 1...9: return "\(number)"
            case 10: return "0"
            default: return nil
            }
        }

        var body: some View {
            TabScroller(row: row, rowWidth: rowWidth, stripWidth: width, request: request) { visible = $0 }
                .frame(width: width, height: NotchDock.height)
                .overlay(alignment: .leading) {
                    if showsLeadingChevron {
                        EdgeChevron(edge: .leading) { scroll(toward: .leading) }
                    }
                }
                .overlay(alignment: .trailing) {
                    if showsTrailingChevron {
                        EdgeChevron(edge: .trailing) { scroll(toward: .trailing) }
                    }
                }
                .animation(.easeOut(duration: 0.15), value: showsLeadingChevron)
                .animation(.easeOut(duration: 0.15), value: showsTrailingChevron)
                .onChange(of: controller.activeTerminal?.id) { revealActiveTab() }
                .onChange(of: tabIDs) { revealActiveTab() }
                // A ⌘⇧ size step.
                .onChange(of: width) { revealActiveTab() }
        }

        private var row: some View {
            ZStack(alignment: .leading) {
                // ⌘T adds one, ⌘W closes the active one, ⌘1 to ⌘9 and ⌘0 pick
                // one of the first ten by number; the rest have no key to show.
                ForEach(tabIDs, id: \.self) { id in
                    let index = tabIDs.firstIndex(of: id) ?? 0
                    let isClosing = closingTabs.contains(id)
                    let isActive = !controller.isShowingSettings && id == controller.activeTerminal?.id
                    let number = (controller.terminals.firstIndex { $0.id == id } ?? index) + 1
                    DockButton(symbol: "apple.terminal", label: "Terminal \(number)",
                               keyHint: showsKeyHints ? Self.keyHint(forTab: number) : nil,
                               isOn: isActive,
                               highlighted: isActive,
                               animatesSelectionOnAppear: true) {
                        if let terminal = controller.terminals.first(where: { $0.id == id }) {
                            controller.activate(terminal)
                        }
                    }
                    .opacity(isClosing ? 0 : 1)
                    .animation(.easeOut(duration: NotchDock.tabFadeDuration), value: isClosing)
                    .allowsHitTesting(!isClosing)
                    .accessibilityHidden(isClosing)
                    // Explicit slots never compress to accommodate an outgoing
                    // view. Removal happens only once it is fully transparent.
                    .offset(x: NotchDock.capsuleEndPadding + NotchDock.slot * CGFloat(index))
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
                // Same as ⌘T. Last in the row, so it scrolls with the tabs.
                DockButton(symbol: "plus", label: "New Terminal",
                           keyHint: showsKeyHints ? "T" : nil,
                           isOn: false,
                           highlighted: false) {
                    controller.newTerminal()
                }
                .offset(x: NotchDock.capsuleEndPadding + NotchDock.slot * CGFloat(tabIDs.count))
            }
            // Slots and capsule share the same layout transaction. The plus
            // remains a single view, moving with the row's trailing edge.
            .frame(maxWidth: .infinity, minHeight: NotchDock.height, alignment: .leading)
            .animation(NotchDock.tabChange, value: tabIDs)
        }

        /// Brings the active tab into the clear when it is scrolled out or
        /// under a chevron slot. A tab already in the clear stays put, so
        /// clicking it never shifts the strip. The last tab counts together
        /// with the plus after it and comes in at the row's end, so the plus
        /// shows too; a tab opened with ⌘T is always this case, and the end
        /// has moved, so it always scrolls. Nothing to do while the whole row
        /// fits.
        private func revealActiveTab() {
            guard scrollable,
                  let active = controller.activeTerminal,
                  let index = tabIDs.firstIndex(of: active.id) else { return }
            let isLast = index == tabIDs.count - 1
            let minX = NotchDock.capsuleEndPadding + NotchDock.slot * CGFloat(index)
            let maxX = minX + NotchDock.slot * (isLast ? 2 : 1)
            // The row may have just changed length; only the offset is taken
            // from the last report, the widths come from the layout math.
            let clearMinX = visible.minX + (showsLeadingChevron ? Self.edgeWidth : 0)
            let clearMaxX = visible.minX + width - (showsTrailingChevron ? Self.edgeWidth : 0)
            guard minX < clearMinX || maxX > clearMaxX else { return }
            scroll(to: isLast ? rowWidth - width : (minX + maxX - width) / 2)
        }

        /// A chevron slot was clicked: moves the row one step that way. The
        /// click landed in the SwiftUI body, so the terminal gets the
        /// keyboard back.
        private func scroll(toward edge: HorizontalEdge) {
            scroll(to: visible.minX + (edge == .leading ? -Self.clickStep : Self.clickStep))
            controller.focusActivePane()
        }

        /// Asks the scroller for `x`, kept within the row's ends.
        private func scroll(to x: CGFloat) {
            request = ScrollRequest(x: min(max(x, 0), rowWidth - width))
        }

        /// A solid slot in one of the capsule's corners, with the chevron in
        /// the same gray as an inactive tab's icon, white under the pointer.
        /// Drawn as a rectangle: DockGlass clips it to the capsule, so its
        /// round side is the capsule's own end.
        private struct EdgeChevron: View {
            let edge: HorizontalEdge
            let action: () -> Void

            @State private var hovering = false

            var body: some View {
                Button(action: action) {
                    Image(systemName: edge == .leading ? "chevron.compact.left" : "chevron.compact.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(hovering ? NotchDock.iconOn : NotchDock.iconOff)
                        .frame(width: TabStrip.edgeWidth, height: NotchDock.height)
                        .background(NotchDock.slotFill)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(edge == .leading ? "Earlier Tabs" : "Later Tabs")
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .transition(.opacity)
            }
        }
    }

    /// A scroll the scroller applies once. A fresh id each time, so asking
    /// for the same offset twice still scrolls.
    private struct ScrollRequest: Equatable {
        let x: CGFloat
        let id = UUID()
    }

    /// Keep the row in the same SwiftUI tree as its glass. A separately
    /// hosted row starts its layout animation on a different frame and can
    /// leave the plus outside the shrinking capsule, even with equal durations.
    private struct TabScroller<Row: View>: View {
        let row: Row
        let rowWidth: CGFloat
        let stripWidth: CGFloat
        let request: ScrollRequest?
        let onVisibleChange: (CGRect) -> Void

        @State private var position = ScrollPosition(x: 0)
        @State private var contentWidth: CGFloat = 0
        @State private var settledContentWidth: CGFloat = 0

        private struct ScrollLayout: Equatable {
            let requestID: UUID?
            let contentWidth: CGFloat
            let stripWidth: CGFloat
        }

        var body: some View {
            ScrollView(.horizontal) {
                row.frame(width: rowWidth, height: NotchDock.height, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .defaultScrollAnchor(.leading)
            .scrollClipDisabled()
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                CGRect(origin: geometry.contentOffset, size: geometry.containerSize)
            } action: { _, visible in
                onVisibleChange(visible)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.width } action: { _, width in
                contentWidth = width
            }
            .task(id: ScrollLayout(requestID: request?.id, contentWidth: contentWidth, stripWidth: stripWidth)) {
                guard let request else { return }
                // ScrollView reports its target extent before an animated
                // resize finishes. Wait for that extent to become available
                // or it can clamp a new-tab request to the previous end.
                // Chevron clicks in an unchanged row do not need this wait.
                if contentWidth != settledContentWidth {
                    do {
                        try await Task.sleep(for: .seconds(NotchDock.tabChangeDuration))
                    } catch { return }
                }
                guard !Task.isCancelled else { return }
                settledContentWidth = contentWidth
                withAnimation(NotchDock.tabChange) {
                    position.scrollTo(x: min(max(request.x, 0), max(0, rowWidth - stripWidth)))
                }
            }
        }
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
    /// Both get the hairline rim, and both clip their content to the capsule
    /// so a tab scrolled halfway out is cut by the round end, not drawn past it.
    private struct DockGlass<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            if #available(macOS 26, *) {
                content
                    .frame(height: NotchDock.height)
                    .background { Capsule().fill(NotchDock.fill) }
                    .clipShape(Capsule())
                    .contentShape(Capsule())
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
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            }
        }
    }

    private struct DockButton: View {
        let symbol: String
        let label: String
        /// Shown in a ⌘ badge over the icon's corner: the key that, with ⌘,
        /// does what a click does. Set only while ⌘ is held, and never for a
        /// control without a shortcut.
        var keyHint: String? = nil
        /// Drawn white; otherwise mid gray.
        let isOn: Bool
        /// Draws the pill behind the icon. Tabs only.
        let highlighted: Bool
        var highlightSize = NotchDock.tabHighlightSize
        var animatesSelectionOnAppear = false
        let action: () -> Void

        @State private var hovering = false
        @State private var appeared = false

        private var selectionVisible: Bool { appeared || !animatesSelectionOnAppear }

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn && selectionVisible ? NotchDock.iconOn : NotchDock.iconOff)
                    .frame(width: NotchDock.slot, height: NotchDock.slot)
                    .background {
                        Capsule()
                            .fill(.white.opacity(highlighted && selectionVisible ? 0.18 : hovering ? 0.07 : 0))
                            .frame(width: highlightSize.width, height: highlightSize.height)
                    }
                    // Kept inside the slot, so the badge never reaches the
                    // capsule's clipped round ends.
                    .overlay(alignment: .topTrailing) {
                        if let keyHint {
                            KeyBadge(key: keyHint)
                                .padding(.top, 7)
                                .padding(.trailing, 6)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .onAppear { appeared = true }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: keyHint)
            .animation(.easeOut(duration: 0.15), value: isOn)
            .animation(.easeOut(duration: 0.15), value: highlighted)
            .animation(.easeOut(duration: NotchDock.tabChangeDuration), value: appeared)
        }
    }

    /// ⌘[ on the tab capsule's leading end and ⌘] on its trailing end, each
    /// centered on the edge, so half of it sits outside, and a little below
    /// mid height to keep clear of the tab badges in the top corners. In the
    /// dock's coordinates: the capsule is the dock's first group, so its
    /// leading end is x 0 and its trailing end is `stripWidth`. Clicks pass
    /// through to the chevron slots under the inner halves.
    private struct EdgeKeyBadges: View {
        let stripWidth: CGFloat

        private static let drop: CGFloat = 18

        var body: some View {
            let y = NotchDock.height / 2 + Self.drop
            ZStack {
                KeyBadge(key: "[").position(x: 8, y: y)
                KeyBadge(key: "]").position(x: stripWidth - 8 , y: y)
            }
            .allowsHitTesting(false)
        }
    }
}

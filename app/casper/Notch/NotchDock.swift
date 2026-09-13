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
//  A right click on a tab brings up a menu: a Finder window at that
//  terminal's directory, or closing the tab. Dragging a tab along the row
//  moves it there: the others slide out of its way, and the ⌘ numbers
//  follow the new order.
//  After ⌘ is held briefly every control with a shortcut gets a small ⌘ badge over
//  the corner of its icon: the first nine tabs their number (⌘1 to ⌘9), the
//  tenth a 0 (⌘0), the plus a T (⌘T) and settings an S (⌘S). ⌘[ and ⌘]
//  step through the tabs, and their badges sit on the ends of the tab
//  capsule; ⌘W closes the active tab, and its badge sits under that tab's
//  number badge, level with them. From the settings pane
//  only the tabs and the plus wear theirs: the brackets and ⌘S do nothing
//  there, and no tab is active.
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
    /// The bracket badges and the ⌘W badge sit this far below mid height,
    /// clear of the tab badges in the top corners.
    private static let lowerBadgeDrop: CGFloat = 18
    /// A badge in a slot's top trailing corner sits this far in from the
    /// slot's trailing edge. The ⌘W badge lines up under it.
    private static let slotBadgeTrailingPadding: CGFloat = 6
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
    /// How far the tab row is scrolled, reported by the strip. Places the
    /// ⌘W badge over the active tab from outside the capsule.
    @State private var rowScrollX: CGFloat = 0

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
                             width: stripWidth, rowWidth: rowWidth, showsKeyHints: showsTabKeyHints,
                             scrollX: $rowScrollX, onMove: moveTab)
                }
                // Settings, selected while its pane is up in place of the terminal. Same as ⌘S.
                // Its badge stays on while the pane is up, like the tabs', so
                // the dock does not lose just one hint when settings opens.
                DockGlass {
                    DockButton(symbol: controller.isShowingSettings ? "gearshape.fill" : "gearshape", label: "Settings",
                               keyHint: showsTabKeyHints ? "S" : nil,
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
        // the tab capsule. ⌘W closes the active tab; its badge sits under
        // that tab's number badge. Laid over the whole glass group, not
        // inside it: the group draws its glass above anything in it that is
        // not glass content, and the capsule clips what is. The badges'
        // positions follow the capsule's ends and the active tab, so they
        // ride along when the capsule grows or the row scrolls.
        .overlay {
            if showsTerminalOnlyKeyHints {
                EdgeKeyBadges(stripWidth: stripWidth)
                if let slot = activeTabSlot {
                    CloseKeyBadge(numberKey: Self.keyHint(forTab: slot.number), slotMaxX: slot.maxX)
                }
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

    /// A tab dropped after a drag: puts it at `index` in the row, and its
    /// terminal at the same place in the controller's order. Both change in
    /// the same transaction, so the tab settles straight into its new slot.
    /// The controller's order has no fading slots in it.
    private func moveTab(_ id: UUID, to index: Int) {
        guard let from = presentedTabs.firstIndex(of: id) else { return }
        presentedTabs.remove(at: from)
        presentedTabs.insert(id, at: index)
        let live = presentedTabs.filter { !closingTabs.contains($0) }
        guard let terminal = controller.terminals.first(where: { $0.id == id }),
              let liveIndex = live.firstIndex(of: id) else { return }
        controller.move(terminal, to: liveIndex)
    }

    /// ⌘ has been held long enough. The tabs and the plus wear their badges from every pane:
    /// ⌘1 to ⌘9, ⌘0 and ⌘T reach a terminal as Ghostty's own bindings, and
    /// from the settings pane the panel takes them itself.
    private var showsTabKeyHints: Bool { controller.showsShortcutHints }

    /// ⌘[ and ⌘] step between terminals. They do nothing while the settings
    /// pane is up, so their badges stay off there.
    private var showsTerminalOnlyKeyHints: Bool { controller.showsShortcutHints && !controller.isShowingSettings }

    /// Width of the tab capsule: the row, until it outgrows its room.
    private var stripWidth: CGFloat { min(rowWidth, rowWidthLimit) }

    /// The active tab: its number (from one) and its slot's trailing edge
    /// in the dock's coordinates, moved by the row's scroll. Nil while the
    /// slot is not wholly inside the strip: revealing brings it back, but
    /// the chevrons can scroll it out in between, and the ⌘W badge should
    /// not float over them.
    private var activeTabSlot: (number: Int, maxX: CGFloat)? {
        guard let active = controller.activeTerminal,
              let index = tabIDs.firstIndex(of: active.id) else { return nil }
        let slotMinX = Self.capsuleEndPadding + Self.slot * CGFloat(index) - rowScrollX
        let slotMaxX = slotMinX + Self.slot
        guard slotMinX >= 0, slotMaxX <= stripWidth else { return nil }
        let number = (controller.terminals.firstIndex { $0.id == active.id } ?? index) + 1
        return (number, slotMaxX)
    }

    /// The digit that, with ⌘, jumps to the tab at `number` (from one):
    /// 1 to 9 for the first nine, 0 for the tenth, none past that.
    private static func keyHint(forTab number: Int) -> String? {
        switch number {
        case 1...9: return "\(number)"
        case 10: return "0"
        default: return nil
        }
    }

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
    /// when it changes, and when the strip resizes. A tab pulled sideways
    /// comes along under the pointer, the others close up around the slot
    /// it is over, and letting go drops it there.
    private struct TabStrip: View {
        @EnvironmentObject private var controller: AppRootController
        let tabIDs: [UUID]
        let closingTabs: Set<UUID>
        let width: CGFloat
        let rowWidth: CGFloat
        /// ⌘ is held: each tab and the plus wear their key's badge.
        let showsKeyHints: Bool
        /// How far the row is scrolled, for the dock to place the ⌘W badge.
        @Binding var scrollX: CGFloat
        /// A tab was dropped: which one, and the slot it should take.
        let onMove: (UUID, Int) -> Void

        /// The tab under the pointer since it was picked up, if any.
        @State private var drag: TabDrag?
        /// The tab picked up last. Drawn above the others, so it passes
        /// over them while dragged and still settles into its slot on top.
        @State private var raisedTab: UUID?

        private struct TabDrag {
            let id: UUID
            /// How far the pointer has moved since picking the tab up, in
            /// row coordinates.
            let translation: CGFloat
        }

        /// What places a tab in the row, for the animation keyed on it: a
        /// change of slot slides the tab there, and being dropped slides it
        /// from under the pointer into its slot. Being picked up does not
        /// animate, nor does the pointer carrying it across slots.
        private struct Placement: Equatable {
            let slot: Int
            let isDragged: Bool
        }

        /// How far the pointer must move before a press on a tab becomes a
        /// drag rather than a click.
        private static let dragStart: CGFloat = 4
        private static let rowSpace = "tabRow"

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

        var body: some View {
            TabScroller(row: row, rowWidth: rowWidth, stripWidth: width, request: request) {
                visible = $0
                scrollX = $0.minX
            }
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
                    // nil once the controller has closed it and its slot is fading.
                    let terminal = controller.terminals.first { $0.id == id }
                    let isClosing = closingTabs.contains(id)
                    let isActive = !controller.isShowingSettings && id == controller.activeTerminal?.id
                    let isDragged = drag?.id == id
                    let number = (controller.terminals.firstIndex { $0.id == id } ?? index) + 1
                    DockButton(symbol: "apple.terminal", label: "Terminal \(number)",
                               keyHint: showsKeyHints ? NotchDock.keyHint(forTab: number) : nil,
                               isOn: isActive,
                               highlighted: isActive,
                               animatesSelectionOnAppear: true) {
                        if let terminal { controller.activate(terminal) }
                    }
                    .contextMenu {
                        if let terminal {
                            TabMenu(terminal: terminal)
                        }
                    }
                    // Alongside the button's own click, which a drag never
                    // becomes: the pull has to pass `dragStart` first.
                    .simultaneousGesture(dragGesture(for: id))
                    // Lifted a little while carried.
                    .scaleEffect(isDragged ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: isDragged)
                    .opacity(isClosing ? 0 : 1)
                    .animation(.easeOut(duration: NotchDock.tabFadeDuration), value: isClosing)
                    .allowsHitTesting(!isClosing)
                    .accessibilityHidden(isClosing)
                    // Explicit slots never compress to accommodate an outgoing
                    // view. Removal happens only once it is fully transparent.
                    .offset(x: tabX(id, at: index))
                    .animation(isDragged ? nil : NotchDock.tabChange,
                               value: Placement(slot: slotOrder.firstIndex(of: id) ?? index, isDragged: isDragged))
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .zIndex(id == raisedTab ? 1 : 0)
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
            // Drags are measured here, so a tab stays under the pointer even
            // if the row scrolls while it is carried.
            .coordinateSpace(.named(Self.rowSpace))
        }

        // MARK: Dragging a tab

        /// Picks the tab up once the pointer has pulled it `dragStart`, so a
        /// click stays a click, and carries it until the button comes up.
        /// Picking a tab up selects it, as pressing one does.
        private func dragGesture(for id: UUID) -> some Gesture {
            DragGesture(minimumDistance: Self.dragStart, coordinateSpace: .named(Self.rowSpace))
                .onChanged { value in
                    if drag == nil, let terminal = controller.terminals.first(where: { $0.id == id }) {
                        raisedTab = id
                        controller.activate(terminal)
                    }
                    drag = TabDrag(id: id, translation: value.translation.width)
                }
                .onEnded { _ in drop() }
        }

        /// Puts the dragged tab down in the slot it is over. The press landed
        /// in the SwiftUI body, so the terminal gets the keyboard back.
        private func drop() {
            guard let drag else { return }
            let from = tabIDs.firstIndex(of: drag.id) ?? 0
            let to = slot(for: drag)
            self.drag = nil
            if to != from { onMove(drag.id, to) }
            controller.focusActivePane()
        }

        /// Where the tab at `index` is drawn, from the row's leading end.
        /// While one is dragged it rides under the pointer, and the others
        /// close up around the slot it is over.
        private func tabX(_ id: UUID, at index: Int) -> CGFloat {
            let x: CGFloat
            if let drag, drag.id == id {
                x = draggedX(for: drag)
            } else {
                x = NotchDock.slot * CGFloat(slotOrder.firstIndex(of: id) ?? index)
            }
            return NotchDock.capsuleEndPadding + x
        }

        /// Where the dragged tab is, from the first slot: as far as the
        /// pointer has carried it, but never before the first slot or past
        /// the last tab's, so it cannot pass the plus.
        private func draggedX(for drag: TabDrag) -> CGFloat {
            let from = tabIDs.firstIndex(of: drag.id) ?? 0
            let x = NotchDock.slot * CGFloat(from) + drag.translation
            return min(max(x, 0), NotchDock.slot * CGFloat(tabIDs.count - 1))
        }

        /// The slot the dragged tab is nearest to.
        private func slot(for drag: TabDrag) -> Int {
            Int((draggedX(for: drag) / NotchDock.slot).rounded())
        }

        /// The row as it will be on drop: the dragged tab in the slot it is
        /// over and the others closed up around it. The row as it is while
        /// nothing is dragged.
        private var slotOrder: [UUID] {
            guard let drag, let from = tabIDs.firstIndex(of: drag.id) else { return tabIDs }
            var order = tabIDs
            order.remove(at: from)
            order.insert(drag.id, at: slot(for: drag))
            return order
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

        /// The items of a tab's context menu. Closing is what ⌘W does for
        /// the active tab, so with one tab left it asks about quitting. The
        /// menu came up over the SwiftUI body, so afterwards the terminal
        /// gets the keyboard back.
        private struct TabMenu: View {
            @EnvironmentObject private var controller: AppRootController
            let terminal: NotchTerminalScreen

            var body: some View {
                Button("Reveal in Finder") {
                    controller.revealInFinder(terminal)
                }
                .disabled(terminal.workingDirectory == nil)
                Divider()
                Button("Close Terminal") {
                    controller.close(terminal)
                    controller.focusActivePane()
                }
            }
        }

        /// A solid slot in one of the capsule's corners, with the chevron in
        /// the same gray as an inactive tab's icon, white under the pointer.
        /// Drawn as a rectangle: DockGlass clips it to the capsule, so its
        /// round side is the capsule's own end.
        private struct EdgeChevron: View {
            let edge: HorizontalEdge
            let action: () -> Void

            @State private var hovering = false

            private var label: String { edge == .leading ? "Earlier Tabs" : "Later Tabs" }

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
                .accessibilityLabel(label)
                .toolTip(label)
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
                                .padding(.trailing, NotchDock.slotBadgeTrailingPadding)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .toolTip(label)
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
    /// centered on the end's outermost point, and a little below mid height
    /// to keep clear of the tab badges in the top corners. Centered on the
    /// curve at that height they would sit further in and run into ⌘W when
    /// the first tab is active. In the dock's coordinates: the capsule is
    /// the dock's first group, so its leading end is x 0 and its trailing
    /// end is `stripWidth`. Clicks pass through to the chevron slots under
    /// the inner halves.
    private struct EdgeKeyBadges: View {
        let stripWidth: CGFloat

        var body: some View {
            let y = NotchDock.height / 2 + NotchDock.lowerBadgeDrop
            ZStack {
                KeyBadge(key: "[").position(x: 0, y: y)
                KeyBadge(key: "]").position(x: stripWidth, y: y)
            }
            .allowsHitTesting(false)
        }
    }

    /// ⌘W on the active tab: level with the bracket badges, and under the
    /// tab's number badge in its top trailing corner with their leading
    /// edges flush. A hidden copy of that badge, placed the way DockButton
    /// places it, stands in for it, so the two line up whatever the
    /// number's width. Tabs past the tenth have no number badge; ⌘W then
    /// sits where one would be. Clicks pass through to the tab under it.
    ///
    /// The ZStack is not decoration. The badge comes and goes with the
    /// hints, and a transition runs on the root of what comes and goes. A
    /// positioned view as that root would get the badge's own scale
    /// transition applied to its full-size frame, scaling about the dock's
    /// center, so the badge would slide into place. With the ZStack as
    /// root it fades in where it sits, like the bracket badges.
    private struct CloseKeyBadge: View {
        let numberKey: String?
        /// The slot's trailing edge, in the dock's coordinates.
        let slotMaxX: CGFloat

        var body: some View {
            ZStack {
                KeyBadge(key: numberKey ?? "0")
                    .hidden()
                    // Its own size, not the stand-in's: ⌘W is the wider badge.
                    .overlay(alignment: .leading) { KeyBadge(key: "W").fixedSize() }
                    .padding(.trailing, NotchDock.slotBadgeTrailingPadding)
                    .frame(width: NotchDock.slot, alignment: .trailing)
                    .position(x: slotMaxX - NotchDock.slot / 2, y: NotchDock.height / 2 + NotchDock.lowerBadgeDrop)
            }
            .allowsHitTesting(false)
        }
    }
}

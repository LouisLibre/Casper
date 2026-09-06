//
//  NotchToolTip.swift
//
//  The system tooltip for a control in the panel. SwiftUI's own `.help`
//  keeps one tooltip per hosting view and reads the text once, where the
//  pointer first enters that view: coming in over the terminal and moving
//  on to a dock button shows nothing, and moving from one button to the
//  next keeps the first one's text. So each control gets an AppKit view of
//  its own under it, with the tooltip on that: AppKit tracks every tooltip
//  rectangle separately, whatever path the pointer took. The view is
//  click-through, so the control keeps its clicks.
//

import AppKit
import SwiftUI

extension View {
    /// The system tooltip reading `text` while the pointer rests on the
    /// view. Only while the panel is expanded: it keeps its full frame while
    /// collapsed, with the controls invisible, and a tooltip must not pop
    /// up over one of those.
    func toolTip(_ text: String) -> some View {
        background { ToolTipView(text: text) }
    }
}

private struct ToolTipView: NSViewRepresentable {
    let text: String
    @EnvironmentObject private var controller: AppRootController

    func makeNSView(context: Context) -> ClickThroughView {
        let view = ClickThroughView()
        view.toolTip = controller.isExpanded ? text : nil
        return view
    }

    func updateNSView(_ view: ClickThroughView, context: Context) {
        view.toolTip = controller.isExpanded ? text : nil
    }

    /// Takes no clicks, so the SwiftUI control over it keeps them. The
    /// tooltip still shows: AppKit tracks it apart from hit-testing.
    final class ClickThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

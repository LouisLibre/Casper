//
//  NotchResizeHandle.swift
//
//  Drag target along the bottom of the expanded shape, for resizing it by
//  hand. Three zones: the bottom edge, and an L of margin around each
//  bottom corner. Pulling the edge down, or a corner down or out, steps
//  the shape up the size ladder; pulling back steps it down. The size is
//  a rung of ExpandedSizeLadder, so the shape snaps from rung to rung
//  under the pointer: whichever rung has its edge nearest the pointer.
//
//  The zones lie in the margin between the shape's edge and the pane
//  (AppRootController.paneInset), inside the shape: they never cover the
//  terminal, and nothing past the shape's edge can be grabbed, as the
//  panel's transparent pixels let clicks through. Under the pointer each
//  zone shows the resize cursor for its direction. Hidden while
//  collapsed, so it takes no clicks then.
//

import AppKit

final class NotchResizeHandle: NSView {
    /// The rung the shape is on, asked when a drag begins.
    var currentStep: (() -> Int)?
    /// The rung the drag has pulled the shape to, counted from the one it
    /// began on. Called for every move, on the same rung or not.
    var onDrag: ((Int) -> Void)?

    /// How thick the zones are: the margin between the shape's edge and
    /// the pane, all of it.
    static let thickness = AppRootController.paneInset
    /// How far along the bottom and up the sides a corner zone reaches,
    /// a little past the rounded corner
    /// (NotchPanelBody.expandedBottomCornerRadius). The view is this tall.
    static let cornerReach: CGFloat = 28

    private enum Zone {
        case bottomLeft
        case bottom
        case bottomRight

        var cursor: NSCursor {
            switch self {
            case .bottomLeft: .frameResize(position: .bottomLeft, directions: .all)
            case .bottom: .frameResize(position: .bottom, directions: .all)
            case .bottomRight: .frameResize(position: .bottomRight, directions: .all)
            }
        }

        /// How many rungs a pull of `pull` from the drag's start amounts to,
        /// along whichever axis it has moved the shape's edge farthest. A
        /// bottom corner counts down and out; the bottom edge only down.
        /// Screen coordinates, so a pull down is a negative dy.
        func rungs(for pull: CGVector) -> Int {
            let down = -pull.dy / ExpandedSizeLadder.heightStep
            let out: CGFloat
            switch self {
            case .bottomLeft: out = -pull.dx / ExpandedSizeLadder.sideStep
            case .bottom: out = 0
            case .bottomRight: out = pull.dx / ExpandedSizeLadder.sideStep
            }
            let farthest = abs(out) > abs(down) ? out : down
            return Int(farthest.rounded())
        }
    }

    private struct Drag {
        let zone: Zone
        /// Where the pointer was on screen, and which rung the shape was on.
        let start: NSPoint
        let startStep: Int
    }

    private var drag: Drag?

    /// Only the zones take clicks; the rest of the view is the room above
    /// the bottom margin that the corner zones reach up into.
    override func hitTest(_ point: NSPoint) -> NSView? {
        zone(at: convert(point, from: superview)) == nil ? nil : self
    }

    /// A drag should start on the first click, even while another app has
    /// the keyboard and the notch stays open pinned.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        for rect in zoneRects {
            addTrackingArea(NSTrackingArea(rect: rect,
                                           options: [.cursorUpdate, .activeAlways],
                                           owner: self,
                                           userInfo: nil))
        }
    }

    /// The zones as rectangles, one tracking area each: the bottom margin
    /// in three parts, and the side margin up each corner. Split at the
    /// corners so that moving along the bottom into a corner enters a new
    /// area and the cursor changes with it.
    private var zoneRects: [NSRect] {
        let width = bounds.width
        let thickness = Self.thickness
        let reach = Self.cornerReach
        return [
            NSRect(x: 0, y: 0, width: reach, height: thickness),
            NSRect(x: reach, y: 0, width: width - reach * 2, height: thickness),
            NSRect(x: width - reach, y: 0, width: reach, height: thickness),
            NSRect(x: 0, y: 0, width: thickness, height: reach),
            NSRect(x: width - thickness, y: 0, width: thickness, height: reach),
        ]
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let zone = zone(at: convert(event.locationInWindow, from: nil)) else {
            super.cursorUpdate(with: event)
            return
        }
        zone.cursor.set()
    }

    // MARK: - Drag

    override func mouseDown(with event: NSEvent) {
        guard let zone = zone(at: convert(event.locationInWindow, from: nil)) else { return }
        drag = Drag(zone: zone, start: NSEvent.mouseLocation, startStep: currentStep?() ?? 0)
        // Keeps the resize cursor while the pointer runs past the zone,
        // which every pull does: the shape only follows rung by rung.
        zone.cursor.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        // The pointer's place on screen, not in the window: the panel's
        // frame moves under the pointer with every rung.
        let pointer = NSEvent.mouseLocation
        let pull = CGVector(dx: pointer.x - drag.start.x, dy: pointer.y - drag.start.y)
        onDrag?(drag.startStep + drag.zone.rungs(for: pull))
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        NSCursor.pop()
    }

    /// Which zone `point` (in this view's coordinates) is in, if any. The
    /// view sits on the shape's bottom edge, so y counts up from it.
    private func zone(at point: NSPoint) -> Zone? {
        guard bounds.contains(point) else { return nil }
        let fromLeft = point.x
        let fromRight = bounds.width - point.x
        let onBottomMargin = point.y <= Self.thickness
        if fromLeft <= Self.cornerReach, onBottomMargin || fromLeft <= Self.thickness {
            return .bottomLeft
        }
        if fromRight <= Self.cornerReach, onBottomMargin || fromRight <= Self.thickness {
            return .bottomRight
        }
        return onBottomMargin ? .bottom : nil
    }
}

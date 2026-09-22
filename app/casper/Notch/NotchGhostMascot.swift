//
//  NotchGhostMascot.swift
//
//  The ghost from MenuBarIcon.svg, drawn as a path so the eyes can move.
//  Same geometry as the SVG in its 70 by 70 box: a dome, three bumps along
//  the bottom, and two eye holes. The holes need an even-odd fill.
//

import SwiftUI

nonisolated struct NotchGhostMascot: Shape {
    /// Where the eyes look: -1 is left, as in the icon; 1 is right.
    var gaze: CGFloat

    var animatableData: CGFloat {
        get { gaze }
        set { gaze = newValue }
    }

    /// The box the SVG draws in.
    private static let box: CGFloat = 70
    /// Each eye's center sits this far from the body's center line when the
    /// eyes look straight ahead...
    private static let eyeSpacing: CGFloat = 12
    /// ...and travels this far to either side.
    private static let eyeTravel: CGFloat = 5
    private static let eyeRadius: CGFloat = 4.25
    /// Centers of an eye's top and bottom caps.
    private static let eyeTop: CGFloat = 27.5
    private static let eyeBottom: CGFloat = 33.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Dome from the left shoulder over the top to the right shoulder.
        path.move(to: CGPoint(x: 5, y: 30))
        path.addArc(center: CGPoint(x: 35, y: 30), radius: 30,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: 65, y: 60))
        // Three bumps along the bottom, right to left.
        for centerX: CGFloat in [55, 35, 15] {
            path.addArc(center: CGPoint(x: centerX, y: 60), radius: 10,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        path.closeSubpath()

        let shift = gaze * Self.eyeTravel
        for centerX in [35 - Self.eyeSpacing + shift, 35 + Self.eyeSpacing + shift] {
            path.addPath(Self.eye(centerX: centerX))
        }

        // Fit the box in the rect, centered, as the SVG is when drawn.
        let scale = min(rect.width, rect.height) / Self.box
        let offset = CGPoint(x: rect.minX + (rect.width - Self.box * scale) / 2,
                             y: rect.minY + (rect.height - Self.box * scale) / 2)
        return path.applying(CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale))
    }

    /// A stadium: two half circles joined by straight sides.
    private static func eye(centerX: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centerX - eyeRadius, y: eyeTop))
        path.addArc(center: CGPoint(x: centerX, y: eyeTop), radius: eyeRadius,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: centerX + eyeRadius, y: eyeBottom))
        path.addArc(center: CGPoint(x: centerX, y: eyeBottom), radius: eyeRadius,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

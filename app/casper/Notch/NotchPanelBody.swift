//
//  NotchPanelBody.swift
//

import SwiftUI

struct NotchPanelBody: View {
    @EnvironmentObject private var controller: AppRootController

    static let borderColor = Color.white.opacity(0.3)
    static let borderWidth: CGFloat = 1

    var body: some View {
        let size = controller.isExpanded ? controller.expandedSize : controller.collapsedSize
        let topRadius: CGFloat = controller.isExpanded ? NotchShape.maxTopCornerRadius : 10
        let bottomRadius: CGFloat = controller.isExpanded ? 22 : 12

        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(.black)
                .frame(width: size.width, height: size.height)
                // Restrict hit-testing to the visible shape so the transparent
                // rest of the panel doesn't swallow clicks.
                .contentShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))

            // Hairline along the ears, sides and bottom. The top edge is skipped:
            // it sits flush with the screen edge, and a line there would show
            // across the menu bar either side of the hardware notch. Drawn from
            // the same radii and frame as the fill so both ride the same spring.
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, includesTopEdge: false)
                .strokeBorder(Self.borderColor, lineWidth: Self.borderWidth)
                .frame(width: size.width, height: size.height)
                .opacity(controller.isExpanded ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        // Same spring as the terminal's reveal mask. Window frame never animates.
        .animation(NotchSpring.swiftUI, value: controller.isExpanded)
    }
}


/// Notch cutout flush against the top of the screen: rounded bottom corners, and top
/// corners that flare outward into the menu bar ("ears"). The ears are drawn *outside*
/// `rect` so the body of the shape stays aligned with the physical notch.
struct NotchShape: InsettableShape {
    var topCornerRadius: CGFloat = 10
    var bottomCornerRadius: CGFloat = 12
    /// `false` leaves the path open between the two ear tips, for stroking an
    /// outline without a line along the screen edge.
    var includesTopEdge = true
    var insetAmount: CGFloat = 0

    /// Largest ear radius used anywhere; the panel frame reserves this much slack
    /// on each side so the ears never get clipped by the window edge.
    static let maxTopCornerRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - topCornerRadius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + topCornerRadius),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomCornerRadius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topCornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + topCornerRadius, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        if includesTopEdge {
            path.closeSubpath()
        }
        return path
    }
}

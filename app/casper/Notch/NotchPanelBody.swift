//
//  NotchPanelBody.swift
//

import SwiftUI

struct NotchPanelBody: View {
    @EnvironmentObject private var controller: AppRootController

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
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 10
    var bottomCornerRadius: CGFloat = 12

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

    func path(in rect: CGRect) -> Path {
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
        path.closeSubpath()
        return path
    }
}

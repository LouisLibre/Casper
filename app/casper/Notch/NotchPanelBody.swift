//
//  NotchPanelBody.swift
//

import SwiftUI

struct NotchPanelBody: View {
    @EnvironmentObject private var controller: AppRootController

    static let borderColor = Color.white.opacity(0.3)
    static let borderWidth: CGFloat = 1

    /// The backdrop is darkened by a vertical black gradient: fully opaque over
    /// the band where the menu bar and hardware notch sit behind the panel,
    /// then easing out to the tint alone. The collapsed shape never grows
    /// past that band, so the pill stays solid black without special-casing.
    static let fadeHeight: CGFloat = 56
    /// All of the terminal's darkness lives here: the surface itself renders
    /// with a fully transparent background (see defaults.ghostty), so the
    /// backdrop reads as one sheet with no inner frame around the terminal.
    static let backdropTint = Color.black.opacity(0.6)
    /// With transparency off the tint goes solid, hiding the frosted backdrop
    /// so the shape reads as flat black.
    static let opaqueTint = Color.black

    /// Shape of the darkening under the band. `.u` lights the bottom center
    /// and darkens toward the top corners and sides; `.o` lights the middle
    /// and darkens toward every edge; `.none` leaves only the band and tint.
    /// The band stays at menu bar height; the vignette supplies the rest.
    enum Vignette { case none, u, o }
    static let vignette: Vignette = .u
    /// Darkest alpha the vignette reaches at the far edge.
    static let vignetteStrength = 0.95
    /// Fraction of the reach that stays untouched around the light spot.
    static let vignetteInner: CGFloat = 0.2
    /// How far the falloff extends, as a fraction of the shape's size. Above 1
    /// the far corners never reach full strength; below 1 the edges clip.
    static let vignetteReach: CGFloat = 1.1

    var body: some View {
        let size = controller.isExpanded ? controller.expandedSize : controller.collapsedSize
        let topRadius: CGFloat = controller.isExpanded ? NotchShape.maxTopCornerRadius : 10
        let bottomRadius: CGFloat = controller.isExpanded ? 22 : 12
        let shape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)

        ZStack(alignment: .top) {
            
            // Uncomment for actual transparency
            //Color.init(red: 0.175, green: 0.175, blue: 0.175, opacity: 1)
            NotchBackdrop()
                .notchSized(CGSize(width: size.width + NotchShape.maxTopCornerRadius * 2, height: size.height),
                            expanding: controller.isExpanded)
                .mask { shape.notchSized(size, expanding: controller.isExpanded) }
                .overlay { shape.fill(Self.backdropTint).notchSized(size, expanding: controller.isExpanded) }
                .overlay {
                    shape.fill(Self.opaqueTint)
                        .notchSized(size, expanding: controller.isExpanded)
                        .opacity(controller.isTerminalTransparent ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: controller.isTerminalTransparent)
                }
                .allowsHitTesting(false)

            if let vignette = Self.vignetteGradient(Self.vignette) {
                shape
                    .fill(vignette)
                    .notchSized(size, expanding: controller.isExpanded)
                    .allowsHitTesting(false)
            }

            shape
                .fill(Self.topGradient(solid: controller.collapsedSize.height, height: size.height))
                .notchSized(size, expanding: controller.isExpanded)
                // Restrict hit-testing to the visible shape so the transparent
                // rest of the panel doesn't swallow clicks.
                .contentShape(shape)

            // Hairline along the ears, sides and bottom. The top edge is skipped:
            // it sits flush with the screen edge, and a line there would show
            // across the menu bar either side of the hardware notch. Drawn from
            // the same radii and frame as the fill so both ride the same spring.
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, includesTopEdge: false)
                .strokeBorder(Self.borderColor, lineWidth: Self.borderWidth)
                .notchSized(size, expanding: controller.isExpanded)
                .opacity(controller.isExpanded ? 1 : 0)
                .allowsHitTesting(false)

            // Floats in the band the panel reserves under the expanded shape.
            // Rises into place on the same spring as the shape; while
            // collapsed it is invisible and lets clicks through.
            NotchDock()
                .padding(.top, controller.expandedSize.height + NotchDock.topGap)
                .offset(y: controller.isExpanded ? 0 : -12)
                .opacity(controller.isExpanded ? 1 : 0)
                .allowsHitTesting(controller.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        // Same spring as the terminal's reveal mask. Window frame never
        // animates. `isExpanded` already holds the new value here, so it
        // names the direction this transition runs in. Widths and heights
        // are animated closer to the leaves by `notchSized`; this covers
        // everything else (radii, gradients, opacity).
        .animation(NotchSpring.swiftUI(expanding: controller.isExpanded), value: controller.isExpanded)
    }

    /// Opaque down to `solid` points from the top, then a smoothstep fade over
    /// `fadeHeight`. Stops are fractions of the current height so the band
    /// keeps its size in points while the shape springs between states.
    private static func topGradient(solid: CGFloat, height: CGFloat) -> LinearGradient {
        func alpha(_ y: CGFloat) -> Double {
            let t = min(max((y - solid) / fadeHeight, 0), 1)
            return 1 - Double(t * t * (3 - 2 * t))
        }
        // Never place a stop past the bottom edge: while collapsed the whole
        // shape sits inside the solid band, and stops beyond 1 would let the
        // last (transparent) one bleed into the bottom row.
        let start = min(solid, height)
        let end = min(solid + fadeHeight, height)
        let steps = 16
        var stops: [Gradient.Stop] = [.init(color: .black, location: 0)]
        for i in 0...steps {
            let y = start + (end - start) * CGFloat(i) / CGFloat(steps)
            stops.append(.init(color: .black.opacity(alpha(y)), location: y / height))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Clear around the light spot, then a smoothstep ramp to
    /// `vignetteStrength` at `vignetteReach`. Radii are fractions of the
    /// frame, so the ellipse keeps the shape's aspect through the spring.
    private static func vignetteGradient(_ style: Vignette) -> EllipticalGradient? {
        let center: UnitPoint
        switch style {
        case .none: return nil
        case .u: center = UnitPoint(x: 0.5, y: 1)
        case .o: center = .center
        }
        let steps = 8
        var stops: [Gradient.Stop] = [.init(color: .black.opacity(0), location: 0)]
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let eased = Double(t * t * (3 - 2 * t))
            stops.append(.init(color: .black.opacity(vignetteStrength * eased),
                               location: vignetteInner + (1 - vignetteInner) * t))
        }
        return EllipticalGradient(stops: stops, center: center,
                                  startRadiusFraction: 0, endRadiusFraction: vignetteReach)
    }
}


private extension View {
    /// `frame(width:height:)` with each axis on its own spring, so the two
    /// can collapse on different clocks. Innermost animation wins in SwiftUI,
    /// so these override the body-wide one for the frame alone.
    func notchSized(_ size: CGSize, expanding: Bool) -> some View {
        self
            .animation(NotchSpring.swiftUI(axis: .vertical, expanding: expanding)) {
                $0.frame(height: size.height)
            }
            .animation(NotchSpring.swiftUI(axis: .horizontal, expanding: expanding)) {
                $0.frame(width: size.width)
            }
    }
}

/// Frosted backdrop behind the shape and the dock. An NSVisualEffectView
/// rather than SwiftUI's glassEffect: glass follows the window's key status
/// and flattens the moment a click lands in another app, which happens on
/// every press outside the panel and on every drag that starts elsewhere and
/// ends on the terminal. `state = .active` pins the material regardless of
/// key status.
struct NotchBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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

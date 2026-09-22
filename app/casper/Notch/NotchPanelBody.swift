//
//  NotchPanelBody.swift
//

import SwiftUI

struct NotchPanelBody: View {
    @EnvironmentObject private var controller: AppRootController
    @ObservedObject private var terminalRuntime = GhosttyRuntime.shared

    enum Region { case body, band }
    var region: Region = .body

    static let borderColor = Color.white.opacity(0.3)
    static let borderWidth: CGFloat = 1
    /// Radius of the expanded shape's bottom corners. The size hints sit
    /// on the bottom-right one (see NotchSizeHints).
    static let expandedBottomCornerRadius: CGFloat = 22

    /// The backdrop is darkened by a vertical black gradient: fully opaque over
    /// the band where the menu bar and hardware notch sit behind the panel,
    /// then easing out to the tint alone. The collapsed shape only grows a
    /// few points past that band, under the pointer, where the fade has
    /// barely begun, so the pill stays solid black without special-casing.
    static let fadeHeight: CGFloat = 56
    /// How far the collapsed shape grows out each side and down while the
    /// pointer is over the pill, a hint that the strip takes clicks. The top
    /// edge is flush with the screen and stays put.
    static let hoverGrowth: CGFloat = 6
    /// The tint supplies the terminal's darkness while glass is on. The
    /// surface's clear background lets the panel supply either this glass
    /// or the theme's solid background, including the terminal's margins.
    static let backdropTint = Color.black.opacity(0.6)

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
        let size = controller.isExpanded ? controller.expandedSize : collapsedShapeSize
        let topRadius: CGFloat = controller.isExpanded ? NotchShape.maxTopCornerRadius : 10
        let bottomRadius: CGFloat = controller.isExpanded ? Self.expandedBottomCornerRadius : 12
        let shape = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
        let opaqueTint = controller.isShowingSettings ? Color.black : Color(nsColor: terminalRuntime.backgroundColor)

        ZStack(alignment: .top) {
            if region == .body {
                NotchBackdrop()
                    .notchSized(CGSize(width: size.width + NotchShape.maxTopCornerRadius * 2, height: size.height))
                    .mask { shape.notchSized(size) }
                    .overlay { shape.fill(Self.backdropTint).notchSized(size) }
                    .overlay {
                        shape.fill(opaqueTint)
                            .notchSized(size)
                            .opacity(controller.isTerminalTransparent ? 0 : 1)
                    }
                    .allowsHitTesting(false)

                // Both gradients are drawn once, at the expanded size, and
                // clipped by the animating shape. Filling the shape with them
                // directly re-rasterizes the gradients at every animated
                // size, which held the panel's SwiftUI frames to 25-40 per
                // second on expand (measured) while the terminal's Core
                // Animation mask ran at the display's full rate and overtook
                // the shape. Clipping also keeps the band `solid` points tall
                // throughout, which fractional stops only approximated.
                if let vignette = Self.vignetteGradient(Self.vignette) {
                    Rectangle()
                        .fill(vignette)
                        .notchSized(controller.expandedSize)
                        .mask(alignment: .top) { shape.notchSized(size) }
                        .opacity(controller.isTerminalTransparent ? 1 : 0)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(Self.topGradient(solid: controller.collapsedSize.height, height: controller.expandedSize.height))
                    .notchSized(controller.expandedSize)
                    .mask(alignment: .top) { shape.notchSized(size) }
                    .opacity(controller.isTerminalTransparent ? 1 : 0)
                    .allowsHitTesting(false)

                // Keep the hardware notch and its controls black in solid mode,
                // with a clean edge above the terminal instead of a dark fade
                // across the theme's background. Cover the hover swell too.
                shape
                    .fill(.black)
                    .notchSized(size)
                    .mask(alignment: .top) {
                        Rectangle().frame(width: size.width + NotchShape.maxTopCornerRadius * 2,
                                          height: controller.isExpanded ? controller.collapsedSize.height : size.height)
                    }
                    .opacity(controller.isTerminalTransparent ? 0 : 1)
                    .allowsHitTesting(false)
            } else {
                // The window clips this to the top strip. Use the very same
                // shape, size and springs as the body, including the pill's
                // hover swell, without another glass backdrop behind it.
                // Keep this fill hit-testable: disabling it makes the band's
                // black pixels click-through at the window level, before
                // AppKit can route the click to our band and button targets.
                shape.fill(.black).notchSized(size)
            }

            shape
                .fill(.clear)
                .notchSized(size)
                // Restrict hit-testing to the visible shape so the transparent
                // rest of the panel doesn't swallow clicks.
                .contentShape(shape)

            // The panes, inside the shape: `paneInset` in from its sides and
            // bottom, under the band. Clipped by the shape itself, inset a
            // few points so the clip's edge stays behind the shape's
            // anti-aliased edge (measured: the terminal edge then sits 2 to
            // 8 points inside the black on every frame of either
            // animation). Collapsed, the clip is the pill, entirely above
            // the pane, so nothing of it shows; the pill's hover swell is
            // left out so hovering cannot uncover a sliver of terminal.
            if region == .body {
                let inset = AppRootController.paneInset
                let clipSize = controller.isExpanded ? controller.expandedSize : controller.collapsedSize
                NotchPaneHostView()
                    .frame(width: controller.expandedSize.width - inset * 2,
                           height: controller.expandedSize.height - controller.collapsedSize.height - inset)
                    .padding(.top, controller.collapsedSize.height)
                    .mask(alignment: .top) { shape.inset(by: 3).notchSized(clipSize) }
                    .allowsHitTesting(controller.isExpanded)
            }

            // Hairline along the ears, sides and bottom. The top edge is skipped:
            // it sits flush with the screen edge, and a line there would show
            // across the menu bar either side of the hardware notch. Drawn from
            // the same radii and frame as the fill so both ride the same spring.
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius, includesTopEdge: false)
                .strokeBorder(Self.borderColor, lineWidth: Self.borderWidth)
                .notchSized(size)
                .opacity(controller.isExpanded ? 1 : 0)
                .allowsHitTesting(false)

            // Floats in the band the panel reserves under the expanded shape.
            // Rises into place on the same spring as the shape; while
            // collapsed it is invisible and lets clicks through.
            if region == .body {
                NotchDock()
                    .padding(.top, controller.expandedSize.height + NotchDock.topGap)
                    .offset(y: controller.isExpanded ? 0 : -12)
                    .opacity(controller.isExpanded ? 1 : 0)
                    .allowsHitTesting(controller.isExpanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .mask(alignment: .top) {
            // The two windows draw complementary slices, so translucent
            // edges aren't painted twice. The band host has the full body
            // size for identical layout, clipped by its thin window.
            if region == .body {
                VStack(spacing: 0) {
                    Color.clear.frame(height: controller.collapsedSize.height)
                    Color.white
                }
            } else {
                Color.white
            }
        }
        // Window frame never animates. `isExpanded` already holds the new
        // value here, so it names the direction this transition runs in.
        // Drives the frames set by `notchSized`, the clip on the panes, and
        // everything else (radii, gradients, opacity).
        .animation(NotchSpring.swiftUI(expanding: controller.isExpanded), value: controller.isExpanded)
        // The hover swell is neither an expand nor a collapse, so it runs on
        // its own spring. A value-keyed animation is needed: the scoped ones
        // in `notchSized` do not fire on their own for a change of size.
        .animation(NotchSpring.hover, value: controller.isPillHovered)
        .animation(.easeInOut(duration: 0.2), value: controller.isTerminalTransparent)
    }

    /// The collapsed shape, a little bigger under the pointer. The change
    /// of size rides `NotchSpring.hover`.
    private var collapsedShapeSize: CGSize {
        var size = controller.collapsedSize
        guard controller.isPillHovered else { return size }
        size.width += Self.hoverGrowth * 2
        size.height += Self.hoverGrowth
        return size
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
    /// The shape's frame. Animated by the body-wide `animation(_:value:)`
    /// on expand and collapse, both axes on the one spring (see
    /// `NotchSpring.swiftUI(expanding:)`).
    func notchSized(_ size: CGSize) -> some View {
        frame(width: size.width, height: size.height)
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
nonisolated struct NotchShape: InsettableShape {
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

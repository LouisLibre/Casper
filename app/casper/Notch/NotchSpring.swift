//
//  NotchSpring.swift
//
//  The one expand/collapse spring, expressed for both animation systems.
//  The SwiftUI shape and the Core Animation terminal mask must follow the
//  same curve or the terminal shows outside the black shape mid-animation.
//

import QuartzCore
import SwiftUI

enum NotchSpring {
    /// Which side of a size a spring drives. Own type rather than SwiftUI's
    /// `Axis` so the AppKit-only mask code can name it.
    enum Axis { case horizontal, vertical }

    /// Underdamped on expand: the slight overshoot reads as a lively snap
    /// against the large target.
    static let expandResponse: CGFloat = 0.32
    static let expandDampingFraction: CGFloat = 0.82
    /// Collapse runs a hair under critical damping: 0.9 keeps the overshoot
    /// under half a point (invisible) without the long tail of a critically
    /// damped spring.
    static let collapseDampingFraction: CGFloat = 0.9
    /// The two axes collapse on different clocks. Both travel a similar
    /// distance, but the last few points are a third of the pill's height
    /// and a sliver of its width, so on one clock the width looks finished
    /// while the height is still closing. Running the height faster than
    /// the width lands both at "done" together: the shape flattens first,
    /// then draws in to the pill.
    static let collapseWidthResponse: CGFloat = 0.30
    static let collapseHeightResponse: CGFloat = 0.18

    static func response(axis: Axis, expanding: Bool) -> CGFloat {
        guard !expanding else { return expandResponse }
        return axis == .horizontal ? collapseWidthResponse : collapseHeightResponse
    }

    static func dampingFraction(expanding: Bool) -> CGFloat {
        expanding ? expandDampingFraction : collapseDampingFraction
    }

    static func swiftUI(axis: Axis, expanding: Bool) -> Animation {
        .spring(response: response(axis: axis, expanding: expanding),
                dampingFraction: dampingFraction(expanding: expanding))
    }

    /// For values that are not a width or a height (corner radii, gradient
    /// stops, opacity). Rides the height clock so they settle with the
    /// last axis to finish.
    static func swiftUI(expanding: Bool) -> Animation {
        swiftUI(axis: .vertical, expanding: expanding)
    }

    /// The CA mask spring starts on the commit that schedules it, while SwiftUI
    /// samples its spring one display frame later — so an undelayed mask leads
    /// the shape and the terminal pokes out past the black edge on expand.
    /// Holding the reveal back one frame keeps the mask at or behind the shape;
    /// overshooting the true offset only hides the terminal edge deeper inside
    /// the black, so erring long is safe. The conceal must NOT be delayed: there
    /// the leading mask already trails *inside* the shape, and a delay would
    /// push it outside instead.
    static let revealStartDelay: CFTimeInterval = 1.0 / 60.0

    /// CASpringAnimation with the same physics as `swiftUI(axis:expanding:)`:
    /// mass 1, stiffness (2π/response)², damping 2·ζ·√stiffness.
    /// Matches exactly for animations that start from rest; a retarget
    /// mid-flight loses the carried velocity SwiftUI would preserve.
    static func caSpring(keyPath: String, from: NSValue, to: NSValue,
                         axis: Axis, expanding: Bool) -> CASpringAnimation {
        let omega = 2 * CGFloat.pi / response(axis: axis, expanding: expanding)
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = omega * omega
        spring.damping = 2 * dampingFraction(expanding: expanding) * omega
        spring.initialVelocity = 0
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }
}

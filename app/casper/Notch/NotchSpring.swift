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
    static let response: CGFloat = 0.32
    static let dampingFraction: CGFloat = 0.82

    static var swiftUI: Animation {
        .spring(response: response, dampingFraction: dampingFraction)
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

    /// CASpringAnimation with the same physics as `swiftUI`:
    /// mass 1, stiffness (2π/response)², damping 2·ζ·√stiffness.
    /// Matches exactly for animations that start from rest; a retarget
    /// mid-flight loses the carried velocity SwiftUI would preserve.
    static func caSpring(keyPath: String, from: NSValue, to: NSValue) -> CASpringAnimation {
        let omega = 2 * CGFloat.pi / response
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = omega * omega
        spring.damping = 2 * dampingFraction * omega
        spring.initialVelocity = 0
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }
}

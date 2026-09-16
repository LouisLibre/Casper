//
//  NotchSpring.swift
//
//  The one expand/collapse spring. The black shape and the clip on the
//  terminal ride it together, in the same SwiftUI transaction.
//

import SwiftUI

enum NotchSpring {
    /// Underdamped on expand: the slight overshoot reads as a lively snap
    /// against the large target.
    static let expandResponse: CGFloat = 0.32
    static let expandDampingFraction: CGFloat = 0.82
    /// Collapse runs a hair under critical damping: 0.9 keeps the overshoot
    /// under half a point (invisible) without the long tail of a critically
    /// damped spring.
    static let collapseResponse: CGFloat = 0.18
    static let collapseDampingFraction: CGFloat = 0.9

    /// One spring per direction, for both axes. Width and height were once
    /// given separate collapse clocks through scoped animations on each
    /// frame axis, but SwiftUI animates the shape's frame with the
    /// body-wide animation regardless (measured frame by frame on macOS 26:
    /// both edges follow the same curve).
    static func swiftUI(expanding: Bool) -> Animation {
        .spring(response: expanding ? expandResponse : collapseResponse,
                dampingFraction: expanding ? expandDampingFraction : collapseDampingFraction)
    }

    /// How long the collapse spring takes to come to rest. Work that must
    /// wait until the shape is the pill again (parking the panes, see
    /// NotchPaneHost.setParked) is scheduled after this.
    static var collapseSettlingDuration: Duration {
        .seconds(Spring(response: collapseResponse, dampingRatio: collapseDampingFraction).settlingDuration)
    }

    /// The pill's hover swell: the strip grows a little under the pointer,
    /// and the mascot in it looks right and grows too, all on this one
    /// spring. The mascot in the corner glances and shrinks on it as well.
    /// Soft, with a hint of bounce at the end.
    static let hover = Animation.spring(response: 0.4, dampingFraction: 0.7)
}

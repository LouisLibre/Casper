//
//  AppGeometryReader.swift
//

import AppKit

struct AppGeometryReader {
    let screen: NSScreen
    let notchSize: CGSize
    
    /// Used on external / non-notched displays so the overlay still has somewhere to live.
    static let fallbackSize = CGSize(width: 185, height: 32)

    /// Extra width on each side of the hardware notch. The camera housing occupies
    /// `notchSize`; this inset is the visible collapsed chrome and holds the click-affordance icon.
    static let collapsedSideInset: CGFloat = 32
    
    init(screen: NSScreen) {
        self.screen = screen
        
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                               height: top)
        } else {
            /// Size of the physical notch is `.zero` on displays without one.
            notchSize = .zero
        }
    }
    
    var hasNotch: Bool { notchSize.height > 0 }
    
    var collapsedSize: CGSize {
        let base = hasNotch ? notchSize : Self.fallbackSize
        return CGSize(width: base.width + Self.collapsedSideInset * 2, height: base.height + 1)
    }

    /// Screen with a real notch, falling back to whichever screen holds the menu bar.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
    
    /// Panel frame in global coordinates, top-centered on the screen.
    func frame(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2,
               y: screen.frame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    /// The panel is the expanded shape plus slack for its ears on each side
    /// and the band under it that holds the dock.
    static func panelSize(forExpanded size: CGSize) -> CGSize {
        CGSize(width: size.width + NotchShape.maxTopCornerRadius * 2,
               height: size.height + NotchDock.reserve)
    }

    /// Highest rung of the size ladder whose whole panel still fits this
    /// screen. Both axes are checked; whichever runs out first decides.
    var maxExpandedStep: Int {
        var step = ExpandedSizeLadder.minStep
        while step < ExpandedSizeLadder.maxStep {
            let next = Self.panelSize(forExpanded: ExpandedSizeLadder.size(at: step + 1))
            guard next.width <= screen.frame.width, next.height <= screen.frame.height else { break }
            step += 1
        }
        return step
    }
}

/// Sizes the expanded shape can take: 4:3 sizes stepped by a fixed width,
/// indexed from the 640x480 default. Only the index is stored; the size is
/// derived, so the ratio can never drift.
enum ExpandedSizeLadder {
    static let aspect: CGFloat = 4.0 / 3.0
    static let baseWidth: CGFloat = 640
    /// 80 wide is 60 tall at 4:3, so every rung lands on whole points.
    static let widthStep: CGFloat = 80
    /// 480x360. Below this an 80-column terminal wraps at the default font.
    static let minStep = -2
    /// Ceiling for the search in `maxExpandedStep`; screens clamp well before it.
    static let maxStep = 40

    static func size(at step: Int) -> CGSize {
        let width = baseWidth + widthStep * CGFloat(step)
        return CGSize(width: width, height: (width / aspect).rounded())
    }
}

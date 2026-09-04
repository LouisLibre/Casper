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
}

//
//  NotchPanelBand.swift
//
//  Click target for the band: the strip along the top of the expanded
//  shape that holds the corner buttons. A click anywhere in it collapses
//  the notch, as a click on the pill does while collapsed. It sits under
//  the pill and the corner controls, so those take their clicks first.
//  Hidden while collapsed, so it takes no clicks then.
//

import AppKit

final class NotchPanelBand: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClick?() }
}

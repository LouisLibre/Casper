//
//  NotchCornerControls.swift
//
//  Two small buttons in the top-right corner of the expanded shape: collapse
//  the notch, and quit the app (after confirming). They sit in the band above
//  the terminal, so the terminal view never covers them.
//

import SwiftUI

struct NotchCornerControls: View {
    @EnvironmentObject private var controller: AppRootController

    /// Distance from the shape's right edge.
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 8
    /// Same point size and weight as the pill's chevron so the three read as one set.
    static let symbolSize: CGFloat = 15
    static let symbolWeight: Font.Weight = .regular
    static let restingOpacity = 0.44
    static let hoverOpacity = 1.0

    var body: some View {
        HStack(spacing: Self.spacing) {
            CornerButton(symbol: "chevron.up.circle.fill", label: "Collapse") {
                controller.collapse()
            }
            CornerButton(symbol: "x.circle.fill", label: "Quit Casper") {
                controller.confirmQuit()
            }
        }
        .padding(.trailing, Self.padding)
    }

    private struct CornerButton: View {
        let symbol: String
        let label: String
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: NotchCornerControls.symbolSize, weight: NotchCornerControls.symbolWeight))
                    .foregroundStyle(.white.opacity(hovering ? NotchCornerControls.hoverOpacity
                                                             : NotchCornerControls.restingOpacity))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(label)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

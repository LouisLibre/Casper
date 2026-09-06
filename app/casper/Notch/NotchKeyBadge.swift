//
//  NotchKeyBadge.swift
//
//  Small capsule reading ⌘ and a key, shown while ⌘ is held: over the
//  corner of a dock control's icon, on an end of the tab capsule, or under
//  a corner control. The same solid gray as the dock's chevron slots, with
//  the same hairline as the expanded shape.
//

import SwiftUI

struct KeyBadge: View {
    let key: String

    /// Brackets are thin and short at the badge's size, so they get a
    /// heavier, larger glyph and a little room after the ⌘.
    private var isBracket: Bool { key == "[" || key == "]" }

    var body: some View {
        HStack(spacing: isBracket ? 2 : 0) {
            Text("⌘")
                .font(.system(size: 9, weight: .medium, design: .rounded))
            Text(key)
                .font(isBracket ? .system(size: 12, weight: .medium, design: .rounded)
                                : .system(size: 9, weight: .medium, design: .rounded))
        }
        .foregroundStyle(NotchDock.iconOn)
        .padding(.trailing, 6)
        .padding(.leading, 8)
        .padding(.top, 2.33)
        .padding(.bottom, 3)
        .background { Capsule().fill(NotchDock.slotFill) }
        .overlay { Capsule().strokeBorder(NotchPanelBody.borderColor, lineWidth: NotchPanelBody.borderWidth) }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

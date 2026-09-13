//
//  NotchKeyBadge.swift
//
//  Small capsule reading ⌘ and a key, shown while ⌘ is held: over the
//  corner of a dock control's icon, on an end of the tab capsule, or under
//  a corner control. Or a bare chord such as ⌃⌥, with no ⌘ before it. The
//  same solid gray as the dock's chevron slots, with the same hairline as
//  the expanded shape.
//

import SwiftUI

struct KeyBadge: View {
    /// Shown before the key. Empty for a badge that reads a bare chord.
    var modifiers = "⌘"
    let key: String

    /// Brackets are thin and short at the badge's size, so they get a
    /// heavier, larger glyph and a little room after the ⌘.
    private var isBracket: Bool { key == "[" || key == "]" }

    var body: some View {
        HStack(spacing: isBracket ? 2 : 0) {
            Text(modifiers)
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
        .keyBadgeCapsule()
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

/// A taller badge for the size shortcuts, on the bottom-right corner of
/// the expanded shape (see NotchSizeHints): a symbol showing which way
/// the corner moves, over the ⌘⇧ chord that moves it. Same capsule as
/// KeyBadge, stood on end to hold both.
struct SizeKeyBadge: View {
    let symbol: String
    let key: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            HStack(spacing: 1) {
                Text("⌘⇧")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                // Plus and minus are small at 9 points, as the brackets are.
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .foregroundStyle(NotchDock.iconOn)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .keyBadgeCapsule()
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

private extension View {
    /// The capsule every badge wears: the dock's slot gray with the
    /// expanded shape's hairline.
    func keyBadgeCapsule() -> some View {
        self
            .background { Capsule().fill(NotchDock.slotFill) }
            .overlay { Capsule().strokeBorder(NotchPanelBody.borderColor, lineWidth: NotchPanelBody.borderWidth) }
    }
}

import SwiftUI
import UIKit

/// System-harmonized semantic surfaces and tokens for native iOS presentation.
enum NativeTheme {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = adaptive(light: 0xFFFFFF, dark: 0x242529)
    static let composer = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let userBubble = adaptive(light: 0xE8F0FE, dark: 0x182B49)
    static let guidanceBubble = adaptive(light: 0xEEF4FF, dark: 0x17253B)
    static let border = Color(uiColor: .separator).opacity(0.32)
    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let accent = adaptive(light: 0x0066EE, dark: 0x4C9AFF)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x071830)
    static let inactiveControl = Color(uiColor: .tertiarySystemFill)
    static let inactiveSymbol = Color(uiColor: .tertiaryLabel)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

import SwiftUI
import UIKit

/// Shrinkly design tokens. Dark only: deep graphite-teal ink, ivory text, "glacier" mint for everything that got smaller
/// and champagne for the one action that matters on each screen.
enum SK {
    enum Palette {
        /// App background.
        static let ink      = Color(hex: 0x0C1519)
        /// First surface above the background.
        static let surface  = Color(hex: 0x14232A)
        /// Raised surface (selected rows, pressed buttons).
        static let raised   = Color(hex: 0x1D3038)
        /// Hairline rules and outlines.
        static let line     = Color.white.opacity(0.10)
        /// Primary text.
        static let ivory    = Color(hex: 0xF2EEE4)
        /// Secondary text (about 7:1 on `ink`).
        static let mist     = Color(hex: 0x9DB0B7)
        /// Saved / smaller / success.
        static let glacier  = Color(hex: 0x7FE3CF)
        /// Primary action.
        static let champagne = Color(hex: 0xE6C98B)
        static let champagneDeep = Color(hex: 0xC9A765)
        /// Text and icons on champagne.
        static let onChampagne = Color(hex: 0x1A1409)
        static let danger   = Color(hex: 0xF0948A)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let control: CGFloat = 14
        static let card: CGFloat = 22
    }

    /// Widest readable column on iPad and in landscape.
    static let readableWidth: CGFloat = 640

    enum Font {
        private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
            min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * 1.5)
        }
        /// Large editorial numerals and headlines (New York).
        static func display(_ size: CGFloat = 40) -> SwiftUI.Font {
            .system(size: scaled(size, .largeTitle), weight: .regular, design: .serif)
        }
        static func title(_ size: CGFloat = 24) -> SwiftUI.Font {
            .system(size: scaled(size, .title2), weight: .medium, design: .serif)
        }
        static let headline = SwiftUI.Font.system(.headline, design: .default).weight(.semibold)
        static let body = SwiftUI.Font.system(.body, design: .default)
        static let callout = SwiftUI.Font.system(.callout, design: .default)
        static let label = SwiftUI.Font.system(.footnote, design: .default).weight(.medium)
        static let caption = SwiftUI.Font.system(.caption, design: .default)
        static let number = SwiftUI.Font.system(.callout, design: .rounded).monospacedDigit().weight(.medium)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// Full-screen background in the app's base colour.
    func skScreen() -> some View {
        background(SK.Palette.ink.ignoresSafeArea())
    }

    /// Centres content in a readable column (iPad, landscape) without stretching it edge to edge.
    func skReadable(maxWidth: CGFloat = SK.readableWidth) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

/// Appearance for system bars, set once at launch.
enum SKAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xF2EEE4)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(hex: 0xF2EEE4)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(hex: 0xE6C98B)
    }
}

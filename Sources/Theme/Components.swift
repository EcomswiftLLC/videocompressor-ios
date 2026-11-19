import SwiftUI
import UIKit

// MARK: - Buttons

enum SKButtonKind { case primary, secondary, quiet }

struct SKButtonStyle: ButtonStyle {
    var kind: SKButtonKind = .primary
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SK.Font.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, SK.Space.l)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: SK.Radius.control, style: .continuous)
                    .strokeBorder(kind == .secondary ? SK.Palette.ivory.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SK.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return SK.Palette.onChampagne
        case .secondary: return SK.Palette.ivory
        case .quiet: return SK.Palette.champagne
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [SK.Palette.champagne, SK.Palette.champagneDeep.opacity(pressed ? 1 : 0.94)],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary:
            if pressed { SK.Palette.raised } else { Color.clear }
        case .quiet:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == SKButtonStyle {
    static var skPrimary: SKButtonStyle { SKButtonStyle(kind: .primary) }
    static var skPrimaryWide: SKButtonStyle { SKButtonStyle(kind: .primary, fullWidth: true) }
    static var skSecondary: SKButtonStyle { SKButtonStyle(kind: .secondary) }
    static var skSecondaryWide: SKButtonStyle { SKButtonStyle(kind: .secondary, fullWidth: true) }
    static var skQuiet: SKButtonStyle { SKButtonStyle(kind: .quiet) }
}

// MARK: - Structure

struct SKHairline: View {
    var body: some View {
        Rectangle().fill(SK.Palette.line).frame(height: 1 / UIScreen.main.scale)
    }
}

struct SKSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(SK.Font.title(22))
            .foregroundStyle(SK.Palette.ivory)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A grouped surface. One radius, one fill: hierarchy comes from spacing and type, not from nesting cards.
struct SKCard<Content: View>: View {
    var padding: CGFloat = SK.Space.m
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SK.Palette.surface, in: RoundedRectangle(cornerRadius: SK.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SK.Radius.card, style: .continuous)
                    .strokeBorder(SK.Palette.line, lineWidth: 1)
            )
    }
}

/// Small pill used for format and state facts ("HEVC", "HDR", "1080p").
struct SKChip: View {
    let text: String
    var tint: Color = SK.Palette.mist
    var body: some View {
        Text(text)
            .font(SK.Font.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: SK.Radius.chip, style: .continuous))
    }
}

/// A selectable option (preset, resolution, codec). Selected state is shown with colour AND a check, never colour alone.
struct SKOptionChip: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).imageScale(.medium)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(SK.Font.label).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(SK.Font.caption).foregroundStyle(selected ? SK.Palette.glacier : SK.Palette.mist).lineLimit(1)
                    }
                }
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(SK.Palette.glacier)
                }
            }
            .foregroundStyle(SK.Palette.ivory)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(selected ? SK.Palette.raised : SK.Palette.surface, in: RoundedRectangle(cornerRadius: SK.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SK.Radius.control, style: .continuous)
                    .strokeBorder(selected ? SK.Palette.glacier.opacity(0.7) : SK.Palette.line, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The signature element: the original size as a long bar, the new size as a short one, and the saving between them.
struct SKSizeBars: View {
    let before: Int64
    let after: Int64
    var body: some View {
        let ratio = before > 0 ? max(0.02, min(1, Double(after) / Double(before))) : 1
        VStack(alignment: .leading, spacing: 10) {
            bar(label: "Original", value: ByteFormat.string(before), fraction: 1, color: SK.Palette.mist.opacity(0.55))
            bar(label: "Now", value: ByteFormat.string(after), fraction: ratio, color: SK.Palette.glacier)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Original \(ByteFormat.string(before)), now \(ByteFormat.string(after))"))
    }

    private func bar(label: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                Spacer()
                Text(value).font(SK.Font.number).foregroundStyle(SK.Palette.ivory)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.Palette.surface)
                    Capsule().fill(color).frame(width: max(8, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
        }
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        f.includesUnit = true
        return f.string(fromByteCount: bytes)
    }

    static func megabytes(_ bytes: Int64) -> Double { Double(bytes) / 1_000_000 }
}

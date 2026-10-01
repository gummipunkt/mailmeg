import AppKit
import MailmegKit
import SwiftUI

enum Theme {
    static let cardRadius: CGFloat = 12
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)

    static let avatarPalette: [(Color, Color)] = [
        (Color(hex: "#5B8CFF"), Color(hex: "#3550E0")),
        (Color(hex: "#B07CFF"), Color(hex: "#7A45E0")),
        (Color(hex: "#FF8FB1"), Color(hex: "#E0457B")),
        (Color(hex: "#FFB86B"), Color(hex: "#F07A2A")),
        (Color(hex: "#4FD1C5"), Color(hex: "#1A9E95")),
        (Color(hex: "#7BD88F"), Color(hex: "#2FA44F")),
        (Color(hex: "#8E9BFF"), Color(hex: "#5560D6")),
        (Color(hex: "#F6C453"), Color(hex: "#D69A12")),
    ]
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Round avatar with initials and a stable colour per name.
struct AvatarView: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let colors = Theme.avatarPalette[Self.hash(name) % Theme.avatarPalette.count]
        Circle()
            .fill(LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" })
            .filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    private static func hash(_ string: String) -> Int {
        string.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7FFF_FFFF }
    }
}

/// Small coloured capsule for a Gmail label.
struct LabelChip: View {
    let label: GmailLabel

    var body: some View {
        let color = label.color?.backgroundColor.map(Color.init(hex:)) ?? .secondary
        Text(label.name.components(separatedBy: "/").last ?? label.name)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Borderless icon button used for hover and header actions.
struct IconButton: View {
    let systemImage: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

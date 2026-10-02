import AppKit
import MailmegKit
import SwiftUI

/// The app's colour palette: https://colorkit.co/palette/dfe2fe-b1cbfa-8e98f5-7971ea/
enum Palette {
    static let mist = Color(hex: "#DFE2FE")
    static let sky = Color(hex: "#B1CBFA")
    static let periwinkle = Color(hex: "#8E98F5")
    static let violet = Color(hex: "#7971EA")
}

enum Theme {
    static let cardRadius: CGFloat = 12

    /// Sidebar background: the lightest palette tone.
    static let sidebar = Color(light: "#E3E6FE", dark: "#1A1B2F")
    /// Message list background.
    static let listBackground = Color(light: "#FAFAFF", dark: "#1D1E34")
    /// Background behind conversation cards.
    static let canvas = Color(light: "#EEF0FE", dark: "#15162A")
    /// Cards, text fields.
    static let cardFill = Color(light: "#FFFFFF", dark: "#25263F")
    /// Subtle fills: chips, counters, banners.
    static let tint = Color(light: "#DFE2FE", dark: "#2F3058")
    /// Lines and outlines.
    static let hairline = Color(light: "#B1CBFA", dark: "#3A3C6B")

    /// Avatar styles built from the palette: gradient top, bottom and text colour.
    static let avatarStyles: [(Color, Color, Color)] = [
        (Palette.periwinkle, Palette.violet, .white),
        (Palette.sky, Palette.periwinkle, Color(hex: "#2E2A7A")),
        (Palette.violet, Color(hex: "#5A51D6"), .white),
        (Palette.mist, Palette.sky, Color(hex: "#4A44B8")),
        (Color(hex: "#A3B4F8"), Palette.violet, .white),
        (Palette.sky, Palette.violet, .white),
    ]
}

extension Color {
    /// A colour that adapts to light and dark appearance.
    init(light: String, dark: String) {
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }

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
        let style = Theme.avatarStyles[Self.hash(name) % Theme.avatarStyles.count]
        Circle()
            .fill(LinearGradient(colors: [style.0, style.1], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.2)
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
        let color = label.color?.backgroundColor.map(Color.init(hex:)) ?? Palette.violet
        Text(label.name.components(separatedBy: "/").last ?? label.name)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Gmail's "Important" marker, styled like a label chip.
struct ImportantChip: View {
    private static let color = Color(hex: "#E8A200")

    var body: some View {
        Label(tr("Wichtig", "Important"), systemImage: "bookmark.fill")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10.5, weight: .medium))
            .imageScale(.small)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(Self.color)
            .background(Self.color.opacity(0.15), in: Capsule())
            .help(tr("Von Gmail als wichtig markiert", "Marked important by Gmail"))
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.45))
            )
            .shadow(color: Palette.violet.opacity(0.10), radius: 10, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Paints `color` behind the view *and* the window toolbar above it, so the toolbar
    /// takes the colour of the column below instead of the system grey.
    func themedWindowBackground(_ color: Color) -> some View {
        modifier(ToolbarBandModifier(background: color))
    }
}

struct ToolbarBandModifier<Background: View>: ViewModifier {
    let background: Background

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                // Covers content that scrolls up underneath the transparent toolbar.
                .overlay(alignment: .top) {
                    background
                        .frame(height: proxy.safeAreaInsets.top)
                        .offset(y: -proxy.safeAreaInsets.top)
                        .allowsHitTesting(false)
                }
        }
        .background(background.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

// MARK: - Glass (Airmail-style translucent surfaces)

/// AppKit vibrancy: blurs whatever is behind the window (the desktop).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Frosted surfaces for the three columns, lightly tinted with the palette.
enum GlassStyle {
    case sidebar, list, canvas

    @ViewBuilder
    var background: some View {
        switch self {
        case .sidebar:
            ZStack {
                VisualEffectView(material: .sidebar)
                Theme.sidebar.opacity(0.55)
            }
        case .list:
            ZStack {
                VisualEffectView(material: .menu)
                Theme.listBackground.opacity(0.6)
            }
        case .canvas:
            ZStack {
                VisualEffectView(material: .underWindowBackground)
                Theme.canvas.opacity(0.62)
            }
        }
    }
}

extension View {
    /// Frosted glass behind the view and the toolbar above it.
    func glassBackground(_ style: GlassStyle) -> some View {
        modifier(ToolbarBandModifier(background: style.background))
    }
}

/// Round frosted button, as in Airmail's toolbar.
struct GlassCircleButton: View {
    let systemImage: String
    let help: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCircleLabel(systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GlassCircleLabel: View {
    let systemImage: String
    var isActive = false
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.8))
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: Circle())
            .background(Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0.05)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .contentShape(Circle())
            .onHover { isHovering = $0 }
    }
}

/// A round glass button that opens a menu.
struct GlassCircleMenu<Content: View>: View {
    let systemImage: String
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            GlassCircleLabel(systemImage: systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .help(help)
        .accessibilityLabel(help)
    }
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

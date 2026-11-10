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
    static let cardRadius: CGFloat = 14

    /// Sidebar background: a breath of the lightest palette tone over the desktop blur.
    static let sidebar = Color(light: "#E9EBFB", dark: "#16172A")
    /// Message list background.
    static let listBackground = Color(light: "#FFFFFF", dark: "#1A1B2E")
    /// Background behind conversation cards.
    static let canvas = Color(light: "#F3F4FB", dark: "#121324")
    /// Cards, text fields.
    static let cardFill = Color(light: "#FFFFFF", dark: "#212238")
    /// Subtle fills: chips, counters, banners.
    static let tint = Color(light: "#E9EBFD", dark: "#2B2C4E")
    /// Lines and outlines.
    static let hairline = Color(light: "#D5D9F0", dark: "#34365C")
    /// The barely visible edge of cards.
    static let cardStroke = Color(light: "#E7E9F5", dark: "#2C2D49")
    /// Fill of the selected row in lists.
    static let selection = Color(light: "#E4E6FD", dark: "#34366A")

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
    /// The person's address: its domain's website icon is shown when there is one.
    var email: String? = nil
    var size: CGFloat = 32
    @AppStorage(AppSettings.faviconAvatarsKey) private var usesWebsiteIcons = true

    var body: some View {
        if usesWebsiteIcons, let icon = FaviconStore.shared.image(forAddress: email) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.62, height: size * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                .frame(width: size, height: size)
                .background(Color.white, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline.opacity(0.8), lineWidth: 0.8))
                .accessibilityHidden(true)
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        let style = Theme.avatarStyles[Self.hash(name) % Theme.avatarStyles.count]
        return Circle()
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
                    .strokeBorder(Theme.cardStroke)
            )
            .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
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
                Theme.sidebar.opacity(0.5)
            }
        case .list:
            ZStack {
                VisualEffectView(material: .menu)
                Theme.listBackground.opacity(0.86)
            }
        case .canvas:
            ZStack {
                VisualEffectView(material: .underWindowBackground)
                Theme.canvas.opacity(0.82)
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

extension View {
    /// Frosted backing for bars that float above scrolling content (list header, action bar),
    /// so rows passing underneath are blurred instead of mixing with the controls.
    func frostedBar(tint: Color) -> some View {
        background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                tint.opacity(0.55)
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
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
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.78))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0.06)))
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
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

/// Capsule switch between a few options, in the app's glass style.
struct PillSwitch<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let systemImage: String?
        let identifier: String
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = option.value }
                } label: {
                    Group {
                        if let systemImage = option.systemImage {
                            Label(option.title, systemImage: systemImage)
                        } else {
                            Text(option.title)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.cardFill)
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(option.identifier)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }
}

/// Small capsule button with text, matching the round glass buttons.
struct GlassCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var isProminent = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isProminent ? Color.white : Color.primary.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if isProminent {
                    Capsule().fill(LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom))
                } else {
                    Capsule().fill(Color.primary.opacity(isHovering ? 0.12 : 0.06))
                }
            }
            .shadow(color: isProminent ? Palette.violet.opacity(0.3) : .clear, radius: 5, y: 2)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grouped toolbar controls

/// Several toolbar buttons sharing one capsule, like the grouped controls of current macOS.
struct ToolbarGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 1) {
            content()
        }
        .padding(.horizontal, 3)
        .frame(height: 32)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// The face of a button inside a `ToolbarGroup`.
struct ToolbarIconLabel: View {
    let systemImage: String
    var isActive = false
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.78))
            .frame(width: 34, height: 26)
            .background(Capsule().fill(Color.primary.opacity(isHovering ? 0.1 : 0)))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarIconLabel(systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A button inside a `ToolbarGroup` that opens a menu.
struct ToolbarIconMenu<Content: View>: View {
    let systemImage: String
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            ToolbarIconLabel(systemImage: systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Soft list selection

/// Turns off a list's own (solid) selection highlight, so its rows can draw a softer one.
/// Put it into the background of a row.
struct ListHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view {
                if let table = current as? NSTableView {
                    if table.selectionHighlightStyle != .none {
                        table.selectionHighlightStyle = .none
                    }
                    return
                }
                view = current.superview
            }
        }
    }
}

// MARK: - Windows

/// Keeps a window out of macOS' window restoration. A compose window reopened after a
/// restart would show the message as it was when the window first opened, not what was
/// written since – that is in Gmail's drafts.
struct NonRestorableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isRestorable = false
        }
    }
}

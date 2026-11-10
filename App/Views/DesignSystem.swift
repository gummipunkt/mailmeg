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
    static let cardRadius: CGFloat = 18

    /// The pastel backdrop behind everything: lilac at the top, sky in the middle, a blush
    /// of pink at the bottom. It only changes from top to bottom, so the columns of the
    /// window line up without a seam.
    static let backdropTop = Color(light: "#EDE6FF", dark: "#1D1936")
    static let backdropMiddle = Color(light: "#E5EAFF", dark: "#181733")
    static let backdropBottom = Color(light: "#F9E6F2", dark: "#221735")

    /// Sidebar, list and canvas all sit on the backdrop; these are its top tone.
    static let sidebar = backdropTop
    static let listBackground = backdropTop
    static let canvas = backdropTop
    /// The floating panels (message list, calendar): not pure white, but a milky tone that
    /// follows the backdrop from lilac to rosé.
    static let panel = Color(light: "#F7F3FF", dark: "#221F3D")
    static let panelMiddle = Color(light: "#F4F5FF", dark: "#201F3E")
    static let panelBottom = Color(light: "#FCF3F9", dark: "#261F3E")
    /// Cards, text fields: a lilac-tinted white.
    static let cardFill = Color(light: "#FAF7FF", dark: "#272445")
    /// Subtle fills: chips, counters, banners.
    static let tint = Color(light: "#EAE3FF", dark: "#342F5E")
    /// Lines and outlines.
    static let hairline = Color(light: "#DCD4F8", dark: "#3D3870")
    /// The barely visible edge of cards.
    static let cardStroke = Color(light: "#FFFFFF", dark: "#353060")
    /// Fill of the selected row in lists.
    static let selection = Color(light: "#E2D8FF", dark: "#3D3678")
    /// Soft coloured shadow under floating panels and cards.
    static let shadow = Color(light: "#7B6BD6", dark: "#000000")

    /// Prominent buttons: lilac into violet.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "#A990FF"), Palette.violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Pastel avatar styles in several hues: gradient top, bottom and text colour.
    static let avatarStyles: [(Color, Color, Color)] = [
        (Color(hex: "#E6DDFF"), Color(hex: "#CDBFFB"), Color(hex: "#5B45C2")),
        (Color(hex: "#FFDCCB"), Color(hex: "#FFC4AA"), Color(hex: "#B5502A")),
        (Color(hex: "#CFF2E0"), Color(hex: "#ABE5C9"), Color(hex: "#1F7A55")),
        (Color(hex: "#D3E6FF"), Color(hex: "#B1CBFA"), Color(hex: "#2B5FB8")),
        (Color(hex: "#FFD6E6"), Color(hex: "#FBB8D2"), Color(hex: "#B03A6E")),
        (Color(hex: "#FFEFC0"), Color(hex: "#FFE08F"), Color(hex: "#8A6500")),
        (Color(hex: "#CBEFF3"), Color(hex: "#A6E1E9"), Color(hex: "#1B7480")),
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
            .shadow(color: Theme.shadow.opacity(0.13), radius: 16, y: 6)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Paints `color` behind the view *and* the window toolbar above it, so the toolbar
    /// takes the colour of the column below instead of the system grey.
    func themedWindowBackground(_ color: Color) -> some View {
        modifier(ToolbarBandModifier(background: color, band: color))
    }
}

struct ToolbarBandModifier<Background: View, Band: View>: ViewModifier {
    let background: Background
    /// What covers content scrolling up underneath the transparent toolbar.
    let band: Band

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(alignment: .top) {
                    band
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

/// The pastel backdrop of the window. Every column draws the same top-to-bottom gradient
/// over its full height, so together they read as one surface.
struct AppBackdrop: View {
    var body: some View {
        LinearGradient(
            stops: [
                // Flat at the top, where the toolbar band has to match exactly.
                .init(color: Theme.backdropTop, location: 0),
                .init(color: Theme.backdropTop, location: 0.12),
                .init(color: Theme.backdropMiddle, location: 0.55),
                .init(color: Theme.backdropBottom, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The surfaces of the window. They share one backdrop; the names say what sits on it.
enum GlassStyle {
    case sidebar, list, canvas
}

struct BackdropModifier: ViewModifier {
    let style: GlassStyle

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), style == .sidebar {
            // The system's sidebar is a floating pane of Liquid Glass: nothing is painted
            // over it, the window's backdrop shows through.
            content
        } else {
            content.modifier(ToolbarBandModifier(background: AppBackdrop(), band: Theme.backdropTop))
        }
    }
}

// MARK: - Liquid Glass

extension View {
    /// The pastel backdrop as the background of the whole window, behind the glass sidebar.
    @ViewBuilder
    func windowBackdrop() -> some View {
        if #available(macOS 26.0, *) {
            containerBackground(for: .window) { AppBackdrop() }
        } else {
            self
        }
    }

    /// A control surface: Liquid Glass on macOS 26 and later, the milky fill before that.
    @ViewBuilder
    func glassControl<S: InsettableShape>(in shape: S, isHighlighted: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.interactive(), in: shape)
        } else {
            background(shape.fill(Theme.cardFill.opacity(isHighlighted ? 1 : 0.7)))
                .shadow(color: Theme.shadow.opacity(0.1), radius: 4, y: 2)
        }
    }

    /// The surface of a prominent control: violet-tinted glass, or the accent gradient.
    @ViewBuilder
    func prominentGlass<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.tint(Palette.violet).interactive(), in: shape)
        } else {
            background(shape.fill(Theme.accentGradient))
                .shadow(color: Palette.violet.opacity(0.35), radius: 6, y: 2)
        }
    }

    /// The track of a switch: glass, or a breath of violet.
    @ViewBuilder
    func glassTrack() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular, in: Capsule())
        } else {
            background(Capsule().fill(Palette.violet.opacity(0.1)))
        }
    }
}

extension View {
    /// The pastel backdrop behind the view and the toolbar above it.
    func glassBackground(_ style: GlassStyle) -> some View {
        modifier(BackdropModifier(style: style))
    }

    /// A floating milky panel with rounded corners and a soft coloured shadow.
    func floatingPanel(radius: CGFloat = 18) -> some View {
        self
            .background(
                LinearGradient(
                    stops: [
                        // Flat at the top, where the pinned header has to match.
                        .init(color: Theme.panel, location: 0),
                        .init(color: Theme.panel, location: 0.3),
                        .init(color: Theme.panelMiddle, location: 0.6),
                        .init(color: Theme.panelBottom, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardStroke)
            )
            .shadow(color: Theme.shadow.opacity(0.13), radius: 16, y: 6)
    }
}

extension View {
    /// Backing for the bar that floats above a scrolling conversation: the backdrop's own
    /// top tone, so the bar belongs to the window instead of sitting on a grey strip.
    func frostedBar(tint: Color) -> some View {
        background(Theme.backdropTop)
    }
}

/// Round button: white glass on the backdrop, or lilac-tinted on a white panel.
struct GlassCircleButton: View {
    let systemImage: String
    let help: String
    var isActive = false
    var isTinted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCircleLabel(systemImage: systemImage, isActive: isActive, isTinted: isTinted)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GlassCircleLabel: View {
    let systemImage: String
    var isActive = false
    var isTinted = false
    @State private var isHovering = false

    var body: some View {
        Group {
            if isTinted {
                icon.background(Circle().fill(Theme.tint.opacity(isHovering ? 1 : 0.75)))
            } else {
                icon.glassControl(in: Circle(), isHighlighted: isHovering)
            }
        }
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(isActive || isTinted ? Color.accentColor : Color.primary.opacity(0.78))
            .frame(width: 32, height: 32)
    }
}

/// A round glass button that opens a menu.
struct GlassCircleMenu<Content: View>: View {
    let systemImage: String
    let help: String
    var isTinted = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            GlassCircleLabel(systemImage: systemImage, isTinted: isTinted)
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
        .glassTrack()
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
            .modifier(CapsuleButtonSurface(isProminent: isProminent, isHovering: isHovering))
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

private struct CapsuleButtonSurface: ViewModifier {
    let isProminent: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        if isProminent {
            content.prominentGlass(in: Capsule())
        } else {
            content.glassControl(in: Capsule(), isHighlighted: isHovering)
        }
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
        .glassControl(in: Capsule())
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
            .background(Capsule().fill(Palette.violet.opacity(isHovering ? 0.14 : 0)))
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

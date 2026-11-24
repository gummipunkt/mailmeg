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
    /// Height of the window's title bar with its toolbar.
    static let titleBarHeight: CGFloat = 52

    /// A label's colour, made readable on the light pastel surfaces: Gmail allows very pale
    /// label colours (even white), which would vanish as an icon or as text.
    static func labelColor(hex: String?) -> Color {
        guard let hex, let color = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) else { return Palette.periwinkle }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.12 {
            // White, grey or black: a neutral that shows in both appearances.
            return brightness > 0.8 || brightness < 0.25 ? Palette.periwinkle : Color(hue: hue, saturation: saturation, brightness: 0.55)
        }
        return Color(hue: hue, saturation: max(saturation, 0.55), brightness: min(max(brightness, 0.55), 0.82))
    }

    /// Fallback tones of the backdrop, for the few places that need one flat colour.
    static let backdropTop = Color(light: "#E4D9FF", dark: "#1B1638")
    static let backdropMiddle = Color(light: "#E6E4FF", dark: "#181733")
    static let backdropBottom = Color(light: "#F6DDF0", dark: "#221735")

    /// The floating sheets (message list, conversation, calendar): frosted, so the colours
    /// of the backdrop shimmer through.
    static let panel = Color(light: "#FFFFFF", 0.70, dark: "#100D26", 0.62)
    /// Cards and text fields on a sheet or on the backdrop: a lighter layer of the same frost.
    static let cardFill = Color(light: "#FFFFFF", 0.74, dark: "#FFFFFF", 0.07)
    /// Small surfaces that have to cover what is underneath: the selected segment of a
    /// switch, hover buttons, event cards.
    static let solidCard = Color(light: "#FFFFFF", dark: "#2B2749")
    /// Subtle fills: chips, counters, banners, search fields.
    static let tint = Color(light: "#6F4DFF", 0.10, dark: "#B3A6FF", 0.17)
    /// Lines and outlines.
    static let hairline = Color(light: "#D9D0F7", dark: "#3D3870", lightContrast: "#8E82C9", darkContrast: "#8C84D6")
    /// The light edge of sheets and cards.
    static let cardStroke = Color(light: "#FFFFFF", 0.85, dark: "#FFFFFF", 0.10)
    /// Fill of the selected row in lists.
    static let selection = Color(light: "#E4DAFF", dark: "#3D3678", lightContrast: "#C9B8FF", darkContrast: "#564BB0")
    /// Soft coloured shadow under small floating elements.
    static let shadow = Color(light: "#4B2FC0", dark: "#000000")

    /// Prominent buttons: two tones of violet.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "#8F6BFF"), Color(hex: "#6C4CF1")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Vivid avatar gradients (top, bottom); the initials are white.
    static let avatarStyles: [(Color, Color)] = [
        (Color(hex: "#A78BFF"), Color(hex: "#6C4CF1")),
        (Color(hex: "#FF9CC2"), Color(hex: "#EC4F93")),
        (Color(hex: "#6CC0FF"), Color(hex: "#2F86F6")),
        (Color(hex: "#4FDCC4"), Color(hex: "#12A38D")),
        (Color(hex: "#FFB877"), Color(hex: "#F47A3A")),
        (Color(hex: "#C79BFF"), Color(hex: "#9A4DE8")),
        (Color(hex: "#FFD166"), Color(hex: "#E89200")),
        (Color(hex: "#7FE3A2"), Color(hex: "#22A862")),
    ]
}

extension Color {
    /// A colour that adapts to light and dark appearance.
    /// The `Contrast` variants are used with "Increase contrast" in System Settings.
    init(light: String, dark: String, lightContrast: String? = nil, darkContrast: String? = nil) {
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        let lightContrastColor = NSColor(Color(hex: lightContrast ?? light))
        let darkContrastColor = NSColor(Color(hex: darkContrast ?? dark))
        self.init(nsColor: NSColor(name: nil) { appearance in
            let names: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
            let match = appearance.bestMatch(from: names) ?? .aqua
            if match == .darkAqua { return darkColor }
            if match == .accessibilityHighContrastAqua { return lightContrastColor }
            if match == .accessibilityHighContrastDarkAqua { return darkContrastColor }
            return lightColor
        })
    }

    /// A translucent colour per appearance.
    init(light: String, _ lightAlpha: Double, dark: String, _ darkAlpha: Double) {
        let lightColor = NSColor(Color(hex: light)).withAlphaComponent(lightAlpha)
        let darkColor = NSColor(Color(hex: dark)).withAlphaComponent(darkAlpha)
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
            .fill(LinearGradient(colors: [style.0, style.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
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
        let color = label.color?.backgroundColor == nil ? Palette.violet : Theme.labelColor(hex: label.color?.backgroundColor)
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
            // A light edge instead of a shadow: a shadow would show through the frosted fill.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.cardStroke)
            )
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

// MARK: - Backdrop

/// The colours of the window's backdrop, chosen in Settings.
enum ColorMood: String, CaseIterable, Identifiable {
    case aurora, lagoon, sunset, pastel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return tr("Aurora", "Aurora")
        case .lagoon: return tr("Lagune", "Lagoon")
        case .sunset: return tr("Abendrot", "Sunset")
        case .pastel: return tr("Pastell", "Pastel")
        }
    }

    /// A soft patch of colour: where it sits in the window and how far it reaches.
    struct Blob {
        let color: String
        let alpha: Double
        let center: UnitPoint
        let radius: CGFloat
    }

    struct Colors {
        let top: String
        let bottom: String
        let blobs: [Blob]
    }

    func colors(dark: Bool) -> Colors {
        // The strongest colour sits behind the sidebar (left); the reading area stays lighter.
        let places: [(UnitPoint, CGFloat)] = [
            (UnitPoint(x: 0.02, y: 0.08), 0.62),
            (UnitPoint(x: 0.06, y: 1.0), 0.58),
            (UnitPoint(x: 1.0, y: 0.0), 0.60),
            (UnitPoint(x: 0.98, y: 1.02), 0.52),
        ]
        let palette: (top: String, bottom: String, blobs: [(String, Double)])
        switch (self, dark) {
        case (.aurora, false):
            palette = ("#E7DEFF", "#F4E3F7", [("#8A63FF", 0.62), ("#FF78C4", 0.50), ("#58B4FF", 0.46), ("#FFA8D8", 0.40)])
        case (.aurora, true):
            palette = ("#140F2E", "#1A102C", [("#6A3FFF", 0.62), ("#C22C92", 0.44), ("#2A66FF", 0.44), ("#7A2BD0", 0.40)])
        case (.lagoon, false):
            palette = ("#DCEBFF", "#E1F6F2", [("#4C8DFF", 0.58), ("#2FD3C0", 0.48), ("#8E7BFF", 0.44), ("#6FD2FF", 0.40)])
        case (.lagoon, true):
            palette = ("#0C1530", "#0B1E27", [("#2A62F0", 0.60), ("#11988A", 0.44), ("#5B45D6", 0.42), ("#1C7FB8", 0.38)])
        case (.sunset, false):
            palette = ("#FFE3EC", "#FFEAD9", [("#FF5FA2", 0.52), ("#FF9A3D", 0.46), ("#A87BFF", 0.46), ("#FFB796", 0.40)])
        case (.sunset, true):
            palette = ("#231025", "#281316", [("#C4307A", 0.56), ("#C25E1B", 0.42), ("#6B3FD0", 0.44), ("#9A3B5C", 0.38)])
        case (.pastel, false):
            palette = ("#EDE6FF", "#F9E6F2", [("#DAD0FF", 0.55), ("#F6D3EA", 0.5), ("#DCE6FF", 0.55), ("#F3DDF2", 0.4)])
        case (.pastel, true):
            palette = ("#1D1936", "#221735", [("#2B2452", 0.6), ("#32203F", 0.5), ("#1D2550", 0.55), ("#2A1D40", 0.4)])
        }
        let blobs = zip(palette.blobs, places).map { blob, place in
            Blob(color: blob.0, alpha: blob.1, center: place.0, radius: place.1)
        }
        return Colors(top: palette.top, bottom: palette.bottom, blobs: blobs)
    }

    /// The colours of the little preview in Settings.
    var swatch: [Color] {
        colors(dark: false).blobs.prefix(3).map { Color(hex: $0.color) }
    }
}

/// The backdrop as one picture, the size of the view it is given.
struct MoodCanvas: View {
    let mood: ColorMood
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = mood.colors(dark: colorScheme == .dark)
        GeometryReader { proxy in
            let reach = max(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: [Color(hex: colors.top), Color(hex: colors.bottom)], startPoint: .top, endPoint: .bottom)
                ForEach(colors.blobs.indices, id: \.self) { index in
                    let blob = colors.blobs[index]
                    let color = Color(hex: blob.color)
                    RadialGradient(
                        stops: [
                            .init(color: color.opacity(blob.alpha), location: 0),
                            .init(color: color.opacity(blob.alpha * 0.5), location: 0.45),
                            .init(color: color.opacity(0), location: 1),
                        ],
                        center: blob.center,
                        startRadius: 0,
                        endRadius: reach * blob.radius
                    )
                }
            }
        }
    }
}

private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    /// The size of the main window's content, so every column can draw its part of one backdrop.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

/// The colourful backdrop of the window. Every column draws the part of the same picture
/// that lies behind it (in window coordinates), so together they read as one surface.
struct AppBackdrop: View {
    /// A white veil over the colours, for text that sits directly on the backdrop.
    var veil: Double = 0
    @AppStorage(AppSettings.colorMoodKey) private var moodName = ColorMood.aurora.rawValue
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let mood = ColorMood(rawValue: moodName) ?? .aurora
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let isPlaced = windowSize.width > 0 && windowSize.height > 0
            MoodCanvas(mood: mood)
                .frame(width: isPlaced ? windowSize.width : proxy.size.width, height: isPlaced ? windowSize.height : proxy.size.height)
                .offset(x: isPlaced ? -frame.minX : 0, y: isPlaced ? -frame.minY : 0)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .overlay(Color(light: "#FFFFFF", veil, dark: "#000000", veil * 0.6))
        .clipped()
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
            // Without system glass the sidebar's text sits directly on the colours.
            let veil = style == .sidebar ? 0.34 : 0
            content.modifier(ToolbarBandModifier(background: AppBackdrop(veil: veil), band: AppBackdrop(veil: veil)))
        }
    }
}

/// The backdrop behind the whole window (and so behind the glass sidebar of macOS 26).
private struct WindowBackdrop: View {
    @AppStorage(AppSettings.colorMoodKey) private var moodName = ColorMood.aurora.rawValue

    var body: some View {
        MoodCanvas(mood: ColorMood(rawValue: moodName) ?? .aurora)
    }
}

// MARK: - Liquid Glass

extension View {
    /// The pastel backdrop as the background of the whole window, behind the glass sidebar.
    @ViewBuilder
    func windowBackdrop() -> some View {
        if #available(macOS 26.0, *) {
            containerBackground(for: .window) { WindowBackdrop() }
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

/// Neighbouring glass controls belong into one container: glass cannot sample other glass,
/// and in a container the shapes render together and can flow into each other when they
/// move. `spacing` is the distance below which two shapes merge – keep it smaller than
/// the gap between the controls, so they stay separate at rest.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// The pastel backdrop behind the view and the toolbar above it.
    func glassBackground(_ style: GlassStyle) -> some View {
        modifier(BackdropModifier(style: style))
    }

    /// A floating frosted sheet with rounded corners; the backdrop shimmers through.
    func floatingPanel(radius: CGFloat = 20) -> some View {
        self
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardStroke)
            )
    }
}

extension View {
    /// The reading pane of the main window: a frosted sheet next to the message list.
    func detailSheet() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingPanel()
            .padding(.trailing, 8)
            .padding(.top, 2)
            .padding(.bottom, 10)
            .glassBackground(.canvas)
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
                                .fill(Theme.solidCard)
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

// MARK: - System toolbar

/// Flexible space in the window toolbar: what follows moves to the trailing edge.
struct ToolbarFlexibleGap: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem { Spacer() }
        }
    }
}

/// Separates two groups of toolbar buttons; on macOS 26 each group shares one capsule of glass.
struct ToolbarGroupGap: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
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

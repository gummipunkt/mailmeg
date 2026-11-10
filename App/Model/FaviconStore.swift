import AppKit
import Foundation
import Observation

/// Website icons of mail domains, shown as the sender's picture.
///
/// Icons come from Google's favicon service (this is a Gmail client, so Google already
/// knows who you correspond with) and are kept on disk. Private mailbox providers such
/// as gmail.com are skipped: their icon says nothing about the person.
@MainActor
@Observable
final class FaviconStore {
    static let shared = FaviconStore()

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var missing: [String: Date] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// Demo mode draws its own icons and touches neither network nor disk.
    private let isDemo = LaunchOptions.demo
    @ObservationIgnored private lazy var session = URLSession(configuration: .ephemeral)

    private init() {
        guard !isDemo, let url = Self.missingURL, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        missing = stored
    }

    /// The icon for an address, if its domain has one. Starts loading it otherwise.
    func image(forAddress address: String?) -> NSImage? {
        guard let domain = Self.domain(of: address) else { return nil }
        if let image = images[domain] { return image }
        if !loading.contains(domain), !isKnownMissing(domain) {
            loading.insert(domain)
            Task { await load(domain) }
        }
        return nil
    }

    // MARK: - Domains

    /// Mailbox providers whose icon would be the same for millions of people.
    private static let personalProviders: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "outlook.de", "hotmail.com", "hotmail.de", "live.com", "live.de", "msn.com",
        "yahoo.com", "yahoo.de", "ymail.com", "icloud.com", "me.com", "mac.com", "aol.com", "gmx.de", "gmx.net", "gmx.at", "gmx.ch",
        "web.de", "t-online.de", "freenet.de", "arcor.de", "posteo.de", "mailbox.org", "proton.me", "protonmail.com", "pm.me",
        "tutanota.com", "tuta.io", "mail.de", "online.de", "vodafone.de", "1und1.de", "kabelmail.de", "unitybox.de",
    ]

    /// Second-level suffixes under which organizations register their names.
    private static let compoundSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "com.br", "com.mx", "co.at", "or.at",
        "com.tr", "co.za", "com.cn", "com.sg", "co.in", "com.pl",
    ]

    static func domain(of address: String?) -> String? {
        guard let address, let at = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: at)...].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        guard domain.contains("."), !personalProviders.contains(domain) else { return nil }
        return domain
    }

    /// "mail.example.co.uk" → "example.co.uk": where the organization's website usually is.
    static func registrableDomain(_ domain: String) -> String {
        let labels = domain.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return domain }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return labels.suffix(compoundSuffixes.contains(lastTwo) ? 3 : 2).joined(separator: ".")
    }

    // MARK: - Loading

    private func isKnownMissing(_ domain: String) -> Bool {
        guard let checked = missing[domain] else { return false }
        // Look again after a week: sites get icons.
        return Date().timeIntervalSince(checked) < 7 * 86_400
    }

    private func load(_ domain: String) async {
        defer { loading.remove(domain) }
        if isDemo {
            images[domain] = DemoFavicons.image(for: domain)
            if images[domain] == nil { missing[domain] = Date() }
            return
        }
        if let url = Self.fileURL(for: domain), let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            images[domain] = image
            return
        }
        var candidates = [domain]
        let base = Self.registrableDomain(domain)
        if base != domain { candidates.append(base) }
        for candidate in candidates {
            guard let data = await fetch(candidate), let image = NSImage(data: data) else { continue }
            images[domain] = image
            if let url = Self.fileURL(for: domain) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
            return
        }
        missing[domain] = Date()
        saveMissing()
    }

    /// Asks Google's favicon service. It answers 404 (with a placeholder) when a site has no icon.
    private func fetch(_ domain: String) async -> Data? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "128")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 100 else { return nil }
        return data
    }

    // MARK: - Disk

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MailMeG", isDirectory: true)
            .appendingPathComponent("favicons", isDirectory: true)
    }

    private static func fileURL(for domain: String) -> URL? {
        let safe = domain.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !safe.isEmpty, !safe.hasPrefix(".") else { return nil }
        return directory?.appendingPathComponent(safe + ".img")
    }

    private static var missingURL: URL? { directory?.appendingPathComponent("missing.json") }

    private func saveMissing() {
        guard let url = Self.missingURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(missing).write(to: url, options: .atomic)
    }
}

/// Stand-in icons for the companies of the demo mailbox, so the demo shows what
/// website icons look like without loading anything.
@MainActor
enum DemoFavicons {
    private static let icons: [String: (symbol: String, color: NSColor)] = [
        "sonnenweg.example": ("airplane", NSColor(red: 0.12, green: 0.23, blue: 0.58, alpha: 1)),
        "stadtwerke-nord.example": ("bolt.fill", NSColor(red: 0.95, green: 0.62, blue: 0.07, alpha: 1)),
        "runclub.example": ("figure.run", NSColor(red: 0.13, green: 0.65, blue: 0.42, alpha: 1)),
    ]

    static func image(for domain: String) -> NSImage? {
        guard let icon = icons[domain] else { return nil }
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            icon.color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let origin = NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
                symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
    }
}

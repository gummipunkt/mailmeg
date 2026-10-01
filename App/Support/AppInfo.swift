import AppKit
import Foundation

/// Version and imprint information shown in "About Mailmeg" and in Settings.
enum AppInfo {
    static let name = "Mailmeg"
    static let author = "Patrick Walter"
    static let website = URL(string: "https://www.gummipunkt.eu")!
    static let websiteLabel = "www.gummipunkt.eu"
    static let email = "mailmeg@gummipunkt.eu"
    static let copyright = "© 2026 Patrick Walter"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    static var versionLine: String {
        tr("Version \(version) (Build \(build))", "Version \(version) (build \(build))")
    }

    @MainActor
    static func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        credits.append(NSAttributedString(string: tr("Ein nativer Gmail-Client für macOS.\n", "A native Gmail client for macOS.\n"), attributes: base))
        credits.append(NSAttributedString(string: tr("Kontakt: ", "Contact: "), attributes: base))
        var link = base
        link[.link] = website
        credits.append(NSAttributedString(string: websiteLabel, attributes: link))
        credits.append(NSAttributedString(string: " · ", attributes: base))
        link[.link] = URL(string: "mailto:\(email)")!
        credits.append(NSAttributedString(string: email, attributes: link))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: name,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

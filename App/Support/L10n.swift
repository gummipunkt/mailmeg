import Foundation
import MailmegKit

/// MailMeG ships German and English. The language follows the order in
/// System Settings → General → Language & Region (German if it comes before English).
enum L10n {
    static let isGerman: Bool = {
        if let forced = LaunchOptions.language { return forced == "de" }
        for language in Locale.preferredLanguages {
            if language.hasPrefix("de") { return true }
            if language.hasPrefix("en") { return false }
        }
        return false
    }()

    static var replyStrings: ReplyBuilder.Strings { isGerman ? .german : .english }
}

/// Returns the German or English text depending on the app language.
func tr(_ german: String, _ english: String) -> String {
    L10n.isGerman ? german : english
}

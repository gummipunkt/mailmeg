import Foundation
import MailmegKit

/// Value passed to a compose window. Codable so SwiftUI can restore the window.
struct ComposeDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    var accountID: String
    var kind: ComposeKind = .new
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    var threadID: String?
    var inReplyTo: String?
    var references: [String] = []
    var forwardedAttachments: [AttachmentInfo] = []
}

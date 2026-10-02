import Foundation

public enum ComposeKind: String, Codable, Sendable {
    case new, reply, replyAll, forward
}

/// Derives recipients, subject and quoted body for replies and forwards.
public enum ReplyBuilder {
    /// Texts used in quoted replies and forwarded messages.
    public struct Strings: Sendable {
        public var wrote: @Sendable (_ date: String, _ sender: String) -> String
        public var forwardedHeader: String
        public var from: String
        public var date: String
        public var subject: String
        public var to: String
        public var cc: String
        public var unknownSender: String

        public init(
            wrote: @escaping @Sendable (String, String) -> String,
            forwardedHeader: String, from: String, date: String, subject: String, to: String, cc: String, unknownSender: String
        ) {
            self.wrote = wrote
            self.forwardedHeader = forwardedHeader
            self.from = from
            self.date = date
            self.subject = subject
            self.to = to
            self.cc = cc
            self.unknownSender = unknownSender
        }

        public static let english = Strings(
            wrote: { date, sender in "On \(date), \(sender) wrote:" },
            forwardedHeader: "---------- Forwarded message ---------",
            from: "From", date: "Date", subject: "Subject", to: "To", cc: "Cc", unknownSender: "unknown sender"
        )

        public static let german = Strings(
            wrote: { date, sender in "Am \(date) schrieb \(sender):" },
            forwardedHeader: "---------- Weitergeleitete Nachricht ---------",
            from: "Von", date: "Datum", subject: "Betreff", to: "An", cc: "Cc", unknownSender: "unbekannter Absender"
        )
    }

    public static func subject(for original: String, kind: ComposeKind) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .new:
            return trimmed
        case .reply, .replyAll:
            return hasPrefix(trimmed, ["re:", "aw:"]) ? trimmed : "Re: \(trimmed)"
        case .forward:
            return hasPrefix(trimmed, ["fwd:", "fw:", "wg:"]) ? trimmed : "Fwd: \(trimmed)"
        }
    }

    private static func hasPrefix(_ subject: String, _ prefixes: [String]) -> Bool {
        let lower = subject.lowercased()
        return prefixes.contains { lower.hasPrefix($0) }
    }

    public static func recipients(for message: GmailMessage, kind: ComposeKind, selfAddresses: Set<String>) -> (to: [EmailAddress], cc: [EmailAddress]) {
        let own = Set(selfAddresses.map { $0.lowercased() })
        let sender = message.replyTo.isEmpty ? [message.from].compactMap { $0 } : message.replyTo

        switch kind {
        case .new, .forward:
            return ([], [])
        case .reply:
            // Replying to one's own sent message goes to its original recipients.
            if let from = message.from, own.contains(from.address.lowercased()) {
                return (message.to, [])
            }
            return (sender, [])
        case .replyAll:
            var seen = own
            func unique(_ addresses: [EmailAddress]) -> [EmailAddress] {
                addresses.filter { seen.insert($0.address.lowercased()).inserted }
            }
            let senderIsSelf = message.from.map { own.contains($0.address.lowercased()) } ?? false
            let to = unique(senderIsSelf ? message.to : sender + message.to)
            let cc = unique(message.cc)
            return (to, cc)
        }
    }

    public static func references(for message: GmailMessage) -> [String] {
        var references = message.references
        if let id = message.messageIDHeader, !references.contains(id) {
            references.append(id)
        }
        return references
    }

    /// The quoted part of a reply ("On …, … wrote:" + quoted lines) or the forwarded-message
    /// block, without surrounding blank lines. Empty for new messages.
    public static func quote(for message: GmailMessage, quotedText: String, kind: ComposeKind, strings: Strings = .english, dateFormatter: (Date) -> String) -> String {
        let sender = message.from?.formatted ?? strings.unknownSender
        let date = message.date.map(dateFormatter) ?? ""
        switch kind {
        case .new:
            return ""
        case .reply, .replyAll:
            let quoted = quotedText
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.hasPrefix(">") ? ">\($0)" : "> \($0)" }
                .joined(separator: "\n")
            return "\(strings.wrote(date, sender))\n\(quoted)"
        case .forward:
            var lines = [
                strings.forwardedHeader,
                "\(strings.from): \(sender)",
                "\(strings.date): \(date)",
                "\(strings.subject): \(message.subject)",
            ]
            if !message.to.isEmpty { lines.append("\(strings.to): \(message.to.map(\.formatted).joined(separator: ", "))") }
            if !message.cc.isEmpty { lines.append("\(strings.cc): \(message.cc.map(\.formatted).joined(separator: ", "))") }
            lines += ["", quotedText]
            return lines.joined(separator: "\n")
        }
    }

    /// Reply body with the cursor area above the quote (the classic Gmail layout).
    public static func body(for message: GmailMessage, quotedText: String, kind: ComposeKind, strings: Strings = .english, dateFormatter: (Date) -> String) -> String {
        let block = quote(for: message, quotedText: quotedText, kind: kind, strings: strings, dateFormatter: dateFormatter)
        return block.isEmpty ? "" : "\n\n\(block)\n"
    }

    /// Headers that name the address a message was delivered to, in order of reliability
    /// after To and Cc (Gmail puts the receiving account into Delivered-To, forwarders use the others).
    static let deliveryHeaders = ["X-Original-To", "Delivered-To", "X-Forwarded-To", "X-Forwarded-For", "Envelope-To"]

    /// The alias a reply should be sent from: the own address the original message was
    /// written to, so replies keep using the address the sender wrote to. If the message
    /// is one's own, its sender is kept. Earlier messages of the conversation are the
    /// fallback (e.g. when the address was only in Bcc).
    public static func preferredSender(for message: GmailMessage, in thread: [GmailMessage] = [], ownAddresses: [String]) -> String? {
        let own = Set(ownAddresses.map { $0.lowercased() })
        func ownAddress(of message: GmailMessage) -> String? {
            if let from = message.from?.address.lowercased(), own.contains(from) { return from }
            var candidates = message.to + message.cc
            for name in deliveryHeaders {
                candidates += message.header(name).map(EmailAddress.parseList) ?? []
            }
            // First match in header order, not in alphabetical order of one's addresses.
            return candidates.map { $0.address.lowercased() }.first { own.contains($0) }
        }
        if let address = ownAddress(of: message) { return address }
        for earlier in thread.reversed() where earlier.id != message.id {
            if let address = ownAddress(of: earlier) { return address }
        }
        return nil
    }
}

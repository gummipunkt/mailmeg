import Foundation

/// What the message list needs to show for one conversation.
public struct ThreadSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var subject: String
    public var participants: [String]
    public var snippet: String
    public var date: Date?
    public var isUnread: Bool
    public var isStarred: Bool
    public var messageCount: Int
    public var hasAttachments: Bool
    public var labelIDs: Set<String>
    /// The other side of the conversation: senders other than oneself or, for
    /// conversations that only contain one's own messages, their recipients.
    public var correspondents: [String]
    /// `true` if every message in the conversation was sent by oneself.
    public var isOnlyOwnMessages: Bool

    public init(thread: GmailThread, selfAddresses: Set<String> = [], selfName: String = "me") {
        let messages = thread.messages ?? []
        let ownAddresses = Set(selfAddresses.map { $0.lowercased() })
        id = thread.id
        subject = messages.first?.subject ?? ""
        snippet = HTMLText.decodeEntities(messages.last?.snippet ?? thread.snippet ?? "")
        date = messages.compactMap(\.date).max()
        isUnread = messages.contains(where: \.isUnread)
        isStarred = messages.contains(where: \.isStarred)
        messageCount = messages.count
        hasAttachments = messages.contains { $0.payload?.mimeType?.lowercased() == "multipart/mixed" }
        labelIDs = Set(messages.flatMap { $0.labelIds ?? [] })

        var seen = Set<String>()
        var names: [String] = []
        for message in messages {
            guard let from = message.from else { continue }
            let key = from.address.lowercased()
            guard seen.insert(key).inserted else { continue }
            names.append(ownAddresses.contains(key) ? selfName : from.displayName)
        }
        participants = names

        let others = messages.compactMap(\.from).filter { !ownAddresses.contains($0.address.lowercased()) }
        isOnlyOwnMessages = !messages.isEmpty && others.isEmpty
        var counterparts: [String] = []
        var counterpartKeys = Set<String>()
        let candidates = others.isEmpty ? messages.flatMap { $0.to + $0.cc } : others
        for address in candidates where !ownAddresses.contains(address.address.lowercased()) {
            if counterpartKeys.insert(address.address.lowercased()).inserted {
                counterparts.append(address.displayName)
            }
        }
        correspondents = counterparts
    }
}

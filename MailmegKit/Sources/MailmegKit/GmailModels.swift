import Foundation

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String
    public let messagesTotal: Int?
    public let threadsTotal: Int?
    public let historyId: String
}

public struct GmailSendAs: Decodable, Sendable {
    public let sendAsEmail: String
    public let displayName: String?
    public let isDefault: Bool?
    public let isPrimary: Bool?
}

public struct GmailLabel: Codable, Identifiable, Hashable, Sendable {
    public struct Color: Codable, Hashable, Sendable {
        public let textColor: String?
        public let backgroundColor: String?
    }

    public let id: String
    public var name: String
    public var type: String?
    public var messageListVisibility: String?
    public var labelListVisibility: String?
    public var messagesTotal: Int?
    public var messagesUnread: Int?
    public var threadsTotal: Int?
    public var threadsUnread: Int?
    public var color: Color?

    public init(id: String, name: String, type: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
    }

    public var isSystem: Bool { type == "system" }
    public var isHidden: Bool { labelListVisibility == "labelHide" }
}

public struct GmailThreadRef: Decodable, Sendable, Hashable {
    public let id: String
    public let snippet: String?
    public let historyId: String?
}

public struct GmailThreadList: Decodable, Sendable {
    public let threads: [GmailThreadRef]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
}

public struct GmailThread: Decodable, Identifiable, Sendable {
    public let id: String
    public let historyId: String?
    public let snippet: String?
    public let messages: [GmailMessage]?
}

public struct GmailMessage: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let threadId: String
    public var labelIds: [String]?
    public let snippet: String?
    public let historyId: String?
    public let internalDate: String?
    public let sizeEstimate: Int?
    public let payload: MessagePart?

    public init(id: String, threadId: String, labelIds: [String]? = nil, snippet: String? = nil, historyId: String? = nil, internalDate: String? = nil, sizeEstimate: Int? = nil, payload: MessagePart? = nil) {
        self.id = id
        self.threadId = threadId
        self.labelIds = labelIds
        self.snippet = snippet
        self.historyId = historyId
        self.internalDate = internalDate
        self.sizeEstimate = sizeEstimate
        self.payload = payload
    }
}

public struct MessagePart: Decodable, Sendable, Hashable {
    public let partId: String?
    public let mimeType: String?
    public let filename: String?
    public let headers: [MessageHeader]?
    public let body: MessagePartBody?
    public let parts: [MessagePart]?

    public init(partId: String? = nil, mimeType: String? = nil, filename: String? = nil, headers: [MessageHeader]? = nil, body: MessagePartBody? = nil, parts: [MessagePart]? = nil) {
        self.partId = partId
        self.mimeType = mimeType
        self.filename = filename
        self.headers = headers
        self.body = body
        self.parts = parts
    }

    public func header(_ name: String) -> String? {
        headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public struct MessageHeader: Codable, Sendable, Hashable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MessagePartBody: Decodable, Sendable, Hashable {
    public let attachmentId: String?
    public let size: Int?
    public let data: String?

    public init(attachmentId: String? = nil, size: Int? = nil, data: String? = nil) {
        self.attachmentId = attachmentId
        self.size = size
        self.data = data
    }

    public var decodedData: Data? { data.flatMap(Base64URL.decode) }
}

public struct GmailHistoryList: Decodable, Sendable {
    public struct Record: Decodable, Sendable {
        public struct MessageAdded: Decodable, Sendable {
            public let message: GmailMessage
        }

        public let id: String
        public let messagesAdded: [MessageAdded]?
    }

    public let history: [Record]?
    public let nextPageToken: String?
    public let historyId: String?
}

public enum SystemLabel {
    public static let inbox = "INBOX"
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let important = "IMPORTANT"
    public static let sent = "SENT"
    public static let draft = "DRAFT"
    public static let spam = "SPAM"
    public static let trash = "TRASH"
}

// MARK: - Convenience accessors

extension GmailMessage {
    public func header(_ name: String) -> String? { payload?.header(name) }

    public var subject: String { header("Subject") ?? "" }
    public var from: EmailAddress? { header("From").flatMap { EmailAddress.parseList($0).first } }
    public var replyTo: [EmailAddress] { header("Reply-To").map(EmailAddress.parseList) ?? [] }
    public var to: [EmailAddress] { header("To").map(EmailAddress.parseList) ?? [] }
    public var cc: [EmailAddress] { header("Cc").map(EmailAddress.parseList) ?? [] }
    public var messageIDHeader: String? { header("Message-ID") ?? header("Message-Id") }
    public var references: [String] {
        (header("References") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var date: Date? {
        guard let internalDate, let milliseconds = Double(internalDate) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    public var isUnread: Bool { labelIds?.contains(SystemLabel.unread) ?? false }
    public var isStarred: Bool { labelIds?.contains(SystemLabel.starred) ?? false }
}

import Foundation

public struct GmailAPIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public let reason: String?

    public init(status: Int, message: String, reason: String?) {
        self.status = status
        self.message = message
        self.reason = reason
    }

    public var errorDescription: String? { "Gmail API error \(status): \(message)" }

    /// Google's per-user / per-project quota was exhausted ("Quota exceeded …").
    public var isRateLimited: Bool {
        status == 429 || (status == 403 && ["rateLimitExceeded", "userRateLimitExceeded", "quotaExceeded"].contains(reason ?? ""))
    }

    var isRetryable: Bool {
        isRateLimited || [500, 502, 503, 504].contains(status)
    }
}

/// Thin, typed wrapper around the Gmail REST API (v1).
public final class GmailClient: Sendable {
    public enum ThreadFormat: String, Sendable {
        case minimal, metadata, full
    }

    public static let summaryHeaders = ["From", "To", "Subject", "Date"]

    let tokens: TokenManager
    let transport: HTTPTransport
    let apiBase = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!
    let uploadBase = URL(string: "https://gmail.googleapis.com/upload/gmail/v1/users/me/")!
    let maxAttempts: Int
    let sleep: @Sendable (UInt64) async throws -> Void

    public init(
        tokens: TokenManager,
        transport: HTTPTransport = URLSessionTransport(),
        maxAttempts: Int = 5,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.tokens = tokens
        self.transport = transport
        self.maxAttempts = maxAttempts
        self.sleep = sleep
    }

    // MARK: - Account

    public func profile() async throws -> GmailProfile {
        try await get("profile")
    }

    public func sendAsAliases() async throws -> [GmailSendAs] {
        struct Response: Decodable { let sendAs: [GmailSendAs]? }
        let response: Response = try await get("settings/sendAs")
        return response.sendAs ?? []
    }

    // MARK: - Labels

    public func labels() async throws -> [GmailLabel] {
        struct Response: Decodable { let labels: [GmailLabel]? }
        let response: Response = try await get("labels")
        return response.labels ?? []
    }

    /// Single label including message/thread counters (not returned by `labels()`).
    public func label(id: String) async throws -> GmailLabel {
        try await get("labels/\(escapePath(id))")
    }

    /// Labels including their counters, fetched concurrently.
    public func labels(ids: [String], concurrency: Int = 6) async throws -> [GmailLabel] {
        try await boundedMap(ids, concurrency: concurrency) { id in
            do {
                return try await self.label(id: id)
            } catch let error as GmailAPIError where error.status == 404 {
                return nil
            }
        }
    }

    // MARK: - Threads

    public func listThreads(labelIDs: [String] = [], query: String? = nil, pageToken: String? = nil, maxResults: Int = 50) async throws -> GmailThreadList {
        var items = labelIDs.map { URLQueryItem(name: "labelIds", value: $0) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        items.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        return try await get("threads", query: items)
    }

    public func thread(id: String, format: ThreadFormat = .full, metadataHeaders: [String] = GmailClient.summaryHeaders) async throws -> GmailThread {
        var items = [URLQueryItem(name: "format", value: format.rawValue)]
        if format == .metadata {
            items += metadataHeaders.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        }
        return try await get("threads/\(escapePath(id))", query: items)
    }

    /// Fetches several threads concurrently (bounded) and returns them in the order of `ids`.
    /// Threads that fail to load (e.g. deleted in the meantime) are skipped.
    public func threads(ids: [String], format: ThreadFormat = .metadata, concurrency: Int = 8) async throws -> [GmailThread] {
        try await boundedMap(ids, concurrency: concurrency) { id in
            do {
                return try await self.thread(id: id, format: format)
            } catch let error as GmailAPIError where error.status == 404 {
                return nil
            }
        }
    }

    public func modifyThread(id: String, add: [String] = [], remove: [String] = []) async throws {
        struct Body: Encodable { let addLabelIds: [String]; let removeLabelIds: [String] }
        let _: GmailThreadRef = try await post("threads/\(escapePath(id))/modify", json: Body(addLabelIds: add, removeLabelIds: remove))
    }

    public func trashThread(id: String) async throws {
        let _: GmailThreadRef = try await post("threads/\(escapePath(id))/trash")
    }

    public func untrashThread(id: String) async throws {
        let _: GmailThreadRef = try await post("threads/\(escapePath(id))/untrash")
    }

    // MARK: - Messages

    public func message(id: String, format: ThreadFormat = .full) async throws -> GmailMessage {
        try await get("messages/\(escapePath(id))", query: [URLQueryItem(name: "format", value: format.rawValue)])
    }

    /// The complete original message (RFC 822 source) as Gmail stores it.
    public func rawMessage(id: String) async throws -> Data {
        struct Raw: Decodable { let raw: String? }
        let response: Raw = try await get("messages/\(escapePath(id))", query: [URLQueryItem(name: "format", value: "raw")])
        guard let raw = response.raw, let data = Base64URL.decode(raw) else {
            throw GmailAPIError(status: 0, message: "The message source could not be decoded.", reason: nil)
        }
        return data
    }

    public func attachment(messageID: String, attachmentID: String) async throws -> Data {
        let body: MessagePartBody = try await get("messages/\(escapePath(messageID))/attachments/\(escapePath(attachmentID))")
        guard let data = body.decodedData else {
            throw GmailAPIError(status: 0, message: "Attachment data could not be decoded.", reason: nil)
        }
        return data
    }

    /// Sends an RFC 5322 message. Uses the multipart upload endpoint so large
    /// attachments (up to Gmail's 35 MB limit) work and `threadId` can be set.
    @discardableResult
    public func send(rfc822 message: Data, threadID: String? = nil) async throws -> GmailMessage {
        struct Metadata: Encodable { let threadId: String? }
        return try await upload(path: "messages/send", method: "POST", metadata: Metadata(threadId: threadID), rfc822: message)
    }

    // MARK: - Drafts

    private struct DraftMetadata: Encodable {
        struct Message: Encodable { let threadId: String? }
        let id: String?
        let message: Message
    }

    /// Creates a draft in Gmail (visible in Gmail's Drafts on all devices).
    public func createDraft(rfc822 message: Data, threadID: String? = nil) async throws -> GmailDraft {
        try await upload(path: "drafts", method: "POST", metadata: DraftMetadata(id: nil, message: .init(threadId: threadID)), rfc822: message)
    }

    /// Replaces the content of an existing draft.
    public func updateDraft(id: String, rfc822 message: Data, threadID: String? = nil) async throws -> GmailDraft {
        try await upload(path: "drafts/\(escapePath(id))", method: "PUT", metadata: DraftMetadata(id: id, message: .init(threadId: threadID)), rfc822: message)
    }

    public func deleteDraft(id: String) async throws {
        var request = URLRequest(url: url("drafts/\(escapePath(id))", query: []))
        request.httpMethod = "DELETE"
        _ = try await performRaw(request)
    }

    /// Sends a saved draft; Gmail removes it from Drafts.
    @discardableResult
    public func sendDraft(id: String) async throws -> GmailMessage {
        struct Body: Encodable { let id: String }
        return try await post("drafts/send", json: Body(id: id))
    }

    public func listDrafts(pageToken: String? = nil, maxResults: Int = 500) async throws -> GmailDraftList {
        var items = [URLQueryItem(name: "maxResults", value: String(maxResults))]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get("drafts", query: items)
    }

    /// Multipart upload of an RFC 822 message with JSON metadata (send, create/update draft).
    private func upload<T: Decodable, Metadata: Encodable>(path: String, method: String, metadata: Metadata, rfc822 message: Data) async throws -> T {
        let boundary = "mailmeg-upload-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(try JSONEncoder().encode(metadata))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: message/rfc822\r\n\r\n".utf8))
        body.append(message)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var components = URLComponents(url: uploadBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }

    // MARK: - History

    public func history(startHistoryID: String, labelID: String? = nil, historyTypes: [String] = ["messageAdded"], pageToken: String? = nil) async throws -> GmailHistoryList {
        var items = [URLQueryItem(name: "startHistoryId", value: startHistoryID)]
        items += historyTypes.map { URLQueryItem(name: "historyTypes", value: $0) }
        if let labelID { items.append(URLQueryItem(name: "labelId", value: labelID)) }
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get("history", query: items)
    }

    // MARK: - Plumbing

    /// Runs `transform` for every element with at most `concurrency` requests in flight,
    /// keeping the input order and dropping `nil` results.
    func boundedMap<Output: Sendable>(
        _ inputs: [String],
        concurrency: Int,
        _ transform: @escaping @Sendable (String) async throws -> Output?
    ) async throws -> [Output] {
        var results = [Output?](repeating: nil, count: inputs.count)
        try await withThrowingTaskGroup(of: (Int, Output?).self) { group in
            var pending: [(offset: Int, element: String)] = Array(inputs.enumerated().reversed())
            for _ in 0..<max(1, concurrency) {
                guard let item = pending.popLast() else { break }
                group.addTask { (item.offset, try await transform(item.element)) }
            }
            while let result = try await group.next() {
                results[result.0] = result.1
                if let item = pending.popLast() {
                    group.addTask { (item.offset, try await transform(item.element)) }
                }
            }
        }
        return results.compactMap { $0 }
    }

    private func escapePath(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? component
    }

    private func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: apiBase.absoluteString + path)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await perform(URLRequest(url: url(path, query: query)))
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = "POST"
        return try await perform(request)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, json: Body) async throws -> T {
        var request = URLRequest(url: url(path, query: []))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(json)
        return try await perform(request)
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let reason: String? }
        struct Body: Decodable {
            let code: Int?
            let message: String?
            let errors: [Detail]?
        }
        let error: Body
    }

    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await performRaw(request))
    }

    /// Sends a request with auth, token refresh and retries; returns the body of a 2xx response.
    func performRaw(_ baseRequest: URLRequest) async throws -> Data {
        var attempt = 0
        var forceRefresh = false
        while true {
            attempt += 1
            var request = baseRequest
            let token = try await tokens.accessToken(forceRefresh: forceRefresh)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await transport.data(for: request)
            if (200..<300).contains(response.statusCode) {
                return data
            }

            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let error = GmailAPIError(
                status: response.statusCode,
                message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                reason: envelope?.error.errors?.first?.reason
            )

            if response.statusCode == 401, !forceRefresh {
                forceRefresh = true
                continue
            }
            forceRefresh = false
            guard error.isRetryable, attempt < maxAttempts else { throw error }
            try await self.sleep(Self.retryDelay(attempt: attempt, error: error, response: response))
        }
    }

    /// Backoff in nanoseconds. Quota errors wait noticeably longer (Gmail counts quota per minute)
    /// and honour a `Retry-After` header when Google sends one.
    static func retryDelay(attempt: Int, error: GmailAPIError, response: HTTPURLResponse) -> UInt64 {
        let jitter = Double.random(in: 0...0.25)
        if error.isRateLimited {
            if let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(header) {
                return UInt64((min(seconds, 60) + jitter) * 1_000_000_000)
            }
            return UInt64((min(pow(2, Double(attempt)), 30) + jitter) * 1_000_000_000)
        }
        return UInt64((pow(2, Double(attempt - 1)) * 0.5 + jitter) * 1_000_000_000)
    }
}

import Foundation

/// A file in the user's Google Drive (as far as MailMeG needs it).
public struct DriveFile: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let mimeType: String?
    /// Drive reports sizes as strings.
    public let size: String?
    public let webViewLink: String?
    public let trashed: Bool?

    public init(id: String, name: String?, mimeType: String? = nil, size: String? = nil, webViewLink: String? = nil, trashed: Bool? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.webViewLink = webViewLink
        self.trashed = trashed
    }

    public var byteCount: Int? { size.flatMap(Int.init) }

    /// The link recipients open; falls back to the standard file URL.
    public var link: String { webViewLink ?? "https://drive.google.com/file/d/\(id)/view" }
}

/// Google Drive API (v3) for sending large files as links. MailMeG uses the narrow
/// `drive.file` scope: it only sees the files it uploaded itself.
public final class DriveClient: Sendable {
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    /// Upload chunks must be multiples of 256 KiB.
    public static let defaultChunkSize = 8 * 1024 * 1024

    let api: GmailClient
    let base = "https://www.googleapis.com/drive/v3/"
    let uploadBase = "https://www.googleapis.com/upload/drive/v3/"
    static let fileFields = "id,name,mimeType,size,webViewLink"

    public init(api: GmailClient) {
        self.api = api
    }

    public static func isGranted(scope: String?) -> Bool {
        guard let scope else { return false }
        let granted = Set(scope.split(separator: " ").map(String.init))
        return granted.contains(Self.scope) || granted.contains("https://www.googleapis.com/auth/drive")
    }

    // MARK: - Folder

    public func createFolder(named name: String) async throws -> DriveFile {
        struct Folder: Encodable {
            let name: String
            let mimeType = "application/vnd.google-apps.folder"
        }
        var request = makeRequest(base + "files", query: [URLQueryItem(name: "fields", value: Self.fileFields)])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Folder(name: name))
        return try await api.perform(request)
    }

    /// The file if it still exists and is not in the trash.
    public func file(id: String) async throws -> DriveFile? {
        let request = makeRequest(base + "files/\(escape(id))", query: [URLQueryItem(name: "fields", value: Self.fileFields + ",trashed")])
        do {
            let file: DriveFile = try await api.perform(request)
            return file.trashed == true ? nil : file
        } catch let error as GmailAPIError where error.status == 404 {
            return nil
        }
    }

    // MARK: - Upload

    /// Uploads a file in chunks (resumable upload), reporting progress from 0 to 1.
    public func upload(
        fileAt url: URL,
        name: String,
        mimeType: String,
        parentID: String?,
        chunkSize: Int = DriveClient.defaultChunkSize,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> DriveFile {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try await upload(size: size, name: name, mimeType: mimeType, parentID: parentID, chunkSize: chunkSize, progress: progress) { offset, length in
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length) ?? Data()
        }
    }

    public func upload(
        data: Data,
        name: String,
        mimeType: String,
        parentID: String?,
        chunkSize: Int = DriveClient.defaultChunkSize,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> DriveFile {
        try await upload(size: data.count, name: name, mimeType: mimeType, parentID: parentID, chunkSize: chunkSize, progress: progress) { offset, length in
            data.subdata(in: offset..<min(offset + length, data.count))
        }
    }

    private func upload(
        size: Int,
        name: String,
        mimeType: String,
        parentID: String?,
        chunkSize: Int,
        progress: @escaping @Sendable (Double) -> Void,
        read: (Int, Int) throws -> Data
    ) async throws -> DriveFile {
        struct Metadata: Encodable {
            let name: String
            let parents: [String]?
        }
        // 1. Start the upload session.
        var start = makeRequest(uploadBase + "files", query: [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: Self.fileFields),
        ])
        start.httpMethod = "POST"
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONEncoder().encode(Metadata(name: name, parents: parentID.map { [$0] }))
        let session = try await api.send(start)
        guard let location = session.response.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw GmailAPIError(status: session.response.statusCode, message: "Google Drive did not start the upload.", reason: nil)
        }

        // 2. Send the bytes chunk by chunk; Google answers 308 until the last one.
        let step = max(256 * 1024, chunkSize / (256 * 1024) * (256 * 1024))
        var offset = 0
        progress(0)
        while true {
            let chunk = size == 0 ? Data() : try read(offset, min(step, size - offset))
            var request = URLRequest(url: sessionURL)
            request.httpMethod = "PUT"
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue(
                size == 0 ? "bytes */0" : "bytes \(offset)-\(offset + chunk.count - 1)/\(size)",
                forHTTPHeaderField: "Content-Range"
            )
            request.httpBody = chunk
            let result = try await api.send(request, accepting: [308])
            if result.response.statusCode != 308 {
                progress(1)
                return try JSONDecoder().decode(DriveFile.self, from: result.data)
            }
            // "Range: bytes=0-1234" tells how much Google has; continue from there.
            if let range = result.response.value(forHTTPHeaderField: "Range"),
               let last = range.split(separator: "-").last.flatMap({ Int($0) }) {
                offset = last + 1
            } else {
                offset += chunk.count
            }
            progress(size == 0 ? 1 : min(Double(offset) / Double(size), 1))
            // Everything was sent but Google still waits for more: give up instead of looping.
            if offset >= size { break }
        }
        throw GmailAPIError(status: 500, message: "Google Drive did not finish the upload.", reason: nil)
    }

    // MARK: - Sharing

    /// Anyone with the link can view the file.
    public func shareWithAnyone(fileID: String) async throws {
        try await addPermission(fileID: fileID, body: ["role": "reader", "type": "anyone"], notify: false)
    }

    /// Only these people can view the file. Addresses without a Google account need
    /// Drive's own invitation email, so those are retried with a notification.
    public func share(fileID: String, with emails: [String]) async throws {
        for email in emails {
            let body = ["role": "reader", "type": "user", "emailAddress": email]
            do {
                try await addPermission(fileID: fileID, body: body, notify: false)
            } catch let error as GmailAPIError where error.status == 400 {
                try await addPermission(fileID: fileID, body: body, notify: true)
            }
        }
    }

    private func addPermission(fileID: String, body: [String: String], notify: Bool) async throws {
        var request = makeRequest(base + "files/\(escape(fileID))/permissions", query: [
            URLQueryItem(name: "sendNotificationEmail", value: notify ? "true" : "false"),
        ])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await api.performRaw(request)
    }

    // MARK: - Plumbing

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? component
    }

    private func makeRequest(_ url: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(string: url)!
        if !query.isEmpty { components.queryItems = query }
        return URLRequest(url: components.url!)
    }
}

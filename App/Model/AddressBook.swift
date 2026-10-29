import Contacts
import Foundation
import MailmegKit
import Observation

/// The people MailMeG suggests while you type an address: everyone you wrote to or got
/// mail from, plus the contacts of the macOS address book (if you allow it).
@MainActor
@Observable
final class AddressBook {
    static let shared = AddressBook()

    struct Entry: Codable, Hashable {
        var name: String?
        var address: String
        /// How often you wrote to this address.
        var sent = 0
        /// How often you got mail from it.
        var received = 0
        var lastSeen = Date.distantPast
        var isContact = false

        var emailAddress: EmailAddress { EmailAddress(name: name, address: address) }

        /// Addresses you write to come first, then frequent and recent senders, then contacts.
        var score: Double {
            let days = max(Date().timeIntervalSince(lastSeen) / 86_400, 0)
            let recency = lastSeen == .distantPast ? 0 : max(0, 30 - days) / 10
            return Double(sent) * 6 + Double(min(received, 20)) + recency + (isContact ? 4 : 0)
        }
    }

    /// Keyed by lowercased address.
    private var mailEntries: [String: Entry] = [:]
    private var contactEntries: [String: Entry] = [:]
    private var contactsRequested = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Demo mode keeps everything in memory, so the real address book stays untouched.
    var isPersistent = !LaunchOptions.demo

    private init() {
        load()
    }

    // MARK: - Collecting

    /// Learns the addresses of messages: recipients of your own mail, senders of the rest.
    func note(_ messages: [GmailMessage], ownAddresses: Set<String>) {
        var changed = false
        for message in messages {
            let date = message.date ?? Date()
            let isOwn = (message.labelIds ?? []).contains(SystemLabel.sent)
                || message.from.map { ownAddresses.contains($0.address.lowercased()) } == true
            if isOwn {
                for address in message.to + message.cc where record(address, sent: true, date: date, own: ownAddresses) {
                    changed = true
                }
            } else if let from = message.from, record(from, sent: false, date: date, own: ownAddresses) {
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    func noteSent(to addresses: [EmailAddress], ownAddresses: Set<String>) {
        for address in addresses {
            _ = record(address, sent: true, date: Date(), own: ownAddresses)
        }
        scheduleSave()
    }

    @discardableResult
    private func record(_ address: EmailAddress, sent: Bool, date: Date, own: Set<String>) -> Bool {
        let key = address.address.lowercased()
        guard key.contains("@"), !own.contains(key), !Self.isAutomated(key) else { return false }
        var entry = mailEntries[key] ?? Entry(address: address.address)
        if let name = address.name, !name.contains("@") { entry.name = name }
        if sent { entry.sent += 1 } else { entry.received += 1 }
        entry.lastSeen = max(entry.lastSeen, date)
        mailEntries[key] = entry
        return true
    }

    /// No-reply senders and mailing robots are not worth suggesting.
    static func isAutomated(_ address: String) -> Bool {
        let local = address.split(separator: "@").first.map(String.init) ?? address
        return ["noreply", "no-reply", "donotreply", "do-not-reply", "mailer-daemon", "postmaster", "bounce", "notifications", "notification"]
            .contains { local.contains($0) }
    }

    // MARK: - Suggestions

    /// The best matches for what was typed, without the addresses already in the field.
    func suggestions(for query: String, excluding: Set<String> = [], limit: Int = 6) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var merged = contactEntries
        for (key, entry) in mailEntries {
            if var existing = merged[key] {
                existing.sent = entry.sent
                existing.received = entry.received
                existing.lastSeen = entry.lastSeen
                if existing.name == nil { existing.name = entry.name }
                merged[key] = existing
            } else {
                merged[key] = entry
            }
        }
        return merged
            .filter { key, entry in !excluding.contains(key) && Self.matches(entry, query) }
            .map(\.value)
            .sorted { $0.score == $1.score ? $0.address < $1.address : $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private static func matches(_ entry: Entry, _ query: String) -> Bool {
        let address = entry.address.lowercased()
        if address.hasPrefix(query) { return true }
        if let domain = address.split(separator: "@").last, domain.hasPrefix(query) { return true }
        guard let name = entry.name?.lowercased() else { return false }
        if name.hasPrefix(query) { return true }
        return name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).contains { $0.hasPrefix(query) }
    }

    // MARK: - macOS Contacts

    /// Asks once for access to Contacts and reads their email addresses.
    func loadContactsIfNeeded() async {
        guard isPersistent, !contactsRequested else { return }
        contactsRequested = true
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            guard (try? await store.requestAccess(for: .contacts)) == true else { return }
        case .authorized:
            break
        default:
            return
        }
        let entries: [String: Entry] = await Task.detached(priority: .utility) {
            var result: [String: Entry] = [:]
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let person = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let name = person.isEmpty ? contact.organizationName : person
                for email in contact.emailAddresses {
                    let address = (email.value as String).trimmingCharacters(in: .whitespaces)
                    guard address.contains("@") else { continue }
                    result[address.lowercased()] = Entry(name: name.isEmpty ? nil : name, address: address, isContact: true)
                }
            }
            return result
        }.value
        contactEntries = entries
    }

    // MARK: - Storage

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("MailMeG", isDirectory: true).appendingPathComponent("addresses.json")
    }

    private func load() {
        guard isPersistent, let url = Self.fileURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        mailEntries = Dictionary(entries.map { ($0.address.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func scheduleSave() {
        guard isPersistent else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    private func save() {
        guard let url = Self.fileURL else { return }
        // Keep the file small: the 3000 most relevant addresses.
        let entries = mailEntries.values.sorted { $0.score > $1.score }.prefix(3000)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(entries)).write(to: url, options: .atomic)
        } catch {
            DebugLog.log("address book not saved: \(error)")
        }
    }
}

import Foundation
import MailmegKit

/// A fake Gmail backend with sample data. It sits behind the real `GmailClient`
/// (as its HTTP transport), so the demo runs exactly the same code as a real account.
/// Used for "Demo ansehen" on the welcome screen and for UI tests (`--demo`).
enum DemoMailbox {
    static let email = "alex@example.com"
    static let displayName = "Alex Berger"

    @MainActor
    static func makeSession() -> AccountSession {
        let tokens = OAuthTokens(accessToken: "demo", refreshToken: "demo", expiresAt: .distantFuture)
        let config = GoogleOAuthConfig(clientID: "demo.apps.googleusercontent.com")
        return AccountSession(email: email, tokens: tokens, config: config, transport: DemoTransport(), persistsTokens: false)
    }
}

// MARK: - Sample data

private struct DemoPerson {
    let name: String
    let email: String

    var header: String { "\(name) <\(email)>" }
    static let me = DemoPerson(name: DemoMailbox.displayName, email: DemoMailbox.email)
}

private struct DemoAttachment {
    let filename: String
    let mimeType: String
    let size: Int
}

private struct DemoMessage {
    let from: DemoPerson
    let to: [DemoPerson]
    let hoursAgo: Double
    let text: String
    var html: String? = nil
    var attachments: [DemoAttachment] = []
}

private struct DemoThread {
    let id: String
    var subject: String
    var labels: Set<String>
    var messages: [DemoMessage]
}

private enum DemoData {
    static let anna = DemoPerson(name: "Anna Becker", email: "anna.becker@example.com")
    static let jonas = DemoPerson(name: "Jonas Weber", email: "jonas@example.org")
    static let lena = DemoPerson(name: "Lena Hoffmann", email: "lena.hoffmann@example.com")
    static let mia = DemoPerson(name: "Mia Schulz", email: "mia.schulz@example.net")
    static let travel = DemoPerson(name: tr("Reisebüro Sonnenweg", "Sunway Travel"), email: "buchung@sonnenweg.example")
    static let utility = DemoPerson(name: tr("Stadtwerke Nord", "Northside Utilities"), email: "rechnung@stadtwerke-nord.example")
    static let runClub = DemoPerson(name: "Run Club", email: "hallo@runclub.example")
    static let itSupport = DemoPerson(name: tr("IT-Support", "IT Support"), email: "it@example.com")
    static let landlord = DemoPerson(name: tr("Hausverwaltung Krüger", "Krüger Property Management"), email: "kontakt@krueger-hv.example")
    static let events = DemoPerson(name: "Team Events", email: "events@example.com")
    static let spammer = DemoPerson(name: tr("Glücksbüro", "Lucky Prize Office"), email: "winner@lucky-prize.example")

    static let labels: [(id: String, name: String, color: String)] = [
        ("Label_1", tr("Projekte", "Projects"), "#4a86e8"),
        ("Label_2", tr("Projekte/Website", "Projects/Website"), "#16a766"),
        ("Label_3", tr("Reisen", "Travel"), "#ffad47"),
        ("Label_4", tr("Rechnungen", "Invoices"), "#e66550"),
    ]

    static func threads() -> [DemoThread] {
        [
            DemoThread(id: "t-projektplan", subject: tr("Projektplan Q4", "Q4 project plan"), labels: ["INBOX", "UNREAD", "IMPORTANT", "Label_1"], messages: [
                DemoMessage(from: .me, to: [anna], hoursAgo: 26, text: tr(
                    "Hi Anna,\n\nkannst du mir bis Freitag den aktuellen Stand zum Projektplan schicken?\n\nDanke!\nAlex",
                    "Hi Anna,\n\ncould you send me the current state of the project plan by Friday?\n\nThanks!\nAlex")),
                DemoMessage(from: anna, to: [.me], hoursAgo: 0.4, text: tr(
                    "Hallo Alex,\n\nanbei der Projektplan für Q4. Die wichtigsten Meilensteine:\n\n• Kick-off am 7. Oktober\n• Design-Review am 21. Oktober\n• Launch Anfang Dezember\n\nLass uns Donnerstag kurz drüber sprechen.\n\nViele Grüße\nAnna",
                    "Hi Alex,\n\nattached is the Q4 project plan. The key milestones:\n\n• Kick-off on October 7\n• Design review on October 21\n• Launch in early December\n\nLet’s talk it through on Thursday.\n\nBest,\nAnna"),
                            html: tr("""
                            <p>Hallo Alex,</p>
                            <p>anbei der <b>Projektplan für Q4</b>. Die wichtigsten Meilensteine:</p>
                            <ul><li>Kick-off am 7. Oktober</li><li>Design-Review am 21. Oktober</li><li>Launch Anfang Dezember</li></ul>
                            <p>Lass uns Donnerstag kurz drüber sprechen.</p>
                            <p>Viele Grüße<br>Anna</p>
                            """, """
                            <p>Hi Alex,</p>
                            <p>attached is the <b>Q4 project plan</b>. The key milestones:</p>
                            <ul><li>Kick-off on October 7</li><li>Design review on October 21</li><li>Launch in early December</li></ul>
                            <p>Let’s talk it through on Thursday.</p>
                            <p>Best,<br>Anna</p>
                            """),
                            attachments: [DemoAttachment(filename: tr("Projektplan-Q4.pdf", "Project-plan-Q4.pdf"), mimeType: "application/pdf", size: 482_133)]),
            ]),
            DemoThread(id: "t-flug", subject: tr("Ihre Buchungsbestätigung: Flug nach Lissabon", "Your booking confirmation: flight to Lisbon"), labels: ["INBOX", "UNREAD", "Label_3"], messages: [
                DemoMessage(from: travel, to: [.me], hoursAgo: 2.5, text: tr("Ihre Reise nach Lissabon ist gebucht.", "Your trip to Lisbon is booked."),
                            html: tr("""
                            <div style="font-family: -apple-system, Helvetica, sans-serif; max-width: 560px; margin: 0 auto;">
                              <img src="https://example.com/banner.png" width="560" height="120" alt="">
                              <h2 style="color:#1f3a93; margin-bottom: 4px;">Gute Reise, Alex!</h2>
                              <p style="color:#555">Ihre Buchung <b>SW-48213</b> ist bestätigt.</p>
                              <table style="width:100%; border-collapse: collapse; margin-top: 12px;">
                                <tr style="background:#f3f6ff"><td style="padding:10px">Hinflug</td><td style="padding:10px"><b>Fr, 17. Okt · 07:45</b><br>Hamburg → Lissabon</td></tr>
                                <tr><td style="padding:10px">Rückflug</td><td style="padding:10px"><b>Mo, 20. Okt · 18:10</b><br>Lissabon → Hamburg</td></tr>
                                <tr style="background:#f3f6ff"><td style="padding:10px">Gepäck</td><td style="padding:10px">1 × 23 kg</td></tr>
                              </table>
                              <p style="margin-top:16px"><a href="https://example.com/buchung" style="background:#1f3a93;color:white;padding:10px 16px;border-radius:6px;text-decoration:none">Buchung ansehen</a></p>
                            </div>
                            """, """
                            <div style="font-family: -apple-system, Helvetica, sans-serif; max-width: 560px; margin: 0 auto;">
                              <img src="https://example.com/banner.png" width="560" height="120" alt="">
                              <h2 style="color:#1f3a93; margin-bottom: 4px;">Have a great trip, Alex!</h2>
                              <p style="color:#555">Your booking <b>SW-48213</b> is confirmed.</p>
                              <table style="width:100%; border-collapse: collapse; margin-top: 12px;">
                                <tr style="background:#f3f6ff"><td style="padding:10px">Outbound</td><td style="padding:10px"><b>Fri, Oct 17 · 07:45</b><br>Hamburg → Lisbon</td></tr>
                                <tr><td style="padding:10px">Return</td><td style="padding:10px"><b>Mon, Oct 20 · 18:10</b><br>Lisbon → Hamburg</td></tr>
                                <tr style="background:#f3f6ff"><td style="padding:10px">Baggage</td><td style="padding:10px">1 × 23 kg</td></tr>
                              </table>
                              <p style="margin-top:16px"><a href="https://example.com/buchung" style="background:#1f3a93;color:white;padding:10px 16px;border-radius:6px;text-decoration:none">View booking</a></p>
                            </div>
                            """)),
            ]),
            DemoThread(id: "t-kaffee", subject: tr("Kaffee am Donnerstag?", "Coffee on Thursday?"), labels: ["INBOX", "STARRED"], messages: [
                DemoMessage(from: jonas, to: [.me], hoursAgo: 5, text: tr(
                    "Hey Alex,\n\nhast du Donnerstag Zeit für einen Kaffee? Ich wollte dir von dem neuen Job erzählen.\n\nGruß\nJonas",
                    "Hey Alex,\n\ndo you have time for a coffee on Thursday? I wanted to tell you about the new job.\n\nCheers,\nJonas")),
                DemoMessage(from: .me, to: [jonas], hoursAgo: 4, text: tr("Klar, 15 Uhr im Café am Park?\n\nAlex", "Sure, 3 pm at the café by the park?\n\nAlex")),
                DemoMessage(from: jonas, to: [.me], hoursAgo: 3.2, text: tr("Perfekt, bis dann! ☕️", "Perfect, see you then! ☕️")),
            ]),
            DemoThread(id: "t-rechnung", subject: tr("Ihre Rechnung für Oktober", "Your invoice for October"), labels: ["INBOX", "Label_4"], messages: [
                DemoMessage(from: utility, to: [.me], hoursAgo: 20, text: tr(
                    "Sehr geehrter Herr Berger,\n\nim Anhang finden Sie Ihre Rechnung für Oktober. Der Betrag von 84,20 € wird am 15. des Monats abgebucht.\n\nMit freundlichen Grüßen\nIhre Stadtwerke Nord",
                    "Dear Mr Berger,\n\nplease find your invoice for October attached. The amount of €84.20 will be debited on the 15th of the month.\n\nKind regards,\nNorthside Utilities"),
                            attachments: [DemoAttachment(filename: tr("Rechnung-2026-10.pdf", "Invoice-2026-10.pdf"), mimeType: "application/pdf", size: 96_412)]),
            ]),
            DemoThread(id: "t-darkmode", subject: tr("Neues Feature: Dark Mode fürs Dashboard", "New feature: dark mode for the dashboard"), labels: ["INBOX", "Label_2"], messages: [
                DemoMessage(from: lena, to: [.me, anna], hoursAgo: 30, text: tr(
                    "Hallo zusammen,\n\nich habe einen ersten Entwurf für den Dark Mode gebaut. Feedback willkommen!\n\nLena",
                    "Hi both,\n\nI built a first draft of the dark mode. Feedback welcome!\n\nLena")),
                DemoMessage(from: anna, to: [lena, .me], hoursAgo: 28, text: tr(
                    "Sieht super aus! Die Kontraste in den Diagrammen könnten noch etwas stärker sein.",
                    "Looks great! The contrast in the charts could be a little stronger.")),
                DemoMessage(from: lena, to: [.me, anna], hoursAgo: 22, text: tr(
                    "Guter Punkt, ist angepasst. Ich deploye das morgen auf Staging.",
                    "Good point, fixed. I’ll deploy it to staging tomorrow.")),
            ]),
            DemoThread(id: "t-fotos", subject: tr("Fotos vom Wochenende", "Photos from the weekend"), labels: ["INBOX", "UNREAD"], messages: [
                DemoMessage(from: mia, to: [.me], hoursAgo: 8, text: tr(
                    "Hi Alex!\n\nHier die Fotos vom Ausflug an den See. War ein toller Tag!\n\nLiebe Grüße\nMia",
                    "Hi Alex!\n\nHere are the photos from our trip to the lake. What a great day!\n\nLove,\nMia"),
                            attachments: [
                                DemoAttachment(filename: tr("See-1.jpg", "Lake-1.jpg"), mimeType: "image/jpeg", size: 2_310_442),
                                DemoAttachment(filename: tr("See-2.jpg", "Lake-2.jpg"), mimeType: "image/jpeg", size: 1_982_017),
                            ]),
            ]),
            DemoThread(id: "t-lauf", subject: tr("Dein Wochenrückblick: 23,4 km gelaufen", "Your week in review: 23.4 km run"), labels: ["INBOX"], messages: [
                DemoMessage(from: runClub, to: [.me], hoursAgo: 40, text: tr("Starke Woche! Du bist 23,4 km gelaufen.", "Strong week! You ran 23.4 km."),
                            html: tr("""
                            <div style="font-family:-apple-system,Helvetica,sans-serif;text-align:center;padding:24px;background:#fff7ed;border-radius:12px">
                              <div style="font-size:42px;font-weight:700;color:#ea580c">23,4 km</div>
                              <div style="color:#7c2d12">in 4 Läufen · Ø 5:21 min/km</div>
                              <p style="color:#555">Das sind 12 % mehr als letzte Woche. Weiter so!</p>
                            </div>
                            """, """
                            <div style="font-family:-apple-system,Helvetica,sans-serif;text-align:center;padding:24px;background:#fff7ed;border-radius:12px">
                              <div style="font-size:42px;font-weight:700;color:#ea580c">23.4 km</div>
                              <div style="color:#7c2d12">in 4 runs · avg 5:21 min/km</div>
                              <p style="color:#555">That’s 12% more than last week. Keep it up!</p>
                            </div>
                            """)),
            ]),
            DemoThread(id: "t-wartung", subject: tr("Server-Wartung am Samstag", "Server maintenance on Saturday"), labels: ["INBOX"], messages: [
                DemoMessage(from: itSupport, to: [.me], hoursAgo: 52, text: tr(
                    "Hallo zusammen,\n\nam Samstag zwischen 8 und 12 Uhr sind VPN und Intranet wegen Wartungsarbeiten nicht erreichbar.\n\nEuer IT-Support",
                    "Hi everyone,\n\nthe VPN and intranet will be unavailable on Saturday between 8 am and noon for maintenance.\n\nYour IT Support")),
            ]),
            DemoThread(id: "t-wohnung", subject: tr("Wohnungsübergabe", "Apartment handover"), labels: ["SENT"], messages: [
                DemoMessage(from: .me, to: [landlord], hoursAgo: 70, text: tr(
                    "Sehr geehrte Frau Krüger,\n\npasst Ihnen die Übergabe am 31. um 10 Uhr?\n\nViele Grüße\nAlex Berger",
                    "Dear Ms Krüger,\n\nwould the handover on the 31st at 10 am work for you?\n\nKind regards,\nAlex Berger")),
            ]),
            DemoThread(id: "t-sommerfest", subject: tr("Einladung: Sommerfest 2026", "Invitation: summer party 2026"), labels: [], messages: [
                DemoMessage(from: events, to: [.me], hoursAgo: 900, text: tr(
                    "Liebe Kolleginnen und Kollegen,\n\nwir laden euch herzlich zum Sommerfest ein!",
                    "Dear colleagues,\n\nyou are warmly invited to our summer party!")),
            ]),
            DemoThread(id: "t-entwurf", subject: tr("Angebot Website-Relaunch", "Proposal: website relaunch"), labels: ["DRAFT"], messages: [
                DemoMessage(from: .me, to: [anna], hoursAgo: 12, text: tr("Hallo Anna,\n\nhier mein Entwurf für das Angebot …", "Hi Anna,\n\nhere is my draft of the proposal…")),
            ]),
            DemoThread(id: "t-spam", subject: tr("Herzlichen Glückwunsch, Sie haben gewonnen!!!", "Congratulations, you have won!!!"), labels: ["SPAM", "UNREAD"], messages: [
                DemoMessage(from: spammer, to: [.me], hoursAgo: 6, text: tr("Klicken Sie hier, um Ihren Preis abzuholen.", "Click here to claim your prize.")),
            ]),
        ]
    }
}

// MARK: - Fake Gmail API

/// Answers Gmail REST requests from in-memory sample data, including label changes.
private final class DemoTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var threads = DemoData.threads()
    private var draftCounter = 0
    private let now = Date()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 120_000_000) // feels like a network
        let (status, body) = lock.withLock { route(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (try JSONSerialization.data(withJSONObject: body), response)
    }

    private func route(_ request: URLRequest) -> (Int, Any) {
        guard let url = request.url else { return (400, [:]) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let path = url.path
            .replacingOccurrences(of: "/upload/gmail/v1/users/me/", with: "")
            .replacingOccurrences(of: "/gmail/v1/users/me/", with: "")
        let parts = path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        let method = request.httpMethod ?? "GET"

        switch (method, parts.first ?? "", parts.count) {
        case ("GET", "profile", _):
            return (200, ["emailAddress": DemoMailbox.email, "historyId": "1000", "messagesTotal": 20, "threadsTotal": threads.count])
        case ("GET", "settings", _):
            return (200, ["sendAs": [
                [
                    "sendAsEmail": DemoMailbox.email, "displayName": DemoMailbox.displayName, "isDefault": true, "isPrimary": true,
                    "signature": tr(
                        "<div>Viele Grüße<br><b>Alex Berger</b><br>Produktmanagement · <a href=\"https://example.com\">example.com</a></div>",
                        "<div>Best regards,<br><b>Alex Berger</b><br>Product Management · <a href=\"https://example.com\">example.com</a></div>"
                    ),
                ],
                [
                    "sendAsEmail": "alex@berger-photo.example", "displayName": tr("Alex Berger Fotografie", "Alex Berger Photography"),
                    "signature": "<div>Alex Berger<br>berger-photo.example</div>", "verificationStatus": "accepted",
                ],
            ]])
        case ("GET", "labels", 1):
            return (200, ["labels": allLabels().map { labelJSON($0, withCounts: false) }])
        case ("GET", "labels", 2):
            guard let label = allLabels().first(where: { $0.id == parts[1] }) else { return notFound() }
            return (200, labelJSON(label, withCounts: true))
        case ("GET", "threads", 1):
            return (200, listThreads(labelIDs: query.filter { $0.name == "labelIds" }.compactMap(\.value), q: query.first { $0.name == "q" }?.value))
        case ("GET", "threads", 2):
            guard let thread = threads.first(where: { $0.id == parts[1] }) else { return notFound() }
            return (200, threadJSON(thread))
        case ("POST", "threads", 3):
            guard let index = threads.firstIndex(where: { $0.id == parts[1] }) else { return notFound() }
            switch parts[2] {
            case "modify":
                let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: [String]]) ?? [:]
                threads[index].labels.formUnion(body["addLabelIds"] ?? [])
                threads[index].labels.subtract(body["removeLabelIds"] ?? [])
            case "trash":
                threads[index].labels.insert("TRASH")
                threads[index].labels.remove("INBOX")
            case "untrash":
                threads[index].labels.remove("TRASH")
                threads[index].labels.insert("INBOX")
            default:
                return notFound()
            }
            return (200, ["id": threads[index].id])
        case ("GET", "messages", _) where parts.count == 4:
            return (200, ["size": 18, "data": Base64URL.encode(Data("Mailmeg Demo-Anhang".utf8))])
        case ("GET", "messages", 2) where query.contains(where: { $0.name == "format" && $0.value == "raw" }):
            guard let source = rawSource(messageID: parts[1]) else { return notFound() }
            return (200, ["id": parts[1], "raw": Base64URL.encode(Data(source.utf8))])
        case ("GET", "messages", 2):
            for thread in threads {
                if let json = threadJSON(thread)["messages"] as? [[String: Any]],
                   let message = json.first(where: { $0["id"] as? String == parts[1] }) {
                    return (200, message)
                }
            }
            return notFound()
        case ("POST", "messages", _):
            return (200, ["id": "demo-sent-\(UUID().uuidString)", "threadId": "t-sent", "labelIds": ["SENT"]])
        case ("GET", "drafts", 1):
            let drafts = threads.filter { $0.labels.contains("DRAFT") }.map { thread -> [String: Any] in
                ["id": "d-\(thread.id)", "message": ["id": "\(thread.id)-\(thread.messages.count - 1)", "threadId": thread.id]]
            }
            return (200, ["drafts": drafts])
        case ("POST", "drafts", 2) where parts[1] == "send":
            let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: String]) ?? [:]
            let threadID = String((body["id"] ?? "").dropFirst(2))
            threads.removeAll { $0.id == threadID }
            return (200, ["id": "demo-sent-\(UUID().uuidString)", "threadId": threadID, "labelIds": ["SENT"]])
        case ("POST", "drafts", 1):
            guard let draft = parseDraftUpload(request.httpBody) else { return (400, ["error": ["code": 400, "message": "Bad draft"]]) }
            draftCounter += 1
            let threadID = "t-draft-\(draftCounter)"
            threads.append(DemoThread(id: threadID, subject: draft.subject, labels: ["DRAFT"], messages: [draft.message]))
            return (200, ["id": "d-\(threadID)", "message": ["id": "\(threadID)-0", "threadId": threadID]])
        case ("PUT", "drafts", 2):
            let threadID = String(parts[1].dropFirst(2))
            guard let index = threads.firstIndex(where: { $0.id == threadID }),
                  let draft = parseDraftUpload(request.httpBody) else { return notFound() }
            threads[index].subject = draft.subject
            threads[index].messages[threads[index].messages.count - 1] = draft.message
            return (200, ["id": parts[1], "message": ["id": "\(threadID)-\(threads[index].messages.count - 1)", "threadId": threadID]])
        case ("DELETE", "drafts", 2):
            let threadID = String(parts[1].dropFirst(2))
            guard threads.contains(where: { $0.id == threadID }) else { return notFound() }
            threads.removeAll { $0.id == threadID }
            return (204, [:] as [String: Any])
        case ("GET", "history", _):
            return (200, ["historyId": "1000", "history": []])
        default:
            return notFound()
        }
    }

    /// A plausible RFC 822 source for a demo message ("thread-index").
    private func rawSource(messageID: String) -> String? {
        guard let dash = messageID.lastIndex(of: "-"), let index = Int(messageID[messageID.index(after: dash)...]),
              let thread = threads.first(where: { $0.id == String(messageID[..<dash]) }),
              thread.messages.indices.contains(index) else { return nil }
        let message = thread.messages[index]
        let date = now.addingTimeInterval(-message.hoursAgo * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let stamp = formatter.string(from: date)
        let domain = message.from.email.split(separator: "@").last.map(String.init) ?? "example.com"
        let lines = [
            "Delivered-To: \(DemoMailbox.email)",
            "Received: by 2002:a05:6a10:demo with SMTP id demo;",
            "        \(stamp)",
            "Return-Path: <\(message.from.email)>",
            "Received: from mail.\(domain) (mail.\(domain). [203.0.113.7])",
            "        by mx.google.com with ESMTPS id demo.\(index)",
            "        for <\(DemoMailbox.email)>; \(stamp)",
            "Authentication-Results: mx.google.com; dkim=pass header.i=@\(domain); spf=pass; dmarc=pass",
            "Message-ID: <\(messageID)@demo.mailmeg>",
            "Date: \(stamp)",
            "From: \(message.from.header)",
            "To: \(message.to.map(\.header).joined(separator: ", "))",
            "Subject: \(MIMEBuilder.encodeHeaderText(thread.subject))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=\"UTF-8\"",
            "Content-Transfer-Encoding: 8bit",
            "",
            message.text,
        ]
        return lines.joined(separator: "\r\n")
    }

    /// Tiny MIME reader for the demo: subject, recipients and the text/plain part.
    private func parseDraftUpload(_ body: Data?) -> (subject: String, message: DemoMessage)? {
        guard let body, let text = String(data: body, encoding: .utf8),
              let rawStart = text.range(of: "Content-Type: message/rfc822\r\n\r\n") else { return nil }
        var raw = String(text[rawStart.upperBound...])
        if let end = raw.range(of: "\r\n--mailmeg-upload-", options: .backwards) { raw = String(raw[..<end.lowerBound]) }
        let headerEnd = raw.range(of: "\r\n\r\n")?.lowerBound ?? raw.endIndex
        let headerText = raw[..<headerEnd].replacingOccurrences(of: "\r\n ", with: " ")
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        func decodeWords(_ value: String) -> String {
            guard value.contains("=?UTF-8?B?") else { return value }
            return value.components(separatedBy: " ").map { word -> String in
                guard word.hasPrefix("=?UTF-8?B?"), word.hasSuffix("?=") else { return word }
                let encoded = word.dropFirst(10).dropLast(2)
                return Data(base64Encoded: String(encoded)).flatMap { String(data: $0, encoding: .utf8) } ?? word
            }.joined()
        }
        var bodyText = ""
        if let plain = raw.range(of: "Content-Type: text/plain"),
           let start = raw.range(of: "\r\n\r\n", range: plain.upperBound..<raw.endIndex) {
            var encoded = String(raw[start.upperBound...])
            if let end = encoded.range(of: "\r\n--") { encoded = String(encoded[..<end.lowerBound]) }
            bodyText = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            bodyText = bodyText.replacingOccurrences(of: "\r\n", with: "\n")
        }
        let recipients = EmailAddress.parseList(decodeWords(headers["to"] ?? ""))
            .map { DemoPerson(name: $0.name ?? $0.address, email: $0.address) }
        let message = DemoMessage(from: .me, to: recipients, hoursAgo: 0, text: bodyText)
        return (decodeWords(headers["subject"] ?? ""), message)
    }

    private func notFound() -> (Int, Any) {
        (404, ["error": ["code": 404, "message": "Not found (demo)"]])
    }

    // MARK: Labels

    private struct Label {
        let id: String
        let name: String
        let type: String
        let color: String?
    }

    private func allLabels() -> [Label] {
        let system = ["INBOX", "STARRED", "IMPORTANT", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD"]
            .map { Label(id: $0, name: $0, type: "system", color: nil) }
        let user = DemoData.labels.map { Label(id: $0.id, name: $0.name, type: "user", color: $0.color) }
        return system + user
    }

    private func labelJSON(_ label: Label, withCounts: Bool) -> [String: Any] {
        var json: [String: Any] = [
            "id": label.id, "name": label.name, "type": label.type,
            "labelListVisibility": "labelShow", "messageListVisibility": "show",
        ]
        if let color = label.color {
            json["color"] = ["backgroundColor": color, "textColor": "#ffffff"]
        }
        if withCounts {
            let tagged = threads.filter { $0.labels.contains(label.id) }
            json["threadsTotal"] = tagged.count
            json["threadsUnread"] = tagged.filter { $0.labels.contains("UNREAD") }.count
            json["messagesTotal"] = tagged.reduce(0) { $0 + $1.messages.count }
            json["messagesUnread"] = json["threadsUnread"]
        }
        return json
    }

    // MARK: Threads

    private func latestDate(_ thread: DemoThread) -> Date {
        now.addingTimeInterval(-(thread.messages.map(\.hoursAgo).min() ?? 0) * 3600)
    }

    private func listThreads(labelIDs: [String], q: String?) -> [String: Any] {
        var terms = (q ?? "").lowercased().split(separator: " ").map(String.init)
        let unreadOnly = terms.contains("is:unread")
        terms.removeAll { $0.contains(":") }

        let matching = threads
            .filter { thread in
                if labelIDs.isEmpty {
                    if !thread.labels.isDisjoint(with: ["SPAM", "TRASH"]) { return false }
                } else if !Set(labelIDs).isSubset(of: thread.labels) {
                    return false
                }
                if unreadOnly, !thread.labels.contains("UNREAD") { return false }
                guard !terms.isEmpty else { return true }
                let haystack = ([thread.subject] + thread.messages.flatMap { [$0.text, $0.from.name, $0.from.email] })
                    .joined(separator: " ").lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { latestDate($0) > latestDate($1) }
        return ["threads": matching.map { ["id": $0.id, "historyId": "1000"] }, "resultSizeEstimate": matching.count]
    }

    private func threadJSON(_ thread: DemoThread) -> [String: Any] {
        let messages = thread.messages.enumerated().map { index, message -> [String: Any] in
            let isLast = index == thread.messages.count - 1
            var labelIDs = thread.labels.subtracting(["UNREAD", "STARRED"])
            if isLast {
                labelIDs.formUnion(thread.labels.intersection(["UNREAD", "STARRED"]))
            }
            if message.from.email == DemoMailbox.email {
                labelIDs.insert("SENT")
            }
            let id = "\(thread.id)-\(index)"
            let date = now.addingTimeInterval(-message.hoursAgo * 3600)
            return [
                "id": id,
                "threadId": thread.id,
                "labelIds": Array(labelIDs),
                "snippet": String(message.text.replacingOccurrences(of: "\n", with: " ").prefix(140)),
                "historyId": "1000",
                "internalDate": String(Int64(date.timeIntervalSince1970 * 1000)),
                "payload": payload(for: message, thread: thread, id: id, date: date),
            ]
        }
        return ["id": thread.id, "historyId": "1000", "messages": messages]
    }

    private func payload(for message: DemoMessage, thread: DemoThread, id: String, date: Date) -> [String: Any] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let headers: [[String: String]] = [
            ["name": "Delivered-To", "value": DemoMailbox.email],
            ["name": "From", "value": message.from.header],
            ["name": "To", "value": message.to.map(\.header).joined(separator: ", ")],
            ["name": "Subject", "value": thread.subject],
            ["name": "Date", "value": formatter.string(from: date)],
            ["name": "Message-ID", "value": "<\(id)@demo.mailmeg>"],
        ]

        func textPart(_ text: String, subtype: String, partID: String) -> [String: Any] {
            let data = Data(text.utf8)
            return [
                "partId": partID, "mimeType": "text/\(subtype)", "filename": "",
                "headers": [["name": "Content-Type", "value": "text/\(subtype); charset=UTF-8"]],
                "body": ["size": data.count, "data": Base64URL.encode(data)],
            ]
        }

        var body: [String: Any]
        if let html = message.html {
            body = [
                "partId": "0", "mimeType": "multipart/alternative", "filename": "",
                "body": ["size": 0],
                "parts": [textPart(message.text, subtype: "plain", partID: "0.0"), textPart(html, subtype: "html", partID: "0.1")],
            ]
        } else {
            body = textPart(message.text, subtype: "plain", partID: "0")
        }

        guard !message.attachments.isEmpty else {
            body["headers"] = headers + ((body["headers"] as? [[String: String]]) ?? [])
            return body
        }
        let attachmentParts: [[String: Any]] = message.attachments.enumerated().map { index, attachment in
            [
                "partId": "\(index + 1)", "mimeType": attachment.mimeType, "filename": attachment.filename,
                "headers": [["name": "Content-Disposition", "value": "attachment; filename=\"\(attachment.filename)\""]],
                "body": ["attachmentId": "att-\(index)", "size": attachment.size],
            ]
        }
        return [
            "partId": "", "mimeType": "multipart/mixed", "filename": "",
            "headers": headers,
            "body": ["size": 0],
            "parts": [body] + attachmentParts,
        ]
    }
}

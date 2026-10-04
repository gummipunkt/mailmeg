import Foundation
import MailmegKit

/// A new calendar event being written in the event window.
struct EventDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    var accountID: String
    var title = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var location = ""
    /// Comma-separated email addresses.
    var attendees = ""
    var notes = ""
    var calendarID: String?
    var notifyAttendees = true

    /// An hour-long event at the next full hour (on `day`, if given).
    static func new(accountID: String, day: Date? = nil) -> EventDraft {
        let calendar = Calendar.current
        let now = Date()
        var start = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        if let day, !calendar.isDate(day, inSameDayAs: now) {
            start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        }
        return EventDraft(accountID: accountID, start: start, end: start.addingTimeInterval(3600))
    }

    /// Prefilled from an email: its subject as title, the people in it as guests.
    @MainActor
    static func from(_ message: GmailMessage, account: AccountSession) -> EventDraft {
        var draft = new(accountID: account.id)
        draft.title = message.subject
            .replacingOccurrences(of: #"^((re|aw|wg|fwd?):\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
        let own = Set(account.ownAddresses)
        var seen = Set<String>()
        let people = ([message.from].compactMap { $0 } + message.to + message.cc).filter { address in
            let key = address.address.lowercased()
            guard !own.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        draft.attendees = people.map(\.address).joined(separator: ", ")
        let sender = message.from?.displayName ?? ""
        draft.notes = tr("Aus der E-Mail „\(message.subject)“ von \(sender).", "From the email “\(message.subject)” by \(sender).")
        return draft
    }

    var attendeeAddresses: [String] {
        EmailAddress.parseList(attendees).map(\.address).filter { $0.contains("@") }
    }

    /// The event for the Calendar API. All-day events end on the day after the last day.
    var newEvent: NewCalendarEvent {
        let calendar = Calendar.current
        let startValue: EventDateTime
        let endValue: EventDateTime
        if isAllDay {
            let firstDay = calendar.startOfDay(for: start)
            let lastDay = max(calendar.startOfDay(for: end), firstDay)
            startValue = EventDateTime(firstDay, allDay: true)
            endValue = EventDateTime(calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay, allDay: true)
        } else {
            startValue = EventDateTime(start, allDay: false)
            endValue = EventDateTime(max(end, start.addingTimeInterval(60)), allDay: false)
        }
        let guests = attendeeAddresses.map { EventAttendee(email: $0) }
        return NewCalendarEvent(
            summary: title.trimmingCharacters(in: .whitespacesAndNewlines),
            start: startValue,
            end: endValue,
            location: location.isEmpty ? nil : location,
            description: notes.isEmpty ? nil : notes,
            attendees: guests.isEmpty ? nil : guests
        )
    }
}

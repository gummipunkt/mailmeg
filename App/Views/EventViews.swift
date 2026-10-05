import AppKit
import MailmegKit
import SwiftUI

// MARK: - Invitation card in a message

/// A calendar invitation inside an email: date, place and the answer buttons.
struct InvitationCard: View {
    @Environment(AppModel.self) private var model
    let item: MessageItem
    let detail: ThreadDetailModel
    @State private var isResponding = false

    private var invitation: CalendarInvitation? { item.invitation }
    private var store: CalendarStore { detail.account.calendar }

    var body: some View {
        if let invitation {
            HStack(alignment: .top, spacing: 14) {
                dateTile(invitation.start)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(invitation.summary.isEmpty ? tr("(Ohne Titel)", "(No title)") : invitation.summary)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(2)
                        if invitation.isCancellation {
                            badge(tr("Abgesagt", "Cancelled"), color: Color(hex: "#d93025"))
                        } else if let response = item.invitationEvent?.myResponse, response != .needsAction {
                            badge(CalendarFormat.responseLabel(response), color: RSVPIcon.color(response))
                                .accessibilityIdentifier("invitation.status")
                        }
                    }
                    Text(CalendarFormat.invitationRange(invitation))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let location = invitation.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let organizer = invitation.organizer {
                        Text(tr("Einladung von \(organizer.displayName)", "Invitation from \(organizer.displayName)"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                    actions(invitation)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.5))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("invitation.card")
        }
    }

    @ViewBuilder
    private func actions(_ invitation: CalendarInvitation) -> some View {
        if invitation.isCancellation || invitation.isReply {
            EmptyView()
        } else if store.access == .needsConsent {
            Button(tr("Kalender verbinden, um zu antworten …", "Connect your calendar to reply…")) {
                model.showCalendar(accountID: detail.account.id)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        } else if let event = item.invitationEvent {
            HStack(spacing: 10) {
                if event.selfAttendee != nil {
                    RSVPButtons(current: event.myResponse, isBusy: isResponding) { status in
                        isResponding = true
                        Task {
                            await detail.respond(to: item.id, with: status)
                            isResponding = false
                        }
                    }
                }
                Button(tr("Im Kalender zeigen", "Show in Calendar")) {
                    model.showCalendar(accountID: detail.account.id, day: event.startDate ?? Date(), eventID: event.key)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        } else if store.isUsable {
            Text(tr("Dieser Termin ist nicht in deinem Google Kalender.", "This event isn’t in your Google Calendar."))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func dateTile(_ date: Date?) -> some View {
        VStack(spacing: 0) {
            Text((date ?? Date()).formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Palette.violet)
            Text(date.map { "\(Calendar.current.component(.day, from: $0))" } ?? "–")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 52, height: 56)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - New event window

struct EventEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsDelete = false

    init(draft: EventDraft) {
        _draft = State(initialValue: draft)
    }

    private var account: AccountSession? {
        model.account(id: draft.accountID) ?? model.accounts.first
    }

    private var store: CalendarStore? { account?.calendar }

    /// The event being edited, as last loaded.
    private var original: CalendarEvent? {
        guard let eventID = draft.eventID else { return nil }
        return store?.events.first { $0.id == eventID && $0.calendarID == draft.calendarID }
            ?? store?.events.first { $0.id == eventID }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && store?.isUsable == true
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                row(tr("Titel", "Title")) {
                    TextField("", text: $draft.title, prompt: Text(tr("Worum geht es?", "What’s it about?")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("event.title")
                }
                if let store, store.writableCalendars.count > 1, !draft.isEditing {
                    row(tr("Kalender", "Calendar")) {
                        Picker("", selection: Binding(
                            get: { draft.calendarID ?? store.writableCalendars.first?.id ?? "primary" },
                            set: { draft.calendarID = $0 }
                        )) {
                            ForEach(store.writableCalendars) { calendar in
                                Text(calendar.title).tag(calendar.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                    }
                }
                row(tr("Ganztägig", "All-day")) {
                    Toggle("", isOn: $draft.isAllDay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                }
                row(tr("Beginn", "Starts")) {
                    DatePicker("", selection: Binding(
                        get: { draft.start },
                        set: { newStart in
                            // Moving the start keeps the duration.
                            let duration = draft.end.timeIntervalSince(draft.start)
                            draft.start = newStart
                            draft.end = newStart.addingTimeInterval(max(duration, draft.isAllDay ? 0 : 900))
                        }
                    ), displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
                    .accessibilityIdentifier("event.start")
                    Spacer()
                }
                row(tr("Ende", "Ends")) {
                    DatePicker("", selection: $draft.end, in: draft.start..., displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                    Spacer()
                }
                row(tr("Ort", "Location")) {
                    TextField("", text: $draft.location, prompt: Text(tr("Adresse oder Raum", "Address or room")))
                        .textFieldStyle(.plain)
                }
                row(tr("Gäste", "Guests"), showsDivider: false) {
                    TextField("", text: $draft.attendees, prompt: Text(tr("name@beispiel.de, …", "name@example.com, …")))
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("event.attendees")
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Notizen", "Notes"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.notes)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70)
            }
            .padding(12)
            .card()

            HStack(spacing: 10) {
                if !draft.attendeeAddresses.isEmpty {
                    Toggle(tr("Einladungen per E-Mail senden", "Email invitations to guests"), isOn: $draft.notifyAttendees)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                if store?.access == .needsConsent {
                    Label(tr("Kalender noch nicht verbunden", "Calendar not connected yet"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if draft.isEditing {
                    Button(tr("Löschen …", "Delete…"), role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("event.delete")
                }
                Button(tr("Abbrechen", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(draft.isEditing ? tr("Sichern", "Save") : tr("Termin anlegen", "Add Event"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
                .accessibilityIdentifier("event.save")
            }
        }
        .padding(14)
        .glassBackground(.canvas)
        .navigationTitle(draft.title.isEmpty ? (draft.isEditing ? tr("Termin bearbeiten", "Edit Event") : tr("Neuer Termin", "New Event")) : draft.title)
        .frame(minWidth: 480, minHeight: 470)
        .confirmationDialog(tr("Termin löschen?", "Delete this event?"), isPresented: $confirmsDelete) {
            Button(tr("Löschen", "Delete"), role: .destructive) { Task { await delete() } }
        } message: {
            Text(draft.attendeeAddresses.isEmpty
                 ? tr("Der Termin wird aus deinem Google Kalender entfernt.", "The event is removed from your Google Calendar.")
                 : tr("Die Gäste bekommen eine Absage per E-Mail.", "Guests get a cancellation by email."))
        }
        .alert(draft.isEditing ? tr("Termin nicht gesichert", "Event Not Saved") : tr("Termin nicht angelegt", "Event Not Added"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if let store, store.calendars.isEmpty {
                let start = Calendar.current.startOfDay(for: draft.start)
                await store.ensureLoaded(DateInterval(start: start, end: start.addingTimeInterval(86_400)))
            }
        }
    }

    private func row<Content: View>(_ title: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                content()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if showsDivider {
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.leading, 16)
            }
        }
    }

    private func save() async {
        guard let store else { return }
        isSaving = true
        defer { isSaving = false }
        let calendarID = draft.calendarID ?? store.writableCalendars.first?.id ?? "primary"
        do {
            if draft.isEditing, let eventID = draft.eventID {
                let event = original ?? CalendarEvent(
                    id: eventID, summary: draft.title,
                    start: EventDateTime(draft.start, allDay: draft.isAllDay), end: EventDateTime(draft.end, allDay: draft.isAllDay),
                    calendarID: calendarID
                )
                let updated = try await store.update(event, with: draft.patch(keeping: original), notifyAttendees: draft.notifyAttendees)
                model.eventCreated(updated, accountID: store.accountID)
            } else {
                let created = try await store.create(draft.newEvent, calendarID: calendarID, notifyAttendees: draft.notifyAttendees)
                model.eventCreated(created, accountID: store.accountID)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        guard let store, let event = original else {
            dismiss()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.delete(event, notifyAttendees: draft.notifyAttendees)
            model.calendarView?.selectedEventID = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

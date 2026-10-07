import MailmegKit
import SwiftUI

struct MailCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(tr("Über MailMeG", "About MailMeG")) { AppInfo.showAboutPanel() }
        }

        CommandGroup(replacing: .newItem) {
            Button(tr("Neue E-Mail", "New Message")) { openWindow(value: model.newDraft()) }
                .keyboardShortcut("n")
                .disabled(model.accounts.isEmpty)
            Button(tr("Neuer Termin …", "New Event…")) { openWindow(value: model.newEventDraft()) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model.accounts.isEmpty)
        }

        CommandMenu(tr("Postfach", "Mailbox")) {
            Button(tr("Neue E-Mails abrufen", "Get New Mail")) { Task { await model.refreshAll() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(tr("Mail", "Mail")) { model.show(.mail) }
                .keyboardShortcut("1")
                .disabled(model.accounts.isEmpty)
            Button(tr("Kalender", "Calendar")) { model.show(.calendar) }
                .keyboardShortcut("2")
                .disabled(model.accounts.isEmpty)
            Divider()
            Button(tr("Konto hinzufügen …", "Add Account…")) { Task { await model.signIn() } }
        }

        CommandMenu(tr("E-Mail", "Message")) {
            Button(tr("Antworten", "Reply")) { compose(.reply) }
                .keyboardShortcut("r")
                .disabled(model.threadDetail == nil)
            Button(tr("Allen antworten", "Reply All")) { compose(.replyAll) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Button(tr("Weiterleiten", "Forward")) { compose(.forward) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Divider()
            Button(tr("Archivieren", "Archive")) { model.perform(.archive) }
                .keyboardShortcut("a", modifiers: [.command, .control])
                .disabled(model.selectedThreadID == nil)
            Button(tr("In den Papierkorb", "Move to Trash")) { model.perform(.trash) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedThreadID == nil)
            Button(tr("Als Spam melden", "Report Spam")) { model.perform(.reportSpam) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Divider()
            Button(model.selectedThread?.isUnread == true ? tr("Als gelesen markieren", "Mark as Read") : tr("Als ungelesen markieren", "Mark as Unread")) { model.toggleRead() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Button(model.selectedThread?.isStarred == true ? tr("Markierung entfernen", "Remove Star") : tr("Markieren", "Star")) { model.toggleStar() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Divider()
            Button(tr("Vorherige Konversation", "Previous Conversation")) { model.selectAdjacentThread(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model.mailbox?.threads.isEmpty ?? true)
            Button(tr("Nächste Konversation", "Next Conversation")) { model.selectAdjacentThread(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model.mailbox?.threads.isEmpty ?? true)
            Divider()
            Button(tr("Termin aus E-Mail erstellen …", "Create Event from Email…")) {
                if let draft = model.eventDraftFromSelectedMessage() { openWindow(value: draft) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(model.threadDetail == nil)
            Divider()
            Button(tr("Header anzeigen", "Show Headers")) { showSource(.headers) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Button(tr("Quelltext anzeigen", "Show Source")) { showSource(.source) }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(model.threadDetail == nil)
        }
    }

    private func showSource(_ mode: SourceRequest.Mode) {
        if let request = model.threadDetail?.sourceRequest(mode) {
            openWindow(value: request)
        }
    }

    private func compose(_ kind: ComposeKind) {
        if let draft = model.replyDraft(kind) {
            openWindow(value: draft)
        }
    }
}

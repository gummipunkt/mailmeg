import MailmegKit
import SwiftUI

struct MailCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neue E-Mail") { openWindow(value: model.newDraft()) }
                .keyboardShortcut("n")
                .disabled(model.accounts.isEmpty)
        }

        CommandMenu("Postfach") {
            Button("Neue E-Mails abrufen") { Task { await model.refreshAll() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Konto hinzufügen …") { Task { await model.signIn() } }
        }

        CommandMenu("E-Mail") {
            Button("Antworten") { compose(.reply) }
                .keyboardShortcut("r")
                .disabled(model.threadDetail == nil)
            Button("Allen antworten") { compose(.replyAll) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Button("Weiterleiten") { compose(.forward) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Divider()
            Button("Archivieren") { model.perform(.archive) }
                .keyboardShortcut("a", modifiers: [.command, .control])
                .disabled(model.selectedThreadID == nil)
            Button("In den Papierkorb") { model.perform(.trash) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedThreadID == nil)
            Button("Als Spam melden") { model.perform(.reportSpam) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Divider()
            Button(model.selectedThread?.isUnread == true ? "Als gelesen markieren" : "Als ungelesen markieren") { model.toggleRead() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Button(model.selectedThread?.isStarred == true ? "Markierung entfernen" : "Markieren") { model.toggleStar() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
        }
    }

    private func compose(_ kind: ComposeKind) {
        if let draft = model.replyDraft(kind) {
            openWindow(value: draft)
        }
    }
}

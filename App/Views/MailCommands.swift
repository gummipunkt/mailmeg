import MailmegKit
import SwiftUI

struct MailCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Message") { openWindow(value: model.newDraft()) }
                .keyboardShortcut("n")
                .disabled(model.accounts.isEmpty)
        }

        CommandMenu("Mailbox") {
            Button("Get New Mail") { Task { await model.refreshAll() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Add Account…") { Task { await model.signIn() } }
        }

        CommandMenu("Message") {
            Button("Reply") { compose(.reply) }
                .keyboardShortcut("r")
                .disabled(model.threadDetail == nil)
            Button("Reply All") { compose(.replyAll) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Button("Forward") { compose(.forward) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.threadDetail == nil)
            Divider()
            Button("Archive") { model.perform(.archive) }
                .keyboardShortcut("a", modifiers: [.command, .control])
                .disabled(model.selectedThreadID == nil)
            Button("Move to Trash") { model.perform(.trash) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedThreadID == nil)
            Button("Report Spam") { model.perform(.reportSpam) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Divider()
            Button(model.selectedThread?.isUnread == true ? "Mark as Read" : "Mark as Unread") { model.toggleRead() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.selectedThreadID == nil)
            Button(model.selectedThread?.isStarred == true ? "Remove Star" : "Add Star") { model.toggleStar() }
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

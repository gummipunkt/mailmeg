import MailmegKit
import SwiftUI

@main
struct MailmegApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Mailmeg", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 520)
        }
        .commands {
            MailCommands(model: model)
        }

        WindowGroup("New Message", id: "compose", for: ComposeDraft.self) { $draft in
            ComposeView(draft: draft ?? model.newDraft())
                .environment(model)
        }
        .defaultSize(width: 680, height: 560)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

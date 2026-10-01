import MailmegKit
import SwiftUI

@main
struct MailmegApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Mailmeg", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            MailCommands(model: model)
        }

        WindowGroup("Neue E-Mail", id: "compose", for: ComposeDraft.self) { $draft in
            ComposeView(draft: draft ?? model.newDraft())
                .environment(model)
        }
        .defaultSize(width: 700, height: 600)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

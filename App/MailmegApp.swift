import MailmegKit
import SwiftUI

@main
struct MailmegApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("MailMeG", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            MailCommands(model: model)
        }

        WindowGroup(tr("Neue E-Mail", "New Message"), id: "compose", for: ComposeDraft.self) { $draft in
            ComposeView(draft: draft ?? model.newDraft())
                .environment(model)
        }
        .defaultSize(width: 700, height: 600)
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup(tr("Quelltext", "Source"), id: "source", for: SourceRequest.self) { $request in
            if let request {
                SourceView(request: request)
                    .environment(model)
            }
        }
        .defaultSize(width: 820, height: 620)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

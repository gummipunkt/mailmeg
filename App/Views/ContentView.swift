import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.accounts.isEmpty {
                OnboardingView()
            } else {
                RootView()
            }
        }
        .task {
            if LaunchOptions.dark {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            await model.start()
        }
        .alert(
            tr("Da ist etwas schiefgelaufen", "Something Went Wrong"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

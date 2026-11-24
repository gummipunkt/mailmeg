import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Group {
                if model.isLoadingAccounts {
                    LoadingAccountsView()
                } else if model.accounts.isEmpty {
                    OnboardingView()
                } else {
                    RootView()
                }
            }
            // Every column draws its part of one backdrop; for that it needs the window's size.
            .environment(\.windowSize, CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ))
        }
        // Mail actions go to the window's undo stack (Edit > Undo, ⌘Z).
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        // "Reduce motion" in System Settings: no sliding and springing.
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
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

/// Shown while the saved sign-ins are read from the keychain at launch.
private struct LoadingAccountsView: View {
    @State private var showsHint = false

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            ProgressView()
                .controlSize(.small)
            Text(tr("Konten werden geladen …", "Loading accounts…"))
                .font(.system(size: 13, weight: .medium))
            if showsHint {
                Text(tr(
                    "Fragt macOS nach dem Zugriff auf den Schlüsselbund? Gib dein Mac-Passwort ein und wähle „Immer erlauben“. Das Fenster kann hinter anderen Fenstern liegen.",
                    "Is macOS asking for keychain access? Enter your Mac password and choose “Always Allow”. The dialog may be hidden behind other windows."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .transition(.opacity)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(.canvas)
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showsHint = true }
        }
    }
}

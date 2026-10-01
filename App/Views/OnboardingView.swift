import AppKit
import MailmegKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var clientID = AppSettings.clientID

    private var isValid: Bool { GoogleOAuthConfig(clientID: clientID).isValid }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(light: "#B1CBFA", dark: "#2B2D5C"),
                    Color(light: "#DFE2FE", dark: "#17182C"),
                    Color(light: "#8E98F5", dark: "#3A3586"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

                VStack(spacing: 6) {
                    Text("Willkommen bei Mailmeg")
                        .font(.system(size: 30, weight: .bold))
                    Text("Gmail als echte Mac-App, direkt über die Gmail-API. Ohne Browser, ohne Umwege.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Projekt in der Google Cloud Console anlegen und die **Gmail API** aktivieren.")
                    step(2, "OAuth-Client vom Typ **iOS** erstellen, Bundle-ID `de.mailmeg.app`.")
                    step(3, "Client-ID hier einfügen und anmelden.")

                    TextField("1234567890-abc.apps.googleusercontent.com", text: $clientID)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(isValid ? Color.accentColor : Theme.hairline)
                        )
                        .onChange(of: clientID) { _, newValue in
                            AppSettings.clientID = newValue
                        }

                    Button {
                        Task { await model.signIn() }
                    } label: {
                        HStack {
                            if model.isSigningIn {
                                ProgressView().controlSize(.small)
                            }
                            Text("Mit Google anmelden")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || model.isSigningIn)

                    Text("Die genaue Anleitung steht in der README. Deine Daten bleiben zwischen deinem Mac und Google.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(width: 460)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.hairline.opacity(0.6))
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)

                Button("Erst mal ohne Konto ausprobieren →") {
                    Task { await model.startDemo() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("onboarding.demo")
            }
            .padding(40)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

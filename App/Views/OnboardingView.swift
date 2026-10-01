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
                    Text(tr("Willkommen bei Mailmeg", "Welcome to Mailmeg"))
                        .font(.system(size: 30, weight: .bold))
                    Text(tr("Gmail als echte Mac-App, direkt über die Gmail-API. Ohne Browser, ohne Umwege.", "Gmail as a real Mac app, straight through the Gmail API. No browser, no detours."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    step(1, tr("Projekt in der Google Cloud Console anlegen und die **Gmail API** aktivieren.", "Create a project in the Google Cloud Console and enable the **Gmail API**."))
                    step(2, tr("OAuth-Client vom Typ **iOS** erstellen, Bundle-ID `de.mailmeg.app`.", "Create an OAuth client of type **iOS** with bundle ID `de.mailmeg.app`."))
                    step(3, tr("Client-ID hier einfügen und anmelden.", "Paste the client ID here and sign in."))

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
                            Text(tr("Mit Google anmelden", "Sign in with Google"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || model.isSigningIn)

                    Text(tr("Die genaue Anleitung steht in der README. Deine Daten bleiben zwischen deinem Mac und Google.", "Step-by-step instructions are in the README. Your data stays between your Mac and Google."))
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

                Button(tr("Erst mal ohne Konto ausprobieren →", "Try it without an account first →")) {
                    Task { await model.startDemo() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("onboarding.demo")

                HStack(spacing: 6) {
                    Text(AppInfo.copyright)
                    Text("·")
                    Link(AppInfo.websiteLabel, destination: AppInfo.website)
                    Text("·")
                    Text(AppInfo.versionLine)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .padding(.top, 8)
            }
            .padding(40)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

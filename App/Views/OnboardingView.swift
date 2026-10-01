import MailmegKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var clientID = AppSettings.clientID

    private var isValid: Bool { GoogleOAuthConfig(clientID: clientID).isValid }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Mailmeg")
                .font(.largeTitle.weight(.semibold))
            Text("A native Gmail client that talks to the Gmail API directly — no web wrapper.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Google OAuth client ID")
                    .font(.headline)
                TextField("1234567890-abc.apps.googleusercontent.com", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: clientID) { _, newValue in
                        AppSettings.clientID = newValue
                    }
                Text("Create an OAuth client of type “iOS” in the Google Cloud Console with the Gmail API enabled. The README explains every step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 460)

            Button {
                Task { await model.signIn() }
            } label: {
                if model.isSigningIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign in with Google")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || model.isSigningIn)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StatsStore
    var onDone: (() -> Void)?

    @State private var token = ""
    @State private var accountID = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("API Token", text: $token, prompt: Text(store.hasToken ? "Saved in Keychain — leave blank to keep" : "Paste your Cloudflare API token"))
                TextField("Account ID", text: $accountID, prompt: Text("Optional — limits the list to one account"))
            } header: {
                Text("Cloudflare Credentials")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create a token with **Zone → Zone → Read** and **Zone → Analytics → Read** for **All zones** (optionally add **Account → Account Settings → Read** to show your account name). All your domains are found automatically. The token is stored securely in your Keychain.")
                    Link("Create an API token…", destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if saved, let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if saved, store.isLoading {
                ProgressView("Connecting…").controlSize(.small)
            } else if saved, store.lastUpdated != nil {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                if let onDone {
                    Button("Close", action: onDone)
                        .keyboardShortcut(.cancelAction)
                }
                Button("Save & Connect") {
                    store.save(
                        token: token,
                        accountID: accountID
                    )
                    token = ""
                    saved = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty && !store.hasToken)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear {
            accountID = store.accountID
        }
    }
}

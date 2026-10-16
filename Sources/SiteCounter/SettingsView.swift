import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StatsStore
    var onDone: (() -> Void)?

    @State private var token = ""
    @State private var zoneID = ""
    @State private var accountID = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("API Token", text: $token, prompt: Text(store.hasToken ? "Saved in Keychain — leave blank to keep" : "Paste your Cloudflare API token"))
                TextField("Zone ID", text: $zoneID, prompt: Text("e.g. 023e105f4ecef8ad9ca31a8372d0c353"))
                TextField("Account ID", text: $accountID, prompt: Text("Optional — shows your account name"))
            } header: {
                Text("Cloudflare Credentials")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create a token with **Zone → Analytics → Read** (and optionally **Account → Account Settings → Read**). The token is stored securely in your Keychain.")
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
                        zoneID: zoneID,
                        accountID: accountID
                    )
                    token = ""
                    saved = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(zoneID.trimmingCharacters(in: .whitespaces).isEmpty || (token.isEmpty && !store.hasToken))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear {
            zoneID = store.zoneID
            accountID = store.accountID
        }
    }
}

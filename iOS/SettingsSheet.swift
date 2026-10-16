import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: StatsStore
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var accountID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(store.hasToken ? "Saved — leave blank to keep" : "API Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Account ID (optional)", text: $accountID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cloudflare Credentials")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create a token with **Zone → Zone → Read** and **Zone → Analytics → Read** for **All zones**. Add **Account → Account Settings → Read** to show your account name. The token is stored securely in your Keychain.")
                        Link("Create an API token", destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
                    }
                }

                if store.isConfigured, let error = store.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.save(token: token, accountID: accountID)
                        dismiss()
                    }
                    .disabled(token.isEmpty && !store.hasToken)
                }
            }
            .onAppear { accountID = store.accountID }
        }
    }
}

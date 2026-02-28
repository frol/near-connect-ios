import SwiftUI
import NEARConnect

struct SignInAndSignMessageDemoView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var message = "Sign in to NEAR Connect Demo"
    @State private var recipient = "near-connect-demo.near"
    @State private var isProcessing = false
    @State private var result: SignInResult?
    @State private var showError = false
    @State private var errorMessage = ""

    struct SignInResult {
        let accountId: String
        let publicKey: String?
        let walletId: String
        let signedMessage: String?
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Connect a wallet and sign a message in a single step. The wallet presents one approval screen for both sign-in and message signing.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Message Parameters")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $message)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 60)
                    }

                    TextField("Recipient", text: $recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if walletManager.isSignedIn {
                    Section {
                        HStack {
                            Text("Connected as")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(walletManager.currentAccount?.accountId ?? "")
                                .font(.caption)
                        }

                        Button(action: {
                            walletManager.disconnect()
                            result = nil
                        }) {
                            Text("Disconnect first to test connect flow")
                                .foregroundColor(.red)
                        }
                    }
                }

                Section {
                    Button(action: connectAndSign) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isProcessing ? "Connecting..." : "Connect & Sign Message")
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || message.isEmpty || recipient.isEmpty || walletManager.isSignedIn)
                }

                if let result {
                    Section(header: Text("Result")) {
                        VStack(alignment: .leading, spacing: 8) {
                            resultRow("Account", value: result.accountId)
                            resultRow("Wallet", value: result.walletId)
                            if let publicKey = result.publicKey {
                                resultRow("Public Key", value: publicKey)
                            }
                            if let signedMessage = result.signedMessage {
                                resultRow("Signed Message", value: signedMessage)
                            } else {
                                Text("Signed message: not returned (wallet may not support this feature)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }

                Section {
                    Text("A random nonce is generated automatically to prevent replay attacks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Connect & Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isProcessing)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func resultRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.green)
        }
    }

    private func connectAndSign() {
        Task {
            isProcessing = true
            defer { isProcessing = false }

            do {
                let signInResult = try await walletManager.connectAndSignMessage(
                    message: message,
                    recipient: recipient
                )
                result = SignInResult(
                    accountId: signInResult.account.accountId,
                    publicKey: signInResult.account.publicKey,
                    walletId: signInResult.account.walletId,
                    signedMessage: signInResult.signedMessage
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

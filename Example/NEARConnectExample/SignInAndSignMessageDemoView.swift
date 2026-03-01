import SwiftUI
import NEARConnect

struct SignInAndSignMessageDemoView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss
    var onLog: ((_ action: String, _ params: String, _ output: String, _ isError: Bool) -> Void)?

    @State private var message = "Sign in to NEAR Connect Demo"
    @State private var recipient = "near-connect-demo.near"
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

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

    private func connectAndSign() {
        let params = "message: \(message), recipient: \(recipient)"
        Task {
            isProcessing = true
            defer { isProcessing = false }

            do {
                let signInResult = try await walletManager.connectAndSignMessage(
                    message: message,
                    recipient: recipient
                )
                var output = "account: \(signInResult.account.accountId), wallet: \(signInResult.account.walletId)"
                if let pk = signInResult.account.publicKey {
                    output += ", publicKey: \(pk)"
                }
                if let sig = signInResult.signedMessage {
                    output += "\nsignedMessage: \(sig)"
                }
                onLog?("connectAndSignMessage", params, output, false)
            } catch {
                onLog?("connectAndSignMessage", params, error.localizedDescription, true)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

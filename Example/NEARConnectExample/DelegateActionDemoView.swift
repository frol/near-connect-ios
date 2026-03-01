import SwiftUI
import NEARConnect

struct DelegateActionDemoView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss
    var onLog: ((_ action: String, _ params: String, _ output: String, _ isError: Bool) -> Void)?

    @State private var receiverId = "guest-book.near"
    @State private var methodName = "add_message"
    @State private var argsText = "{\"text\": \"Hello via meta tx!\"}"
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Sign delegate actions for meta transactions (NEP-366). The wallet signs but does not broadcast — a relayer submits them.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Delegate Action")) {
                    HStack {
                        Text("Signer")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(walletManager.currentAccount?.accountId ?? "")
                            .font(.caption)
                    }

                    TextField("Receiver ID", text: $receiverId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Method Name", text: $methodName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments (JSON)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $argsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                    }
                }

                Section {
                    Button(action: signDelegate) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isProcessing ? "Signing..." : "Sign Delegate Actions")
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || receiverId.isEmpty || methodName.isEmpty)
                }

                Section {
                    Text("The signed delegate actions can be submitted to the network by a relayer service that pays for gas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Delegate Actions")
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

    private func signDelegate() {
        guard let argsData = argsText.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            errorMessage = "Invalid JSON arguments"
            showError = true
            return
        }

        let argsJSON = try? JSONSerialization.data(withJSONObject: args)
        let argsBase64 = argsJSON?.base64EncodedString() ?? ""

        let delegateActions: [[String: Any]] = [
            [
                "receiverId": receiverId,
                "actions": [
                    [
                        "type": "FunctionCall",
                        "params": [
                            "methodName": methodName,
                            "args": argsBase64,
                            "gas": "30000000000000",
                            "deposit": "0"
                        ]
                    ]
                ]
            ]
        ]

        let params = "receiver: \(receiverId), method: \(methodName), args: \(argsText)"
        Task {
            isProcessing = true
            defer { isProcessing = false }

            do {
                let delegateResult = try await walletManager.signDelegateActions(
                    delegateActions: delegateActions
                )
                let output = delegateResult.rawResult ?? "(no raw result returned)"
                onLog?("signDelegateActions", params, output, false)
            } catch {
                onLog?("signDelegateActions", params, error.localizedDescription, true)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

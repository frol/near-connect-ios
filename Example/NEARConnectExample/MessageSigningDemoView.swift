import SwiftUI
import NEARConnect

struct MessageSigningDemoView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var contractId = "guest-book.near"
    @State private var methodName = "add_message"
    @State private var argsText = "{\"text\": \"Hello from iOS!\"}"
    @State private var deposit = "0"
    @State private var isProcessing = false
    @State private var result: String?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Call a smart contract function on NEAR")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Contract Call")) {
                    HStack {
                        Text("Signer")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(walletManager.currentAccount?.accountId ?? "")
                            .font(.caption)
                    }

                    TextField("Contract ID", text: $contractId)
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

                    HStack {
                        TextField("Deposit", text: $deposit)
                            .keyboardType(.decimalPad)
                        Text("NEAR")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: callContract) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isProcessing ? "Calling..." : "Call Contract")
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || contractId.isEmpty || methodName.isEmpty)
                }

                if let result {
                    Section(header: Text("Result")) {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.green)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Call Contract")
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

    private func callContract() {
        guard let argsData = argsText.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            errorMessage = "Invalid JSON arguments"
            showError = true
            return
        }

        let depositYocto = NEARWalletManager.toYoctoNEAR(deposit) ?? "0"

        Task {
            isProcessing = true
            defer { isProcessing = false }

            do {
                let txResult = try await walletManager.callFunction(
                    contractId: contractId,
                    methodName: methodName,
                    args: args,
                    deposit: depositYocto
                )
                result = "Contract called!\n\nHash: \(txResult.transactionHashes.joined(separator: "\n"))"
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

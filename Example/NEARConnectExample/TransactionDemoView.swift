import SwiftUI
import NEARConnect

struct TransactionDemoView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss
    var onLog: ((_ action: String, _ params: String, _ output: String, _ isError: Bool) -> Void)?

    @State private var receiverId = ""
    @State private var amount = "0.01"
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Send NEAR tokens to another account via your connected wallet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Transfer Details")) {
                    HStack {
                        Text("From")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(walletManager.currentAccount?.accountId ?? "")
                            .font(.caption)
                    }

                    TextField("Receiver (e.g., bob.near)", text: $receiverId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        Text("NEAR")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: sendTransaction) {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isProcessing ? "Sending..." : "Send NEAR")
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || receiverId.isEmpty || amount.isEmpty)
                }

                Section {
                    Text("The wallet will open to confirm the transaction. The transaction is signed and broadcast by the wallet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Send NEAR")
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

    private func sendTransaction() {
        guard let yocto = NEARWalletManager.toYoctoNEAR(amount) else {
            errorMessage = "Invalid amount"
            showError = true
            return
        }

        let params = "to: \(receiverId), amount: \(amount) NEAR"
        Task {
            isProcessing = true
            defer { isProcessing = false }

            do {
                let txResult = try await walletManager.sendNEAR(
                    to: receiverId,
                    amountYocto: yocto
                )
                let hashes = txResult.transactionHashes.joined(separator: ", ")
                onLog?("sendNEAR", params, "Hashes: \(hashes)", false)
            } catch {
                onLog?("sendNEAR", params, error.localizedDescription, true)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

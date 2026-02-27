import SwiftUI
import NEARConnect

struct ContentView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @State private var showTransactionDemo = false
    @State private var showContractCallDemo = false
    @State private var accountBalance: String?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 30) {
                        headerView
                            .padding(.top, 40)

                        if walletManager.isSignedIn, let account = walletManager.currentAccount {
                            accountView(account)
                        } else {
                            connectPrompt
                        }

                        Spacer(minLength: 40)
                        footerView
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $walletManager.showWalletUI) {
                WalletBridgeSheet()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showTransactionDemo) {
                TransactionDemoView()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showContractCallDemo) {
                MessageSigningDemoView()
                    .environmentObject(walletManager)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("NEAR Connect")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("iOS Demo")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Account View

    private func accountView(_ account: NEARAccount) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                VStack(spacing: 8) {
                    Text("Connected")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(account.accountId)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    if let balance = accountBalance {
                        Text("\(balance) NEAR")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "wallet.pass.fill")
                        .font(.caption)
                    Text(account.walletId)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )

            VStack(spacing: 12) {
                Button(action: { showTransactionDemo = true }) {
                    Label("Send NEAR", systemImage: "arrow.right.arrow.left")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                Button(action: { showContractCallDemo = true }) {
                    Label("Call Contract", systemImage: "terminal")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }
            }

            Button(action: {
                walletManager.disconnect()
                accountBalance = nil
            }) {
                Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
            }
        }
        .padding()
        .task {
            await fetchBalance()
        }
    }

    // MARK: - Connect Prompt

    private var connectPrompt: some View {
        VStack(spacing: 20) {
            Text("Connect your NEAR wallet to get started")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: { walletManager.connect() }) {
                Label("Connect Wallet", systemImage: "wallet.pass")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            Text("Powered by NEAR Protocol")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Uses near-connect for secure wallet integration")
                    .font(.caption2)
            }
            .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.bottom, 20)
    }

    private func fetchBalance() async {
        do {
            let result = try await walletManager.viewAccount()
            if let amountStr = result["amount"] as? String {
                accountBalance = NEARWalletManager.formatNEAR(yoctoNEAR: amountStr)
            }
        } catch {
            // Silently fail
        }
    }
}

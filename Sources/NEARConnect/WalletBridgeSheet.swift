import SwiftUI

/// Full-screen cover that shows the persistent bridge WebView.
///
/// Present this view when `NEARWalletManager.showWalletUI` is true.
/// It handles wallet connection, transaction approval, and message signing flows.
public struct WalletBridgeSheet: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var didTrigger = false

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                BridgeWebViewContainer(webView: walletManager.bridgeWebView)

                if !walletManager.isBridgeReady {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading wallet connector...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        walletManager.isBusy = false
                        walletManager.showWalletUI = false
                    }
                }
            }
            .onChange(of: walletManager.isBridgeReady) { _ in
                triggerConnectIfNeeded()
            }
            .onAppear {
                triggerConnectIfNeeded()
            }
        }
    }

    private func triggerConnectIfNeeded() {
        guard walletManager.isBridgeReady,
              walletManager.pendingConnect,
              !didTrigger else { return }
        didTrigger = true
        walletManager.pendingConnect = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            walletManager.triggerWalletSelector()
        }
    }
}

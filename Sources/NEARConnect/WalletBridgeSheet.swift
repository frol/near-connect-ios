import SwiftUI

/// Full-screen cover that shows the persistent bridge WebView.
///
/// Present this view when `NEARWalletManager.showWalletUI` is true.
/// It handles wallet connection, transaction approval, and message signing flows.
public struct WalletBridgeSheet: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    @State private var didTrigger = false

    public init() {}

    public var body: some View {
        ZStack {
            BridgeWebViewContainer(webView: walletManager.bridgeWebView)
                .ignoresSafeArea()

            if !walletManager.isBridgeReady {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading wallet connector...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: cancelFlow) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.6))
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .onChange(of: walletManager.isBridgeReady) { _ in
            triggerConnectIfNeeded()
        }
        .onAppear {
            triggerConnectIfNeeded()
        }
        .onDisappear {
            walletManager.cleanUpOnDismiss()
        }
    }

    private func cancelFlow() {
        walletManager.showWalletUI = false
    }

    private func triggerConnectIfNeeded() {
        guard walletManager.isBridgeReady, !didTrigger else { return }

        if let params = walletManager.pendingSignMessageParams {
            didTrigger = true
            walletManager.pendingSignMessageParams = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                walletManager.triggerConnectWithSignMessage(
                    message: params.message,
                    recipient: params.recipient,
                    nonce: params.nonce
                )
            }
        } else if walletManager.pendingConnect {
            didTrigger = true
            walletManager.pendingConnect = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                walletManager.triggerWalletSelector()
            }
        }
    }
}

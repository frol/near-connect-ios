import Foundation
import SwiftUI
import Combine
import WebKit
import Security

/// Manages NEAR wallet connection state.
///
/// Owns a persistent WKWebView running the near-connect JavaScript bridge.
/// The WebView lives for the lifetime of the manager so that wallet sessions
/// and JS state survive across sheet presentations.
@MainActor
public class NEARWalletManager: ObservableObject {

    // MARK: - Published State

    @Published public var currentAccount: NEARAccount?
    @Published public var isBusy = false
    @Published public var lastError: String?
    @Published public private(set) var isBridgeReady = false

    /// When true, the wallet WebView should be presented to the user
    /// (for connect flow, transaction approval, etc.)
    @Published public var showWalletUI = false

    /// When true, the wallet selector should be auto-triggered on sheet appear.
    public var pendingConnect = false

    /// Network for wallet connections.
    public enum Network: String, Sendable {
        case mainnet
        case testnet
    }
    @Published public var network: Network = .mainnet

    public var isSignedIn: Bool { currentAccount != nil }

    // MARK: - WebView (owned by this manager, persistent)

    public private(set) var bridgeWebView: WKWebView!
    private var coordinator: WebViewCoordinator!

    // MARK: - Continuations for async operations

    private var signInContinuation: CheckedContinuation<NEARAccount, any Error>?
    private var transactionContinuation: CheckedContinuation<TransactionResult, any Error>?
    private var messageContinuation: CheckedContinuation<MessageSignResult, any Error>?

    // MARK: - Persistence

    private let userDefaults: UserDefaults
    private let accountStorageKey = "near_connected_account"

    // MARK: - Init

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadStoredAccount()
        setupBridgeWebView()
    }

    private func setupBridgeWebView() {
        coordinator = WebViewCoordinator(manager: self)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "nearConnect")
        config.userContentController = contentController

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 800), configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        bridgeWebView = webView
        loadBridgePage()
    }

    private func loadBridgePage() {
        guard let htmlURL = Bundle.module.url(forResource: "near-connect-bridge", withExtension: "html") else {
            lastError = "Bridge HTML not found in bundle"
            return
        }

        if let htmlContent = try? String(contentsOf: htmlURL, encoding: .utf8) {
            let modifiedHTML = htmlContent.replacingOccurrences(
                of: "window.location.search",
                with: "'?network=\(network.rawValue)'"
            )
            bridgeWebView.loadHTMLString(modifiedHTML, baseURL: URL(string: "https://near-connect-bridge.local/")!)
        }
    }

    /// Remove all popup webviews (wallet pages opened via window.open).
    public func closePopups() {
        coordinator.closeAllPopups()
    }

    // MARK: - Handle events from WebView

    func handleEvent(_ event: NEARConnectEvent) {
        switch event {
        case .ready:
            isBridgeReady = true
            lastError = nil

        case .signedIn(let accountId, let publicKey, let walletId):
            let account = NEARAccount(
                accountId: accountId,
                publicKey: publicKey,
                walletId: walletId
            )
            currentAccount = account
            saveAccount(account)
            signInContinuation?.resume(returning: account)
            signInContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .signedOut:
            currentAccount = nil
            clearStoredAccount()
            isBusy = false

        case .transactionResult(let hash, let rawResult):
            let result = TransactionResult(
                transactionHashes: [hash],
                rawResult: rawResult
            )
            transactionContinuation?.resume(returning: result)
            transactionContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .transactionsResult(let rawResults):
            let result = TransactionResult(
                transactionHashes: [],
                rawResult: rawResults
            )
            transactionContinuation?.resume(returning: result)
            transactionContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .transactionError(let message):
            transactionContinuation?.resume(throwing: NEARError.walletError(message))
            transactionContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .messageResult(let accountId, let publicKey, let signature):
            let result = MessageSignResult(
                accountId: accountId,
                publicKey: publicKey,
                signature: signature
            )
            messageContinuation?.resume(returning: result)
            messageContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .messageError(let message):
            messageContinuation?.resume(throwing: NEARError.walletError(message))
            messageContinuation = nil
            isBusy = false
            closePopups()
            showWalletUI = false

        case .error(let message):
            lastError = message
            signInContinuation?.resume(throwing: NEARError.walletError(message))
            signInContinuation = nil
            transactionContinuation?.resume(throwing: NEARError.walletError(message))
            transactionContinuation = nil
            messageContinuation?.resume(throwing: NEARError.walletError(message))
            messageContinuation = nil
            isBusy = false
        }
    }

    // MARK: - Connect Wallet

    /// Present the wallet selector.
    public func connect() {
        pendingConnect = true
        showWalletUI = true
    }

    /// Trigger the near-connect wallet selector UI.
    public func triggerWalletSelector() {
        bridgeWebView.callNEARConnect("window.nearConnect()")
    }

    /// Connect with a specific wallet by ID.
    public func connect(walletId: String) {
        showWalletUI = true
        let escaped = walletId.replacingOccurrences(of: "'", with: "\\'")
        bridgeWebView.callNEARConnect("window.nearConnectWallet('\(escaped)')")
    }

    // MARK: - Disconnect

    /// Disconnect the current wallet.
    public func disconnect() {
        bridgeWebView.callNEARConnect("window.nearDisconnect()")
        currentAccount = nil
        clearStoredAccount()
        lastError = nil
    }

    // MARK: - Sign & Send Transaction

    /// Result of a signed and sent transaction.
    public struct TransactionResult {
        public let transactionHashes: [String]
        public let rawResult: String?

        public init(transactionHashes: [String], rawResult: String?) {
            self.transactionHashes = transactionHashes
            self.rawResult = rawResult
        }
    }

    /// Sign and send a transaction with custom actions.
    public func signAndSendTransaction(
        receiverId: String,
        actions: [[String: Any]]
    ) async throws -> TransactionResult {
        guard isSignedIn else { throw NEARError.notSignedIn }
        guard !isBusy else { throw NEARError.operationInProgress }
        guard isBridgeReady else { throw NEARError.webViewNotReady }

        isBusy = true
        lastError = nil
        showWalletUI = true

        let actionsData = try JSONSerialization.data(withJSONObject: actions)
        let actionsJSON = String(data: actionsData, encoding: .utf8) ?? "[]"

        return try await withCheckedThrowingContinuation { continuation in
            transactionContinuation = continuation
            let escapedReceiver = receiverId.replacingOccurrences(of: "'", with: "\\'")
            let escapedActions = actionsJSON.replacingOccurrences(of: "'", with: "\\'")
            bridgeWebView.callNEARConnect(
                "window.nearSignAndSendTransaction('\(escapedReceiver)', '\(escapedActions)')"
            )
        }
    }

    /// Send a NEAR transfer.
    public func sendNEAR(to receiverId: String, amountYocto: String) async throws -> TransactionResult {
        let actions: [[String: Any]] = [
            [
                "type": "Transfer",
                "params": ["deposit": amountYocto]
            ]
        ]
        return try await signAndSendTransaction(receiverId: receiverId, actions: actions)
    }

    /// Call a smart contract function.
    public func callFunction(
        contractId: String,
        methodName: String,
        args: [String: Any] = [:],
        gas: String = "30000000000000",
        deposit: String = "0"
    ) async throws -> TransactionResult {
        let argsJSON = try JSONSerialization.data(withJSONObject: args)
        let argsBase64 = argsJSON.base64EncodedString()

        let actions: [[String: Any]] = [
            [
                "type": "FunctionCall",
                "params": [
                    "methodName": methodName,
                    "args": argsBase64,
                    "gas": gas,
                    "deposit": deposit
                ]
            ]
        ]
        return try await signAndSendTransaction(receiverId: contractId, actions: actions)
    }

    // MARK: - Sign Message (NEP-413)

    /// Result of a signed message.
    public struct MessageSignResult {
        public let accountId: String?
        public let publicKey: String?
        public let signature: String?

        public init(accountId: String?, publicKey: String?, signature: String?) {
            self.accountId = accountId
            self.publicKey = publicKey
            self.signature = signature
        }
    }

    /// Sign an off-chain message (NEP-413).
    public func signMessage(
        message: String,
        recipient: String,
        nonce: Data? = nil
    ) async throws -> MessageSignResult {
        guard isSignedIn else { throw NEARError.notSignedIn }
        guard !isBusy else { throw NEARError.operationInProgress }
        guard isBridgeReady else { throw NEARError.webViewNotReady }

        isBusy = true
        lastError = nil
        showWalletUI = true

        let messageNonce = nonce ?? generateNonce()
        let nonceBase64 = messageNonce.base64EncodedString()

        return try await withCheckedThrowingContinuation { continuation in
            messageContinuation = continuation
            let escapedMsg = message.replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let escapedRecipient = recipient.replacingOccurrences(of: "'", with: "\\'")
            bridgeWebView.callNEARConnect(
                "window.nearSignMessage('\(escapedMsg)', '\(escapedRecipient)', '\(nonceBase64)')"
            )
        }
    }

    // MARK: - NEAR RPC

    /// Query account info via NEAR RPC.
    public func viewAccount(_ accountId: String? = nil) async throws -> [String: Any] {
        let id = accountId ?? currentAccount?.accountId
        guard let id else { throw NEARError.notSignedIn }

        let rpcURL = network == .mainnet
            ? "https://rpc.mainnet.near.org"
            : "https://rpc.testnet.near.org"

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "1",
            "method": "query",
            "params": [
                "request_type": "view_account",
                "finality": "final",
                "account_id": id
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: rpcURL)!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                throw NEARError.rpcError(error["message"] as? String ?? "RPC error")
            }
            throw NEARError.rpcError("Invalid RPC response")
        }

        return result
    }

    // MARK: - Utilities

    /// Convert yoctoNEAR string to human-readable NEAR amount.
    public static func formatNEAR(yoctoNEAR: String) -> String {
        guard let value = Decimal(string: yoctoNEAR) else { return "0" }
        let divisor = Decimal(sign: .plus, exponent: 24, significand: 1)
        let near = value / divisor
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        formatter.numberStyle = .decimal
        return formatter.string(from: near as NSDecimalNumber) ?? "0"
    }

    /// Convert NEAR amount string to yoctoNEAR string.
    public static func toYoctoNEAR(_ near: String) -> String? {
        guard let value = Decimal(string: near) else { return nil }
        let multiplier = Decimal(sign: .plus, exponent: 24, significand: 1)
        let yocto = value * multiplier
        return NSDecimalNumber(decimal: yocto).stringValue
    }

    // MARK: - Private

    private func generateNonce() -> Data {
        var nonce = Data(count: 32)
        _ = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        return nonce
    }

    private func saveAccount(_ account: NEARAccount) {
        if let data = try? JSONEncoder().encode(account) {
            userDefaults.set(data, forKey: accountStorageKey)
        }
    }

    private func loadStoredAccount() {
        guard let data = userDefaults.data(forKey: accountStorageKey),
              let account = try? JSONDecoder().decode(NEARAccount.self, from: data) else {
            return
        }
        currentAccount = account
    }

    private func clearStoredAccount() {
        userDefaults.removeObject(forKey: accountStorageKey)
    }
}

// MARK: - WebView Coordinator

/// Handles WKWebView delegate callbacks for the persistent bridge WebView.
@MainActor
class WebViewCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private weak var manager: NEARWalletManager?
    var popupWebViews: [WKWebView] = []

    init(manager: NEARWalletManager) {
        self.manager = manager
    }

    func closeAllPopups() {
        for popup in popupWebViews {
            popup.removeFromSuperview()
        }
        popupWebViews.removeAll()
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard message.name == "nearConnect",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            let event: NEARConnectEvent
            switch type {
            case "ready":
                event = .ready
            case "signIn", "signInAndSignMessage":
                event = .signedIn(
                    accountId: body["accountId"] as? String ?? "",
                    publicKey: body["publicKey"] as? String,
                    walletId: body["walletId"] as? String ?? "unknown"
                )
            case "signOut":
                event = .signedOut
            case "transactionResult":
                event = .transactionResult(
                    hash: body["transactionHash"] as? String ?? "unknown",
                    rawResult: body["result"] as? String
                )
            case "transactionsResult":
                event = .transactionsResult(rawResults: body["results"] as? String)
            case "transactionError":
                event = .transactionError(body["message"] as? String ?? "Unknown error")
            case "messageResult":
                event = .messageResult(
                    accountId: body["accountId"] as? String,
                    publicKey: body["publicKey"] as? String,
                    signature: body["signature"] as? String
                )
            case "messageError":
                event = .messageError(body["message"] as? String ?? "Unknown error")
            case "error":
                event = .error(body["message"] as? String ?? "Unknown error")
            default:
                return
            }

            self.manager?.handleEvent(event)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let isPopup = popupWebViews.contains(where: { $0 === webView })
        if isPopup, shouldOpenExternally(url) {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
            webView.removeFromSuperview()
            popupWebViews.removeAll { $0 === webView }
            return
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url
        print("[NEARConnect] window.open() URL: \(url?.absoluteString ?? "nil")")

        if let url, shouldOpenExternally(url) {
            UIApplication.shared.open(url)
            return nil
        }

        // Override the data store to enable cookies (required by Cloudflare-protected wallets).
        configuration.websiteDataStore = .default()

        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.backgroundColor = .systemBackground
        popup.isOpaque = true
        popup.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        #if DEBUG
        if #available(iOS 16.4, *) {
            popup.isInspectable = true
        }
        #endif

        if let manager = manager {
            manager.bridgeWebView.addSubview(popup)
        } else {
            webView.addSubview(popup)
        }
        popupWebViews.append(popup)
        return popup
    }

    /// Determine if a URL should be opened in the system browser / native app
    /// rather than rendered in the WKWebView popup.
    private func shouldOpenExternally(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""

        // about:blank / about:srcdoc are used internally by near-connect
        // for popup initialization — must stay in-app
        if scheme == "about" {
            return false
        }

        // Non-HTTP schemes open externally (custom deep links like near://, tg://)
        if scheme != "http" && scheme != "https" {
            return true
        }

        // Known app-link domains that should open native apps
        let externalDomains = ["t.me", "telegram.me"]
        if let host = url.host?.lowercased(),
           externalDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        return false
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.removeFromSuperview()
        popupWebViews.removeAll { $0 === webView }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        print("[NEARConnect] Popup provisional navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        print("[NEARConnect] Popup navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

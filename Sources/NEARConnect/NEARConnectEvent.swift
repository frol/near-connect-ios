import WebKit

/// Events received from the JavaScript bridge.
enum NEARConnectEvent {
    case ready
    case signedIn(accountId: String, publicKey: String?, walletId: String)
    case signedOut
    case transactionResult(hash: String, rawResult: String?)
    case transactionsResult(rawResults: String?)
    case transactionError(String)
    case messageResult(accountId: String?, publicKey: String?, signature: String?)
    case messageError(String)
    case error(String)
}

// MARK: - JS call helper

extension WKWebView {
    func callNEARConnect(_ functionCall: String) {
        evaluateJavaScript(functionCall) { _, error in
            if let error {
                print("[NEARConnect] JS error: \(error.localizedDescription)")
            }
        }
    }
}

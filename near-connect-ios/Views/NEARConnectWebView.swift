//
//  NEARConnectWebView.swift
//  near-connect-ios
//
//  SwiftUI wrapper that hosts the manager's persistent WKWebView
//

import SwiftUI
import WebKit

/// Wraps the persistent WKWebView owned by NEARWalletManager into a SwiftUI view.
/// This allows the same WebView instance to be shown/hidden across different sheets
/// without losing JS state or the near-connect wallet session.
struct BridgeWebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        // Wrap in a container so the WebView can be reparented without SwiftUI issues
        let container = UIView()
        container.backgroundColor = .systemBackground
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Ensure the webView is in this container (it may have been reparented)
        if webView.superview !== uiView {
            webView.frame = uiView.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(webView)
        }
    }
}

// MARK: - Events from JS bridge

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

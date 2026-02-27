import SwiftUI
import WebKit

/// Wraps the persistent WKWebView owned by NEARWalletManager into a SwiftUI view.
///
/// This allows the same WebView instance to be shown/hidden across different sheets
/// without losing JS state or the near-connect wallet session.
public struct BridgeWebViewContainer: UIViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            webView.frame = uiView.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(webView)
        }
    }
}

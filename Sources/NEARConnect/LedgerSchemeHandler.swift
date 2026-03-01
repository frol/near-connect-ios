import Foundation
import WebKit

/// A custom WKURLSchemeHandler that serves the Ledger executor JavaScript
/// from a custom `near-ledger` URL scheme.
///
/// near-connect loads sandbox wallet executors by `fetch()`-ing the executor URL
/// and injecting the response text into an iframe `srcdoc`. It appends a
/// `?nonce=<uuid>` query parameter to bypass caching, which breaks blob URLs.
/// Using a custom URL scheme allows the URL to survive query parameter
/// modification while still being fetchable from within WKWebView.
///
/// The handler responds to any URL matching `near-ledger://` with the
/// ledger-executor.js content loaded from the app bundle.
class LedgerSchemeHandler: NSObject, WKURLSchemeHandler {

    /// The custom URL scheme name.
    static let scheme = "near-ledger"

    /// The canonical executor URL that near-connect will fetch.
    static let executorURL = "\(scheme)://executor/ledger-executor.js"

    /// Cached JavaScript content, loaded once from the bundle.
    private let jsContent: String?

    override init() {
        if let url = Bundle.module.url(forResource: "ledger-executor", withExtension: "js"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            jsContent = content
        } else {
            jsContent = nil
            print("[NEARConnect] Warning: ledger-executor.js not found in bundle")
        }
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let content = jsContent else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "LedgerSchemeHandler", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "ledger-executor.js not found"])
            )
            return
        }

        let data = Data(content.utf8)
        let requestURL = urlSchemeTask.request.url ?? URL(string: Self.executorURL)!

        // Use HTTPURLResponse to include CORS headers so fetch() from the
        // bridge page origin can read the response.
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/javascript; charset=utf-8",
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to cancel — responses are served synchronously
    }
}

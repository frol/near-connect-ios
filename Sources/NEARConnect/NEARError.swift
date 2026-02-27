import Foundation

/// Errors thrown by NEARWalletManager operations.
public enum NEARError: LocalizedError {
    case operationInProgress
    case notSignedIn
    case invalidURL
    case invalidTransaction
    case noTransactionHash
    case walletError(String)
    case webViewNotReady
    case rpcError(String)

    public var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Another wallet operation is in progress"
        case .notSignedIn:
            return "Not signed in. Please connect a wallet first."
        case .invalidURL:
            return "Failed to build wallet URL"
        case .invalidTransaction:
            return "Failed to encode transaction"
        case .noTransactionHash:
            return "Wallet did not return a transaction hash"
        case .walletError(let msg):
            return msg
        case .webViewNotReady:
            return "Wallet bridge is not ready yet"
        case .rpcError(let msg):
            return "RPC error: \(msg)"
        }
    }
}

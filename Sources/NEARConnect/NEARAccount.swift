import Foundation

/// Represents an authenticated NEAR account.
public struct NEARAccount: Codable, Equatable, Hashable, Sendable {
    public let accountId: String
    public let publicKey: String?
    /// Which wallet was used for this account (wallet id).
    public let walletId: String

    public init(accountId: String, publicKey: String?, walletId: String) {
        self.accountId = accountId
        self.publicKey = publicKey
        self.walletId = walletId
    }

    public var displayName: String {
        accountId
    }

    public var shortDisplayName: String {
        if accountId.count > 24 {
            return "\(accountId.prefix(12))...\(accountId.suffix(8))"
        }
        return accountId
    }
}

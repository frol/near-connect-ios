//
//  NEARAccount.swift
//  near-connect-ios
//
//  NEAR Account Model
//

import Foundation

/// Represents an authenticated NEAR account
struct NEARAccount: Codable, Equatable, Hashable {
    let accountId: String
    let publicKey: String?
    /// Which wallet was used for this account (wallet id)
    let walletId: String

    var displayName: String {
        accountId
    }

    var shortDisplayName: String {
        if accountId.count > 24 {
            return "\(accountId.prefix(12))...\(accountId.suffix(8))"
        }
        return accountId
    }
}

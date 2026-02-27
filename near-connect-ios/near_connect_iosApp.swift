//
//  near_connect_iosApp.swift
//  near-connect-ios
//
//  Created by vm on 2/14/26.
//

import SwiftUI

@main
struct near_connect_iosApp: App {
    @StateObject private var walletManager = NEARWalletManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
        }
    }
}

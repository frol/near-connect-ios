import SwiftUI
import NEARConnect

@main
struct NEARConnectExampleApp: App {
    @StateObject private var walletManager = NEARWalletManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
        }
    }
}

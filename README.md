# NEARConnect

A production-ready Swift Package for integrating NEAR Protocol wallet authentication, transaction signing, and message signing into iOS and macOS applications. Similar to [near-connect](https://github.com/azbang/near-connect), but native for Apple platforms.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![iOS 15.0+](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://www.apple.com/ios/)
[![macOS 12.0+](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://www.apple.com/macos/)
[![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

## Features

✨ **Complete NEAR Wallet Integration**
- 🔐 Non-custodial authentication with third-party wallets
- ✍️ Transaction signing (NEP-141, NEP-171, custom contracts)
- 💬 Message signing (NEP-413)
- 🚀 Meta-transaction support (NEP-366)
- 📱 Multi-wallet support (Meteor Wallet, NEAR Mobile, HERE Wallet)
- 🔍 Automatic wallet detection
- 💾 Session persistence
- 🎯 Modern async/await API
- 🧪 Comprehensive test coverage

## Supported Wallets

| Wallet | Sign In | Sign Transaction | Sign Message | Meta-Transaction |
|--------|---------|------------------|--------------|------------------|
| **Meteor Wallet** | ✅ | ✅ | ✅ | ✅ |
| **NEAR Mobile** | ✅ | ✅ | ✅ | ✅ |
| **HERE Wallet** | ✅ | ✅ | ✅ | ❌ |

## Installation

### Swift Package Manager

Add NEARConnect to your project using Xcode:

1. File → Add Package Dependencies...
2. Enter package URL: `https://github.com/yourusername/NEARConnect`
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/NEARConnect", from: "1.0.0")
]
```

## Quick Start

### 1. Configure URL Scheme

Add to your app's `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>meteorwallet</string>
    <string>nearmobile</string>
    <string>herewallet</string>
</array>
```

### 2. Initialize NEARWalletManager

```swift
import SwiftUI
import NEARConnect

@main
struct YourApp: App {
    @StateObject private var walletManager = NEARWalletManager(
        callbackURLScheme: "yourapp",
        appName: "Your App Name"
    )
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
                .onOpenURL { url in
                    walletManager.handleDeepLink(url: url)
                }
        }
    }
}
```

### 3. Authenticate with Wallet

```swift
import SwiftUI
import NEARConnect

struct ContentView: View {
    @EnvironmentObject var walletManager: NEARWalletManager
    
    var body: some View {
        VStack {
            if walletManager.isSignedIn, let account = walletManager.currentAccount {
                Text("Connected: \(account.accountId)")
                
                Button("Sign Out") {
                    walletManager.signOut()
                }
            } else {
                Button("Connect Wallet") {
                    Task {
                        do {
                            let account = try await walletManager.signIn(
                                with: .meteorWallet
                            )
                            print("Signed in as: \(account.accountId)")
                        } catch {
                            print("Error: \(error)")
                        }
                    }
                }
            }
        }
    }
}
```

## Usage Examples

### Sign a Transaction

```swift
import NEARConnect

// Create a simple transfer transaction
let transaction = NEARTransaction(
    signerId: "sender.near",
    receiverId: "receiver.near",
    actions: [
        .transfer(deposit: "1000000000000000000000000") // 1 NEAR in yoctoNEAR
    ]
)

// Sign the transaction
do {
    let result = try await walletManager.signTransaction(transaction)
    if let signature = result.signature {
        print("Transaction signed: \(signature)")
        // Send to your backend or RPC node
    }
} catch {
    print("Transaction signing failed: \(error)")
}
```

### Call a Smart Contract

```swift
// Create a function call transaction
let transaction = NEARTransaction(
    signerId: "user.near",
    receiverId: "contract.near",
    actions: [
        .functionCall(
            methodName: "set_greeting",
            args: "{\"greeting\":\"Hello NEAR!\"}",
            gas: "30000000000000",
            deposit: "0"
        )
    ]
)

let result = try await walletManager.signTransaction(transaction)
```

### Sign a Message (NEP-413)

```swift
// Sign a message for verification
let message = "Please verify my account ownership"
let recipient = "your-app.near"

do {
    let result = try await walletManager.signMessage(
        message,
        recipient: recipient
    )
    
    if let signature = result.signature, let publicKey = result.publicKey {
        print("Message signed!")
        print("Signature: \(signature)")
        print("Public Key: \(publicKey)")
        // Verify signature on your backend
    }
} catch {
    print("Message signing failed: \(error)")
}
```

### Sign a Meta-Transaction (NEP-366)

```swift
// Create a meta-transaction (relayer pays for gas)
let metaTx = NEARMetaTransaction(
    signerId: "user.near",
    receiverId: "contract.near",
    actions: [
        .functionCall(
            methodName: "claim_reward",
            args: "{}",
            gas: "30000000000000",
            deposit: "0"
        )
    ],
    relayerAccountId: "relayer.near"
)

let result = try await walletManager.signMetaTransaction(metaTx)

if let signedDelegateAction = result.signedDelegateAction {
    // Send to your relayer service
    print("Meta-transaction signed: \(signedDelegateAction)")
}
```

### Check Wallet Installation

```swift
let meteor = NEARWallet.meteorWallet

if meteor.isInstalled {
    print("Meteor Wallet is installed!")
} else {
    print("Meteor Wallet not found")
    if let appStoreURL = meteor.appStoreURL {
        // Open App Store to install
        UIApplication.shared.open(appStoreURL)
    }
}
```

### List Available Wallets

```swift
// Get all configured wallets
let allWallets = NEARWallet.allWallets

// Get only installed wallets
let installed = NEARWallet.installedWallets

// Display in UI
ForEach(allWallets) { wallet in
    HStack {
        Text(wallet.name)
        if wallet.isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}
```

## Advanced Usage

### Add Custom Wallet

```swift
extension NEARWallet {
    static let customWallet = NEARWallet(
        id: "custom-wallet",
        name: "Custom Wallet",
        description: "My custom NEAR wallet",
        iconURL: "https://example.com/icon.png",
        urlScheme: "customwallet",
        universalLink: "https://wallet.example.com",
        iosAppStoreURL: "https://apps.apple.com/app/...",
        features: [.signIn, .signTransaction, .signMessage]
    )
}

// Use it
let account = try await walletManager.signIn(with: .customWallet)
```

### Custom Configuration

```swift
// Initialize with custom settings
let walletManager = NEARWalletManager(
    callbackURLScheme: "myapp",
    appName: "My NEAR App",
    appIcon: "https://myapp.com/icon.png",
    userDefaults: .standard,
    accountKey: "my_near_account"
)
```

### Error Handling

```swift
do {
    let account = try await walletManager.signIn(with: .meteorWallet)
} catch NEARWalletError.walletNotInstalled(let walletName) {
    print("\(walletName) is not installed")
} catch NEARWalletError.authenticationFailed(let message) {
    print("Authentication failed: \(message)")
} catch NEARWalletError.notSignedIn {
    print("Please sign in first")
} catch {
    print("Unexpected error: \(error)")
}
```

## Deep Link Protocol

NEARConnect uses deep linking to communicate with wallet apps:

### Authentication
```
{wallet}://auth/signin?request_id={id}&callback={url}&app_name={name}
↓
yourapp://auth/callback?request_id={id}&account_id={account}&public_key={key}
```

### Transaction Signing
```
{wallet}://transaction/sign?request_id={id}&callback={url}&transaction={json}
↓
yourapp://transaction/callback?request_id={id}&signature={sig}&public_key={key}
```

### Message Signing
```
{wallet}://message/sign?request_id={id}&callback={url}&message={msg}&recipient={rec}&nonce={nonce}
↓
yourapp://message/callback?request_id={id}&signature={sig}&public_key={key}
```

## Example App

The package includes a complete example app demonstrating all features:

1. Open `NEARConnectExample/NEARConnectExample.xcodeproj`
2. Build and run on iOS Simulator or device
3. Install Meteor Wallet from the App Store
4. Test authentication, transaction signing, and message signing

## Testing

Run tests using Xcode or command line:

```bash
swift test
```

The package includes comprehensive unit tests for:
- Wallet configuration
- Account management
- URL generation
- Request/response handling
- Transaction creation
- Message signing
- Meta-transactions

## Requirements

- **iOS**: 15.0+
- **macOS**: 12.0+
- **Swift**: 5.9+
- **Xcode**: 15.0+

## Architecture

```
NEARConnect/
├── Models/
│   ├── NEARWallet.swift           # Wallet configurations
│   ├── NEARAccount.swift          # Account and auth models
│   ├── NEARTransaction.swift      # Transaction models
│   ├── NEARMessage.swift          # Message signing (NEP-413)
│   └── NEARMetaTransaction.swift  # Meta-transaction (NEP-366)
├── NEARWalletManager.swift        # Main manager class
└── Tests/
    └── NEARConnectTests.swift     # Unit tests
```

## Security Considerations

🔒 **Non-Custodial**: Your app never has access to private keys. All signing happens in the wallet app.

✅ **Best Practices**:
- Request IDs use cryptographically secure UUIDs
- Deep links are validated before processing
- Only account IDs and public keys are stored locally
- No sensitive data is logged
- All wallet communication uses standard protocols

## Roadmap

- [ ] Support for WalletConnect
- [ ] Ledger hardware wallet support
- [ ] Multi-account management
- [ ] Network selection (mainnet/testnet)
- [ ] Transaction builder helpers
- [ ] RPC integration for transaction broadcasting
- [ ] visionOS support

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Resources

- [NEAR Protocol Docs](https://docs.near.org)
- [NEP-413: Message Signing](https://github.com/near/NEPs/blob/master/neps/nep-0413.md)
- [NEP-366: Meta Transactions](https://github.com/near/NEPs/blob/master/neps/nep-0366.md)
- [NEAR Wallet Selector](https://github.com/near/wallet-selector)

## License

MIT License - see [LICENSE](LICENSE) for details

## Support

- 📧 Email: support@example.com
- 💬 Discord: [NEAR Protocol](https://discord.gg/near)
- 🐦 Twitter: [@NEARProtocol](https://twitter.com/NEARProtocol)

---

Built with ❤️ for the NEAR Protocol ecosystem

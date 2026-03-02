# near-connect-ios

iOS Swift Package wrapping [near-connect](https://github.com/AZbang/near-connect) — connect NEAR Protocol wallets from a native iOS app.

Uses a lightweight WKWebView bridge to load the [`@hot-labs/near-connect`](https://www.npmjs.com/package/@hot-labs/near-connect) JavaScript library, giving your app access to the full wallet ecosystem without reimplementing any wallet-specific protocols.

## Supported wallets

All wallets in the [near-connect manifest](https://github.com/AZbang/near-connect/blob/main/repository/manifest.json) work out of the box, plus Ledger hardware wallets via Bluetooth:

| Wallet | Type | Status |
|--------|------|--------|
| HOT Wallet | Native app (Telegram) | Tested |
| Intear Wallet | Web app | Tested |
| MyNearWallet | Web app | Tested |
| Meteor Wallet | Web app | Tested |
| Ledger (Nano X, Stax, Flex, Nano Gen5) | Hardware (BLE) | Tested |

## Features

- **Wallet connect/disconnect** — presents the near-connect wallet selector UI
- **Send NEAR** — transfer tokens to any account
- **Call smart contracts** — invoke any contract method with JSON args
- **Sign messages (NEP-413)** — off-chain message signing
- **Connect & sign message** — combine sign-in and message signing in one flow
- **Delegate actions (NEP-366)** — sign meta transactions for relayer submission
- **Ledger hardware wallet** — BLE support for Nano X, Stax, Flex, and Nano Gen5
- **Session persistence** — connected account stored in UserDefaults
- **Mainnet / Testnet** — configurable network
- **Modern async/await API** — all wallet operations are async

## Installation

### Swift Package Manager

Add `near-connect-ios` to your project in Xcode:

1. **File > Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/frol/near-connect-ios
   ```
3. Select the version or branch and add the `NEARConnect` library to your target.

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/frol/near-connect-ios", from: "1.0.0")
]
```

Then add `NEARConnect` as a dependency of your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "NEARConnect", package: "near-connect-ios")
    ]
)
```

## How it works

```
┌──────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                               │
│                                                  │
│  NEARWalletManager                               │
│    ├── bridgeWebView (persistent WKWebView)      │
│    │     └── near-connect-bridge.html            │
│    │           └── @hot-labs/near-connect JS     │
│    ├── connect() / disconnect()                  │
│    ├── sendNEAR(to:amountYocto:)                 │
│    ├── callFunction(contractId:methodName:)      │
│    ├── signMessage(message:recipient:)           │
│    ├── signDelegateActions(delegateActions:)     │
│    └── ledgerBLE (LedgerBLEManager)              │
│          └── CoreBluetooth APDU exchange         │
│                                                  │
│  Communication:                                  │
│    Swift → JS:  evaluateJavaScript()             │
│    JS → Swift:  WKScriptMessageHandler           │
│    Ledger:      BLE ↔ Swift ↔ JS iframe relay    │
└──────────────────────────────────────────────────┘
```

`NEARWalletManager` owns a persistent `WKWebView` that loads a minimal HTML page importing the near-connect ES module from CDN. The WebView lives for the lifetime of the manager so JS state and wallet sessions survive across sheet presentations.

When a wallet operation requires user interaction (connect, approve transaction), the manager sets `showWalletUI = true` and the app presents the WebView in a full-screen sheet. Web wallets open as in-app popup WKWebViews; native app wallets (HOT, NEAR Mobile) open via deep links.

For Ledger hardware wallets, a `LedgerBLEManager` handles CoreBluetooth communication. APDU commands are relayed between the Ledger device and a sandboxed JS executor running inside an iframe, with the bridge HTML page acting as a message relay.

## Project structure

```
near-connect-ios/
├── Package.swift
├── Sources/
│   └── NEARConnect/
│       ├── NEARWalletManager.swift      # Core manager + WebViewCoordinator
│       ├── NEARAccount.swift            # Account model (Codable, Sendable)
│       ├── NEARError.swift              # Error types
│       ├── NEARConnectEvent.swift       # Internal JS bridge events
│       ├── BridgeWebViewContainer.swift # UIViewRepresentable for the WebView
│       ├── WalletBridgeSheet.swift      # Ready-to-use wallet UI sheet
│       ├── LedgerBLEManager.swift       # Ledger BLE communication
│       ├── LedgerSchemeHandler.swift    # Custom URL scheme handler
│       └── Resources/
│           ├── near-connect-bridge.html # JS bridge page (loads near-connect from CDN)
│           └── ledger-executor.js       # Ledger hardware wallet executor
└── Example/
    └── NEARConnectExample/
        ├── NEARConnectExampleApp.swift         # App entry point
        ├── ContentView.swift                   # Main UI with connect/disconnect
        ├── TransactionDemoView.swift           # Send NEAR demo
        ├── MessageSigningDemoView.swift        # Call contract demo
        ├── SignInAndSignMessageDemoView.swift  # Connect & sign message demo
        └── DelegateActionDemoView.swift        # Meta transactions demo
```

## Quick start

### 1. Import the library

```swift
import NEARConnect
```

### 2. Create the wallet manager

```swift
@main
struct MyApp: App {
    @StateObject private var walletManager = NEARWalletManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
        }
    }
}
```

### 3. Present the wallet UI

Bind the manager's `showWalletUI` to a full-screen cover and use the provided `WalletBridgeSheet`:

```swift
import SwiftUI
import NEARConnect

struct ContentView: View {
    @EnvironmentObject var walletManager: NEARWalletManager

    var body: some View {
        VStack {
            if walletManager.isSignedIn {
                Text("Connected: \(walletManager.currentAccount!.accountId)")
                Button("Disconnect") { walletManager.disconnect() }
            } else {
                Button("Connect Wallet") { walletManager.connect() }
            }
        }
        .fullScreenCover(isPresented: $walletManager.showWalletUI) {
            WalletBridgeSheet()
                .environmentObject(walletManager)
        }
    }
}
```

### 4. Send NEAR

```swift
let result = try await walletManager.sendNEAR(
    to: "bob.near",
    amountYocto: "1000000000000000000000000" // 1 NEAR
)
print("Transaction hash: \(result.transactionHashes.first ?? "")")
```

### 5. Call a smart contract

```swift
let result = try await walletManager.callFunction(
    contractId: "guest-book.near",
    methodName: "add_message",
    args: ["text": "Hello from iOS!"],
    deposit: "0"
)
```

### 6. Sign a message (NEP-413)

```swift
let result = try await walletManager.signMessage(
    message: "Authenticate with MyApp",
    recipient: "myapp.near"
)
print("Signature: \(result.signature ?? "")")
```

### 7. Connect & sign message in one step

```swift
let result = try await walletManager.connectAndSignMessage(
    message: "Sign in to MyApp",
    recipient: "myapp.near"
)
print("Account: \(result.accountId), Signature: \(result.signature)")
```

### 8. Sign delegate actions (NEP-366 meta transactions)

```swift
let result = try await walletManager.signDelegateActions(
    delegateActions: [
        [
            "receiverId": "guest-book.near",
            "actions": [
                [
                    "type": "FunctionCall",
                    "params": [
                        "methodName": "add_message",
                        "args": ["text": "Hello via relayer!"],
                        "gas": "30000000000000",
                        "deposit": "0"
                    ]
                ]
            ]
        ]
    ]
)
// result.delegateActions contains base64-encoded Borsh-serialized delegate actions
// ready for submission to a relayer
```

### 9. Query account balance

```swift
let account = try await walletManager.viewAccount()
if let amount = account["amount"] as? String {
    let near = NEARWalletManager.formatNEAR(yoctoNEAR: amount)
    print("Balance: \(near) NEAR")
}
```

## API reference

### NEARWalletManager

| Property / Method | Description |
|---|---|
| `currentAccount: NEARAccount?` | Currently connected account (nil if disconnected) |
| `isSignedIn: Bool` | Whether a wallet is connected |
| `isBusy: Bool` | Whether a wallet operation is in progress |
| `isBridgeReady: Bool` | Whether the JS bridge has loaded |
| `showWalletUI: Bool` | Bind to a sheet/cover to show the wallet WebView |
| `network: Network` | `.mainnet` (default) or `.testnet` |
| `ledgerBLE: LedgerBLEManager` | Ledger hardware wallet BLE manager |
| `connect()` | Show wallet selector |
| `connect(walletId:)` | Connect to a specific wallet by ID |
| `disconnect()` | Disconnect current wallet |
| `sendNEAR(to:amountYocto:)` | Transfer NEAR tokens |
| `signAndSendTransaction(receiverId:actions:)` | Send a transaction with custom actions |
| `callFunction(contractId:methodName:args:gas:deposit:)` | Call a contract method |
| `signMessage(message:recipient:nonce:)` | Sign an off-chain message (NEP-413) |
| `connectAndSignMessage(message:recipient:nonce:)` | Connect wallet and sign message in one flow |
| `signDelegateActions(delegateActions:)` | Sign meta transactions (NEP-366) |
| `viewAccount(_:)` | Query account info via NEAR RPC |
| `formatNEAR(yoctoNEAR:)` | Convert yoctoNEAR string to human-readable |
| `toYoctoNEAR(_:)` | Convert NEAR string to yoctoNEAR |
| `closePopups()` | Remove all popup WebViews (wallet pages) |

### NEARAccount

```swift
public struct NEARAccount: Codable, Equatable, Hashable, Sendable {
    public let accountId: String
    public let publicKey: String?
    public let walletId: String
}
```

### LedgerBLEManager

| Property / Method | Description |
|---|---|
| `isScanning: Bool` | Whether scanning for Ledger devices |
| `discoveredDevices: [LedgerDevice]` | Discovered Ledger BLE devices |
| `connectedDevice: LedgerDevice?` | Currently connected Ledger device |
| `bluetoothState: CBManagerState` | Current Bluetooth state |
| `isBluetoothReady: Bool` | Whether Bluetooth is powered on |
| `startScanning()` | Start scanning for Ledger devices |
| `stopScanning()` | Stop scanning |
| `connect(to:)` | Connect to a Ledger device |
| `disconnect()` | Disconnect from the Ledger device |
| `negotiateMTU()` | Negotiate BLE frame size with device |
| `exchange(apdu:)` | Send an APDU command and receive response |

Supported devices: Nano X, Stax, Flex, Nano Gen5 (Apex).

### Error handling

All async methods throw `NEARError`:

```swift
public enum NEARError: LocalizedError {
    case operationInProgress
    case notSignedIn
    case invalidURL
    case invalidTransaction
    case noTransactionHash
    case walletError(String)
    case webViewNotReady
    case rpcError(String)
}
```

Ledger operations throw `LedgerBLEError`:

```swift
public enum LedgerBLEError: LocalizedError {
    case notConnected
    case connectionFailed
    case disconnected
    case serviceNotFound
    case characteristicNotFound
    case exchangeTimeout
    case bluetoothNotAvailable
}
```

## Running the example app

1. Open the project in Xcode (the `Example/NEARConnectExample` directory references the local Swift Package)
2. Build and run on a simulator or device
3. For Ledger testing, run on a physical device (BLE is not available in the simulator)

The example app demonstrates:
- Wallet connection and disconnection
- NEAR token transfers
- Smart contract calls
- NEP-413 message signing
- Connect & sign message in one step
- NEP-366 delegate actions (meta transactions)

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 16.0+
- Physical device required for Ledger BLE support

## Security

This is a **non-custodial** integration. Your app never has access to private keys — all signing happens inside the wallet (or on the Ledger hardware device). Only account IDs and public keys are stored locally in UserDefaults.

## Resources

- [near-connect](https://github.com/AZbang/near-connect) — the JS library this project wraps
- [NEAR Protocol Docs](https://docs.near.org)
- [NEP-413: Message Signing](https://github.com/near/NEPs/blob/master/neps/nep-0413.md)
- [NEP-366: Meta Transactions](https://github.com/near/NEPs/blob/master/neps/nep-0366.md)

## License

MIT

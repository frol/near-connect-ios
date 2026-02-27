# NEARConnect

A proof-of-concept Swift Package for integrating NEAR Protocol wallet authentication, transaction signing, and message signing into iOS and macOS applications.
Wrapping [near-connect](https://github.com/azbang/near-connect) to be readily available for iOS developers.

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
- 📱 Multi-wallet support (Meteor Wallet, Intear Wallet, HOT Wallet, and [more](https://github.com/azbang/near-connect/blob/main/repository/manifest.json))
- 🔍 Automatic wallet detection
- 💾 Session persistence
- 🎯 Modern async/await API
- 🧪 Comprehensive test coverage

## Installation

### Swift Package Manager

Add NEARConnect to your project using Xcode:

1. File → Add Package Dependencies...
2. Enter package URL: `https://github.com/frol/near-connect-ios`
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/frol/near-connect-ios", from: "1.0.0")
]
```

## Quick Start

TBD

## Usage Examples

### Sign a Transaction

TBD

### Call a Smart Contract

TBD

### Sign a Message (NEP-413)

TBD

### Sign a Meta-Transaction (NEP-366)

TBD

### Check Wallet Installation

TBD

### List Available Wallets

TBD

## Advanced Usage

### Add Custom Wallet

TBD

### Custom Configuration

TBD

### Error Handling

TBD

## Example App

TBD

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

TBD

## Security Considerations

🔒 **Non-Custodial**: Your app never has access to private keys. All signing happens in the wallet app.

✅ **Best Practices**:
- Only account IDs and public keys are stored locally
- No sensitive data is logged
- All wallet communication uses standard protocols

## Roadmap

- [ ] Ledger hardware wallet support
- [ ] Multi-account management
- [ ] Network selection (mainnet/testnet)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Resources

- [NEAR Connect](https://github.com/azbang/near-connect)
- [NEAR Protocol Docs](https://docs.near.org)
- [NEP-413: Message Signing](https://github.com/near/NEPs/blob/master/neps/nep-0413.md)
- [NEP-366: Meta Transactions](https://github.com/near/NEPs/blob/master/neps/nep-0366.md)
- Legacy [NEAR Wallet Selector](https://github.com/near/wallet-selector)

## License

MIT License - see [LICENSE](LICENSE) for details

---

Built with ❤️ for the NEAR Protocol ecosystem

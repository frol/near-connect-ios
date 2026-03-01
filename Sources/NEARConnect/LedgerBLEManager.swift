import Foundation
import CoreBluetooth
import Combine

/// Manages BLE communication with a Ledger hardware wallet device.
///
/// Implements the Ledger APDU exchange protocol over Bluetooth Low Energy,
/// using the standard Ledger BLE service and characteristics. Frames are
/// sent/received using the Ledger framing protocol (channel 0x0101).
@MainActor
public class LedgerBLEManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published public private(set) var isScanning = false
    @Published public private(set) var discoveredDevices: [LedgerDevice] = []
    @Published public private(set) var connectedDevice: LedgerDevice?
    @Published public private(set) var bluetoothState: CBManagerState = .unknown

    /// Represents a discovered Ledger BLE device.
    public struct LedgerDevice: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let peripheral: CBPeripheral

        public static func == (lhs: LedgerDevice, rhs: LedgerDevice) -> Bool {
            lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Ledger BLE Protocol Constants

    /// Ledger Nano X BLE service UUID
    private static let ledgerServiceUUID = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")

    /// Write characteristic (app sends APDU frames here)
    private static let writeCharUUID = CBUUID(string: "13D63400-2C97-0004-0002-4C6564676572")

    /// Notify characteristic (app receives response frames here)
    private static let notifyCharUUID = CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572")

    /// BLE framing channel ID used by Ledger
    private static let channelID: UInt16 = 0x0101

    /// Maximum BLE frame payload (MTU minus framing overhead)
    private static let frameSize = 20

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private var bleDelegate: BLEDelegate!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// Buffer for assembling incoming response frames
    private var responseBuffer = Data()
    private var expectedResponseLength: Int = 0
    private var responseSequence: Int = 0

    /// Continuation for the current APDU exchange
    private var exchangeContinuation: CheckedContinuation<Data, any Error>?

    /// Continuation for scanning
    private var scanContinuation: CheckedContinuation<Void, Never>?

    /// Continuation for connection
    private var connectContinuation: CheckedContinuation<Void, any Error>?

    // MARK: - Init

    public override init() {
        super.init()
        bleDelegate = BLEDelegate(manager: self)
        centralManager = CBCentralManager(delegate: bleDelegate, queue: nil)
    }

    // MARK: - Public API

    /// Whether Bluetooth is available and powered on.
    public var isBluetoothReady: Bool {
        centralManager.state == .poweredOn
    }

    /// Start scanning for Ledger devices.
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[LedgerBLE] Bluetooth not ready, state: \(centralManager.state.rawValue)")
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [Self.ledgerServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Stop scanning for devices.
    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    /// Connect to a specific Ledger device.
    public func connect(to device: LedgerDevice) async throws {
        stopScanning()

        return try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.centralManager.connect(device.peripheral, options: nil)
        }
    }

    /// Disconnect from the currently connected device.
    public func disconnect() {
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device.peripheral)
        cleanUpConnection()
    }

    /// Exchange an APDU command with the connected Ledger device.
    ///
    /// Frames the APDU using the Ledger BLE framing protocol, sends it
    /// in chunks, and reassembles the response.
    ///
    /// - Parameter apdu: The raw APDU bytes to send.
    /// - Returns: The response bytes from the device.
    public func exchange(apdu: Data) async throws -> Data {
        guard let writeChar = writeCharacteristic else {
            throw LedgerBLEError.notConnected
        }
        guard let peripheral = connectedDevice?.peripheral else {
            throw LedgerBLEError.notConnected
        }

        // Reset response state
        responseBuffer = Data()
        expectedResponseLength = 0
        responseSequence = 0

        return try await withCheckedThrowingContinuation { continuation in
            self.exchangeContinuation = continuation

            // Frame and send the APDU
            let frames = self.frameAPDU(apdu)
            for frame in frames {
                peripheral.writeValue(frame, for: writeChar, type: .withResponse)
            }
        }
    }

    // MARK: - APDU Framing

    /// Frame an APDU into Ledger BLE transport frames.
    ///
    /// Ledger BLE framing:
    /// - Frame 0: [channel(2)] [tag=0x05] [seq(2)=0x0000] [length(2)] [data...]
    /// - Frame N: [channel(2)] [tag=0x05] [seq(2)] [data...]
    private func frameAPDU(_ apdu: Data) -> [Data] {
        var frames: [Data] = []
        var offset = 0
        var sequenceIndex: UInt16 = 0

        // First frame: includes length prefix
        var frame = Data()
        frame.append(UInt8(Self.channelID >> 8))
        frame.append(UInt8(Self.channelID & 0xFF))
        frame.append(0x05) // tag
        frame.append(UInt8(sequenceIndex >> 8))
        frame.append(UInt8(sequenceIndex & 0xFF))
        frame.append(UInt8(apdu.count >> 8))
        frame.append(UInt8(apdu.count & 0xFF))

        let firstChunkSize = min(apdu.count, Self.frameSize - 7)
        frame.append(contentsOf: apdu[offset..<(offset + firstChunkSize)])
        // Pad to frameSize
        while frame.count < Self.frameSize {
            frame.append(0x00)
        }
        frames.append(frame)
        offset += firstChunkSize
        sequenceIndex += 1

        // Subsequent frames
        while offset < apdu.count {
            var nextFrame = Data()
            nextFrame.append(UInt8(Self.channelID >> 8))
            nextFrame.append(UInt8(Self.channelID & 0xFF))
            nextFrame.append(0x05) // tag
            nextFrame.append(UInt8(sequenceIndex >> 8))
            nextFrame.append(UInt8(sequenceIndex & 0xFF))

            let chunkSize = min(apdu.count - offset, Self.frameSize - 5)
            nextFrame.append(contentsOf: apdu[offset..<(offset + chunkSize)])
            while nextFrame.count < Self.frameSize {
                nextFrame.append(0x00)
            }
            frames.append(nextFrame)
            offset += chunkSize
            sequenceIndex += 1
        }

        return frames
    }

    /// Process an incoming BLE notification frame (response data).
    private func handleResponseFrame(_ data: Data) {
        guard data.count >= 5 else { return }

        // Parse header
        let channel = (UInt16(data[0]) << 8) | UInt16(data[1])
        guard channel == Self.channelID else { return }
        let tag = data[2]
        guard tag == 0x05 else { return }
        let seq = (UInt16(data[3]) << 8) | UInt16(data[4])

        if seq == 0 {
            // First frame: read total response length
            guard data.count >= 7 else { return }
            expectedResponseLength = Int(UInt16(data[5]) << 8 | UInt16(data[6]))
            responseBuffer = Data()
            responseSequence = 0

            let payloadStart = 7
            if payloadStart < data.count {
                responseBuffer.append(contentsOf: data[payloadStart...])
            }
        } else {
            // Continuation frame
            let payloadStart = 5
            if payloadStart < data.count {
                responseBuffer.append(contentsOf: data[payloadStart...])
            }
        }

        responseSequence += 1

        // Check if we have the complete response
        if responseBuffer.count >= expectedResponseLength {
            let response = Data(responseBuffer.prefix(expectedResponseLength))
            exchangeContinuation?.resume(returning: response)
            exchangeContinuation = nil
        }
    }

    // MARK: - Internal Callbacks

    fileprivate func didUpdateBluetoothState(_ state: CBManagerState) {
        bluetoothState = state
    }

    fileprivate func didDiscoverPeripheral(_ peripheral: CBPeripheral, name: String?) {
        let deviceName = name ?? peripheral.name ?? "Ledger Device"
        let device = LedgerDevice(
            id: peripheral.identifier,
            name: deviceName,
            peripheral: peripheral
        )
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
        }
    }

    fileprivate func didConnectPeripheral(_ peripheral: CBPeripheral) {
        peripheral.delegate = bleDelegate
        peripheral.discoverServices([Self.ledgerServiceUUID])
    }

    fileprivate func didFailToConnect(_ peripheral: CBPeripheral, error: (any Error)?) {
        let err = error ?? LedgerBLEError.connectionFailed
        connectContinuation?.resume(throwing: err)
        connectContinuation = nil
    }

    fileprivate func didDisconnectPeripheral(_ peripheral: CBPeripheral) {
        cleanUpConnection()
        // Cancel any pending exchange
        exchangeContinuation?.resume(throwing: LedgerBLEError.disconnected)
        exchangeContinuation = nil
    }

    fileprivate func didDiscoverServices(_ peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: {
            $0.uuid == Self.ledgerServiceUUID
        }) else {
            connectContinuation?.resume(throwing: LedgerBLEError.serviceNotFound)
            connectContinuation = nil
            return
        }
        peripheral.discoverCharacteristics(
            [Self.writeCharUUID, Self.notifyCharUUID],
            for: service
        )
    }

    fileprivate func didDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService) {
        for char in service.characteristics ?? [] {
            if char.uuid == Self.writeCharUUID {
                writeCharacteristic = char
            } else if char.uuid == Self.notifyCharUUID {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        if writeCharacteristic != nil && notifyCharacteristic != nil {
            connectedDevice = discoveredDevices.first(where: {
                $0.peripheral.identifier == peripheral.identifier
            }) ?? LedgerDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Ledger",
                peripheral: peripheral
            )
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    fileprivate func didUpdateValue(_ characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.notifyCharUUID,
              let data = characteristic.value else { return }
        handleResponseFrame(data)
    }

    private func cleanUpConnection() {
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        responseBuffer = Data()
        expectedResponseLength = 0
        responseSequence = 0
    }
}

// MARK: - BLE Delegate (NSObject-based for CoreBluetooth)

/// Non-isolated NSObject delegate that forwards CoreBluetooth callbacks
/// to the MainActor-isolated LedgerBLEManager.
private class BLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private weak var manager: LedgerBLEManager?

    init(manager: LedgerBLEManager) {
        self.manager = manager
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            manager?.didUpdateBluetoothState(central.state)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        Task { @MainActor in
            manager?.didDiscoverPeripheral(peripheral, name: name)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            manager?.didConnectPeripheral(peripheral)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor in
            manager?.didFailToConnect(peripheral, error: error)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor in
            manager?.didDisconnectPeripheral(peripheral)
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { @MainActor in
            manager?.didDiscoverServices(peripheral)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        Task { @MainActor in
            manager?.didDiscoverCharacteristics(peripheral, service: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor in
            manager?.didUpdateValue(characteristic)
        }
    }
}

// MARK: - Errors

/// Errors specific to Ledger BLE communication.
public enum LedgerBLEError: LocalizedError {
    case notConnected
    case connectionFailed
    case disconnected
    case serviceNotFound
    case characteristicNotFound
    case exchangeTimeout
    case bluetoothNotAvailable

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Ledger device is not connected"
        case .connectionFailed:
            return "Failed to connect to Ledger device"
        case .disconnected:
            return "Ledger device disconnected"
        case .serviceNotFound:
            return "Ledger BLE service not found on device"
        case .characteristicNotFound:
            return "Ledger BLE characteristic not found"
        case .exchangeTimeout:
            return "Ledger APDU exchange timed out"
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        }
    }
}

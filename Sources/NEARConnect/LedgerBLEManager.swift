import Foundation
import CoreBluetooth
import Combine

/// Manages BLE communication with a Ledger hardware wallet device.
///
/// Implements the Ledger APDU exchange protocol over Bluetooth Low Energy,
/// using the standard Ledger BLE service and characteristics. Supports
/// all BLE-capable Ledger models (Nano X, Stax, Flex, Nano Gen5).
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

    /// BLE descriptor for a specific Ledger device model.
    private struct DeviceBLE {
        let name: String
        let serviceUUID: CBUUID
        let notifyUUID: CBUUID
        let writeUUID: CBUUID
        let writeCmdUUID: CBUUID
    }

    /// All BLE-capable Ledger device models and their UUIDs.
    /// UUID pattern: 13D63400-2C97-{model}04-{role}-4C6564676572
    ///   model: 00=NanoX, 60=Stax, 30=Flex, 80/90=NanoGen5(Apex)
    ///   role:  0000=Service, 0001=Notify, 0002=Write, 0003=WriteCmd
    private static let supportedDevices: [DeviceBLE] = [
        DeviceBLE(
            name: "Nano X",
            serviceUUID:  CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572"),
            notifyUUID:   CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572"),
            writeUUID:    CBUUID(string: "13D63400-2C97-0004-0002-4C6564676572"),
            writeCmdUUID: CBUUID(string: "13D63400-2C97-0004-0003-4C6564676572")
        ),
        DeviceBLE(
            name: "Stax",
            serviceUUID:  CBUUID(string: "13D63400-2C97-6004-0000-4C6564676572"),
            notifyUUID:   CBUUID(string: "13D63400-2C97-6004-0001-4C6564676572"),
            writeUUID:    CBUUID(string: "13D63400-2C97-6004-0002-4C6564676572"),
            writeCmdUUID: CBUUID(string: "13D63400-2C97-6004-0003-4C6564676572")
        ),
        DeviceBLE(
            name: "Flex",
            serviceUUID:  CBUUID(string: "13D63400-2C97-3004-0000-4C6564676572"),
            notifyUUID:   CBUUID(string: "13D63400-2C97-3004-0001-4C6564676572"),
            writeUUID:    CBUUID(string: "13D63400-2C97-3004-0002-4C6564676572"),
            writeCmdUUID: CBUUID(string: "13D63400-2C97-3004-0003-4C6564676572")
        ),
        DeviceBLE(
            name: "Nano Gen5",
            serviceUUID:  CBUUID(string: "13D63400-2C97-8004-0000-4C6564676572"),
            notifyUUID:   CBUUID(string: "13D63400-2C97-8004-0001-4C6564676572"),
            writeUUID:    CBUUID(string: "13D63400-2C97-8004-0002-4C6564676572"),
            writeCmdUUID: CBUUID(string: "13D63400-2C97-8004-0003-4C6564676572")
        ),
        DeviceBLE(
            name: "Nano Gen5",
            serviceUUID:  CBUUID(string: "13D63400-2C97-9004-0000-4C6564676572"),
            notifyUUID:   CBUUID(string: "13D63400-2C97-9004-0001-4C6564676572"),
            writeUUID:    CBUUID(string: "13D63400-2C97-9004-0002-4C6564676572"),
            writeCmdUUID: CBUUID(string: "13D63400-2C97-9004-0003-4C6564676572")
        ),
    ]

    /// All service UUIDs to scan for.
    private static let allServiceUUIDs: [CBUUID] = supportedDevices.map(\.serviceUUID)

    /// Look up the device BLE descriptor by its service UUID.
    private static func deviceBLE(forService uuid: CBUUID) -> DeviceBLE? {
        supportedDevices.first { $0.serviceUUID == uuid }
    }

    /// Default BLE frame size (ATT MTU 23 minus 3 bytes ATT overhead)
    private static let defaultMTUSize = 20

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private var bleDelegate: BLEDelegate!
    /// Write-with-response characteristic (UUID suffix 0002)
    private var writeCharacteristic: CBCharacteristic?
    /// Write-without-response characteristic (UUID suffix 0003), preferred when available
    private var writeCmdCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// The BLE descriptor for the currently connected device model.
    private var connectedDeviceBLE: DeviceBLE?

    /// Negotiated MTU frame size (payload bytes per BLE write)
    private var mtuSize: Int = defaultMTUSize

    /// Buffer for assembling incoming response frames
    private var responseBuffer = Data()
    private var expectedResponseLength: Int = 0
    private var responseSequence: Int = 0

    /// Continuation for MTU negotiation response
    private var mtuContinuation: CheckedContinuation<Int, any Error>?

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
            withServices: Self.allServiceUUIDs,
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

    /// Negotiate MTU with the Ledger device.
    ///
    /// Sends a `0x08` command and reads the negotiated MTU from the response.
    /// Must be called after connection and before any APDU exchange.
    public func negotiateMTU() async throws {
        guard let peripheral = connectedDevice?.peripheral else {
            throw LedgerBLEError.notConnected
        }

        let negotiatedMTU = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
            self.mtuContinuation = continuation
            let mtuRequest = Data([0x08, 0x00, 0x00, 0x00, 0x00])
            self.writeToDevice(peripheral: peripheral, data: mtuRequest)
        }

        if negotiatedMTU > Self.defaultMTUSize {
            mtuSize = negotiatedMTU
        }
        print("[LedgerBLE] Negotiated MTU size: \(mtuSize)")
    }

    /// Exchange an APDU command with the connected Ledger device.
    ///
    /// Frames the APDU using the Ledger BLE framing protocol, sends it
    /// in chunks, and reassembles the response.
    ///
    /// - Parameter apdu: The raw APDU bytes to send.
    /// - Returns: The response bytes from the device.
    public func exchange(apdu: Data) async throws -> Data {
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
                self.writeToDevice(peripheral: peripheral, data: frame)
            }
        }
    }

    /// Write data to the Ledger device, preferring writeCmd (without response) if available.
    private func writeToDevice(peripheral: CBPeripheral, data: Data) {
        if let writeCmdChar = writeCmdCharacteristic {
            peripheral.writeValue(data, for: writeCmdChar, type: .withoutResponse)
        } else if let writeChar = writeCharacteristic {
            peripheral.writeValue(data, for: writeChar, type: .withResponse)
        }
    }

    // MARK: - APDU Framing

    /// Frame an APDU into Ledger BLE transport frames.
    ///
    /// Ledger BLE framing (no channel bytes, unlike HID):
    /// - Frame 0: [tag=0x05] [seq(2)=0x0000] [length(2)] [data...]  (5-byte header)
    /// - Frame N: [tag=0x05] [seq(2)] [data...]                      (3-byte header)
    /// Frames are NOT padded — each is exactly header + payload bytes.
    private func frameAPDU(_ apdu: Data) -> [Data] {
        var frames: [Data] = []
        var offset = 0
        var sequenceIndex: UInt16 = 0

        // First frame: 5-byte header (tag + seq + length)
        var frame = Data()
        frame.append(0x05) // tag
        frame.append(UInt8(sequenceIndex >> 8))
        frame.append(UInt8(sequenceIndex & 0xFF))
        frame.append(UInt8(apdu.count >> 8))
        frame.append(UInt8(apdu.count & 0xFF))

        let firstChunkSize = min(apdu.count, mtuSize - 5)
        frame.append(contentsOf: apdu[offset..<(offset + firstChunkSize)])
        frames.append(frame)
        offset += firstChunkSize
        sequenceIndex += 1

        // Subsequent frames: 3-byte header (tag + seq)
        while offset < apdu.count {
            var nextFrame = Data()
            nextFrame.append(0x05) // tag
            nextFrame.append(UInt8(sequenceIndex >> 8))
            nextFrame.append(UInt8(sequenceIndex & 0xFF))

            let chunkSize = min(apdu.count - offset, mtuSize - 3)
            nextFrame.append(contentsOf: apdu[offset..<(offset + chunkSize)])
            frames.append(nextFrame)
            offset += chunkSize
            sequenceIndex += 1
        }

        return frames
    }

    /// Process an incoming BLE notification frame (response data).
    private func handleNotification(_ data: Data) {
        guard data.count >= 1 else { return }

        let tag = data[0]

        // MTU negotiation response (tag 0x08)
        if tag == 0x08 {
            if data.count >= 6 {
                let negotiatedMTU = Int(data[5])
                print("[LedgerBLE] MTU negotiation response: \(negotiatedMTU)")
                mtuContinuation?.resume(returning: negotiatedMTU)
                mtuContinuation = nil
            }
            return
        }

        // APDU response frame (tag 0x05)
        guard tag == 0x05 else {
            print("[LedgerBLE] Unknown notification tag: 0x\(String(tag, radix: 16))")
            return
        }
        guard data.count >= 3 else { return }

        let seq = (UInt16(data[1]) << 8) | UInt16(data[2])

        if seq == 0 {
            // First frame: [tag=0x05] [seq(2)] [length(2)] [data...]
            guard data.count >= 5 else { return }
            expectedResponseLength = Int(UInt16(data[3]) << 8 | UInt16(data[4]))
            responseBuffer = Data()
            responseSequence = 0

            let payloadStart = 5
            if payloadStart < data.count {
                responseBuffer.append(contentsOf: data[payloadStart...])
            }
        } else {
            // Continuation frame: [tag=0x05] [seq(2)] [data...]
            let payloadStart = 3
            if payloadStart < data.count {
                responseBuffer.append(contentsOf: data[payloadStart...])
            }
        }

        responseSequence += 1

        // Check if we have the complete response
        if responseBuffer.count >= expectedResponseLength && expectedResponseLength > 0 {
            let response = Data(responseBuffer.prefix(expectedResponseLength))
            print("[LedgerBLE] APDU response complete: \(response.count) bytes")
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
        peripheral.discoverServices(Self.allServiceUUIDs)
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
        // Find the first Ledger service that matches any supported device model
        guard let service = peripheral.services?.first(where: { svc in
            Self.deviceBLE(forService: svc.uuid) != nil
        }),
        let deviceSpec = Self.deviceBLE(forService: service.uuid) else {
            connectContinuation?.resume(throwing: LedgerBLEError.serviceNotFound)
            connectContinuation = nil
            return
        }
        connectedDeviceBLE = deviceSpec
        print("[LedgerBLE] Discovered Ledger \(deviceSpec.name) service")
        peripheral.discoverCharacteristics(
            [deviceSpec.writeUUID, deviceSpec.writeCmdUUID, deviceSpec.notifyUUID],
            for: service
        )
    }

    fileprivate func didDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService) {
        guard let deviceSpec = connectedDeviceBLE else { return }
        for char in service.characteristics ?? [] {
            if char.uuid == deviceSpec.writeUUID {
                writeCharacteristic = char
                print("[LedgerBLE] Found write characteristic (0002)")
            } else if char.uuid == deviceSpec.writeCmdUUID {
                writeCmdCharacteristic = char
                print("[LedgerBLE] Found writeCmd characteristic (0003)")
            } else if char.uuid == deviceSpec.notifyUUID {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[LedgerBLE] Found notify characteristic (0001), subscribing")
            }
        }

        // Need at least one write characteristic and the notify characteristic
        let hasWrite = writeCharacteristic != nil || writeCmdCharacteristic != nil
        if hasWrite && notifyCharacteristic != nil {
            connectedDevice = discoveredDevices.first(where: {
                $0.peripheral.identifier == peripheral.identifier
            }) ?? LedgerDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Ledger",
                peripheral: peripheral
            )
            let writeType = writeCmdCharacteristic != nil ? "withoutResponse (0003)" : "withResponse (0002)"
            print("[LedgerBLE] Connected, using write type: \(writeType)")
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    fileprivate func didUpdateValue(_ characteristic: CBCharacteristic) {
        guard let deviceSpec = connectedDeviceBLE,
              characteristic.uuid == deviceSpec.notifyUUID,
              let data = characteristic.value else { return }
        print("[LedgerBLE] Notification: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
        handleNotification(data)
    }

    private func cleanUpConnection() {
        connectedDevice = nil
        connectedDeviceBLE = nil
        writeCharacteristic = nil
        writeCmdCharacteristic = nil
        notifyCharacteristic = nil
        mtuSize = Self.defaultMTUSize
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

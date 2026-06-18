import CoreBluetooth
import Observation

enum DeviceConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
}

@Observable
final class BluetoothViewModel: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning = false
    var connectionState: DeviceConnectionState = .idle

    var onConnected: ((CBPeripheral) -> Void)?

    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private var pendingPeripheral: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scan

    func startScan() {
        discoveredDevices = []
        peripheralMap = [:]
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    // MARK: - Connect

    func connectDiscovered(_ device: DiscoveredDevice) {
        guard let peripheral = peripheralMap[device.id] else { return }
        connect(peripheral)
    }

    private func connect(_ peripheral: CBPeripheral) {
        pendingPeripheral = peripheral
        connectionState = .connecting
        central.stopScan()
        isScanning = false
        central.connect(peripheral, options: nil)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        peripheralMap[id] = peripheral
        guard !discoveredDevices.contains(where: { $0.id == id }) else { return }
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "未知裝置"
        discoveredDevices.append(DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        onConnected?(peripheral)
        pendingPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: (any Error)?) {
        connectionState = .failed(error?.localizedDescription ?? "連線失敗")
        pendingPeripheral = nil
    }
}

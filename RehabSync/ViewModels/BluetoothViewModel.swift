import CoreBluetooth
import Observation

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

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        discoveredDevices = []
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

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        guard !discoveredDevices.contains(where: { $0.id == id }) else { return }
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "未知裝置"
        discoveredDevices.append(DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue))
    }
}

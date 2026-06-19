import CoreBluetooth
import Observation
import GRDB
import Foundation

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
    private let bleQueue = DispatchQueue(label: "com.rehabsync.ble", qos: .userInitiated)

    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning = false
    var connectionState: DeviceConnectionState = .idle
    var isRecording = false

    var onConnected: ((CBPeripheral) -> Void)?
    var onDisconnected: ((UUID) -> Void)?

    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private(set) var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingPeripheral: CBPeripheral?

    private let deviceVM = DeviceViewModel()
    @ObservationIgnored private var bluetoothConfig: Bluetooth?
    @ObservationIgnored private var charMap: [UUID: [CBUUID: CBCharacteristic]] = [:]
    @ObservationIgnored private var deviceIdMap: [UUID: Int64] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Seed

    func seedIfNeeded() {
        let db = DatabaseManager.shared.dbQueue

        let count = (try? db.read { db in
            try Bluetooth.fetchCount(db)
        }) ?? 0

        guard count == 0 else {
            print("[seed] bluetooth 已有資料，跳過 seed")
            return
        }

        guard let url = Bundle.main.url(forResource: "bluetooth", withExtension: "json") else {
            print("[seed] ❌ 找不到 bluetooth.json")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[seed] ❌ 無法讀取 bluetooth.json")
            return
        }

        let dtos: [BluetoothDTO]
        do {
            dtos = try JSONDecoder().decode([BluetoothDTO].self, from: data)
        } catch {
            print("[seed] ❌ JSON 解析失敗：\(error)")
            return
        }

        do {
            try db.write { db in
                for dto in dtos {
                    var record = Bluetooth(
                        write_uuid:       dto.write_uuid,
                        sub_acc_uuid:     dto.sub_acc_uuid,
                        sub_gyro_uuid:    dto.sub_gyro_uuid,
                        sub_exg_uuid:     dto.sub_exg_uuid,
                        acc_sensitivity:  dto.acc_sensitivity,
                        gyro_sensitivity: dto.gyro_sensitivity,
                        cmd_a0:           Data(dto.cmd_a0),
                        cmd_a1:           Data(dto.cmd_a1),
                        is_default:       dto.is_default
                    )
                    try record.insert(db, onConflict: .replace)
                }
            }
            print("[seed] ✅ bluetooth seed 完成，共 \(dtos.count) 筆")
        } catch {
            print("[seed] ❌ 寫入失敗：\(error)")
        }
    }

    // MARK: - Scan

    func startScan() {
        DispatchQueue.main.async {
            self.discoveredDevices = []
            self.peripheralMap = [:]
        }
        bleQueue.async {
            guard self.central.state == .poweredOn else { return }
            DispatchQueue.main.async { self.isScanning = true }
            self.central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        }
    }

    func stopScan() {
        bleQueue.async { self.central.stopScan() }
        DispatchQueue.main.async { self.isScanning = false }
    }

    // MARK: - Connect / Disconnect

    func connectDiscovered(_ device: DiscoveredDevice) {
        bleQueue.async {
            guard let peripheral = self.peripheralMap[device.id] else { return }
            DispatchQueue.main.async {
                self.pendingPeripheral = peripheral
                self.connectionState = .connecting
                self.isScanning = false
            }
            self.central.stopScan()
            self.central.connect(peripheral, options: nil)
        }
    }

    func disconnect(id: UUID) {
        bleQueue.async {
            guard let peripheral = self.connectedPeripherals[id] else { return }
            self.central.cancelPeripheralConnection(peripheral)
        }
    }

    func cancelPendingConnection() {
        bleQueue.async {
            if let peripheral = self.pendingPeripheral {
                self.central.cancelPeripheralConnection(peripheral)
            }
            DispatchQueue.main.async {
                self.pendingPeripheral = nil
                self.connectionState = .idle
                self.isScanning = false
            }
            self.central.stopScan()
        }
    }

    // MARK: - Recording

    func startRecording(peripheral: CBPeripheral) {
        guard let config = bluetoothConfig,
              let map = charMap[peripheral.identifier] else { return }

        let writeUUID = CBUUID(string: config.write_uuid)
        let accUUID   = CBUUID(string: config.sub_acc_uuid)
        let gyroUUID  = CBUUID(string: config.sub_gyro_uuid)
        let exgUUID   = CBUUID(string: config.sub_exg_uuid)

        if let writeChar = map[writeUUID] {
            peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
        }

        if let c = map[accUUID]  { peripheral.setNotifyValue(true, for: c) }
        if let c = map[gyroUUID] { peripheral.setNotifyValue(true, for: c) }
        if let c = map[exgUUID]  { peripheral.setNotifyValue(true, for: c) }

        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording(peripheral: CBPeripheral) {
        guard let config = bluetoothConfig,
              let map = charMap[peripheral.identifier] else { return }

        let accUUID  = CBUUID(string: config.sub_acc_uuid)
        let gyroUUID = CBUUID(string: config.sub_gyro_uuid)
        let exgUUID  = CBUUID(string: config.sub_exg_uuid)

        if let c = map[accUUID]  { peripheral.setNotifyValue(false, for: c) }
        if let c = map[gyroUUID] { peripheral.setNotifyValue(false, for: c) }
        if let c = map[exgUUID]  { peripheral.setNotifyValue(false, for: c) }

        DispatchQueue.main.async { self.isRecording = false }
    }

    // MARK: - DB Helpers

    private func loadDefaultBluetoothConfig() -> Bluetooth? {
        try? DatabaseManager.shared.dbQueue.read { db in
            try Bluetooth.filter(Column("is_default") == 1).fetchOne(db)
        }
    }

    private func loadDevice(uuid: String) -> Device? {
        try? DatabaseManager.shared.dbQueue.read { db in
            try Device.filter(Column("device_uuid") == uuid).fetchOne(db)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name else { return }

        DispatchQueue.main.async {
            self.peripheralMap[id] = peripheral
            guard !self.discoveredDevices.contains(where: { $0.id == id }) else { return }
            self.discoveredDevices.append(DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue))
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        // 在 bleQueue 直接賦值，確保 discoverServices 前 config 已就緒
        bluetoothConfig = loadDefaultBluetoothConfig()

        peripheral.delegate = self
        peripheral.discoverServices(nil)

        DispatchQueue.main.async {
            self.connectionState = .connected
            self.connectedPeripherals[peripheral.identifier] = peripheral
            self.onConnected?(peripheral)
            self.pendingPeripheral = nil
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: (any Error)?) {
        DispatchQueue.main.async {
            self.connectionState = .failed(error?.localizedDescription ?? "連線失敗")
            self.pendingPeripheral = nil
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        DispatchQueue.main.async {
            self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
            self.charMap.removeValue(forKey: peripheral.identifier)
            self.deviceIdMap.removeValue(forKey: peripheral.identifier)
            self.isRecording = false
            self.onDisconnected?(peripheral.identifier)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothViewModel: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let config = bluetoothConfig,
              let services = peripheral.services else { return }
        let targetUUIDs = [
            CBUUID(string: config.write_uuid),
            CBUUID(string: config.sub_acc_uuid),
            CBUUID(string: config.sub_gyro_uuid),
            CBUUID(string: config.sub_exg_uuid)
        ]
        for service in services {
            peripheral.discoverCharacteristics(targetUUIDs, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        var map = charMap[peripheral.identifier] ?? [:]
        for char in chars { map[char.uuid] = char }
        charMap[peripheral.identifier] = map
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let config = bluetoothConfig,
              let data = characteristic.value else { return }

        // 首次通知時 onConnected 已執行完畢，DB 已有裝置，lazy load device_id
        if deviceIdMap[peripheral.identifier] == nil,
           let d = loadDevice(uuid: peripheral.identifier.uuidString),
           let id = d.id {
            deviceIdMap[peripheral.identifier] = id
        }

        guard let deviceId = deviceIdMap[peripheral.identifier] else { return }

        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let uuid = characteristic.uuid

        if uuid == CBUUID(string: config.sub_acc_uuid) {
            parseACC(data, deviceId: deviceId, timestamp: ts, config: config)
        } else if uuid == CBUUID(string: config.sub_gyro_uuid) {
            parseGYRO(data, deviceId: deviceId, timestamp: ts, config: config)
        } else if uuid == CBUUID(string: config.sub_exg_uuid) {
            parseEXG(data, deviceId: deviceId, timestamp: ts)
        }
    }

    // MARK: - Packet Parsers

    private func parseACC(_ data: Data, deviceId: Int64, timestamp: Int64, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var samples: [(x: Double, y: Double, z: Double)] = []
        for i in 0..<20 {
            let offset = 3 + i * 6
            let x = Double(data.int16BE(at: offset))     * config.acc_sensitivity
            let y = Double(data.int16BE(at: offset + 2)) * config.acc_sensitivity
            let z = Double(data.int16BE(at: offset + 4)) * config.acc_sensitivity
            samples.append((x, y, z))
        }
        deviceVM.insertACC(deviceId: deviceId, timestamp: timestamp, samples: samples)
    }

    private func parseGYRO(_ data: Data, deviceId: Int64, timestamp: Int64, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var samples: [(pitch: Double, roll: Double, yaw: Double)] = []
        for i in 0..<20 {
            let offset = 3 + i * 6
            let pitch = Double(data.int16BE(at: offset))     * config.gyro_sensitivity / 1000
            let roll  = Double(data.int16BE(at: offset + 2)) * config.gyro_sensitivity / 1000
            let yaw   = Double(data.int16BE(at: offset + 4)) * config.gyro_sensitivity / 1000
            samples.append((pitch, roll, yaw))
        }
        deviceVM.insertGYRO(deviceId: deviceId, timestamp: timestamp, samples: samples)
    }

    private func parseEXG(_ data: Data, deviceId: Int64, timestamp: Int64) {
        guard !data.isEmpty else { return }
        let flag = data[0]

        if flag == 0xE8 {
            guard data.count >= 10 else { return }
            let ch1 = Int(data.int16BE(at: 2))
            let ch2 = Int(data.int16BE(at: 6))
            deviceVM.insertEXGBatch(deviceId: deviceId, timestamp: timestamp, values: [ch1, ch2])

        } else if flag == 0xE0 || flag == 0xE1 {
            guard data.count >= 131 else { return }
            var values: [Int] = []
            for i in 0..<64 {
                values.append(Int(data.int16BE(at: 3 + i * 2)))
            }
            deviceVM.insertEXGBatch(deviceId: deviceId, timestamp: timestamp, values: values)
        }
    }
}

// MARK: - Data Helper

private extension Data {
    func int16BE(at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(self[offset]) << 8 | UInt16(self[offset + 1]))
    }
}

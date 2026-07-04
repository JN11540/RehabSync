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
    var isCleaningUp = false
    var recordingStartTime: Int64? = nil
    var recordingEndTime:   Int64? = nil

    var onConnected: ((CBPeripheral) -> Void)?
    var onDisconnected: ((UUID) -> Void)?

    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private(set) var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingPeripheral: CBPeripheral?

    private let deviceVM = DeviceViewModel()
    @ObservationIgnored private var bluetoothConfig: Bluetooth?
    @ObservationIgnored private var charMap: [UUID: [CBUUID: CBCharacteristic]] = [:]
    @ObservationIgnored private var deviceIdMap: [UUID: Int64] = [:]

    // Calibration — UI state (main thread)
    var gyroBiases: [UUID: GyroBias] = [:]
    var calibratingUUIDs: Set<UUID> = []
    // Calibration — internal (bleQueue)
    @ObservationIgnored private var calibratingPeripherals: Set<UUID> = []
    @ObservationIgnored private var calibAccBuffers:   [UUID: [(Double, Double, Double)]] = [:]
    @ObservationIgnored private var calibGyroBuffers:  [UUID: [(Double, Double, Double)]] = [:]
    @ObservationIgnored private var gyroCalibrationMap: [UUID: GyroBias] = [:]

    // Baseline Calibration（膝角基準值，只用加速度計）— UI state (main thread)
    var isCollectingBaseline = false
    var baselineResult: Double? = nil
    // Baseline Calibration — internal (bleQueue)，收集期間不寫入資料庫
    @ObservationIgnored private var baselineCollecting: Set<UUID> = []
    @ObservationIgnored private var baselineAccBuffers: [UUID: [(timestamp: Int64, x: Double, y: Double, z: Double)]] = [:]

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
        let exgUUID   = CBUUID(string: config.sub_exg_uuid)

        if let writeChar = map[writeUUID] {
            peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
        }

        if let c = map[accUUID]  { peripheral.setNotifyValue(true, for: c) }
        if let c = map[exgUUID]  { peripheral.setNotifyValue(true, for: c) }

        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording(peripheral: CBPeripheral) {
        guard let config = bluetoothConfig,
              let map = charMap[peripheral.identifier] else { return }

        let accUUID  = CBUUID(string: config.sub_acc_uuid)
        let exgUUID  = CBUUID(string: config.sub_exg_uuid)

        if let c = map[accUUID]  { peripheral.setNotifyValue(false, for: c) }
        if let c = map[exgUUID]  { peripheral.setNotifyValue(false, for: c) }

        DispatchQueue.main.async { self.isRecording = false }
    }

    // MARK: - Calibration

    func startCalibration(peripheral: CBPeripheral) {
        let id = peripheral.identifier
        DispatchQueue.main.async {
            self.gyroBiases.removeValue(forKey: id)
            self.calibratingUUIDs.insert(id)
        }
        bleQueue.async { [weak self] in
            guard let self,
                  let config = bluetoothConfig,
                  let map = charMap[id] else { return }
            calibAccBuffers[id]  = []
            calibGyroBuffers[id] = []
            calibratingPeripherals.insert(id)
            // 裝置需要收到指令才會開始推送感測資料
            if let writeChar = map[CBUUID(string: config.write_uuid)] {
                peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
            }
            if let c = map[CBUUID(string: config.sub_acc_uuid)]  { peripheral.setNotifyValue(true, for: c) }
            if let c = map[CBUUID(string: config.sub_gyro_uuid)] { peripheral.setNotifyValue(true, for: c) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.bleQueue.async { self?.finishCalibration(peripheral: peripheral) }
            }
        }
    }

    private func finishCalibration(peripheral: CBPeripheral) {
        let id = peripheral.identifier
        calibratingPeripherals.remove(id)

        let accBuf  = calibAccBuffers.removeValue(forKey: id)  ?? []
        let gyroBuf = calibGyroBuffers.removeValue(forKey: id) ?? []
        let count   = min(accBuf.count, gyroBuf.count)

        let samples = (0..<count).map { i in
            IMUSample(
                ax: accBuf[i].0,  ay: accBuf[i].1,  az: accBuf[i].2,
                gx: gyroBuf[i].0, gy: gyroBuf[i].1, gz: gyroBuf[i].2
            )
        }

        let bias = GYROCalibration.calibrate(samples: samples, accStdThreshold: 30.0)
        if let bias { gyroCalibrationMap[id] = bias }

        if let config = bluetoothConfig, let map = charMap[id] {
            if let c = map[CBUUID(string: config.sub_acc_uuid)]  { peripheral.setNotifyValue(false, for: c) }
            if let c = map[CBUUID(string: config.sub_gyro_uuid)] { peripheral.setNotifyValue(false, for: c) }
        }

        DispatchQueue.main.async {
            self.calibratingUUIDs.remove(id)
            if let bias { self.gyroBiases[id] = bias }
        }
    }

    // MARK: - Baseline Calibration（膝角基準值）

    /// 錄製大腿與小腿加速度計 5 秒，收集期間不寫入資料庫，結束後計算膝角基準值。
    func startBaselineCalibration(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.baselineResult = nil
            self.isCollectingBaseline = true
        }
        bleQueue.async { [weak self] in
            guard let self, let config = bluetoothConfig else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }

            baselineAccBuffers[thighPeripheral.identifier] = []
            baselineAccBuffers[calfPeripheral.identifier]  = []
            baselineCollecting = [thighPeripheral.identifier, calfPeripheral.identifier]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.bleQueue.async {
                    self?.finishBaselineCalibration(
                        thighPeripheral: thighPeripheral,
                        calfPeripheral: calfPeripheral,
                        wasRecording: wasRecording
                    )
                }
            }
        }
    }

    private func finishBaselineCalibration(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral, wasRecording: Bool) {
        baselineCollecting = []

        let thighSamples = baselineAccBuffers.removeValue(forKey: thighPeripheral.identifier) ?? []
        let calfSamples  = baselineAccBuffers.removeValue(forKey: calfPeripheral.identifier)  ?? []

        if !wasRecording, let config = bluetoothConfig {
            for peripheral in [thighPeripheral, calfPeripheral] {
                if let map = charMap[peripheral.identifier],
                   let c = map[CBUUID(string: config.sub_acc_uuid)] {
                    peripheral.setNotifyValue(false, for: c)
                }
            }
        }

        let result = Self.computeBaselineAngle(thighSamples: thighSamples, calfSamples: calfSamples)
        DispatchQueue.main.async {
            self.baselineResult = result
            self.isCollectingBaseline = false
        }
    }

    /// 移植自 baseline_check.py（check_whole_range_stable）+ calibration_phase.py（inclination_deg / compute_knee_angle）：
    /// 用加速度算大腿、小腿相對重力的傾角，膝角 = 大腿傾角 - 小腿傾角；整段錄製視為單一區間，
    /// 標準差（樣本標準差）<= 1.5° 且時長 >= 1 秒才算穩定，穩定則回傳角度平均值的絕對值（四捨五入到小數1位），否則回傳 -1。
    static func computeBaselineAngle(
        thighSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        calfSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        stdThresholdDeg: Double = 1.5,
        minDurationSec: Double = 1.0
    ) -> Double {
        func inclinationDeg(_ x: Double, _ y: Double, _ z: Double) -> Double {
            atan2(x, (y * y + z * z).squareRoot()) * 180 / .pi
        }

        // 依 timestamp 分組平均，濾掉同一個 timestamp 底下多筆瞬間取樣的高頻雜訊
        func smoothedIncline(_ samples: [(timestamp: Int64, x: Double, y: Double, z: Double)]) -> [(t: Int64, incline: Double)] {
            var sums: [Int64: (sum: Double, count: Int)] = [:]
            for s in samples {
                let incline = inclinationDeg(s.x, s.y, s.z)
                var g = sums[s.timestamp] ?? (0, 0)
                g.sum += incline
                g.count += 1
                sums[s.timestamp] = g
            }
            return sums.map { (t: $0.key, incline: $0.value.sum / Double($0.value.count)) }
                .sorted { $0.t < $1.t }
        }

        guard !thighSamples.isEmpty, !calfSamples.isEmpty else { return -1 }

        let thighIncline = smoothedIncline(thighSamples)
        let calfIncline  = smoothedIncline(calfSamples)
        let count = min(thighIncline.count, calfIncline.count)
        guard count >= 2 else { return -1 }

        // 大腿與小腿分別平滑後，依時間順序逐一配對計算膝角
        var kneeAngles: [Double] = []
        var tSecs: [Double] = []
        for i in 0..<count {
            kneeAngles.append(thighIncline[i].incline - calfIncline[i].incline)
            tSecs.append(Double(thighIncline[i].t) / 1000.0)
        }

        let duration = tSecs.max()! - tSecs.min()!
        let mean = kneeAngles.reduce(0, +) / Double(kneeAngles.count)
        let variance = kneeAngles.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(kneeAngles.count - 1)
        let std = variance.squareRoot()

        guard std <= stdThresholdDeg, duration >= minDurationSec else { return -1 }

        return (abs(mean) * 10).rounded() / 10
    }

    func startRecordingAll() {
        recordingStartTime = Int64(Date().timeIntervalSince1970 * 1000)
        recordingEndTime   = nil
        for peripheral in connectedPeripherals.values {
            startRecording(peripheral: peripheral)
        }
    }

    func stopRecordingAll() {
        recordingEndTime = Int64(Date().timeIntervalSince1970 * 1000)
        for peripheral in connectedPeripherals.values {
            stopRecording(peripheral: peripheral)
        }
        deviceVM.cleanupIfNeeded(
            onStart:  { self.isCleaningUp = true },
            onFinish: { self.isCleaningUp = false }
        )
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
        gyroCalibrationMap.removeValue(forKey: peripheral.identifier)
        DispatchQueue.main.async {
            self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
            self.charMap.removeValue(forKey: peripheral.identifier)
            self.deviceIdMap.removeValue(forKey: peripheral.identifier)
            self.gyroBiases.removeValue(forKey: peripheral.identifier)
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

        let uuid = characteristic.uuid

        // 校正模式：收集到 buffer，不寫 DB
        if calibratingPeripherals.contains(peripheral.identifier) {
            if uuid == CBUUID(string: config.sub_acc_uuid) {
                collectCalibACC(data, id: peripheral.identifier, config: config)
            } else if uuid == CBUUID(string: config.sub_gyro_uuid) {
                collectCalibGYRO(data, id: peripheral.identifier, config: config)
            }
            return
        }

        // 膝角基準值校正模式：收集到 buffer，不寫 DB
        if baselineCollecting.contains(peripheral.identifier) {
            if uuid == CBUUID(string: config.sub_acc_uuid) {
                collectBaselineACC(data, id: peripheral.identifier, config: config)
            }
            return
        }

        // 首次通知時 onConnected 已執行完畢，DB 已有裝置，lazy load device_id
        if deviceIdMap[peripheral.identifier] == nil,
           let d = loadDevice(uuid: peripheral.identifier.uuidString),
           let id = d.id {
            deviceIdMap[peripheral.identifier] = id
        }

        guard let deviceId = deviceIdMap[peripheral.identifier] else { return }

        let ts = Int64(Date().timeIntervalSince1970 * 1000)

        if uuid == CBUUID(string: config.sub_acc_uuid) {
            parseACC(data, deviceId: deviceId, timestamp: ts, config: config)
        } else if uuid == CBUUID(string: config.sub_gyro_uuid) {
            parseGYRO(data, deviceId: deviceId, timestamp: ts, config: config, peripheralId: peripheral.identifier)
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

    private func parseGYRO(_ data: Data, deviceId: Int64, timestamp: Int64, config: Bluetooth, peripheralId: UUID) {
        guard data.count >= 123 else { return }
        let bias = gyroCalibrationMap[peripheralId]
        var samples: [(pitch: Double, roll: Double, yaw: Double)] = []
        for i in 0..<20 {
            let offset = 3 + i * 6
            let pitch = Double(data.int16BE(at: offset))     * config.gyro_sensitivity / 1000 - (bias?.biasX ?? 0)
            let roll  = Double(data.int16BE(at: offset + 2)) * config.gyro_sensitivity / 1000 - (bias?.biasY ?? 0)
            let yaw   = Double(data.int16BE(at: offset + 4)) * config.gyro_sensitivity / 1000 - (bias?.biasZ ?? 0)
            samples.append((pitch, roll, yaw))
        }
        deviceVM.insertGYRO(deviceId: deviceId, timestamp: timestamp, samples: samples)
    }

    private func collectCalibACC(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var buf = calibAccBuffers[id] ?? []
        for i in 0..<20 {
            let o = 3 + i * 6
            buf.append((
                Double(data.int16BE(at: o))     * config.acc_sensitivity,
                Double(data.int16BE(at: o + 2)) * config.acc_sensitivity,
                Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            ))
        }
        calibAccBuffers[id] = buf
    }

    private func collectCalibGYRO(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var buf = calibGyroBuffers[id] ?? []
        for i in 0..<20 {
            let o = 3 + i * 6
            buf.append((
                Double(data.int16BE(at: o))     * config.gyro_sensitivity / 1000,
                Double(data.int16BE(at: o + 2)) * config.gyro_sensitivity / 1000,
                Double(data.int16BE(at: o + 4)) * config.gyro_sensitivity / 1000
            ))
        }
        calibGyroBuffers[id] = buf
    }

    private func collectBaselineACC(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var buf = baselineAccBuffers[id] ?? []
        for i in 0..<20 {
            let o = 3 + i * 6
            buf.append((
                timestamp: ts,
                x: Double(data.int16BE(at: o))     * config.acc_sensitivity,
                y: Double(data.int16BE(at: o + 2)) * config.acc_sensitivity,
                z: Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            ))
        }
        baselineAccBuffers[id] = buf
    }

    private func parseEXG(_ data: Data, deviceId: Int64, timestamp: Int64) {
        guard !data.isEmpty else { return }
        let flag = data[0]

        guard flag == 0xE0 || flag == 0xE1 else { return }
        guard data.count >= 131 else { return }

        let channel = flag == 0xE0 ? 0 : 1
        var values: [Int] = []
        for i in 0..<64 {
            values.append(Int(data.int16BE(at: 3 + i * 2)))
        }
        deviceVM.insertEXGBatch(deviceId: deviceId, timestamp: timestamp, channel: channel, values: values)
    }
}

// MARK: - Data Helper

private extension Data {
    func int16BE(at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(self[offset]) << 8 | UInt16(self[offset + 1]))
    }
}

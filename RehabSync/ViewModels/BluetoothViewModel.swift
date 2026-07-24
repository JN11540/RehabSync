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

    /// 目前這局遊戲的 treatment_result id，由呼叫端（如 2_Working.swift）在建立 treatment_result 那一刻設定，
    /// 之後 acc/gyro/exg 每一筆寫入都會帶上這個值，藉此對應回是哪一局遊戲、哪一次訓練的資料。
    var currentTreatmentResultId: Int64? = nil

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
    // 共用的加速度計收集機制 — internal (bleQueue)，收集期間不寫入資料庫
    @ObservationIgnored private var accOnlyCollecting: Set<UUID> = []
    @ObservationIgnored private var accOnlyBuffers: [UUID: [(timestamp: Int64, x: Double, y: Double, z: Double)]] = [:]

    // Live Estimated Real Angle（即時預估真實角度，固定 5Hz 更新）— UI state (main thread)
    var isLiveEstimating = false
    var currentEstimatedRealAngle: Double? = nil
    // internal (bleQueue)：只記住「最新一筆」傾角，實際計算交給 liveTickTimer 每 0.2 秒統一處理
    @ObservationIgnored private var liveEstimating: Set<UUID> = []
    @ObservationIgnored private var liveThighId: UUID?
    @ObservationIgnored private var liveCalfId: UUID?
    @ObservationIgnored private var liveThighIncline: Double?
    @ObservationIgnored private var liveCalfIncline: Double?
    @ObservationIgnored private var liveBaselineTable: [(measured: Double, realAngle: Double)] = []
    @ObservationIgnored private var liveShift: Double = 0
    @ObservationIgnored private var liveTickTimer: Timer?

    // Step Status Estimation（登階狀態即時判斷，固定 5Hz 更新）— UI state (main thread)
    var isEstimatingStepStatus = false
    var currentStepStatus: Int? = nil
    // internal (bleQueue)：只記住「最新一筆」傾角，實際判斷交給 stepTickTimer 每 0.2 秒統一處理
    @ObservationIgnored private var stepEstimating: Set<UUID> = []
    @ObservationIgnored private var stepThighId: UUID?
    @ObservationIgnored private var stepCalfId: UUID?
    @ObservationIgnored private var stepThighIncline: Double?
    @ObservationIgnored private var stepCalfIncline: Double?
    @ObservationIgnored private var stepBaseline: Double = 0
    @ObservationIgnored private var stepTickTimer: Timer?

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

    // MARK: - Accelerometer-only Collection（校正／預估真實角度共用）

    /// 讓大腿、小腿加速度計錄製固定秒數，收集期間不寫入資料庫，結束後把兩側緩衝區資料丟給 completion 處理。
    /// 若呼叫當下已經在 `isRecording`（一般資料收集），則不重複寫入指令、結束後也不關閉 ACC notify，避免打斷正在進行的收集。
    private func beginAccOnlyCollection(
        thighPeripheral: CBPeripheral,
        calfPeripheral: CBPeripheral,
        durationSec: Double,
        completion: @escaping (_ thighSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
                                _ calfSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)]) -> Void
    ) {
        bleQueue.async { [weak self] in
            guard let self, let config = bluetoothConfig else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }

            accOnlyBuffers[thighPeripheral.identifier] = []
            accOnlyBuffers[calfPeripheral.identifier]  = []
            accOnlyCollecting = [thighPeripheral.identifier, calfPeripheral.identifier]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + durationSec) { [weak self] in
                self?.bleQueue.async {
                    self?.finishAccOnlyCollection(
                        thighPeripheral: thighPeripheral,
                        calfPeripheral: calfPeripheral,
                        wasRecording: wasRecording,
                        completion: completion
                    )
                }
            }
        }
    }

    private func finishAccOnlyCollection(
        thighPeripheral: CBPeripheral,
        calfPeripheral: CBPeripheral,
        wasRecording: Bool,
        completion: (_ thighSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
                     _ calfSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)]) -> Void
    ) {
        accOnlyCollecting = []

        let thighSamples = accOnlyBuffers.removeValue(forKey: thighPeripheral.identifier) ?? []
        let calfSamples  = accOnlyBuffers.removeValue(forKey: calfPeripheral.identifier)  ?? []

        if !wasRecording, let config = bluetoothConfig {
            for peripheral in [thighPeripheral, calfPeripheral] {
                if let map = charMap[peripheral.identifier],
                   let c = map[CBUUID(string: config.sub_acc_uuid)] {
                    peripheral.setNotifyValue(false, for: c)
                }
            }
        }

        completion(thighSamples, calfSamples)
    }

    // MARK: - Baseline Calibration（膝角基準值）

    /// 錄製大腿與小腿加速度計 5 秒，收集期間不寫入資料庫，結束後計算膝角基準值。
    func startBaselineCalibration(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.baselineResult = nil
            self.isCollectingBaseline = true
        }
        beginAccOnlyCollection(thighPeripheral: thighPeripheral, calfPeripheral: calfPeripheral, durationSec: 5) { [weak self] thighSamples, calfSamples in
            let result = Self.computeBaselineAngle(thighSamples: thighSamples, calfSamples: calfSamples)
            DispatchQueue.main.async {
                self?.baselineResult = result
                self?.isCollectingBaseline = false
            }
        }
    }

    /// 移植自 baseline_check.py（check_whole_range_stable）+ calibration_phase.py（inclination_deg / compute_knee_angle）：
    /// 用加速度算大腿、小腿相對重力的傾角，膝角 = 大腿傾角 - 小腿傾角；整段錄製視為單一區間，
    /// 標準差（樣本標準差）<= 1.5° 且時長 >= 1 秒才算穩定，穩定則回傳角度平均值（保留正負號，四捨五入到小數1位），否則回傳 nil。
    static func computeBaselineAngle(
        thighSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        calfSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        stdThresholdDeg: Double = 1.5,
        minDurationSec: Double = 1.0
    ) -> Double? {
        guard !thighSamples.isEmpty, !calfSamples.isEmpty else { return nil }

        let thighIncline = smoothedIncline(thighSamples)
        let calfIncline  = smoothedIncline(calfSamples)
        let count = min(thighIncline.count, calfIncline.count)
        guard count >= 2 else { return nil }

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

        guard std <= stdThresholdDeg, duration >= minDurationSec else { return nil }

        return (mean * 10).rounded() / 10
    }

    /// 對應 inclination_deg：以重力向量計算肢段相對垂直線的傾角（度）
    private static func inclinationDeg(_ x: Double, _ y: Double, _ z: Double) -> Double {
        atan2(x, (y * y + z * z).squareRoot()) * 180 / .pi
    }

    /// 依 timestamp 分組平均，濾掉同一個 timestamp 底下多筆瞬間取樣的高頻雜訊（對應 load_and_smooth 的分組平均）
    private static func smoothedIncline(
        _ samples: [(timestamp: Int64, x: Double, y: Double, z: Double)]
    ) -> [(t: Int64, incline: Double)] {
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

    /// 對應 build_baseline_mapping_table：以 baseline 為起點建立 (量測角度 -> 預估真實角度) 對應表，依量測角度排序。
    /// 呼叫端必須確保傳進來的 `baseline` 已經是非負值（例如原本是負的就先平移過），這裡不再對 baseline + step 取絕對值，
    /// 避免 baseline 到 baseline+maxStep 之間跨過 0 時，同一個量測值對應到兩個不同 step 的歧義。
    /// 坐姿版：量測角度越大，預估真實角度越小（step=0 對應 90 度，step=maxStep 對應 0 度）。
    private static func baselineMappingTable(
        baseline: Double, maxStep: Int, maxRealAngleDeg: Double
    ) -> [(measured: Double, realAngle: Double)] {
        (0...maxStep).map { step in
            let measured = baseline + Double(step)
            let realAngle = maxRealAngleDeg - Double(step) * (maxRealAngleDeg / Double(maxStep))
            return (measured, realAngle)
        }.sorted { $0.measured < $1.measured }
    }

    /// 對應 realtime_angle_mapping.py 的 build_realtime_mapping_table（站姿版）：跟坐姿版方向相反，
    /// 量測角度越大，預估真實角度越大（step=0 對應 0 度，step=maxStep 對應 90 度）。
    /// 呼叫端一樣要先確保傳進來的 `baseline` 是非負值（原本是負的就先平移過），理由同坐姿版。
    ///
    /// Python 版對負 baseline 的處理是把對應表端點固定在 10／10+span_deg，再把「量測到的膝角」
    /// 平移 |baseline|+10 去查表；這裡改用跟坐姿版一致的手法（呼叫端先把 baseline 本身平移成
    /// 非負值），兩者數學上等價，但不需要另外硬編碼 10 這個端點常數，也跟坐姿版共用同一套機制。
    private static func standingMappingTable(
        baseline: Double, maxStep: Int, maxRealAngleDeg: Double
    ) -> [(measured: Double, realAngle: Double)] {
        (0...maxStep).map { step in
            let measured = baseline + Double(step)
            let realAngle = Double(step) * (maxRealAngleDeg / Double(maxStep))
            return (measured, realAngle)
        }.sorted { $0.measured < $1.measured }
    }

    /// 對應 angle_to_real：線性內插，超出對應表範圍時常數外插（跟 np.interp 行為一致）
    private static func angleToReal(_ measuredDeg: Double, table: [(measured: Double, realAngle: Double)]) -> Double {
        linearInterp(measuredDeg, xs: table.map(\.measured), ys: table.map(\.realAngle))
    }

    /// 對應 np.interp：對已依 x 遞增排序的 (xs, ys) 做線性內插，x 超出範圍時取頭尾常數值
    private static func linearInterp(_ x: Double, xs: [Double], ys: [Double]) -> Double {
        guard let firstX = xs.first, let lastX = xs.last else { return 0 }
        if x <= firstX { return ys.first! }
        if x >= lastX { return ys.last! }
        for i in 0..<(xs.count - 1) {
            if x >= xs[i] && x <= xs[i + 1] {
                guard xs[i + 1] > xs[i] else { return ys[i] }
                let ratio = (x - xs[i]) / (xs[i + 1] - xs[i])
                return ys[i] + ratio * (ys[i + 1] - ys[i])
            }
        }
        return ys.last!
    }

    // MARK: - Live Estimated Real Angle（即時預估真實角度）

    /// 坐姿版量測角度越大、預估真實角度越小；站姿版（對應 realtime_angle_mapping.py）方向相反，
    /// 量測角度越大、預估真實角度也越大，且對應的角度範圍（span）也不同（55° 而非 70°）。
    enum KneePosture {
        case sitting
        case standing
    }

    /// 開始持續錄製大腿與小腿加速度計，收集期間不寫入資料庫。跟批次版「預估真實角度」不同，
    /// 這裡不是錄固定秒數後一次計算，而是持續追蹤兩側「最新一筆」傾角，
    /// 由 `liveTickTimer` 每 0.2 秒（5Hz）讀一次最新值換算成預估真實角度並更新到畫面。
    func startLiveEstimateRealAngle(
        thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral, baseline: Double,
        posture: KneePosture = .sitting
    ) {
        // 坐姿/站立即時預估目前只針對左大腿（side 0, limb 0）+ 左小腿（side 0, limb 1）設計，
        // 配對狀態不是這個組合時不允許啟動。
        let deviceVM = DeviceViewModel()
        guard deviceVM.fetch(side: 0, limb: 0) != nil, deviceVM.fetch(side: 0, limb: 1) != nil else { return }

        let thighId = thighPeripheral.identifier
        let calfId  = calfPeripheral.identifier

        DispatchQueue.main.async {
            self.currentEstimatedRealAngle = nil
            self.isLiveEstimating = true
            self.liveTickTimer?.invalidate()
            self.liveTickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.tickLiveEstimatedRealAngle()
            }
        }

        bleQueue.async { [weak self] in
            guard let self, let config = bluetoothConfig else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }

            liveThighId = thighId
            liveCalfId  = calfId
            liveThighIncline = nil
            liveCalfIncline  = nil
            // baseline 若為負值，整體平移到正值，量測到的膝角也要平移同樣的量，
            // 兩邊平移量一致，相對關係不變，藉此避免 baseline ~ baseline+maxStep 跨過 0 的歧義。
            switch posture {
            case .sitting:
                liveShift = baseline < 0 ? (abs(baseline) + 15) : 0
                liveBaselineTable = Self.baselineMappingTable(baseline: baseline + liveShift, maxStep: 70, maxRealAngleDeg: 90)
            case .standing:
                liveShift = baseline < 0 ? (abs(baseline) + 10) : 0
                liveBaselineTable = Self.standingMappingTable(baseline: baseline + liveShift, maxStep: 55, maxRealAngleDeg: 90)
            }
            liveEstimating = [thighId, calfId]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }
        }
    }

    /// 停止即時預估：關掉 Timer，並在沒有其他一般收集正在進行時把 ACC notify 關掉。
    func stopLiveEstimateRealAngle(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.liveTickTimer?.invalidate()
            self.liveTickTimer = nil
            self.isLiveEstimating = false
        }
        bleQueue.async { [weak self] in
            guard let self else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }
            liveEstimating = []
            if !wasRecording, let config = bluetoothConfig {
                for peripheral in [thighPeripheral, calfPeripheral] {
                    if let map = charMap[peripheral.identifier],
                       let c = map[CBUUID(string: config.sub_acc_uuid)] {
                        peripheral.setNotifyValue(false, for: c)
                    }
                }
            }
        }
    }

    /// Timer callback（main thread 觸發），跳回 bleQueue 讀最新值計算，算完再寫回主執行緒的 UI 屬性。
    private func tickLiveEstimatedRealAngle() {
        bleQueue.async { [weak self] in
            guard let self,
                  let thigh = liveThighIncline,
                  let calf  = liveCalfIncline else { return }
            let kneeAngle = thigh - calf
            let realAngle = Self.angleToReal(kneeAngle + liveShift, table: liveBaselineTable)
            let rounded = (realAngle * 10).rounded() / 10
            DispatchQueue.main.async { self.currentEstimatedRealAngle = rounded }

            // 組間休息（未在記錄中）時暫停寫入，跟 acc/gyro/exg 的起訖規則一致。
            let (recording, treatmentResultId) = DispatchQueue.main.sync {
                (self.isRecording, self.currentTreatmentResultId)
            }
            guard recording else { return }
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            self.deviceVM.insertAdvancedStatistics(timestamp: ts, angle: rounded, treatmentResultId: treatmentResultId)
        }
    }

    /// 只把這一包 20 筆瞬間取樣平均成一個傾角並覆蓋成「最新值」，不計算角度、不發布到畫面。
    private func handleLiveAccPacket(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var sumIncline = 0.0
        for i in 0..<20 {
            let o = 3 + i * 6
            let x = Double(data.int16BE(at: o))     * config.acc_sensitivity
            let y = Double(data.int16BE(at: o + 2)) * config.acc_sensitivity
            let z = Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            sumIncline += Self.inclinationDeg(x, y, z)
        }
        let incline = sumIncline / 20.0

        if id == liveThighId { liveThighIncline = incline }
        if id == liveCalfId  { liveCalfIncline  = incline }
    }

    // MARK: - Step Detection（登階運動）

    /// 登階運動狀態機：0=站立（預設）、1=上階、2=下階。
    /// 觸發後改為純時間驅動，不再依賴下階當下的感測角度：
    /// - 預設狀態（站立）：y >= x+40 觸發上階，記錄上階結束時間 = now + 3 秒。
    /// - 上階期間（未滿 3 秒）：固定回傳 1。
    /// - 上階滿 3 秒：轉入下階，記錄下階結束時間 = now + 3 秒，回傳 2。
    /// - 下階期間（未滿 3 秒）：固定回傳 2。
    /// - 下階滿 3 秒：整個週期結束，重置狀態機，回到預設站立（0），等待下一次 y >= x+40 觸發。
    @ObservationIgnored private var stepUpUntil: Date?
    @ObservationIgnored private var stepDownUntil: Date?

    func detectStepStatus(kneeAngle y: Double, baseline x: Double) -> Int {
        if let downUntil = stepDownUntil {
            if Date() < downUntil { return 2 }
            stepUpUntil = nil
            stepDownUntil = nil
            return 0
        }

        if let upUntil = stepUpUntil {
            if Date() < upUntil { return 1 }
            stepDownUntil = Date().addingTimeInterval(3)
            return 2
        }

        guard y >= x + 40 else { return 0 }
        stepUpUntil = Date().addingTimeInterval(3)
        return 1
    }

    /// 重置登階狀態機（例如重新開始一輪錄製時呼叫）
    func resetStepStatus() {
        stepUpUntil = nil
        stepDownUntil = nil
    }

    /// 開始持續錄製大腿與小腿加速度計，收集期間不寫入資料庫。跟「即時預估真實角度」相同的收集機制，
    /// 差別是這裡把最新的膝角度（大腿傾角 - 小腿傾角）丟給 `detectStepStatus` 判斷登階狀態，
    /// 由 `stepTickTimer` 每 0.2 秒（5Hz）讀一次最新值並更新到畫面。
    func startStepStatusEstimation(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral, baseline: Double) {
        // 登階狀態預估目前只針對左大腿（side 0, limb 0）+ 左小腿（side 0, limb 1）設計，
        // 配對狀態不是這個組合時不允許啟動。
        let deviceVM = DeviceViewModel()
        guard deviceVM.fetch(side: 0, limb: 0) != nil, deviceVM.fetch(side: 0, limb: 1) != nil else { return }

        let thighId = thighPeripheral.identifier
        let calfId  = calfPeripheral.identifier

        DispatchQueue.main.async {
            self.currentStepStatus = nil
            self.isEstimatingStepStatus = true
            self.stepTickTimer?.invalidate()
            self.stepTickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.tickStepStatus()
            }
        }

        bleQueue.async { [weak self] in
            guard let self, let config = bluetoothConfig else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }

            stepThighId = thighId
            stepCalfId  = calfId
            stepThighIncline = nil
            stepCalfIncline  = nil
            stepBaseline = baseline
            resetStepStatus()
            stepEstimating = [thighId, calfId]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }
        }
    }

    /// 停止登階狀態預估：關掉 Timer、重置狀態機，並在沒有其他一般收集正在進行時把 ACC notify 關掉。
    func stopStepStatusEstimation(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.stepTickTimer?.invalidate()
            self.stepTickTimer = nil
            self.isEstimatingStepStatus = false
            self.currentStepStatus = nil
        }
        bleQueue.async { [weak self] in
            guard let self else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }
            stepEstimating = []
            resetStepStatus()
            if !wasRecording, let config = bluetoothConfig {
                for peripheral in [thighPeripheral, calfPeripheral] {
                    if let map = charMap[peripheral.identifier],
                       let c = map[CBUUID(string: config.sub_acc_uuid)] {
                        peripheral.setNotifyValue(false, for: c)
                    }
                }
            }
        }
    }

    /// Timer callback（main thread 觸發），跳回 bleQueue 讀最新值判斷，算完再寫回主執行緒的 UI 屬性。
    private func tickStepStatus() {
        bleQueue.async { [weak self] in
            guard let self,
                  let thigh = stepThighIncline,
                  let calf  = stepCalfIncline else { return }
            let kneeAngle = thigh - calf
            let status = detectStepStatus(kneeAngle: kneeAngle, baseline: stepBaseline)
            DispatchQueue.main.async { self.currentStepStatus = status }

            // 組間休息（未在記錄中）時暫停寫入，跟 acc/gyro/exg 的起訖規則一致。
            let (recording, treatmentResultId) = DispatchQueue.main.sync {
                (self.isRecording, self.currentTreatmentResultId)
            }
            guard recording else { return }
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            self.deviceVM.insertAdvancedStatistics(timestamp: ts, angle: kneeAngle, treatmentResultId: treatmentResultId)
        }
    }

    /// 只把這一包 20 筆瞬間取樣平均成一個傾角並覆蓋成「最新值」，不計算狀態、不發布到畫面。
    private func handleStepAccPacket(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        var sumIncline = 0.0
        for i in 0..<20 {
            let o = 3 + i * 6
            let x = Double(data.int16BE(at: o))     * config.acc_sensitivity
            let y = Double(data.int16BE(at: o + 2)) * config.acc_sensitivity
            let z = Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            sumIncline += Self.inclinationDeg(x, y, z)
        }
        let incline = sumIncline / 20.0

        if id == stepThighId { stepThighIncline = incline }
        if id == stepCalfId  { stepCalfIncline  = incline }
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
    }

    /// 開始新一局遊戲前的準備：花 3 秒判斷資料表是否需要清理，完成後呼叫 `completion()`。
    /// 需要清理則等清理真正處理完成才呼叫 `completion`；不需要清理則 3 秒後直接呼叫。
    /// 取代原本掛在 `stopRecordingAll()` 裡的清理時機，避免清理跟這局遊戲剛結束的資料寫入／匯出查詢搶同一個佇列
    /// （見 database-update-plan.md「5. 資料清理機制（cleanupIfNeeded）觸發時機調整」）。
    func prepareForNewGame(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { completion(); return }
            self.deviceVM.cleanupIfNeeded(
                onStart:  { self.isCleaningUp = true },
                onFinish: {
                    self.isCleaningUp = false
                    completion()
                }
            )
        }
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
        guard let name, name.hasPrefix("ZE1") else { return }

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

        // 校正／預估真實角度共用：收集到 buffer，不寫 DB
        if accOnlyCollecting.contains(peripheral.identifier) {
            if uuid == CBUUID(string: config.sub_acc_uuid) {
                collectAccOnly(data, id: peripheral.identifier, config: config)
            }
            return
        }

        // 即時預估真實角度：更新最新值供 UI 顯示；不 return，讓封包繼續往下走
        // 正常的 acc/gyro/exg 寫入資料庫流程，兩者同時進行。
        if liveEstimating.contains(peripheral.identifier) {
            if uuid == CBUUID(string: config.sub_acc_uuid) {
                handleLiveAccPacket(data, id: peripheral.identifier, config: config)
            }
        }

        // 即時預估登階狀態：更新最新值供畫面顯示；不 return，讓封包繼續往下走
        // 正常的 acc/gyro/exg 寫入資料庫流程，兩者同時進行（比照即時預估真實角度的做法）。
        if stepEstimating.contains(peripheral.identifier) {
            if uuid == CBUUID(string: config.sub_acc_uuid) {
                handleStepAccPacket(data, id: peripheral.identifier, config: config)
            }
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
        let treatmentResultId = DispatchQueue.main.sync { self.currentTreatmentResultId }
        deviceVM.insertACC(deviceId: deviceId, timestamp: timestamp, treatmentResultId: treatmentResultId, samples: samples)
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
        let treatmentResultId = DispatchQueue.main.sync { self.currentTreatmentResultId }
        deviceVM.insertGYRO(deviceId: deviceId, timestamp: timestamp, treatmentResultId: treatmentResultId, samples: samples)
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

    private func collectAccOnly(_ data: Data, id: UUID, config: Bluetooth) {
        guard data.count >= 123 else { return }
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var buf = accOnlyBuffers[id] ?? []
        for i in 0..<20 {
            let o = 3 + i * 6
            buf.append((
                timestamp: ts,
                x: Double(data.int16BE(at: o))     * config.acc_sensitivity,
                y: Double(data.int16BE(at: o + 2)) * config.acc_sensitivity,
                z: Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            ))
        }
        accOnlyBuffers[id] = buf
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
        let treatmentResultId = DispatchQueue.main.sync { self.currentTreatmentResultId }
        deviceVM.insertEXGBatch(deviceId: deviceId, timestamp: timestamp, treatmentResultId: treatmentResultId, channel: channel, values: values)
    }
}

// MARK: - Data Helper

private extension Data {
    func int16BE(at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(self[offset]) << 8 | UInt16(self[offset + 1]))
    }
}

// MARK: - GameDataMerger（database-update-plan.md「大腿／小腿合併策略（acc／gyro／exg）」）

/// 匯出功能專用：把大腿／小腿（或 exg 的 4 條序列）依「按組分段的索引位置對位」規則合併，
/// 對應 database-update-plan.md「大腿／小腿合併策略（acc／gyro／exg）」的規劃。
enum GameDataMerger {

    /// 對多條序列做「按組分段」的索引位置對位：先用 `treatment_result` 的 `set_start_time`／`set_end_time`
    /// 把每條序列切成一組一組的區段，每組各自獨立呼叫 `alignByIndex` 對位，再把各組結果依序串接起來。
    /// `set_start_time`／`set_end_time` 皆為 0（該組從未開始）的組別直接跳過。
    static func mergeByIndexPerSet<T>(
        sequences: [[T]],
        setStartTimes: [Int],
        setEndTimes: [Int],
        timestamp: (T) -> Int64
    ) -> [[T]] {
        var merged: [[T]] = Array(repeating: [], count: sequences.count)

        for i in setStartTimes.indices {
            guard setEndTimes.indices.contains(i) else { continue }
            let start = setStartTimes[i]
            let end = setEndTimes[i]
            guard start > 0, end > 0 else { continue }

            let segments = sequences.map { seq in
                seq.filter { let t = timestamp($0); return t >= Int64(start) && t <= Int64(end) }
            }
            let aligned = alignByIndex(segments, timestamp: timestamp)
            for idx in aligned.indices {
                merged[idx].append(contentsOf: aligned[idx])
            }
        }

        return merged
    }

    /// 單一區段內的索引位置對位：取各序列 timestamp 的共同重疊區間、過濾範圍外的資料，
    /// 再取各序列較短的長度裁切，回傳等長、可依索引直接逐筆對位的序列陣列。
    /// 任一序列是空的（或重疊區間不存在）就回傳全部皆為空陣列。
    static func alignByIndex<T>(_ sequences: [[T]], timestamp: (T) -> Int64) -> [[T]] {
        guard !sequences.isEmpty, sequences.allSatisfy({ !$0.isEmpty }) else {
            return sequences.map { _ in [] }
        }

        let windowStart = sequences.map { timestamp($0.first!) }.max()!
        let windowEnd = sequences.map { timestamp($0.last!) }.min()!
        guard windowStart <= windowEnd else {
            return sequences.map { _ in [] }
        }

        let filtered = sequences.map { seq in
            seq.filter { let t = timestamp($0); return t >= windowStart && t <= windowEnd }
        }

        let count = filtered.map(\.count).min()!
        guard count > 0 else {
            return sequences.map { _ in [] }
        }

        return filtered.map { Array($0.prefix(count)) }
    }
}

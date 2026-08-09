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

struct EXGSample: Identifiable {
    let id = UUID()
    let timestamp: Int64   // 合成時間戳（毫秒），依 sampleRate 從封包到達時間往回推算
    let value: Int
}

struct EXGChannelStatus {
    var recentSamples: [EXGSample] = []   // 依時間先後排序，只保留過去 10 秒
    var droppedPacketCount: Int = 0
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

    // EXG 封包遺失排查用（#if DEBUG）：記錄每個 device+channel 上一次收到的 Serial No／時間，
    // 藉此分辨「裝置端真的沒送那麼快」還是「app 這邊漏收了封包」。
    @ObservationIgnored private var exgPacketTracker: [String: (serial: UInt8, timestamp: Int64)] = [:]

    // 即時 EXG 4 通道監控（Release 也要能用，跟上面 debug-only 的 exgPacketTracker 各自獨立）— UI state (main thread)
    // key 格式："\(deviceId)-\(channel)"，channel 0/1 對應 flag 0xE0/0xE1。
    var exgChannelStatus: [String: EXGChannelStatus] = [:]
    // internal (bleQueue)：只記最新一筆 Serial No，用來算掉包數，不需要被畫面觀察。
    @ObservationIgnored private var exgSerialTracker: [String: UInt8] = [:]

    // Live Estimated Real Angle（即時預估真實角度，固定 5Hz 更新）— UI state (main thread)
    var isLiveEstimating = false
    var currentEstimatedRealAngle: Double? = nil
    // internal (bleQueue)：只記住「最新一筆」傾角，實際計算交給 liveTickTimer 每 0.2 秒統一處理
    @ObservationIgnored private var liveEstimating: Set<UUID> = []
    @ObservationIgnored private var liveThighId: UUID?
    @ObservationIgnored private var liveCalfId: UUID?
    @ObservationIgnored private var liveThighIncline: Double?
    @ObservationIgnored private var liveCalfIncline: Double?
    // 校正失敗排查用（#if DEBUG）：記錄大腿／小腿各自「最後一次收到 ACC 封包」的時間，
    // 用來分辨「畫面角度卡住不動」是封包真的停了、還是換算結果本來就沒變。
    @ObservationIgnored private var liveThighLastPacketAt: Int64?
    @ObservationIgnored private var liveCalfLastPacketAt: Int64?
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
    /// 供 `advanced_statistics` 記錄用：跟「站立即時預估真實角度」同一套換算（`standingMappingTable`／`angleToReal`），
    /// 跟 `detectStepStatus` 拿 `stepBaseline` 直接比較的登階狀態機邏輯完全獨立，不影響既有的登階判定。
    @ObservationIgnored private var stepShift: Double = 0
    @ObservationIgnored private var stepBaselineTable: [(measured: Double, realAngle: Double)] = []
    @ObservationIgnored private var stepTickTimer: Timer?

    // MARK: - Working2 連線檢查／封包新鮮度檢查／共用修復路徑（working2-database-port-plan.md 第 17 節）
    // 只在 isRecording 為 true 時運作。lastPacketAt 是唯一事實來源：ACC／GYRO／EXG_CH0／EXG_CH1
    // 4 個訊號各自獨立記錄最後收到封包的時間，freshnessTimer（1 秒一次）跟 recoverIfNeeded（觸發
    // BLE 層級修復）都讀同一份；tickLiveEstimatedRealAngle 的即時清空（0.2 秒）也讀同一份 ACC 部分。
    private static let signalACC = "ACC"
    private static let signalGYRO = "GYRO"
    private static let signalEXGCh0 = "EXG_CH0"
    private static let signalEXGCh1 = "EXG_CH1"
    @ObservationIgnored private var lastPacketAt: [UUID: [String: Int64]] = [:]
    @ObservationIgnored private var lastRecoveryAttemptAt: [UUID: Int64] = [:]
    @ObservationIgnored private var freshnessTimer: Timer?
    /// 跟 `isRecording` 不同：`didDisconnectPeripheral` 任何裝置斷線都會把 `isRecording` 直接設回
    /// false（見該處，刻意維持不動，繼續給既有的 `.onChange` guard／`advanced_statistics` 寫入守門用），
    /// 但 Working2 端還在同一組進行中、還是想繼續錄——這個旗標在 `startRecordingAll`／`stopRecordingAll`
    /// 函式最外層直接、無條件設定（不透過迴圈遍歷 `connectedPeripherals`，不受裝置當下有沒有連著影響），
    /// 代表「這個錄製 session 的意圖」，不會因為單次斷線被動翻掉，讓 1 秒偵測與重連後自動恢復錄製
    /// 這兩處能正確判斷（working2-database-port-plan.md 17.4）。
    @ObservationIgnored private var recordingSessionActive = false

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

        insertBluetoothFromJSON(db: db)
    }

    private func insertBluetoothFromJSON(db: DatabaseQueue) {
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
                        cmd_a2:           Data(dto.cmd_a2),
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

    /// 背景自動重連：不透過主動掃描（`startScan`／`discoveredDevices`），改用 CoreBluetooth
    /// 已經認得的裝置識別碼直接 `retrievePeripherals(withIdentifiers:)` 找回 `CBPeripheral`
    /// 並嘗試連線——即使裝置暫時不在範圍內、或還沒被系統快取過而找不到，這裡也只是靜靜失敗，
    /// 不拋錯，呼叫端（`Dashboard.checkBoundDevicesReachable()`）每 5 秒會再呼叫一次重試。
    /// 刻意不動用 `connectionState`／`pendingPeripheral`（那是給使用者手動在綁定視窗選裝置連線的
    /// UI 狀態），避免背景重連跟使用者當下手動操作的畫面狀態互相干擾。
    func attemptBackgroundReconnect(uuid: UUID) {
        bleQueue.async {
            #if DEBUG
            print("[RECONNECT-DIAG] attemptBackgroundReconnect 開始 uuid=\(uuid) central.state=\(self.central.state.rawValue)")
            #endif
            guard self.central.state == .poweredOn else {
                #if DEBUG
                print("[RECONNECT-DIAG] 中止：central.state 不是 poweredOn（實際值 \(self.central.state.rawValue)）")
                #endif
                return
            }
            guard self.connectedPeripherals[uuid] == nil else {
                #if DEBUG
                print("[RECONNECT-DIAG] 中止：connectedPeripherals 裡已經有這顆，不需要重連")
                #endif
                return
            }
            guard let peripheral = self.central.retrievePeripherals(withIdentifiers: [uuid]).first else {
                #if DEBUG
                print("[RECONNECT-DIAG] 中止：retrievePeripherals(withIdentifiers:) 找不到這個 uuid，CoreBluetooth 不認得這顆裝置")
                #endif
                return
            }
            #if DEBUG
            print("[RECONNECT-DIAG] retrievePeripherals 找到裝置，peripheral.state=\(peripheral.state.rawValue)（0=disconnected 1=connecting 2=connected 3=disconnecting）")
            #endif
            guard peripheral.state != .connecting, peripheral.state != .connected else {
                #if DEBUG
                print("[RECONNECT-DIAG] 中止：peripheral 已經在連線中或已連線")
                #endif
                return
            }
            // `retrievePeripherals(withIdentifiers:)` 現拿的 peripheral 沒有像掃描流程那樣
            // 先存進 peripheralMap，只是 closure 裡的區域變數；沿用掃描流程的做法先存一份強參照，
            // 避免連線請求送出後沒有東西撐著這個物件、悄悄失敗又永遠等不到 didConnect/didFailToConnect。
            self.peripheralMap[uuid] = peripheral
            #if DEBUG
            print("[RECONNECT-DIAG] 呼叫 central.connect(...)")
            #endif
            self.central.connect(peripheral, options: nil)
        }
    }

    // MARK: - Working2 連線檢查／封包新鮮度檢查（Channel A，working2-database-port-plan.md 17.3）

    /// 每次收到 ACC／GYRO／EXG 封包時記錄「最後收到時間」，`lastPacketAt` 是唯一事實來源，
    /// 給 1 秒偵測（連線檢查＋封包新鮮度檢查）跟 0.2 秒 tick 的即時清空共用讀取。
    private func recordPacketFresh(uuid: UUID, signal: String, at timestamp: Int64) {
        lastPacketAt[uuid, default: [:]][signal] = timestamp
    }

    /// 這顆裝置的 4 個訊號（ACC／GYRO／EXG_CH0／EXG_CH1）任一超過各自門檻就算 stale；
    /// 從未收過封包（nil）不算 stale，避免剛開始錄製、封包還沒送達的第一輪就誤觸發。
    private func isAnySignalStale(uuid: UUID) -> Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let signals = lastPacketAt[uuid] ?? [:]
        func age(_ key: String) -> Int64? { signals[key].map { now - $0 } }
        if let a = age(Self.signalACC),     a > 1000 { return true }
        if let a = age(Self.signalGYRO),    a > 1000 { return true }
        if let a = age(Self.signalEXGCh0),  a > 4500 { return true }
        if let a = age(Self.signalEXGCh1),  a > 4500 { return true }
        return false
    }

    /// Channel A：連線檢查（有順序性，優先於封包新鮮度檢查）＋封包新鮮度檢查，1 秒一次，
    /// 只在 isRecording 為 true 時運作（跟 startRecordingAll／stopRecordingAll 綁在一起啟停）。
    private func tickConnectionAndFreshnessCheck() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            guard self.recordingSessionActive else { return }

            let dvm = DeviceViewModel()
            let side = dvm.fetchAnySide() ?? 0
            guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
                  let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid)
            else { return }

            for uuid in [thighUUID, calfUUID] {
                guard let peripheral = self.peripheralMap[uuid] ?? self.connectedPeripherals[uuid],
                      peripheral.state == .connected else {
                    self.recoverIfNeeded(uuid: uuid)
                    continue
                }
                if self.isAnySignalStale(uuid: uuid) {
                    self.recoverIfNeeded(uuid: uuid)
                }
            }
        }
    }

    /// 共用修復路徑：連線缺失／封包新鮮度逾時都導向這裡，依 `peripheral.state` 分流。
    /// 冷卻 3 秒、per-uuid 各自獨立，避免同一裝置在修復生效前被重複觸發。
    private func recoverIfNeeded(uuid: UUID) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let last = lastRecoveryAttemptAt[uuid], now - last < 3000 { return }
        lastRecoveryAttemptAt[uuid] = now

        guard let peripheral = peripheralMap[uuid] ?? connectedPeripherals[uuid] else {
            attemptBackgroundReconnect(uuid: uuid)
            return
        }
        switch peripheral.state {
        case .connected:
            // 連線物件還在、資料 stale：重新走一次 startRecording，從簡對這顆裝置的
            // ACC／GYRO／EXG 全部重新訂閱，並補送 cmd_a0／cmd_a1／cmd_a2（見 17.4 節）。
            startRecording(peripheral: peripheral)
        case .connecting:
            break
        default:
            attemptBackgroundReconnect(uuid: uuid)
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
            peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
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
                peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
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
                    peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
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

    /// 錄製大腿與小腿加速度計固定秒數，收集期間不寫入資料庫，結束後用 ACCCalibration 計算膝角基準值。
    /// - Parameter durationSec: 收集秒數，預設 5(跟正式流程畫面的 5 秒倒數一致)。
    /// - Parameters:
    ///   - durationSec: 收集秒數，預設 5(跟正式流程畫面的 5 秒倒數一致)。
    ///   - completion: 選填，`baselineResult`／`isCollectingBaseline` 實際寫入完成的那一刻會呼叫（已經在 main thread），
    ///     帶入跟 `baselineResult` 同一個值。呼叫端應該用這個 completion 判斷校正成功/失敗，
    ///     不要另外用固定秒數的計時器去猜「應該已經算完了」——猜測秒數在系統忙碌時會不準，
    ///     導致 UI 判定失敗當下、後端其實已經算出結果的競爭情況。
    func startBaselineCalibration(
        thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral, durationSec: Double = 5,
        completion: ((Double?) -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            self.baselineResult = nil
            self.isCollectingBaseline = true
        }
        let side = DeviceViewModel().fetchAnySide() ?? 0
        beginAccOnlyCollection(thighPeripheral: thighPeripheral, calfPeripheral: calfPeripheral, durationSec: durationSec) { [weak self] thighSamples, calfSamples in
            let result = ACCCalibration.computeBaseline(thighSamples: thighSamples, calfSamples: calfSamples, side: side)
            DispatchQueue.main.async {
                self?.baselineResult = result
                self?.isCollectingBaseline = false
                completion?(result)
            }
        }
    }

    /// 對應 inclination_deg：以重力向量計算肢段相對垂直線的傾角（度）
    private static func inclinationDeg(_ x: Double, _ y: Double, _ z: Double) -> Double {
        atan2(x, (y * y + z * z).squareRoot()) * 180 / .pi
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

    /// 對應 realtime_angle_mapping_right_v2.py 的 build_mapping_table:右膝坐姿版,跟左膝坐姿版
    /// `baselineMappingTable` 的 realAngle-vs-step 公式相同,但右膝感測器安裝方向與左膝相反,
    /// `measured` 隨 step 遞減(而非遞增),導致 `measured` 跟 `realAngle` 的關係左右膝相反:
    /// 左膝是量測角度越大、真實角度越小;右膝反而是量測角度越大、真實角度也越大
    /// (step=0 對應 baseline,realAngle=90;step=maxStep 對應 baseline-maxStep,realAngle=0)。
    /// 呼叫端一樣要先把 `baseline` 換成 `baseline + liveShift` 再傳入,沿用 `baselineMappingTable` 的呼叫慣例。
    /// 回傳依 `measured` 由小到大排序 —— 右膝 step 遞增時 measured 遞減,不排序會違反 `linearInterp`
    /// 假設 xs 遞增的前提。
    private static func baselineMappingTableRight(
        baseline: Double, maxStep: Int, maxRealAngleDeg: Double
    ) -> [(measured: Double, realAngle: Double)] {
        (0...maxStep).map { step in
            let measured = baseline - Double(step)
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

    /// 對應 realtime_angle_mapping_right.py 的 build_mapping_table:右膝站姿版,跟左膝站姿版
    /// `standingMappingTable` 的 realAngle-vs-step 公式相同,但右膝感測器安裝方向與左膝相反,
    /// `measured` 隨 step 遞減(而非遞增),導致 `measured` 跟 `realAngle` 的關係左右膝相反:
    /// 左膝是量測角度越大、真實角度也越大;右膝反而是量測角度越大、真實角度越小
    /// (step=0 對應 baseline,realAngle=0;step=maxStep 對應 baseline-maxStep,realAngle=90)。
    /// 呼叫端一樣要先把 `baseline` 換成 `baseline + liveShift` 再傳入,沿用 `standingMappingTable` 的呼叫慣例。
    /// 回傳依 `measured` 由小到大排序 —— 右膝 step 遞增時 measured 遞減,不排序會違反 `linearInterp`
    /// 假設 xs 遞增的前提。
    private static func standingMappingTableRight(
        baseline: Double, maxStep: Int, maxRealAngleDeg: Double
    ) -> [(measured: Double, realAngle: Double)] {
        (0...maxStep).map { step in
            let measured = baseline - Double(step)
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
        // 坐姿/站立即時預估要求大腿＋小腿配對齊全才允許啟動；不寫死左腳（side 0），
        // 改用 fetchAnySide() 查「目前實際綁定的那一側」——這個 app 一次最多只會綁 2 顆裝置（同一側），
        // 綁在右腳時這裡也要能通過檢查，不然右腳永遠無法啟動即時預估。
        let deviceVM = DeviceViewModel()
        let side = deviceVM.fetchAnySide() ?? 0
        guard deviceVM.fetch(side: side, limb: 0) != nil, deviceVM.fetch(side: side, limb: 1) != nil else { return }

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
            liveThighLastPacketAt = nil
            liveCalfLastPacketAt = nil
            // baseline 若為負值，整體平移到正值，量測到的膝角也要平移同樣的量，
            // 兩邊平移量一致，相對關係不變，藉此避免 baseline ~ baseline+maxStep 跨過 0 的歧義。
            switch posture {
            case .sitting:
                if side == 1 {
                    liveShift = baseline > 0 ? -(baseline + 15) : 0
                    liveBaselineTable = Self.baselineMappingTableRight(baseline: baseline + liveShift, maxStep: 70, maxRealAngleDeg: 90)
                } else {
                    liveShift = baseline < 0 ? (abs(baseline) + 15) : 0
                    liveBaselineTable = Self.baselineMappingTable(baseline: baseline + liveShift, maxStep: 70, maxRealAngleDeg: 90)
                }
            case .standing:
                if side == 1 {
                    liveShift = baseline > 0 ? -(baseline + 10) : 0
                    liveBaselineTable = Self.standingMappingTableRight(baseline: baseline + liveShift, maxStep: 55, maxRealAngleDeg: 90)
                } else {
                    liveShift = baseline < 0 ? (abs(baseline) + 10) : 0
                    liveBaselineTable = Self.standingMappingTable(baseline: baseline + liveShift, maxStep: 55, maxRealAngleDeg: 90)
                }
            }
            liveEstimating = [thighId, calfId]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
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
            guard let self else { return }

            // Working2 封包新鮮度保護（working2-database-port-plan.md 17.4）：閘門用 `recordingSessionActive`，
            // 不是 `isRecording`——`isRecording` 會被 `didDisconnectPeripheral` 在裝置真的斷線當下直接設回
            // false（刻意維持不動，繼續給下面的 DB 寫入守門用），如果這裡也看 `isRecording`，裝置一斷線
            // 這段清空邏輯反而會被跳過，導致 incline 從未被清空、角度停在斷線前最後一個值，變不回「等待
            // 資料...」——這是實測時發現的真實 bug，改看 `recordingSessionActive`（只由 startRecordingAll／
            // stopRecordingAll 控制、不受斷線影響）才能讓斷線也正確觸發清空。組間休息／PreWorking 動作測試
            // （`recordingSessionActive` 恆為 false）不受影響、維持原本行為。只清「真的 stale 的那一側」
            // incline，currentEstimatedRealAngle 不分哪一側 stale 一律清成 nil，才能讓下面既有的
            // nil-guard／畫面/`.onChange` 正確反映「資料不可信」。
            if recordingSessionActive {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                var thighStale = false
                var calfStale = false
                if let thighId = liveThighId {
                    let age = lastPacketAt[thighId]?[Self.signalACC].map { now - $0 }
                    thighStale = age.map { $0 > 1000 } ?? false
                }
                if let calfId = liveCalfId {
                    let age = lastPacketAt[calfId]?[Self.signalACC].map { now - $0 }
                    calfStale = age.map { $0 > 1000 } ?? false
                }
                if thighStale { liveThighIncline = nil }
                if calfStale  { liveCalfIncline  = nil }
                if thighStale || calfStale {
                    DispatchQueue.main.async { self.currentEstimatedRealAngle = nil }
                    return
                }
            }

            #if DEBUG
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let thighAgeMs = liveThighLastPacketAt.map { now - $0 }
            let calfAgeMs = liveCalfLastPacketAt.map { now - $0 }
            print("[LIVE-ANGLE-DIAG] tick: thighIncline=\(liveThighIncline.map { String(format: "%.2f", $0) } ?? "nil")（\(thighAgeMs.map { "\($0)ms 前" } ?? "從未收過")）"
                  + " calfIncline=\(liveCalfIncline.map { String(format: "%.2f", $0) } ?? "nil")（\(calfAgeMs.map { "\($0)ms 前" } ?? "從未收過")）")
            if let thighAgeMs, thighAgeMs > 1000 {
                print("[LIVE-ANGLE-DIAG] ⚠️ 大腿已經超過 1 秒沒收到新封包，畫面角度會凍結不動")
            }
            if let calfAgeMs, calfAgeMs > 1000 {
                print("[LIVE-ANGLE-DIAG] ⚠️ 小腿已經超過 1 秒沒收到新封包，畫面角度會凍結不動")
            }
            #endif
            guard let thigh = liveThighIncline,
                  let calf  = liveCalfIncline else { return }
            let kneeAngle = thigh - calf
            let realAngle = Self.angleToReal(kneeAngle + liveShift, table: liveBaselineTable)
            let rounded = (realAngle * 10).rounded() / 10
            #if DEBUG
            print("[LIVE-ANGLE-DIAG] kneeAngle=\(String(format: "%.2f", kneeAngle)) realAngle=\(rounded)")
            #endif
            DispatchQueue.main.async { self.currentEstimatedRealAngle = rounded }

            // 組間休息（未在記錄中）時暫停寫入，跟 acc/gyro/exg 的起訖規則一致。
            let (stillRecording, treatmentResultId) = DispatchQueue.main.sync {
                (self.isRecording, self.currentTreatmentResultId)
            }
            guard stillRecording else { return }
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
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if id == liveThighId {
            liveThighIncline = incline
            liveThighLastPacketAt = now
            #if DEBUG
            print("[LIVE-ANGLE-DIAG] 收到大腿封包 incline=\(String(format: "%.2f", incline))")
            #endif
        }
        if id == liveCalfId {
            liveCalfIncline = incline
            liveCalfLastPacketAt = now
            #if DEBUG
            print("[LIVE-ANGLE-DIAG] 收到小腿封包 incline=\(String(format: "%.2f", incline))")
            #endif
        }
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
        // 登階狀態預估要求大腿＋小腿配對齊全才允許啟動；不寫死左腳（side 0），
        // 改用 fetchAnySide() 查「目前實際綁定的那一側」，右腳綁定時也要能通過檢查。
        let deviceVM = DeviceViewModel()
        let side = deviceVM.fetchAnySide() ?? 0
        guard deviceVM.fetch(side: side, limb: 0) != nil, deviceVM.fetch(side: side, limb: 1) != nil else { return }

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
            // advanced_statistics 記錄用的換算表，比照「站立即時預估」的站姿版做法（見 startLiveEstimateRealAngle 的 .standing 分支）。
            stepShift = baseline < 0 ? (abs(baseline) + 10) : 0
            stepBaselineTable = Self.standingMappingTable(baseline: baseline + stepShift, maxStep: 55, maxRealAngleDeg: 90)
            resetStepStatus()
            stepEstimating = [thighId, calfId]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
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
            guard let self else { return }

            // Working12 封包新鮮度保護（working12-database-port-plan.md 18.2）：閘門用 `recordingSessionActive`，
            // 不是 `isRecording`——理由同 `tickLiveEstimatedRealAngle()`（working2-database-port-plan.md 17.4）：
            // `isRecording` 會被 `didDisconnectPeripheral` 在裝置真的斷線當下直接設回 false，如果這裡也看
            // `isRecording`，裝置一斷線這段清空邏輯反而會被跳過。組間休息（`recordingSessionActive` 恆為
            // false）不評估、不清空，維持原本行為。只清「真的 stale 的那一側」incline，`currentStepStatus`
            // 不分哪一側 stale 一律清成 nil，並跳過該次 `insertAdvancedStatistics` 寫入。
            if recordingSessionActive {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                var thighStale = false
                var calfStale = false
                if let thighId = stepThighId {
                    let age = lastPacketAt[thighId]?[Self.signalACC].map { now - $0 }
                    thighStale = age.map { $0 > 1000 } ?? false
                }
                if let calfId = stepCalfId {
                    let age = lastPacketAt[calfId]?[Self.signalACC].map { now - $0 }
                    calfStale = age.map { $0 > 1000 } ?? false
                }
                if thighStale { stepThighIncline = nil }
                if calfStale  { stepCalfIncline  = nil }
                if thighStale || calfStale {
                    DispatchQueue.main.async { self.currentStepStatus = nil }
                    return
                }
            }

            #if DEBUG
            // 直接讀 lastPacketAt（跟上面新鮮度判斷同一份資料），不另外宣告 stepThighLastPacketAt／
            // stepCalfLastPacketAt 第二份狀態（working12-database-port-plan.md 18.2 已定案的簡化）。
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let thighAgeMs = stepThighId.flatMap { self.lastPacketAt[$0]?[Self.signalACC] }.map { now - $0 }
            let calfAgeMs = stepCalfId.flatMap { self.lastPacketAt[$0]?[Self.signalACC] }.map { now - $0 }
            print("[STEP-STATUS-DIAG] tick: thighIncline=\(stepThighIncline.map { String(format: "%.2f", $0) } ?? "nil")（\(thighAgeMs.map { "\($0)ms 前" } ?? "從未收過")）"
                  + " calfIncline=\(stepCalfIncline.map { String(format: "%.2f", $0) } ?? "nil")（\(calfAgeMs.map { "\($0)ms 前" } ?? "從未收過")）")
            if let thighAgeMs, thighAgeMs > 1000 {
                print("[STEP-STATUS-DIAG] ⚠️ 大腿已經超過 1 秒沒收到新封包，登階狀態會凍結不動")
            }
            if let calfAgeMs, calfAgeMs > 1000 {
                print("[STEP-STATUS-DIAG] ⚠️ 小腿已經超過 1 秒沒收到新封包，登階狀態會凍結不動")
            }
            #endif

            guard let thigh = stepThighIncline,
                  let calf  = stepCalfIncline else { return }
            let kneeAngle = thigh - calf
            let status = detectStepStatus(kneeAngle: kneeAngle, baseline: stepBaseline)
            DispatchQueue.main.async { self.currentStepStatus = status }

            // 寫進 advanced_statistics 的角度比照「站立即時預估真實角度」的換算方式（angleToReal + 站姿對應表），
            // 不是直接寫 detectStepStatus 用的原始 kneeAngle，兩者計算目的不同、互不影響。
            let realAngle = Self.angleToReal(kneeAngle + stepShift, table: stepBaselineTable)
            let rounded = (realAngle * 10).rounded() / 10

            // 組間休息（未在記錄中）時暫停寫入，跟 acc/gyro/exg 的起訖規則一致。
            let (stillRecording, treatmentResultId) = DispatchQueue.main.sync {
                (self.isRecording, self.currentTreatmentResultId)
            }
            guard stillRecording else { return }
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            self.deviceVM.insertAdvancedStatistics(timestamp: ts, angle: rounded, treatmentResultId: treatmentResultId)
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
        recordingSessionActive = true
        for peripheral in connectedPeripherals.values {
            startRecording(peripheral: peripheral)
        }
        freshnessTimer?.invalidate()
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickConnectionAndFreshnessCheck()
        }
    }

    func stopRecordingAll() {
        recordingEndTime = Int64(Date().timeIntervalSince1970 * 1000)
        recordingSessionActive = false
        for peripheral in connectedPeripherals.values {
            stopRecording(peripheral: peripheral)
        }
        freshnessTimer?.invalidate()
        freshnessTimer = nil

        // 即時 EXG 監控歸零，下次「開始收集」重新從 0 開始算（test-exg-realtime-monitor-plan.md 第 2 節第 4 點）。
        // exgSerialTracker 只在 bleQueue 上被 parseEXG 讀寫，清空也要丟回 bleQueue，避免跟主執行緒的呼叫方 data race；
        // exgChannelStatus 本來就只在主執行緒被更新，跟這裡的呼叫執行緒一致，直接清空即可。
        bleQueue.async { [weak self] in
            self?.exgSerialTracker.removeAll()
        }
        exgChannelStatus.removeAll()
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
        #if DEBUG
        print("[RECONNECT-DIAG] didConnect 成功 uuid=\(peripheral.identifier)")
        #endif
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
        #if DEBUG
        print("[RECONNECT-DIAG] didFailToConnect uuid=\(peripheral.identifier) error=\(error?.localizedDescription ?? "nil")")
        #endif
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

        // 重連後自動恢復錄製：`recordingSessionActive` 代表 Working2 這個 session 還想繼續錄
        // （不像 `isRecording`，斷線當下就會被 `didDisconnectPeripheral` 動翻掉），這裡拿到新的
        // charMap 就重新走一次 startRecording，補回 notify 訂閱與 cmd_a0/a1/a2 設定，
        // 不然連線物件恢復了、裝置實際上還是不會再送資料（working2-database-port-plan.md 17.4）。
        if recordingSessionActive {
            startRecording(peripheral: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let config = bluetoothConfig,
              let data = characteristic.value else { return }

        let uuid = characteristic.uuid

        // Working2 封包新鮮度追蹤（working2-database-port-plan.md 17.3）：不論目前是校正／收集／
        // 一般錄製哪種模式，只要真的收到封包就記一筆，4 個訊號各自獨立（EXG 依 Flag byte 拆 ch0/ch1）。
        let freshAt = Int64(Date().timeIntervalSince1970 * 1000)
        if uuid == CBUUID(string: config.sub_acc_uuid) {
            recordPacketFresh(uuid: peripheral.identifier, signal: Self.signalACC, at: freshAt)
        } else if uuid == CBUUID(string: config.sub_gyro_uuid) {
            recordPacketFresh(uuid: peripheral.identifier, signal: Self.signalGYRO, at: freshAt)
        } else if uuid == CBUUID(string: config.sub_exg_uuid), let flag = data.first, flag == 0xE0 || flag == 0xE1 {
            recordPacketFresh(uuid: peripheral.identifier, signal: flag == 0xE0 ? Self.signalEXGCh0 : Self.signalEXGCh1, at: freshAt)
        }

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

        #if DEBUG
        // RMS 短封包（0xE8）的 layout 跟 raw（0xE0/0xE1）不同：[Flag][Serial No][8 bytes RMS Data]，
        // Serial No 在 offset 1，不是 offset 2；兩種 channel 合併在同一包，所以用獨立的 tracker key。
        if flag == 0xE0 || flag == 0xE1, data.count >= 3 {
            logExgPacketTiming(deviceId: deviceId, trackerKey: "\(deviceId)-\(flag == 0xE0 ? 0 : 1)", serial: data[2], timestamp: timestamp, flag: flag)
        } else if flag == 0xE8, data.count >= 2 {
            logExgPacketTiming(deviceId: deviceId, trackerKey: "\(deviceId)-E8", serial: data[1], timestamp: timestamp, flag: flag)
        }
        #endif

        guard flag == 0xE0 || flag == 0xE1 else { return }
        guard data.count >= 131 else { return }

        let channel = flag == 0xE0 ? 0 : 1
        var values: [Int] = []
        for i in 0..<64 {
            values.append(Int(data.int16BE(at: 3 + i * 2)))
        }
        let treatmentResultId = DispatchQueue.main.sync { self.currentTreatmentResultId }
        deviceVM.insertEXGBatch(deviceId: deviceId, timestamp: timestamp, treatmentResultId: treatmentResultId, channel: channel, values: values)

        updateExgChannelStatus(deviceId: deviceId, channel: channel, serial: data[2], timestamp: timestamp, values: values)
    }

    /// 即時 EXG 4 通道監控：計算掉包數、把封包裡 64 筆樣本依 sampleRate 換算成合成時間戳，
    /// 更新畫面用的 exgChannelStatus，只保留過去 10 秒（test-exg-realtime-monitor-plan.md）。
    private func updateExgChannelStatus(deviceId: Int64, channel: Int, serial: UInt8, timestamp: Int64, values: [Int]) {
        let key = "\(deviceId)-\(channel)"

        var dropped = 0
        if let previousSerial = exgSerialTracker[key] {
            let rawDelta = Int(serial) - Int(previousSerial)
            let delta = rawDelta >= 0 ? rawDelta : rawDelta + 256
            dropped = max(0, delta - 1)
        }
        exgSerialTracker[key] = serial

        let sampleRate = 32.0
        let intervalMs = 1000.0 / sampleRate
        let newSamples: [EXGSample] = values.enumerated().map { i, value in
            let offsetFromEnd = Double(values.count - 1 - i) * intervalMs
            return EXGSample(timestamp: timestamp - Int64(offsetFromEnd), value: value)
        }

        DispatchQueue.main.async {
            var status = self.exgChannelStatus[key] ?? EXGChannelStatus()
            status.droppedPacketCount += dropped
            status.recentSamples.append(contentsOf: newSamples)
            let cutoff = timestamp - 10_000
            status.recentSamples.removeAll { $0.timestamp < cutoff }
            self.exgChannelStatus[key] = status
        }
    }

    #if DEBUG
    private func logExgPacketTiming(deviceId: Int64, trackerKey: String, serial: UInt8, timestamp: Int64, flag: UInt8) {
        if let previous = exgPacketTracker[trackerKey] {
            let deltaT = timestamp - previous.timestamp
            let rawSerialDelta = Int(serial) - Int(previous.serial)
            let deltaSerial = rawSerialDelta >= 0 ? rawSerialDelta : rawSerialDelta + 256
            print(String(format: "[EXG-DIAG] device=%lld flag=0x%02X serial=%d Δserial=%d Δt=%lldms", deviceId, flag, serial, deltaSerial, deltaT))
        }
        exgPacketTracker[trackerKey] = (serial: serial, timestamp: timestamp)
    }
    #endif
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

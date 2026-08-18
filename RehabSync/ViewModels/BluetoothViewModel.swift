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

/// TKE Serial No 探針的單一裝置統計（tke-sitting-calibration-port-plan.md §9 階段 0）。
/// 用來驗證 ACC 封包 Serial No（data[2]）是否符合「逐包 +1、掉包跳號、255→0 繞回」的假設——
/// 這是整個 Serial 索引對齊架構的前提，不成立就得整個改回到達時間錨定。
struct TKESerialProbe {
    var label: String = ""                  // "大腿" / "小腿"
    var lastSerial: UInt8? = nil
    var lastArrivalMs: Double? = nil
    var packetCount: Int = 0
    var deltaHistogram: [Int: Int] = [:]    // serial 增量 -> 出現次數；正常應集中在 1
    var wrapCount: Int = 0                  // 255 -> 0 繞回次數
    var accTypeSeen: Set<UInt8> = []        // data[1]，預期恆為 0x04（104Hz）
    var unexpectedLengthCount: Int = 0      // data.count != 123 的封包數
    var gapSumMs: Double = 0
    var gapCount: Int = 0
    var minGapMs: Double = .greatestFiniteMagnitude
    var maxGapMs: Double = 0

    // 相鄰封包的樣本重疊檢查：測出「每包實際前進幾筆樣本」（shift）。
    // 若 shift == 20 代表每包 20 筆全新（規劃書原本的假設）；
    // 若 shift < 20 代表封包內容重疊，k = packetIndex * 20 + i 會把時間軸灌水 20/shift 倍。
    var lastAccData: Data? = nil
    var shiftHistogram: [Int: Int] = [:]    // shift -> 出現次數

    var meanGapMs: Double { gapCount > 0 ? gapSumMs / Double(gapCount) : 0 }
    /// 除了 delta == 1 之外的所有增量次數總和（掉包 + 重複 + 異常）
    var abnormalDeltaCount: Int {
        deltaHistogram.reduce(0) { $0 + ($1.key == 1 ? 0 : $1.value) }
    }
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

    // TKE Serial No 探針（tke-sitting-calibration-port-plan.md §9 階段 0 鷹架）
    // 預設關閉，只有在 Test 頁按下「TKE探針」才啟用，正式流程完全不受影響。
    // 階段 3 會把它補齊成正式的 TKE 收集分支，屆時這組狀態會被取代。
    var isTKEPathActive = false   // UI state (main thread)
    var isCollectingTKE = false   // UI state (main thread)：8 秒校正收集中
    /// UI state (main thread)。階段 6 才會由即時流程驅動，但 §4.5① 的按鈕停用條件現在就需要它——
    /// 校正與即時共用 tkeBuffers 但保留規則衝突，不能同時啟動。
    var isTKELiveEstimating = false
    var tkeResult: KneeCalibrationResult? = nil   // UI state (main thread)
    @ObservationIgnored private var tkeLiveTimer: Timer?
    @ObservationIgnored private var tkeLiveOThigh = 0.0
    @ObservationIgnored private var tkeLiveOCalf = 0.0
    @ObservationIgnored private var tkeLiveSide = 0
    /// 連續配不到的 tick 數。達到門檻就把角度清成 nil——
    /// 否則封包正常進來但配對持續失敗時，畫面會無限期停在過時的數字且毫無異常徵兆。
    @ObservationIgnored private var tkeLiveConsecutiveMisses = 0
    /// 本次校正使用的動作規格。即時階段必須用同一份 ——
    /// 兩個動作的真值與係數套用肢段都不同，混用會算出完全錯誤的角度。
    @ObservationIgnored private var tkeSpec: any KneeCalibrationSpec.Type = TKESpec.self
    /// TKE 路徑的連線檢查／封包新鮮度 timer（1 秒一次）。
    ///
    /// **沒有它，裝置關機後就永遠回不來** —— `didDisconnectPeripheral` 只清狀態、不發起重連，
    /// 而既有的 `freshnessTimer` 只在錄製時跑、`preTestFreshnessTimer` 只在 PreWorking 跑，
    /// Test 頁的 TKE 路徑不在任何一者的涵蓋範圍內。
    @ObservationIgnored private var tkeFreshnessTimer: Timer?
    /// 校正開始當下的封包數，結算時用差值算出「這 8 秒實收幾包」（供步驟 5b）
    @ObservationIgnored private var tkeCalibStartPackets: [UUID: Int] = [:]
    @ObservationIgnored private var tkeCollecting: Set<UUID> = []          // internal (bleQueue)
    @ObservationIgnored private var tkeProbes: [UUID: TKESerialProbe] = [:]
    /// 啟用時記下兩顆的識別碼，讓 `stopTKEPath()` 不必依賴呼叫端還能取得 peripheral。
    /// 使用者離開頁面時裝置若已斷線，`thighAndCalfPeripherals` 會是 nil——
    /// 那時仍必須能清空狀態，否則 `tkeCollecting` 會永久攔截封包且無從關閉。
    @ObservationIgnored private var tkeThighId: UUID?
    @ObservationIgnored private var tkeCalfId: UUID?
    /// 停用流程的排空期：notify 已關但可能還有在途封包。
    /// 這段期間仍維持攔截（避免漏寫資料庫），但不再做任何處理。
    @ObservationIgnored private var tkeDraining = false

    // 階段 1：Serial 展開 + 增量回歸（Util/BLEClock.swift）
    @ObservationIgnored private var tkeClock: [UUID: BLEDeviceClock] = [:]
    // 階段 2：因果平滑 + 三態 buffer
    @ObservationIgnored private var tkeSmoothers: [UUID: CausalSmoother] = [:]
    @ObservationIgnored private var tkeBuffers: [UUID: [BLESample]] = [:]
    /// 校正收集中的 bleQueue 端旗標。三態（校正中／即時中／閒置串流中）由它與
    /// `tkeLiveEstimating` 決定；`tkeCollecting` 只代表「TKE 路徑已啟用」。
    /// 用 bleQueue 端旗標而非主執行緒的 `isCollectingTKE`，理由同 `recordingSessionActive`。
    @ObservationIgnored private var tkeCalibrating = false
    @ObservationIgnored private var tkeLiveEstimating = false
    /// 即時／閒置狀態下的環形 buffer 容量。220 筆 ≈ 2000ms（÷ b ≈ 9.6ms），
    /// 沿用 Python `SECONDARY_BUFFER_MS` 的量級。校正中則不裁切，保留整個收集期。
    @ObservationIgnored private static let tkeLiveBufferCapacity = 220
    /// 跨裝置共用的時間原點（epoch ms）。兩顆裝置的 `a` 必須落在同一個時間框架，
    /// 否則 `k_c = round((a_thigh + b_thigh·k_t − a_calf) / b_calf)` 這個配對公式不成立。
    /// 同時也讓回歸的 `t` 維持小數值，避免 epoch 毫秒平方後吃掉 Double 的有效位數。
    @ObservationIgnored private var tkeSessionT0Ms: Double?

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

    /// 給畫面用的膝角度：**夾限到 0 以上**。
    ///
    /// 計算端（`publishKneeAngle` 收到的值、寫進 `advanced_statistics` 的值）一律**不夾限** ——
    /// 負角度是校正殘差的真實訊號，夾掉就無法從資料回頭診斷校正品質。
    /// 夾限只發生在顯示層，因為「膝蓋 -3°」對使用者沒有意義。
    ///
    /// 正式流程的角度顯示一律走這個屬性；Test 頁刻意直接讀 `currentEstimatedRealAngle`（未夾限），
    /// 它的用途就是與 Python 逐值比對，夾限會掩蓋差異。
    var displayKneeAngle: Double? {
        currentEstimatedRealAngle.map { max(0, $0) }
    }

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
    /// `detectStepStatus` 的比較基準。動作 12 改用 offset 模型後由呼叫端傳 `0`——
    /// theta 站立時 ≈ 0，「相對站立姿勢」已內建在 theta 裡。
    /// ⚠️ 但 `detectStepStatus` 的 `+40` 門檻仍是舊尺度的值，見 working12-database-port-plan.md §20.3。
    @ObservationIgnored private var stepBaseline: Double = 0
    // stepShift／stepBaselineTable 已於階段 12-C 移除：它們只服務 tickStepStatus() 內
    // 那段 advanced_statistics 寫入，該寫入已交給 TKE 路徑（§20.2）。
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

    // MARK: - PreWorking 獨立 Channel A（working2-database-port-plan.md 第 18 節）
    // 純粹連線檢查＋封包新鮮度檢查，不做原始封包錄製，跟 Working2 的 Channel A 完全獨立。
    // 泛用設計：掛在 BluetoothViewModel 層級，任何呼叫 startLiveEstimateRealAngle 的 PreWorking
    // 頁面都可以直接呼叫這裡的 start/stop 函式，不用各自重新實作。
    @ObservationIgnored private var preTestChannelAActive = false
    /// 要監控哪兩顆裝置，直接用 startPreTestChannelA 自己收到的 thighPeripheral/calfPeripheral 參數
    /// 存下來，不要借用 liveThighId/liveCalfId——PreWorking_12 走的是 startStepStatusEstimation，
    /// 只會設定 stepThighId/stepCalfId，從不碰 liveThighId/liveCalfId，如果 tick 函式讀 liveThighId/
    /// liveCalfId，PreWorking_12 這裡永遠是 nil，Channel A 會變成表面上跑著、實際上每次都空轉的假保護
    /// （preworking12-knee-plan.md 第 7 節）。獨立一組變數後，Channel A 不依賴任何特定 Channel B
    /// 機制（角度／登階皆可），也不用假設 startLiveEstimateRealAngle/startStepStatusEstimation 一定要
    /// 比 startPreTestChannelA 先執行。
    @ObservationIgnored private var preTestThighId: UUID?
    @ObservationIgnored private var preTestCalfId: UUID?
    /// 這個集合裡的 uuid，封包進來只更新 lastPacketAt（給新鮮度檢查用）跟餵給 Channel B，
    /// 不落地寫入 acc/gyro/exg 表——順便一併修正既有的 ACC 孤兒寫入問題（見 18.4 節）。
    @ObservationIgnored private var preTestMonitoring: Set<UUID> = []
    @ObservationIgnored private var preTestFreshnessTimer: Timer?

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

    /// 共用修復路徑的訂閱模式：`.full` 會呼叫 `startRecording`（連帶設定 `isRecording = true`，
    /// 給 Working2 情境用）；`.monitorOnly` 呼叫 `subscribeAllCharacteristics`（不碰 `isRecording`，
    /// 給 PreWorking 情境用，避免誤把 `advanced_statistics` 寫入保護打開，見 working2-database-port-plan.md 18.3）。
    private enum RecoverySubscribeMode {
        case full
        case monitorOnly
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
                self.checkAndRecoverIfNeeded(uuid: uuid, mode: .full)
            }
        }
    }

    /// PreWorking 獨立 Channel A：連線檢查＋封包新鮮度檢查，1 秒一次，只在 `preTestChannelAActive`
    /// 為 true 時運作。裝置 UUID 讀 `preTestThighId`／`preTestCalfId`（`startPreTestChannelA` 用自己
    /// 收到的參數直接存下，不借用 `liveThighId`／`liveCalfId`，見該函式與 preworking12-knee-plan.md
    /// 第 7 節）——不能沿用 `liveThighId`／`liveCalfId`，因為只有走 `startLiveEstimateRealAngle`
    /// 的頁面（`PreWorking_2`／`9`）才會設定這兩個變數，走 `startStepStatusEstimation` 的
    /// `PreWorking_12` 只會設定 `stepThighId`／`stepCalfId`，如果這裡讀 `liveThighId`／`liveCalfId`，
    /// `PreWorking_12` 會拿到 nil、guard 直接 return，整個 Channel A 變成表面上跑著、實際上每次都
    /// 空轉的假保護。
    private func tickPreTestConnectionAndFreshnessCheck() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            guard self.preTestChannelAActive else { return }
            guard let thighUUID = self.preTestThighId, let calfUUID = self.preTestCalfId else { return }

            for uuid in [thighUUID, calfUUID] {
                self.checkAndRecoverIfNeeded(uuid: uuid, mode: .monitorOnly)
            }
        }
    }

    /// 啟動 PreWorking 獨立 Channel A：純連線檢查＋封包新鮮度檢查，不做原始封包錄製。
    /// 呼叫時機比照 `startLiveEstimateRealAngle`／`startStepStatusEstimation`，在 PreWorking
    /// 動作測試面板 `onAppear` 一起呼叫，兩者呼叫先後順序不影響這裡（見 `preTestThighId`／
    /// `preTestCalfId` 宣告處的說明）。
    func startPreTestChannelA(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        // TKE 路徑若已啟用，兩顆裝置在校正階段就已經收過 cmd_a0/a1/a2 且正在正常串流 ——
        // 這裡再送一次只會打斷取樣，讓 tkeClock 重置、動作測試頁開頭約 2 秒沒有角度。
        // 這一行只影響「本來就在串流」的情境；斷線恢復仍由 recoverIfNeeded／
        // didDiscoverCharacteristicsFor 走預設的 sendConfigCommands: true。
        let pathAlreadyConfigured = isTKEPathActive
        DispatchQueue.main.async {
            self.preTestFreshnessTimer?.invalidate()
            self.preTestFreshnessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tickPreTestConnectionAndFreshnessCheck()
            }
        }
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.preTestChannelAActive = true
            self.preTestThighId = thighPeripheral.identifier
            self.preTestCalfId  = calfPeripheral.identifier
            self.preTestMonitoring.insert(thighPeripheral.identifier)
            self.preTestMonitoring.insert(calfPeripheral.identifier)
            self.subscribeAllCharacteristics(peripheral: thighPeripheral,
                                             sendConfigCommands: !pathAlreadyConfigured)
            self.subscribeAllCharacteristics(peripheral: calfPeripheral,
                                             sendConfigCommands: !pathAlreadyConfigured)
            print("[TKE] PreWorking Channel A 啟動（重送設定指令=\(!pathAlreadyConfigured)）")
        }
    }

    /// 停止 PreWorking 獨立 Channel A：**不能依賴 `onDisappear`**——PreWorking 進入 Working2 是走
    /// `.fullScreenCover`，不會觸發底層 `onDisappear`；必須在使用者點擊「遊戲」、觸發導頁的那一刻
    /// 明確呼叫這個函式（working2-database-port-plan.md 18.2），否則會一路帶進 Working2、
    /// 干擾 Working2 自己的 Channel A（例如組間休息時誤把剛關掉的 notify 重新打開）。
    func stopPreTestChannelA(thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.preTestFreshnessTimer?.invalidate()
            self.preTestFreshnessTimer = nil
        }
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.preTestChannelAActive = false
            self.preTestMonitoring.remove(thighPeripheral.identifier)
            self.preTestMonitoring.remove(calfPeripheral.identifier)
        }
    }

    /// 兩個 Channel A（Working2／PreWorking）共用的逐 uuid 檢查邏輯：連線檢查優先於封包新鮮度檢查。
    private func checkAndRecoverIfNeeded(uuid: UUID, mode: RecoverySubscribeMode) {
        guard let peripheral = peripheralMap[uuid] ?? connectedPeripherals[uuid],
              peripheral.state == .connected else {
            recoverIfNeeded(uuid: uuid, mode: mode)
            return
        }
        if isAnySignalStale(uuid: uuid) {
            recoverIfNeeded(uuid: uuid, mode: mode)
        }
    }

    /// 共用修復路徑：連線缺失／封包新鮮度逾時都導向這裡，依 `peripheral.state` 分流。
    /// 冷卻 3 秒、per-uuid 各自獨立，避免同一裝置在修復生效前被重複觸發。
    private func recoverIfNeeded(uuid: UUID, mode: RecoverySubscribeMode) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let last = lastRecoveryAttemptAt[uuid], now - last < 3000 { return }
        lastRecoveryAttemptAt[uuid] = now

        guard let peripheral = peripheralMap[uuid] ?? connectedPeripherals[uuid] else {
            attemptBackgroundReconnect(uuid: uuid)
            return
        }
        switch peripheral.state {
        case .connected:
            // 連線物件還在、資料 stale：從簡對這顆裝置的 ACC／GYRO／EXG 全部重新訂閱，並補送
            // cmd_a0／cmd_a1／cmd_a2（見 17.4 節）。`.full` 連帶設定 isRecording（Working2 情境）；
            // `.monitorOnly` 只訂閱不設定 isRecording（PreWorking 情境，見 18.3 節）。
            switch mode {
            case .full:
                startRecording(peripheral: peripheral)
            case .monitorOnly:
                subscribeAllCharacteristics(peripheral: peripheral)
            }
        case .connecting:
            break
        default:
            attemptBackgroundReconnect(uuid: uuid)
        }
    }

    // MARK: - Recording

    /// 只做「訂閱 ACC+GYRO+EXG + 補送 cmd_a0/a1/a2」，不碰 `isRecording`——給 `startRecording`
    /// 跟 PreWorking Channel A 的 `.monitorOnly` 修復模式共用（working2-database-port-plan.md 18.3）。
    /// 不能讓 PreWorking 的修復動作誤設 `isRecording`，否則會意外打開 `tickLiveEstimatedRealAngle()`
    /// 的 `advanced_statistics` 寫入守門，讓 PreWorking 期間寫入 treatment_result_id 為 nil 的孤兒資料。
    /// - Parameter sendConfigCommands: 是否重送 `cmd_a0`／`cmd_a1`／`cmd_a2`（取樣率等裝置端設定）。
    ///
    ///   預設 `true`，涵蓋所有「裝置剛連上／剛從斷線恢復」的情境 —— 那時裝置端設定是未知的，必須送。
    ///
    ///   傳 `false` 的唯一情境是「裝置**已經**在正常串流、只是要多訂閱幾個 characteristic」。
    ///   實測（階段 C 測試 2）確認重送設定指令會讓取樣**短暫中斷**，
    ///   而 TKE 路徑的 `tkeClock` 會因此偵測到 serial 與到達時間不一致 → 重置 →
    ///   **約 2 秒沒有角度**（回歸重新累積 10 個觀測點 + 平滑視窗重填 30 筆）。
    ///   裝置設定既然已經是對的，這一次重送就是純粹的傷害。
    private func subscribeAllCharacteristics(peripheral: CBPeripheral, sendConfigCommands: Bool = true) {
        guard let config = bluetoothConfig,
              let map = charMap[peripheral.identifier] else { return }

        let writeUUID = CBUUID(string: config.write_uuid)
        let accUUID   = CBUUID(string: config.sub_acc_uuid)
        let gyroUUID  = CBUUID(string: config.sub_gyro_uuid)
        let exgUUID   = CBUUID(string: config.sub_exg_uuid)

        if sendConfigCommands, let writeChar = map[writeUUID] {
            peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
        }

        if let c = map[accUUID]  { peripheral.setNotifyValue(true, for: c) }
        if let c = map[gyroUUID] { peripheral.setNotifyValue(true, for: c) }
        if let c = map[exgUUID]  { peripheral.setNotifyValue(true, for: c) }
    }

    func startRecording(peripheral: CBPeripheral) {
        subscribeAllCharacteristics(peripheral: peripheral)
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

    // MARK: - TKE Serial No 探針（tke-sitting-calibration-port-plan.md §9 階段 0）

    /// 啟用 TKE 路徑（tke-sitting-calibration-port-plan.md §4.4）。
    ///
    /// 連線由總覽頁管理，這裡**不 connect 也不 disconnect**，只開關 ACC notify。
    /// 這是與 Python 腳本最大的行為差異之一 —— Python 用 `async with BleakClient(mac)`
    /// 把連線與斷線都綁在校正的生命週期上，App 不能這樣做。
    ///
    /// 啟用後 notify 與 `tkeCollecting` **同生共死**，一路維持到 `stopTKEPath()`：
    /// 校正結束不關、即時停止也不關。理由見 §4.4 ——
    /// 中途關掉 notify 會讓封包中斷，`tkeClock` 就得面臨要不要重置的問題。
    /// - Parameter ownsConnectionRecovery: 是否由 TKE 路徑自己跑 1 秒連線檢查 timer。
    ///
    ///   `false`（**預設**，正式流程）：PreWorking／Working 已各自有 `preTestFreshnessTimer`／
    ///   `freshnessTimer` 在做同一件事。更關鍵的是**組間休息期間** —— `stopRecordingAll` 會刻意
    ///   關閉 notify，若 TKE 路徑還在跑自己的檢查，會把剛關掉的 notify 重新訂閱回來，
    ///   破壞休息期的起訖規則。（見 preworking2-knee-plan.md §8.3）
    ///
    ///   `true`（Test 頁）：測試頁沒有別的東西在做斷線修復，必須自己跑，否則裝置關機後
    ///   `didDisconnectPeripheral` 只會清狀態、沒有任何東西會嘗試重連（階段 6 踩過的坑）。
    ///
    ///   ⚠️ **預設值刻意選安全的那個。** 危險的是 `true` —— 它在組間休息重新訂閱 notify 時
    ///   不會有任何錯誤徵兆。把危險值當預設，等於「新增呼叫點時忘記傳 = 踩雷」，
    ///   所以反過來讓唯一需要它的 Test 頁顯式傳 `true`。
    func startTKEPath(thighPeripheral: CBPeripheral,
                      calfPeripheral: CBPeripheral,
                      ownsConnectionRecovery: Bool = false) {
        DispatchQueue.main.async {
            self.isTKEPathActive = true
            self.tkeFreshnessTimer?.invalidate()
            self.tkeFreshnessTimer = nil
            if ownsConnectionRecovery {
                self.tkeFreshnessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.tickTKEConnectionCheck()
                }
            }
        }

        bleQueue.async { [weak self] in
            guard let self, let config = bluetoothConfig else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }

            let thighId = thighPeripheral.identifier
            let calfId = calfPeripheral.identifier
            tkeThighId = thighId
            tkeCalfId = calfId

            tkeProbes[thighId] = TKESerialProbe(label: "大腿")
            tkeProbes[calfId]  = TKESerialProbe(label: "小腿")
            tkeClock[thighId] = BLEDeviceClock()
            tkeClock[calfId]  = BLEDeviceClock()
            tkeSmoothers[thighId] = CausalSmoother(window: KneeCalibration.smoothWindow)
            tkeSmoothers[calfId]  = CausalSmoother(window: KneeCalibration.smoothWindow)
            tkeBuffers[thighId] = []
            tkeBuffers[calfId]  = []
            tkeCalibrating = false      // 階段 5 才會由校正流程設為 true
            tkeLiveEstimating = false   // 階段 6 才會由即時流程設為 true
            tkeSessionT0Ms = nil
            tkeCollecting = [thighId, calfId]

            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }
            let c = deviceVM.accRowCounts()
            print("[TKE] 路徑啟用（wasRecording=\(wasRecording)）。notify 開啟，tkeCollecting 已填入兩顆。")
            print("[TKE-DB] 啟用前 acc 表：總筆數=\(c.total)，treatment_result_id 為 nil=\(c.orphan)")
        }
    }

    /// 執行一次膝角校正（tke-sitting-calibration-port-plan.md §9 階段 5）。
    ///
    /// 若 TKE 路徑尚未啟用會先啟用。**校正結束後路徑維持啟用、notify 不關**（§4.4）——
    /// 這是「`tkeClock` 跨階段保留、即時啟動時免暖機」能成立的前提。
    ///
    /// - Parameters:
    ///   - spec: 動作規格（`TKESpec` = 動作 2 坐姿、`SquatSpec` = 動作 9 部分蹲）。
    ///     收集層完全與動作無關，只有結算與即時換算需要知道規格。
    ///   - durationSec: 收集秒數，預設 8。8 秒理論上限 ≈832 筆，
    ///     扣掉平滑暖機與姿勢淘汰後約 723 筆，對 250 門檻有充分餘裕（§5.2）。
    ///   - ownsConnectionRecovery: **只在本次呼叫需要順帶啟用路徑時才生效**，直接轉交
    ///     `startTKEPath(...)`，語意見該函式。正式流程的路徑是在校正面板 `startPreparing()`
    ///     就先啟用的，走不到這個備援分支；但備援分支一旦被走到（例如使用者從動作測試面板
    ///     退回校正面板重按、或啟用當下取不到 peripheral），若這裡漏傳就會用預設值啟用路徑 ——
    ///     所以參數必須一路傳到底，不能只加在 `startTKEPath` 上。
    func startKneeCalibration(
        spec: any KneeCalibrationSpec.Type = TKESpec.self,
        thighPeripheral: CBPeripheral, calfPeripheral: CBPeripheral,
        durationSec: Double = 8,
        ownsConnectionRecovery: Bool = false,
        completion: ((KneeCalibrationResult) -> Void)? = nil
    ) {
        let alreadyActive = isTKEPathActive
        if !alreadyActive {
            startTKEPath(thighPeripheral: thighPeripheral, calfPeripheral: calfPeripheral,
                         ownsConnectionRecovery: ownsConnectionRecovery)
        }

        DispatchQueue.main.async {
            self.tkeResult = nil
            self.isCollectingTKE = true
        }

        let side = DeviceViewModel().fetchAnySide() ?? 0
        let thighId = thighPeripheral.identifier
        let calfId = calfPeripheral.identifier

        // startTKEPath 也是丟到 bleQueue，同一條序列佇列，所以順序有保證
        bleQueue.async { [weak self] in
            guard let self else { return }
            // 校正期間 buffer 不裁切，保留整個收集窗（§4.2 三態）
            tkeCalibrating = true
            tkeBuffers[thighId] = []
            tkeBuffers[calfId] = []
            // clock 刻意不重置——它從路徑啟用起就在累積，重置只會白白丟掉觀測點
            tkeCalibStartPackets[thighId] = tkeProbes[thighId]?.packetCount ?? 0
            tkeCalibStartPackets[calfId] = tkeProbes[calfId]?.packetCount ?? 0
            // 記住這次校正用的規格，即時階段必須用同一份（係數與真值都不同）
            tkeSpec = spec
            print("[KNEE-CAL] \(spec.name) 開始收集 \(Int(durationSec)) 秒（side=\(side == 1 ? "右" : "左")，路徑\(alreadyActive ? "已啟用" : "本次啟用")）")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + durationSec) { [weak self] in
            self?.bleQueue.async {
                self?.finishKneeCalibration(spec: spec, thighId: thighId, calfId: calfId, side: side, completion: completion)
            }
        }
    }

    private func finishKneeCalibration(
        spec: any KneeCalibrationSpec.Type,
        thighId: UUID, calfId: UUID, side: Int,
        completion: ((KneeCalibrationResult) -> Void)?
    ) {
        tkeCalibrating = false

        let thighSamples = tkeBuffers[thighId] ?? []
        let calfSamples = tkeBuffers[calfId] ?? []

        // 觀測點不足時 fit() 回傳 nil，這裡補一個帶真實 pointCount 的替身，
        // 讓 computeOffsets 的步驟 5a 能正確判定「回歸不可信」而不是崩在 nil 上。
        func fitOrFallback(_ id: UUID) -> BLEClockFit {
            if let f = tkeClock[id]?.fit() { return f }
            return BLEClockFit(a: 0, b: BLEDeviceClock.nominalPeriodMs,
                               pointCount: tkeClock[id]?.pointCount ?? 0, residualStdMs: 0)
        }

        let thighPackets = (tkeProbes[thighId]?.packetCount ?? 0) - (tkeCalibStartPackets[thighId] ?? 0)
        let calfPackets = (tkeProbes[calfId]?.packetCount ?? 0) - (tkeCalibStartPackets[calfId] ?? 0)

        let result = KneeCalibration.computeOffsets(
            spec: spec,
            thighSamples: thighSamples, calfSamples: calfSamples, side: side,
            thighFit: fitOrFallback(thighId), calfFit: fitOrFallback(calfId),
            thighPacketCount: thighPackets, calfPacketCount: calfPackets)

        DispatchQueue.main.async {
            self.tkeResult = result
            self.isCollectingTKE = false
            completion?(result)
        }
    }

    // MARK: - TKE 即時角度（§9 階段 6）

    /// 每次 tick 最多往回退幾筆大腿樣本（1 個封包）。
    /// 小腿封包間隔 192ms ≈ tick 間隔 200ms，最新一筆大腿樣本對應的小腿樣本經常還沒到。
    private static let tkeLiveWalkBack = 20
    /// 連續配不到幾次 tick 就清空角度。5 次 ≈ 1 秒，與封包新鮮度門檻對齊。
    private static let tkeLiveMissLimit = 5

    /// 開始即時角度估算。必須先校正成功，且**綁定側要與校正當時相同**。
    func startTKELiveAngle() {
        // 兩條 tick 都發布到 currentEstimatedRealAngle（§20.2），同時運作會互相覆蓋 5Hz 的值，
        // 錄製中更會讓同一時間點寫入兩筆 advanced_statistics。正式流程動作 2 走新路徑、
        // 9／12／22 走舊路徑，本來不該重疊；這道防呆是給 Test 頁與日後誤接用的。
        guard !isLiveEstimating else {
            print("[TKE-LIVE] ⚠️ 舊即時路徑（isLiveEstimating）仍在運作，拒絕啟動 —— 兩條 tick 不可同時發布角度")
            return
        }
        guard let r = tkeResult, let oThigh = r.thigh, let oCalf = r.calf else {
            print("[TKE-LIVE] 尚未校正成功，無法啟動")
            return
        }
        let nowSide = DeviceViewModel().fetchAnySide() ?? 0
        guard r.side == nowSide else {
            // 換綁裝置後用舊 offset 搭配新 side，k 值符號相反、角度會完全錯誤，
            // 而畫面上不會有任何異常徵兆——只會看到一個看似合理但錯誤的數字。
            print("[TKE-LIVE] ⚠️ 綁定側已變更（校正時=\(r.side)、目前=\(nowSide)），請重新校正")
            return
        }

        bleQueue.async { [weak self] in
            guard let self else { return }
            tkeLiveOThigh = oThigh
            tkeLiveOCalf = oCalf
            tkeLiveSide = r.side
            tkeLiveConsecutiveMisses = 0
            tkeLiveEstimating = true
        }

        publishKneeAngle(nil)
        DispatchQueue.main.async {
            self.isTKELiveEstimating = true
            self.tkeLiveTimer?.invalidate()
            self.tkeLiveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.tickTKELiveAngle()
            }
        }
        print("[TKE-LIVE] 啟動（side=\(r.side == 1 ? "右" : "左") o_thigh=\(String(format: "%.2f", oThigh))° o_calf=\(String(format: "%.2f", oCalf))°）")
    }

    /// 停止即時角度。**不關 notify、不清 tkeCollecting**（§4.4）——
    /// 路徑一路維持到離開頁面才由 stopTKEPath 收尾。
    func stopTKELiveAngle() {
        publishKneeAngle(nil)
        DispatchQueue.main.async {
            self.tkeLiveTimer?.invalidate()
            self.tkeLiveTimer = nil
            self.isTKELiveEstimating = false
        }
        bleQueue.async { [weak self] in
            self?.tkeLiveEstimating = false
            self?.tkeLiveConsecutiveMisses = 0
        }
        print("[TKE-LIVE] 停止（notify 維持開啟）")
    }

    /// 每 0.2 秒取最新一筆大腿樣本算一次（§4.2「即時模式的 buffer 管理與計算頻率」）。
    ///
    /// 5Hz 取樣不會造成失真：收集層的因果移動平均 N=30 相當於 0.29 秒視窗，比 tick 間隔還長，
    /// 相鄰兩次 tick 的視窗是重疊的，平滑本身已扮演降頻前的抗混疊濾波器。
    private func tickTKELiveAngle() {
        bleQueue.async { [weak self] in
            guard let self, tkeLiveEstimating,
                  let thighId = tkeThighId, let calfId = tkeCalfId else { return }

            // 防護三：封包新鮮度。任一側超過 1000ms 沒收到封包就視為資料不可信。
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for id in [thighId, calfId] {
                if let last = lastPacketAt[id]?[Self.signalACC], now - last > 1000 {
                    self.publishKneeAngle(nil)
                    return
                }
            }

            guard let thighBuf = tkeBuffers[thighId], !thighBuf.isEmpty,
                  let calfBuf = tkeBuffers[calfId], !calfBuf.isEmpty,
                  let thighFit = tkeClock[thighId]?.fit(),
                  let calfFit = tkeClock[calfId]?.fit() else { return }

            // 防護一：從最新一筆往回退，最多一個封包。
            // 回退必須發生在**大腿側**——在小腿側找鄰近樣本等同「取最近鄰替代」，
            // 那是 findPair 明令禁止的行為。往回取較舊的大腿樣本，配到的仍是時間上真正對應的小腿樣本。
            var paired: (thigh: BLESample, calf: BLESample)?
            for offset in 0 ..< min(Self.tkeLiveWalkBack, thighBuf.count) {
                let t = thighBuf[thighBuf.count - 1 - offset]
                if let c = KneeCalibration.findPair(kThigh: t.k, thighFit: thighFit,
                                                   calfSamples: calfBuf, calfFit: calfFit) {
                    paired = (t, c)
                    break
                }
            }

            guard let p = paired else {
                // 防護二：連續配不到就清空。少了這一層，封包正常但配對持續失敗時
                // （clock 剛重置、回歸尚未收斂）畫面會無限期停在過時角度。
                tkeLiveConsecutiveMisses += 1
                if tkeLiveConsecutiveMisses >= Self.tkeLiveMissLimit {
                    self.publishKneeAngle(nil)
                }
                return
            }
            tkeLiveConsecutiveMisses = 0

            let theta = KneeCalibration.liveAngle(
                spec: tkeSpec,
                thigh: p.thigh, calf: p.calf, side: tkeLiveSide,
                oThigh: tkeLiveOThigh, oCalf: tkeLiveOCalf)
            let rounded = (theta * 10).rounded() / 10
            self.publishKneeAngle(rounded)
        }
    }

    /// TKE 路徑的連線檢查＋封包新鮮度檢查，1 秒一次，只在路徑啟用時運作。
    ///
    /// 走跟 Working2／PreWorking 相同的 `checkAndRecoverIfNeeded`，模式用 `.monitorOnly`
    /// （只訂閱、不設定 `isRecording`）—— TKE 路徑不做原始封包錄製，比照 PreWorking Channel A。
    /// 裝置若已完全斷線，`recoverIfNeeded` 會走到 `attemptBackgroundReconnect` 發起重連，
    /// 重連完成後 `didDiscoverCharacteristicsFor` 再呼叫 `resubscribeTKEAcc` 補回訂閱。
    private func tickTKEConnectionCheck() {
        bleQueue.async { [weak self] in
            guard let self, !tkeCollecting.isEmpty, !tkeDraining else { return }
            guard let thighId = tkeThighId, let calfId = tkeCalfId else { return }
            for uuid in [thighId, calfId] {
                checkAndRecoverIfNeeded(uuid: uuid, mode: .monitorOnly)
            }
        }
    }

    /// 停用 TKE 路徑並印出彙整報告。
    ///
    /// **刻意不收 peripheral 參數** —— 使用者離開頁面時裝置可能已經斷線，
    /// 呼叫端拿不到 peripheral；那時仍必須能清空 `tkeCollecting`，
    /// 否則裝置一旦重連，封包會被永久攔截且無從關閉。
    /// 識別碼在 `startTKEPath` 就已記下，這裡只從 `connectedPeripherals` 盡力關 notify。
    func stopTKEPath() {
        DispatchQueue.main.async {
            self.isTKEPathActive = false
            self.tkeFreshnessTimer?.invalidate()
            self.tkeFreshnessTimer = nil
        }

        bleQueue.async { [weak self] in
            guard let self else { return }
            let wasRecording = DispatchQueue.main.sync { self.isRecording }
            let thighId = tkeThighId
            let calfId = tkeCalfId

            // ⚠️ 順序關鍵：**先關 notify、後清 tkeCollecting**，中間維持攔截。
            //
            // 反過來做（先清 tkeCollecting）會漏 —— setNotifyValue(false) 是非同步生效的，
            // 清空之後、notify 真正停止之前抵達的在途封包不再被攔截，
            // 會一路掉到 parseACC 寫進 acc 表且 treatment_result_id 為 nil。
            // 實測就是這樣漏掉整整一個封包（20 列）。
            tkeDraining = true   // 仍攔截，但不再處理

            // 錄製中不可關 notify，否則會打斷正在進行的收集（比照 finishAccOnlyCollection）
            if !wasRecording, let config = bluetoothConfig {
                let live = DispatchQueue.main.sync { self.connectedPeripherals }
                for id in [thighId, calfId].compactMap({ $0 }) {
                    guard let peripheral = live[id],
                          let map = charMap[id],
                          let c = map[CBUUID(string: config.sub_acc_uuid)] else { continue }
                    peripheral.setNotifyValue(false, for: c)
                }
            }

            if let thighId, let calfId {
                printTKEProbeSummary(thighId: thighId, calfId: calfId)
            }
            tkeProbes.removeAll()
            tkeClock.removeAll()
            tkeSmoothers.removeAll()
            tkeBuffers.removeAll()
            tkeCalibrating = false
            tkeLiveEstimating = false
            tkeSessionT0Ms = nil
            tkeThighId = nil
            tkeCalfId = nil
            tkeCalibStartPackets.removeAll()
            tkeLiveConsecutiveMisses = 0
            self.publishKneeAngle(nil)
            DispatchQueue.main.async {
                self.tkeLiveTimer?.invalidate()
                self.tkeLiveTimer = nil
                self.isTKELiveEstimating = false
                self.tkeResult = nil
                self.isCollectingTKE = false
            }
            print("[TKE] 路徑停用（wasRecording=\(wasRecording)，notify \(wasRecording ? "保留" : "已關閉")）。")

            if wasRecording {
                // 錄製中本來就要讓 ACC 寫進資料庫，立刻放行即可
                tkeCollecting = []
                tkeDraining = false
                print("[TKE] 錄製進行中，立即解除攔截（ACC 應繼續寫入資料庫）。")
            } else {
                // 排空期：等在途封包到齊再解除攔截。1 秒 ≈ 5 個封包間隔，餘裕充足。
                bleQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    tkeCollecting = []
                    tkeDraining = false
                    let c = deviceVM.accRowCounts()
                    print("[TKE-DB] 排空完成後 acc 表：總筆數=\(c.total)，treatment_result_id 為 nil=\(c.orphan)")
                    print("[TKE-DB] → 測試 A 判定：這兩個數字都必須與「啟用前」完全相同")
                }
            }
        }
    }

    /// 階段 2：封包 → clock → 平滑 → buffer。這是 TKE 路徑的收集主流程。
    ///
    /// 三態（§4.2「即時模式的 buffer 管理」）：
    /// - 校正中（`tkeCalibrating`）：保留整個收集期，不裁切
    /// - 即時中／閒置串流中：只保留最近 `tkeLiveBufferCapacity` 筆，逐包裁切
    ///
    /// 回傳 clock 的處理結果供診斷用。
    @discardableResult
    private func collectTKEAcc(_ data: Data, id: UUID, config: Bluetooth) -> BLEDeviceClock.Outcome? {
        guard data.count >= 123 else { return nil }

        let nowMs = Date().timeIntervalSince1970 * 1000
        if tkeSessionT0Ms == nil { tkeSessionT0Ms = nowMs }
        let relMs = nowMs - (tkeSessionT0Ms ?? nowMs)

        guard var clock = tkeClock[id] else { return nil }
        let outcome = clock.ingest(serial: data[2], arrivalMs: relMs)
        tkeClock[id] = clock

        let firstK: Int
        switch outcome {
        case .duplicate:
            return outcome
        case .reset(let k):
            // clock 重置後 k 回到新的編號基準，既有 buffer 與平滑視窗都是舊基準的資料，
            // 留著只會讓配對取到撞號的錯誤樣本，一併清空。
            tkeBuffers[id]?.removeAll(keepingCapacity: true)
            tkeSmoothers[id]?.reset()
            firstK = k
            // 重置的代價是「約 2 秒沒有角度」：回歸要重新累積 10 個觀測點（10 × 192ms ≈ 1.9 秒），
            // 平滑視窗還要再填 30 筆（≈0.29 秒）。所以每一次重置都要能被看見、且能判斷成因。
            if let info = clock.lastResetInfo {
                print(String(format: "[TKE-CLOCK] ⚠️ clock 重置（第 %d 次） id=%@ delta=%d 包 expectedGap=%.0fms actualGap=%.0fms → %@",
                             clock.resetCount, id.uuidString.prefix(8).description,
                             info.delta, info.expectedGapMs, info.actualGapMs,
                             info.actualGapMs > info.expectedGapMs + BLEDeviceClock.crossCheckToleranceMs
                                ? "串流暫停（重送設定指令／重新訂閱打斷取樣）"
                                : "裝置端 serial 跳號"))
            }
        case .accepted(let k):
            firstK = k
        }

        var smoother = tkeSmoothers[id] ?? CausalSmoother(window: KneeCalibration.smoothWindow)
        var buf = tkeBuffers[id] ?? []

        for i in 0 ..< 20 {
            let o = 3 + i * 6
            let rawX = Double(data.int16BE(at: o))     * config.acc_sensitivity
            let rawY = Double(data.int16BE(at: o + 2)) * config.acc_sensitivity
            let rawZ = Double(data.int16BE(at: o + 4)) * config.acc_sensitivity
            // 視窗未滿的樣本直接丟棄，不進 buffer（§5.1）
            guard let s = smoother.push(x: rawX, y: rawY, z: rawZ) else { continue }
            buf.append(BLESample(k: firstK + i, x: s.x, y: s.y, z: s.z))
        }

        // 非校正狀態下裁成環形 buffer，避免無限成長
        if !tkeCalibrating, buf.count > Self.tkeLiveBufferCapacity {
            buf.removeFirst(buf.count - Self.tkeLiveBufferCapacity)
        }

        tkeSmoothers[id] = smoother
        tkeBuffers[id] = buf
        return outcome
    }

    /// 逐包更新統計並印出單行紀錄。只在 `tkeCollecting` 命中時被呼叫。
    private func probeTKESerial(_ data: Data, id: UUID) {
        guard var probe = tkeProbes[id] else { return }

        let nowMs = Date().timeIntervalSince1970 * 1000
        probe.packetCount += 1
        if data.count != 123 { probe.unexpectedLengthCount += 1 }
        if data.count >= 2 { probe.accTypeSeen.insert(data[1]) }

        guard data.count >= 3 else { tkeProbes[id] = probe; return }
        let serial = data[2]

        var deltaText = "—"
        if let last = probe.lastSerial {
            // 與 §4.2 節①的展開公式一致：繞回後仍應得到正確的增量
            let delta = (Int(serial) - Int(last) + 256) % 256
            probe.deltaHistogram[delta, default: 0] += 1
            if serial < last { probe.wrapCount += 1 }
            deltaText = "\(delta)"
        }

        var gapText = "—"
        if let lastAt = probe.lastArrivalMs {
            let gap = nowMs - lastAt
            probe.gapSumMs += gap
            probe.gapCount += 1
            probe.minGapMs = min(probe.minGapMs, gap)
            probe.maxGapMs = max(probe.maxGapMs, gap)
            gapText = String(format: "%.1f", gap)
        }

        // 樣本重疊檢查：找出使「前一包的 samples[s...19] == 本包的 samples[0...(19-s)]」
        // 成立的最小 s，那就是本包相對前一包實際前進的樣本數。
        // 找不到任何 s 則視為 20（完全不重疊，即每包 20 筆全新）。
        var shiftText = "—"
        if data.count >= 123 {
            let acc = Data(data[3 ..< 123])          // 120 bytes = 20 樣本 × 6 bytes
            if let prev = probe.lastAccData, deltaText == "1" {
                // 只在 delta==1（沒掉包）時比對才有意義
                var found = 20
                for s in 1 ... 20 {
                    let overlapBytes = (20 - s) * 6
                    if overlapBytes == 0 { break }
                    if prev[(s * 6) ..< 120] == acc[0 ..< overlapBytes] {
                        found = s
                        break
                    }
                }
                probe.shiftHistogram[found, default: 0] += 1
                shiftText = "\(found)"
            }
            probe.lastAccData = acc
        }

        probe.lastSerial = serial
        probe.lastArrivalMs = nowMs
        tkeProbes[id] = probe

        // ---- 階段 1／2 狀態（clock 與 buffer 由 collectTKEAcc 更新，這裡只讀不寫）----
        var clockText = ""
        if let clock = tkeClock[id], let f = clock.fit() {
            clockText = String(format: " b=%.4fms(%.1fHz) resid=%.1fms n=%d",
                               f.b, f.measuredRateHz, f.residualStdMs, f.pointCount)
        } else {
            clockText = " b=（觀測點不足）"
        }
        let buffered = tkeBuffers[id]?.count ?? 0
        let lastK = tkeBuffers[id]?.last?.k ?? -1
        let warmup = tkeSmoothers[id]?.warmupDiscarded ?? 0
        let bufText = " buf=\(buffered) lastK=\(lastK) warmup丟棄=\(warmup)"

        let flag = (deltaText != "1" && deltaText != "—") ? " ⚠️掉包/重複" : ""
        print(String(format: "[TKE-PROBE] %@ #%-4d serial=%3d delta=%@ shift=%@ gap=%@ms len=%d type=0x%02X%@%@%@",
                     probe.label, probe.packetCount, Int(serial), deltaText, shiftText, gapText,
                     data.count, data.count >= 2 ? data[1] : 0, flag, clockText, bufText))
    }

    /// §9 階段 0 的四項驗收：逐包 +1、掉包跳號、255→0 繞回、兩顆裝置各自獨立計數。
    private func printTKEProbeSummary(thighId: UUID, calfId: UUID) {
        print("\n========== [TKE-PROBE] 彙整報告 ==========")
        for id in [thighId, calfId] {
            guard let p = tkeProbes[id] else { continue }
            let deltaDesc = p.deltaHistogram.sorted { $0.key < $1.key }
                .map { "delta=\($0.key)×\($0.value)" }.joined(separator: ", ")
            let typeDesc = p.accTypeSeen.sorted()
                .map { String(format: "0x%02X", $0) }.joined(separator: ",")
            let shiftDesc = p.shiftHistogram.sorted { $0.key < $1.key }
                .map { "shift=\($0.key)×\($0.value)" }.joined(separator: ", ")
            // 由實測的 shift 與到達間隔反推真實取樣率，與標稱值對照
            let dominantShift = p.shiftHistogram.max { $0.value < $1.value }?.key
            var rateDesc = "（資料不足）"
            if let s = dominantShift, p.meanGapMs > 0 {
                let hz = Double(s) / (p.meanGapMs / 1000.0)
                rateDesc = String(format: "每包前進 %d 筆 → 實測取樣率 ≈ %.1f Hz", s, hz)
            }
            print("""
            [\(p.label)]
              封包數      = \(p.packetCount)
              serial 增量 = \(deltaDesc.isEmpty ? "（無）" : deltaDesc)
              異常增量數  = \(p.abnormalDeltaCount)（delta≠1 的總次數＝掉包或重複）
              繞回次數    = \(p.wrapCount)（255→0）
              ACC Type    = \(typeDesc)（預期 0x04 = 104Hz）
              長度異常    = \(p.unexpectedLengthCount) 包（預期 0，長度應為 123）
              到達間隔    = 平均 \(String(format: "%.1f", p.meanGapMs))ms / 最小 \(String(format: "%.1f", p.minGapMs == .greatestFiniteMagnitude ? 0 : p.minGapMs))ms / 最大 \(String(format: "%.1f", p.maxGapMs))ms
              樣本前進量  = \(shiftDesc.isEmpty ? "（無）" : shiftDesc)
              🔑 \(rateDesc)
            """)
        }

        // 兩顆裝置是否各自獨立計數：serial 若同步前進，代表不是獨立計數器
        if let t = tkeProbes[thighId], let c = tkeProbes[calfId],
           let ts = t.lastSerial, let cs = c.lastSerial {
            print("""
              兩顆最後 serial：大腿=\(ts) 小腿=\(cs) → \(ts == cs ? "⚠️ 相同，需再觀察是否為巧合" : "✅ 不同，符合各自獨立計數")
            """)
        }

        // ---- 階段 1：回歸自檢（§7.1）----
        print("\n---- 回歸自檢（§9 階段 1 / §7.1）----")
        let nominal = BLEDeviceClock.nominalPeriodMs
        for (id, label) in [(thighId, "大腿"), (calfId, "小腿")] {
            guard let clock = tkeClock[id] else { continue }
            guard let f = clock.fit() else {
                print("[\(label)] 觀測點不足（\(clock.pointCount) < \(BLEDeviceClock.minPointsForFit)），無法擬合")
                continue
            }
            let deviationPct = (f.b - nominal) / nominal * 100
            print("""
            [\(label)]
              a = \(String(format: "%.1f", f.a)) ms（相對 session t0）
              b = \(String(format: "%.4f", f.b)) ms/sample → 實測取樣率 \(String(format: "%.2f", f.measuredRateHz)) Hz
                  與標稱 \(String(format: "%.4f", nominal))ms（104Hz）偏差 \(String(format: "%+.2f", deviationPct))%
              殘差標準差 = \(String(format: "%.1f", f.residualStdMs)) ms  ← 這就是實際的 BLE 到達抖動量
              觀測點 = \(f.pointCount)   重置次數 = \(clock.resetCount)
            """)
        }

        // 兩顆的相對時脈差：決定長時間下的漂移速度
        if let tf = tkeClock[thighId]?.fit(), let cf = tkeClock[calfId]?.fit() {
            let ratio = tf.b / cf.b
            let driftMsPerMin = abs(ratio - 1.0) * 60_000
            print("""
              兩顆 b 比值 = \(String(format: "%.6f", ratio))
              → 相對時脈差 \(String(format: "%.4f", abs(ratio - 1.0) * 100))%，
                若只用單次錨定，每分鐘會累積約 \(String(format: "%.1f", driftMsPerMin)) ms 的對齊誤差
                （本架構兩側各自回歸，此項已被吸收）
            """)
        }
        // ---- 階段 2：平滑與 buffer 自檢 ----
        print("\n---- 收集自檢（§9 階段 2）----")
        for (id, label) in [(thighId, "大腿"), (calfId, "小腿")] {
            let buffered = tkeBuffers[id]?.count ?? 0
            let warmup = tkeSmoothers[id]?.warmupDiscarded ?? 0
            let packets = tkeProbes[id]?.packetCount ?? 0
            let expectedTotal = packets * 20                       // 若不丟棄、不裁切
            let cap = Self.tkeLiveBufferCapacity
            let firstK = tkeBuffers[id]?.first?.k ?? -1
            let lastK = tkeBuffers[id]?.last?.k ?? -1
            print("""
            [\(label)]
              buffer 筆數   = \(buffered)（上限 \(cap)）\(buffered <= cap ? "✅ 未超過上限" : "❌ 超過上限")
              暖機丟棄      = \(warmup) 筆 \(warmup == KneeCalibration.smoothWindow - 1 ? "✅ 正好 N-1=\(KneeCalibration.smoothWindow - 1)" : "（預期 \(KneeCalibration.smoothWindow - 1)）")
              k 範圍        = \(firstK) ~ \(lastK)
              收到樣本總數  = \(expectedTotal)（\(packets) 包 × 20）
              → 環形裁切後只留最近 \(buffered) 筆，符合「不隨時間成長」
            """)
        }

        print("""
        ---- 階段 2 驗收 ----
        ① 暖機丟棄        ：應正好 29 筆（N=30 的視窗，前 29 筆未滿）
        ② buffer 不成長   ：跑越久 buffer 筆數仍應停在 220，不隨封包數增加
        ③ k 連續性        ：lastK − firstK 應接近 219（220 筆連續索引），掉包時才會更大

        ---- 階段 1 驗收 ----
        ① b 是否收斂       ：應穩定在 9.6154ms 附近；若明顯偏離，回歸是對的、標稱值是錯的
        ② b 是否跳變       ：同一次工作階段內 b 若突然改變，代表裝置換了送包節奏（階段 0 曾觀察到 6.3 倍差異）
        ③ 殘差標準差       ：這是真實的 σ，用來取代規劃書 §4.2 假設的 30ms
        ④ 重置次數應為 0   ：正常連線下不該觸發 serial 異常判定
        """)
        print("""
        ---- 驗收判定（§9 階段 0）----
        ① 逐包 +1        ：看「serial 增量」是否幾乎全是 delta=1
        ② 掉包跳號        ：刻意拿遠裝置後，應出現 delta≥2 而非亂數
        ③ 255→0 繞回      ：繞回次數 >0 時，該次 delta 仍應是 1
        ④ 兩顆獨立計數    ：兩顆的封包數與 serial 各自前進，不同步
        ⑤ 樣本前進量      ：shift 若集中在 20 → 每包 20 筆全新，k = packetIndex*20 + i 成立
                            shift 若 <20（例如 3）→ 封包內容重疊，該公式會把時間軸灌水
                            20/shift 倍，§4.2 節①必須改成 k = packetIndex*shift + i
        ①–④ 任一不成立 → Serial 索引架構的前提不成立，必須改回到達時間錨定。
        ⑤ 不是 20 → 架構可留，但索引公式與所有時間相關常數都要重算。
        ==========================================\n
        """)
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
        DeviceViewModel().debugDumpAllDevices(tag: "startBaselineCalibration")
        let side = DeviceViewModel().fetchAnySide() ?? 0
        print("[SIDE-DIAG] startBaselineCalibration side=\(side)")
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
        // 防呆同 startTKELiveAngle：兩條 tick 都發布到 currentEstimatedRealAngle，不可同時運作（§20.2）。
        guard !isTKELiveEstimating else {
            print("[LIVE] ⚠️ TKE 即時路徑（isTKELiveEstimating）仍在運作，拒絕啟動 —— 兩條 tick 不可同時發布角度")
            return
        }
        let deviceVM = DeviceViewModel()
        deviceVM.debugDumpAllDevices(tag: "startLiveEstimateRealAngle")
        let side = deviceVM.fetchAnySide() ?? 0
        print("[SIDE-DIAG] startLiveEstimateRealAngle side=\(side) thighUUID=\(thighPeripheral.identifier) calfUUID=\(calfPeripheral.identifier)")
        guard deviceVM.fetch(side: side, limb: 0) != nil, deviceVM.fetch(side: side, limb: 1) != nil else { return }

        let thighId = thighPeripheral.identifier
        let calfId  = calfPeripheral.identifier

        publishKneeAngle(nil)   // 啟動歸零也走共用管道，不留第二個直接寫入點（§20.2）
        DispatchQueue.main.async {
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

    // MARK: - 膝角度的共用發布管道（working2-database-port-plan.md §20.2）

    /// 算出膝角度後**統一由這裡發布**：更新 UI + 依 `isRecording` 決定是否寫入 `advanced_statistics`。
    ///
    /// 新舊兩條 tick（`tickLiveEstimatedRealAngle` 舊、`tickTKELiveAngle` 新）都呼叫同一份，
    /// 確保「算完之後往哪裡去」只有一份實作 —— 寫入條件、時間戳基準、清空目標都不會走鐘。
    ///
    /// - Parameter angle: 角度值；傳 `nil` 代表**清空**（stale 保護、停止即時、停用路徑都用它）。
    ///   清空同樣必須集中在這裡，否則「發布到 A、卻清空 B」會讓角度殘留在畫面上。
    ///
    /// - Note: 動作 12 的登階路徑（`tickStepStatus`）是**第三條獨立 tick**，本次不納入，
    ///   待動作 12 遷移時一併收編（見 §20.2）。
    ///
    /// - Important: **執行緒約定**
    ///   - `nil`（清空）：任何執行緒都可以呼叫 —— 只做 `main.async`，在讀 `isRecording` 之前就 return。
    ///     停止／停用路徑那幾個呼叫點都在主執行緒，靠的就是這一點。
    ///   - **非 `nil`（發布 + 寫入）：只能從 `bleQueue` 呼叫。** 它要用 `main.sync` 讀
    ///     `isRecording`／`currentTreatmentResultId`，從主執行緒呼叫會直接死鎖。
    ///     目前兩個非 nil 呼叫點（`tickTKELiveAngle`／`tickLiveEstimatedRealAngle`）都在 bleQueue 內。
    private func publishKneeAngle(_ angle: Double?) {
        DispatchQueue.main.async { self.currentEstimatedRealAngle = angle }

        guard let angle else { return }
        #if DEBUG
        // 非 nil 路徑底下就是 main.sync，從主執行緒呼叫必然死鎖——在 Debug 就攔下來。
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        // 組間休息（未在記錄中）時暫停寫入，跟 acc/gyro/exg 的起訖規則一致。
        // 守門用 isRecording 而不是 recordingSessionActive——兩者是不同的判斷，不可混用。
        let (stillRecording, treatmentResultId) = DispatchQueue.main.sync {
            (self.isRecording, self.currentTreatmentResultId)
        }
        guard stillRecording else { return }
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        deviceVM.insertAdvancedStatistics(timestamp: ts, angle: angle, treatmentResultId: treatmentResultId)
    }

    /// Timer callback（main thread 觸發），跳回 bleQueue 讀最新值計算，算完再寫回主執行緒的 UI 屬性。
    private func tickLiveEstimatedRealAngle() {
        bleQueue.async { [weak self] in
            guard let self else { return }

            // 封包新鮮度保護（working2-database-port-plan.md 17.4／18.5）：閘門用 `isLiveEstimating`，
            // 不是 `recordingSessionActive`——`recordingSessionActive` 只有 Working2 錄製期間才會是
            // true，PreWorking 期間永遠是 false，如果這裡看 `recordingSessionActive`，PreWorking 動作
            // 測試整段清空邏輯永遠不會執行，角度會停在斷線前最後一個值，變不回「等待資料...」（這是
            // PreWorking 獨立 Channel A 實作完成後、實測時發現的真實 bug）。`isLiveEstimating` 從
            // PreWorking 動作測試面板啟動開始、一路連續到 Working2 結束（含組間休息）才會變 false，
            // 不會有轉場空窗，而且 `recordingSessionActive` 為 true 的範圍完全被包含在
            // `isLiveEstimating` 為 true 的範圍裡，不會漏掉 Working2 原本想涵蓋的情況。組間休息時
            // `isLiveEstimating` 仍是 true，會多做幾次無害的重複判斷，但不影響正確性、也不觸發任何
            // BLE 動作（見 18.5 節）。只清「真的 stale 的那一側」incline，currentEstimatedRealAngle
            // 不分哪一側 stale 一律清成 nil，才能讓下面既有的 nil-guard／畫面/`.onChange` 正確反映
            // 「資料不可信」。
            if isLiveEstimating {
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
                    self.publishKneeAngle(nil)
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
            self.publishKneeAngle(rounded)
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
            // 原本這裡會建立 advanced_statistics 記錄用的換算表（stepShift／stepBaselineTable，
            // 含第 19 節修正的左右膝鏡射分支）。階段 12-C 把角度寫入交給 TKE 路徑之後，
            // 那張表已無人讀取，連同計算一併移除（working12-database-port-plan.md §20.2）。
            // stepBaseline 保留 —— detectStepStatus 的狀態機還在用。
            resetStepStatus()
            stepEstimating = [thighId, calfId]

            // 🔴 TKE 路徑已啟用時**不可重送設定指令**（working12-database-port-plan.md §20.2.1①）。
            //
            // 這一段是自己寫的，不走 subscribeAllCharacteristics，所以動作 2 階段 C 加的
            // `sendConfigCommands` 參數涵蓋不到這裡。實測已證實重送 cmd_a0/a1/a2 會讓取樣短暫中斷，
            // tkeClock 的交叉驗證因此失敗 → 重置 → 清空 buffer 與平滑器 → 約 2 秒沒有角度
            //（working2-database-port-plan.md §20.9）。
            //
            // 動作 12 是唯一在 TKE 路徑啟用後仍會呼叫本函式的動作（動作 2／9 已停用舊即時路徑），
            // 所以也是唯一會踩到這件事的動作。裝置在校正階段就已收過設定指令且正在串流，
            // 這裡再送一次是純粹的傷害。setNotifyValue 是冪等的，維持無條件呼叫。
            let tkePathActive = DispatchQueue.main.sync { self.isTKEPathActive }
            for peripheral in [thighPeripheral, calfPeripheral] {
                guard let map = charMap[peripheral.identifier] else { continue }
                if !wasRecording, !tkePathActive, let writeChar = map[CBUUID(string: config.write_uuid)] {
                    peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
                    peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
                }
                if let c = map[CBUUID(string: config.sub_acc_uuid)] { peripheral.setNotifyValue(true, for: c) }
            }
            print("[STEP] 登階狀態預估啟動（重送設定指令=\(!wasRecording && !tkePathActive)）")
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
            let (wasRecording, tkePathActive) = DispatchQueue.main.sync {
                (self.isRecording, self.isTKEPathActive)
            }
            stepEstimating = []
            resetStepStatus()
            // 🔴 TKE 路徑仍啟用時**不可關 ACC notify**（working12-database-port-plan.md §20.2.1②）。
            //
            // startTKEPath 只訂閱 ACC —— 這一關就把 TKE 路徑的唯一資料來源切斷了，
            // 而本函式原本的判斷條件只有 !wasRecording，完全不知道 TKE 路徑的存在。
            //
            // 目前唯一會走到的路徑是「按返回離開 PreWorking_12」，後面緊接著根 View 的
            // stopTKEPath()，所以影響有限 —— 但那是靠兩個 .onDisappear 的執行順序僥倖成立，
            // 而執行順序是 SwiftUI 的實作細節，不是保證。日後若出現「退回校正面板」的路徑，
            // 這一關會在 TKE 路徑仍需存活時切斷它，校正頁的角度直接死掉且沒有錯誤訊息。
            //
            // 交給 stopTKEPath 統一收尾，與「notify 與 tkeCollecting 同生共死」的原則一致。
            if !wasRecording, !tkePathActive, let config = bluetoothConfig {
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

            // 🔴 `advanced_statistics` 的寫入已於階段 12-C 移除（working12-database-port-plan.md §20.2）。
            //
            // 原本這裡會自己算 realAngle（angleToReal + 站姿對應表）並自己 insert，
            // 是寫入 advanced_statistics 的**第三條獨立 tick**，與 tickLiveEstimatedRealAngle 平行。
            // 動作 12 改用 offset 模型後，角度統一由 tickTKELiveAngle → publishKneeAngle 發布與寫入，
            // 本函式只保留登階狀態機那一半。
            //
            // ⚠️ 移除寫入與「開啟 TKE 即時路徑」必須是同一次改動：
            //   只開路徑不移除這裡 → 同一時間點寫入兩筆 angle
            //   只移除這裡不開路徑 → advanced_statistics 完全沒有資料
            // 兩種都沒有任何畫面徵兆（動作 12 的角度不上畫面）。
            //
            // 連帶：stepShift／stepBaselineTable 只服務這段寫入，移除後不再被讀取。
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
        // 無條件清掉 PreWorking 獨立 Channel A 的殘留狀態（working2-database-port-plan.md 第 19 節）：
        // 如果 PreWorking 導頁進 Working 那一刻裝置剛好瞬斷，thighAndCalfPeripherals 會回傳 nil，
        // performCleanupThenPlay 裡的 stopPreTestChannelA 就完全不會被呼叫，preTestMonitoring 殘留的話
        // 這場 Working 錄製的 acc/gyro/exg 封包會被 didUpdateValueFor 整場靜默攔截、完全不寫入資料庫。
        // 真正開始錄製後，不應該再有任何 uuid 停留在「只監控不落地寫資料庫」模式，這裡無條件清空，
        // 不管殘留是怎麼發生的都能自我修復；正常情況（stopPreTestChannelA 有成功呼叫）下這幾行只是
        // 清一個已經是 false／nil／空集合的狀態，無害。
        DispatchQueue.main.async { [weak self] in
            self?.preTestFreshnessTimer?.invalidate()
            self?.preTestFreshnessTimer = nil
        }
        bleQueue.async { [weak self] in
            self?.preTestChannelAActive = false
            self?.preTestMonitoring.removeAll()
        }
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
        // PreWorking 情境（`preTestChannelAActive`）改呼叫不設定 isRecording 的 subscribeAllCharacteristics
        // （working2-database-port-plan.md 18.3），兩種情境呼叫不同函式、不能共用同一個分支。
        if recordingSessionActive {
            startRecording(peripheral: peripheral)
        } else if preTestChannelAActive {
            subscribeAllCharacteristics(peripheral: peripheral)
        }

        // TKE 路徑同樣要補回訂閱（tke-sitting-calibration-port-plan.md §4.4）。
        // 少了這段，裝置重開後連線物件恢復了、卻永遠不再送 ACC，即時角度會卡在「等待資料…」
        // 不會自動恢復——實測就是這個症狀。
        if tkeCollecting.contains(peripheral.identifier), !tkeDraining {
            resubscribeTKEAcc(peripheral: peripheral)
        }
    }

    /// 重連後補回 TKE 的 ACC 訂閱與設定指令，並重置該側的時間軸狀態。
    ///
    /// **為什麼要明確重置，而不依賴 clock 自己的交叉驗證**：
    /// 裝置重開後 serial 會從 0 重新開始，舊的 `packetIndex` 基準失效。交叉驗證雖然能偵測
    /// 多數 serial 異常，但在長時間斷線後有機會誤判為正常——例如斷線 10 秒、serial 從 200 繞到 0
    /// 算出 delta=56，`expectedGap ≈ 10752ms` 與 `actualGap ≈ 10000ms` 只差 752ms，
    /// 低於 1000ms 容許值就不會觸發重置，於是新舊兩段不同基準的 `(k, t)` 會混進同一條回歸線。
    ///
    /// 「這裡發生過斷線」是交叉驗證沒有的資訊，所以直接重置最安全。
    /// 代價只是重新累積 10 個觀測點（約 2 秒）。
    private func resubscribeTKEAcc(peripheral: CBPeripheral) {
        guard let config = bluetoothConfig, let map = charMap[peripheral.identifier] else { return }
        let id = peripheral.identifier
        let wasRecording = DispatchQueue.main.sync { self.isRecording }

        // 三者必須同進同出：k 的編號基準變了，舊 buffer 與平滑視窗都無法與另一側對齊
        tkeClock[id] = BLEDeviceClock()
        tkeSmoothers[id] = CausalSmoother(window: KneeCalibration.smoothWindow)
        tkeBuffers[id] = []
        // session t0 刻意保留——兩顆的 a 必須落在同一時間框架，配對公式才成立

        if !wasRecording, let writeChar = map[CBUUID(string: config.write_uuid)] {
            peripheral.writeValue(config.cmd_a0, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a1, for: writeChar, type: .withResponse)
            peripheral.writeValue(config.cmd_a2, for: writeChar, type: .withResponse)
        }
        if let c = map[CBUUID(string: config.sub_acc_uuid)] {
            peripheral.setNotifyValue(true, for: c)
        }
        print("[TKE] 重連補訂閱：\(id)（clock／buffer／平滑已重置，需約 2 秒重新收斂）")
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

        // TKE 收集分支（tke-sitting-calibration-port-plan.md §4.2「didUpdateValueFor 的 TKE 分支」）：
        // 位置固定在 accOnlyCollecting 之後、liveEstimating 之前。`tkeCollecting` 只有在
        // Test 頁啟用 TKE 路徑時才非空，正式流程不受影響。
        //
        // 閘門用 `recordingSessionActive`（bleQueue 端旗標）而不是 `isRecording`：後者是主執行緒
        // 屬性，在封包路徑上讀取等於每包都阻塞等 main thread。
        //
        // `return` 必須有條件，兩個方向的風險都是真的：
        //  - 完全不 return → 未錄製時 ACC 掉到下面的 parseACC，靜默寫進 acc 表且
        //    treatment_result_id 為 nil（working2-database-port-plan.md 18.4 修過的那個問題）
        //  - 無條件 return → tkeCollecting 是常駐的，一旦使用者按「開始收集」，
        //    這場錄製的 ACC 會整場被吞掉，acc 表與匯出都是空的
        // collectTKEAcc 放在 return 判斷之前，確保兩種情況下 tkeClock 都持續更新。
        if tkeCollecting.contains(peripheral.identifier) {
            // 排空期（stopTKEPath 已關 notify、等在途封包到齊）只攔截不處理，
            // 否則會把剛清空的 buffer／clock 又重新填回去。
            if !tkeDraining, uuid == CBUUID(string: config.sub_acc_uuid) {
                // 順序固定：先 collectTKEAcc（clock 展開 + 平滑 + buffer），
                // probeTKESerial 只讀狀態做診斷，不可自己再 ingest 一次（會重複累加回歸）。
                collectTKEAcc(data, id: peripheral.identifier, config: config)
                probeTKESerial(data, id: peripheral.identifier)
            }
            if !recordingSessionActive { return }
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

        // PreWorking 獨立 Channel A「監控但不落地寫資料庫」：lastPacketAt 已經在上面更新過，
        // Channel B 需要的 handleLiveAccPacket/handleStepAccPacket 也已經在上面呼叫過，這裡直接
        // return，不落到下面 parseACC/parseGYRO/parseEXG 那段寫入資料庫的邏輯——這同時也修正了
        // 既有的問題：原本 liveEstimating 分支不 return，PreWorking 動作測試期間 ACC 封包會悄悄
        // 寫進 acc 表（treatment_result_id 為 nil）（working2-database-port-plan.md 18.4）。
        if preTestMonitoring.contains(peripheral.identifier) {
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

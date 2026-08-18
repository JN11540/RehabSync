import Foundation

/// 一筆已平滑、已定位的加速度樣本（tke-sitting-calibration-port-plan.md §4.1）。
///
/// `k` 是 Serial 展開後的全域樣本索引，**不存時間戳** —— 時間一律透過 `TKEClockFit` 換算。
/// 型別放在這裡而非 `TKECalibration.swift`（規劃書原本的位置）：`k` 本來就是 clock 的產物，
/// 而且收集層（階段 2）比演算法層（階段 4）更早需要它。
struct TKESample {
    let k: Int      // 全域樣本索引 = packetIndex * 20 + i
    let x: Double   // mg，已套用 N=30 因果移動平均
    let y: Double
    let z: Double
}

/// 因果移動平均（tke-sitting-calibration-port-plan.md §4.2 收集步驟 4-5）。
///
/// 在**原始 x/y/z 域**做平滑，不是角度域。視窗未滿前一律丟棄（§5.1 暖機期處理）——
/// Python 靠 3 秒穩定期讓視窗在收集開始前就填滿，App 不設穩定期，
/// 所以改成「未滿就不輸出」，代價僅 29 筆 ≈ 0.28 秒。
struct TKECausalSmoother {
    static let window = 30

    private var buf: [(x: Double, y: Double, z: Double)] = []
    private var head = 0
    private var sumX = 0.0, sumY = 0.0, sumZ = 0.0

    /// 已因暖機未滿而丟棄的樣本數（診斷用）
    private(set) var warmupDiscarded = 0

    /// 推入一筆原始樣本；視窗未滿時回傳 nil。
    mutating func push(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double)? {
        if buf.count < Self.window {
            buf.append((x, y, z))
            sumX += x; sumY += y; sumZ += z
            if buf.count < Self.window {
                warmupDiscarded += 1
                return nil
            }
        } else {
            // 環形覆寫：扣掉最舊的、加上最新的，維持 O(1)
            let old = buf[head]
            sumX += x - old.x
            sumY += y - old.y
            sumZ += z - old.z
            buf[head] = (x, y, z)
            head = (head + 1) % Self.window
        }
        let n = Double(Self.window)
        return (sumX / n, sumY / n, sumZ / n)
    }

    /// clock 重置時一併呼叫 —— 重置後樣本的 `k` 落在新的編號基準，
    /// 舊視窗裡的資料已無法與另一側對齊，繼續沿用只會產生錯誤的平滑值。
    mutating func reset() {
        buf.removeAll(keepingCapacity: true)
        head = 0
        sumX = 0; sumY = 0; sumZ = 0
    }
}

/// 單一裝置的回歸擬合結果（tke-sitting-calibration-port-plan.md §4.1）。
/// `a`／`b` 供跨裝置配對換算 `k_c`，`pointCount` 供校正失敗時的步驟 5a 判斷。
struct TKEClockFit {
    let a: Double              // 截距（ms，相對於 session t0）
    let b: Double              // 實測取樣週期（ms/sample）
    let pointCount: Int        // 回歸觀測點數
    let residualStdMs: Double  // 殘差標準差＝實際 BLE 到達抖動量（§7.1 自檢用）

    /// 樣本索引 → 主機時刻（ms，相對於 session t0）
    func time(at k: Int) -> Double { a + b * Double(k) }

    /// 主機時刻 → 樣本索引（四捨五入到最近的整數索引）
    func sampleIndex(atTime t: Double) -> Int { Int(((t - a) / b).rounded()) }

    /// 由 `b` 反推的實測取樣率（Hz）
    var measuredRateHz: Double { b > 0 ? 1000.0 / b : 0 }
}

/// 單一裝置的時間軸狀態（tke-sitting-calibration-port-plan.md §4.2 節①②）。
///
/// 兩件事分開處理：
/// - **順序**：用封包的 Serial No 展開成單調遞增的全域樣本索引 `k`，完全不受到達時間影響。
/// - **對應**：用到達時間對 `k` 做增量最小平方回歸，估出 `k → 主機時鐘` 的映射。
///
/// 時間一律使用「相對於 session t0 的毫秒」而非 epoch 毫秒 —— 見 `ingest` 的說明。
struct TKEDeviceClock {

    // MARK: - 常數

    /// 標稱取樣週期（104Hz）。只在回歸尚未可信時，充當交叉驗證的後備估計值。
    static let nominalPeriodMs = 1000.0 / 104.0
    /// 每個封包帶幾筆樣本（§9 階段 0 實測 shift=20，零重疊）
    static let samplesPerPacket = 20
    /// 回歸至少要這麼多觀測點才可信（§4.2 節④）
    static let minPointsForFit = 10
    /// serial 推算的間隔與實際到達間隔差距超過這個值，視為 serial 異常並重置
    static let crossCheckToleranceMs = 1000.0

    // MARK: - Serial 展開狀態

    private(set) var lastSerial: UInt8?
    private(set) var packetIndex = 0
    private(set) var lastArrivalMs: Double?

    // MARK: - 增量最小平方累加量
    // 為了數值精度，`t` 必須是「相對於 session t0」的毫秒，不能用 epoch 毫秒：
    // epoch ms ≈ 1.7e12，平方後 ≈ 3e24，Double 只有約 16 位有效數字，
    // 算 SSE 時的大數相減會把整個殘差資訊吃掉。

    private(set) var sumK = 0.0
    private(set) var sumT = 0.0
    private(set) var sumKK = 0.0
    private(set) var sumKT = 0.0
    private(set) var sumTT = 0.0
    private(set) var pointCount = 0

    /// 因 serial 異常而重置的次數（診斷用）
    private(set) var resetCount = 0

    // MARK: - 結果

    enum Outcome: Equatable {
        /// 正常收下，回傳本包 20 筆樣本的起始索引（樣本 i 的索引為 firstK + i）
        case accepted(firstK: Int)
        /// serial 沒有前進，視為重複封包，丟棄
        case duplicate
        /// serial 與到達時間對不上（計數器被重置、或掉包超過 256 包），已重置狀態後收下本包
        case reset(firstK: Int)
    }

    // MARK: - 主流程

    /// 收下一個封包。
    /// - Parameters:
    ///   - serial: 封包的 Serial No（`data[2]`）
    ///   - arrivalMs: 到達時間，**相對於 session t0 的毫秒**
    mutating func ingest(serial: UInt8, arrivalMs: Double) -> Outcome {
        guard let last = lastSerial else {
            // 第一包：直接錨定，不做交叉驗證
            lastSerial = serial
            lastArrivalMs = arrivalMs
            packetIndex = 0
            addObservation(k: lastSampleIndex(ofPacket: 0), t: arrivalMs)
            return .accepted(firstK: 0)
        }

        let delta = (Int(serial) - Int(last) + 256) % 256
        if delta == 0 { return .duplicate }

        // 交叉驗證（§4.2「Serial 計數器異常的偵測」）：
        // serial 推算出的時間間隔應與實際到達間隔相符。用已擬合的 b 當基準比用標稱值更穩健——
        // §9 階段 0 曾觀察到封包率與標稱值差 6.3 倍的情況，此時標稱值會誤判。
        let periodMs = fit()?.b ?? Self.nominalPeriodMs
        let expectedGap = Double(delta * Self.samplesPerPacket) * periodMs
        let actualGap = arrivalMs - (lastArrivalMs ?? arrivalMs)

        if abs(expectedGap - actualGap) > Self.crossCheckToleranceMs {
            // packetIndex / lastSerial / 回歸累加量必須同進同出，
            // 否則新舊兩段不同編號基準的 (k, t) 會混在同一條回歸線裡。
            reset()
            resetCount += 1
            lastSerial = serial
            lastArrivalMs = arrivalMs
            packetIndex = 0
            addObservation(k: lastSampleIndex(ofPacket: 0), t: arrivalMs)
            return .reset(firstK: 0)
        }

        packetIndex += delta
        lastSerial = serial
        lastArrivalMs = arrivalMs
        addObservation(k: lastSampleIndex(ofPacket: packetIndex), t: arrivalMs)
        return .accepted(firstK: packetIndex * Self.samplesPerPacket)
    }

    /// 目前的擬合結果；觀測點不足時回傳 nil。
    func fit() -> TKEClockFit? {
        guard pointCount >= Self.minPointsForFit else { return nil }
        let n = Double(pointCount)
        let denom = n * sumKK - sumK * sumK
        guard abs(denom) > .ulpOfOne else { return nil }

        let b = (n * sumKT - sumK * sumT) / denom
        let a = (sumT - b * sumK) / n

        // SSE = Σ(t − a − b·k)² = ΣT² − a·ΣT − b·ΣKT（最小平方的標準恆等式，O(1) 求得）
        let sse = sumTT - a * sumT - b * sumKT
        let residualStd = pointCount > 2 ? (max(0, sse) / Double(pointCount - 2)).squareRoot() : 0

        return TKEClockFit(a: a, b: b, pointCount: pointCount, residualStdMs: residualStd)
    }

    /// 清空所有狀態（`resetCount` 除外，那是跨重置的累計診斷值）。
    mutating func reset() {
        lastSerial = nil
        packetIndex = 0
        lastArrivalMs = nil
        sumK = 0; sumT = 0; sumKK = 0; sumKT = 0; sumTT = 0
        pointCount = 0
    }

    // MARK: - Private

    /// 觀測點取封包的**最後一筆**樣本索引 —— 因為封包是「集滿 20 筆才送出」，
    /// 最後一筆的取樣時刻最接近送出時刻。兩顆裝置用同一個約定，任何固定偏移都會在配對時抵消。
    private func lastSampleIndex(ofPacket index: Int) -> Int {
        index * Self.samplesPerPacket + (Self.samplesPerPacket - 1)
    }

    private mutating func addObservation(k: Int, t: Double) {
        let kd = Double(k)
        sumK += kd
        sumT += t
        sumKK += kd * kd
        sumKT += kd * t
        sumTT += t * t
        pointCount += 1
    }
}

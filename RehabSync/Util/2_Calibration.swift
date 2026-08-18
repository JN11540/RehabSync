import Foundation

/// 校正結果（tke-sitting-calibration-port-plan.md §4.1）。
///
/// `thigh`／`calf` 恆同時有值或同時為 nil，呼叫端用 `if let thigh, let calf` 判定成功；
/// `message` 不論成功失敗都可直接顯示。
///
/// `side` 一律回填 —— 即時階段必須確認「現在綁定的側」與「校正當時的側」相同，
/// 否則 `k` 值符號相反會產生完全錯誤的角度，而畫面上不會有任何異常徵兆。
struct TKECalibrationResult {
    let thigh: Double?    // 成功 = o_thigh；失敗 = nil
    let calf: Double?     // 成功 = o_calf； 失敗 = nil
    let message: String   // 成功 = "校正成功"；失敗 = 對應提示
    let side: Int         // 校正當下的綁定側（0=左 1=右）

    var succeeded: Bool { thigh != nil && calf != nil }
}

/// TKE（終端膝伸展）坐姿校正的演算法本體。
/// 對照 tke-sitting-calibration-port-plan.md §4.1，移植自 calibrate_tke_left/right.py 與 tke_live_left/right.py。
///
/// **不依賴任何 BLE 狀態**，輸入全是普通資料，可用合成資料單獨驗證。
/// （帶有診斷 `print` 副作用，見 §5.2 —— 除錯頁階段刻意如此。）
///
/// 與 Python 的差異都是刻意的，理由見規劃書：
/// - 配對用 Serial 索引 + 回歸解析換算，不用最近鄰搜尋（§4.2）
/// - 姿勢門檻額外加方向檢查，避免 180° 翻轉通過（§4.1 步驟 3）
/// - 失敗時依「先看合格數，不足才判斷原因」的順序分類（§4.1 步驟 5）
enum TKECalibration {

    // MARK: - 常數

    /// 因果移動平均的視窗長度（≈0.29 秒 @104Hz）。
    /// `CausalSmoother` 本身是通用的，視窗長度屬於動作層的參數，所以在這裡宣告。
    static let smoothWindow = 30
    /// 姿勢門檻（mg）：該歸零的軸必須小於這個值
    static let postureThresholdMG = 400.0
    /// 方向檢查的容許範圍（度）：算出的 alpha 必須落在真值 ±這個範圍內
    static let directionToleranceDeg = 30.0
    /// 最少合格樣本數。沿用 Python 現值。
    static let minQualifiedSamples = 250
    /// 回歸觀測點少於這個數就視為不可信（與 BLEDeviceClock.minPointsForFit 一致）
    static let minRegressionPoints = 10
    /// 實收封包數低於這個值就視為封包遺失嚴重（只在失敗後用來解釋原因，訂寬訂窄都不會誤殺）
    static let minPacketCount = 20

    /// TKE 校正姿勢的真值：大腿水平
    static let alphaThighTrueDeg = 90.0
    /// TKE 校正姿勢的真值：小腿鉛直
    static let alphaShankTrueDeg = 0.0

    /// 左腳 k=+1、右腳 k=−1（膝關節矢狀面傾角量測_方法學 §4.4）
    static func kValue(side: Int) -> Double { side == 1 ? -1.0 : 1.0 }
    /// 小腿經驗校正係數：左腳 1.167、右腳 1.2。
    /// ⚠️ 來源不明，見規劃書第 8 節；校正與即時兩邊必須一致。
    static func calfCoefficient(side: Int) -> Double { side == 1 ? 1.2 : 1.167 }

    // MARK: - 角度公式

    /// alpha_thigh_raw = atan2(k·ax, −ay)
    static func alphaThighRaw(_ s: BLESample, side: Int) -> Double {
        atan2(kValue(side: side) * s.x, -s.y) * 180 / .pi
    }

    /// alpha_shank_raw = atan2(−k·ax, ay)
    static func alphaShankRaw(_ s: BLESample, side: Int) -> Double {
        atan2(-kValue(side: side) * s.x, s.y) * 180 / .pi
    }

    // MARK: - 姿勢判定

    /// 大腿是否處於校正姿勢（水平）。
    /// 方向檢查**併入**這裡而非獨立一層 —— 步驟 5d 的訊息是依 `thighOnlyPass` 計數分類的，
    /// 方向檢查若在計數之外，會出現「計數說合格、實際卻被剔除」的不一致（§4.1 步驟 3）。
    static func checkThigh(_ s: BLESample, side: Int) -> Bool {
        guard abs(s.y) < postureThresholdMG, abs(s.z) < postureThresholdMG else { return false }
        return abs(alphaThighRaw(s, side: side) - alphaThighTrueDeg) < directionToleranceDeg
    }

    /// 小腿是否處於校正姿勢（鉛直）。方向檢查同樣併入。
    static func checkCalf(_ s: BLESample, side: Int) -> Bool {
        guard abs(s.x) < postureThresholdMG, abs(s.z) < postureThresholdMG else { return false }
        return abs(alphaShankRaw(s, side: side) - alphaShankTrueDeg) < directionToleranceDeg
    }

    // MARK: - 跨裝置配對（校正與即時共用這一份）

    /// 找出大腿樣本 `kThigh` 對應的小腿樣本。
    ///
    /// 換算 `k_c` 後在 `calfSamples` 中查找**確切的索引**，找不到回傳 nil。
    /// **絕不外插、絕不取最近鄰替代** —— 那會讓小腿斷線時安靜地拿舊資料當有效配對
    /// （對應 Python `calf_find_nearest` 不檢查配對距離的缺陷）。
    ///
    /// 必須是「存在檢查」而非「範圍檢查」：只驗 `k_c` 落在 `[k_min, k_max]` 之間
    /// 擋得住尾端掉包，但擋不住**中間**掉包 —— `k_c` 可能落在範圍內卻對應到一段遺失的封包。
    ///
    /// - Note: 校正與即時都必須呼叫這一份，不可各寫一份。這段邏輯帶著多條「不得如何」的限制，
    ///   重複實作等於把限制也複製一遍，遲早有一邊漏掉。
    static func findPair(
        kThigh: Int, thighFit: BLEClockFit,
        calfSamples: [BLESample], calfFit: BLEClockFit
    ) -> BLESample? {
        guard calfFit.b > 0 else { return nil }
        let hostTime = thighFit.time(at: kThigh)
        let kc = calfFit.sampleIndex(atTime: hostTime)

        // calfSamples 依 k 遞增，二分搜尋確切索引
        var lo = 0, hi = calfSamples.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = calfSamples[mid].k
            if k == kc { return calfSamples[mid] }
            if k < kc { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    // MARK: - 即時角度

    /// theta = (alpha_thigh_raw − o_thigh) − (alpha_shank_raw × C − o_calf)
    ///
    /// **不做 0–90 夾限**，超出範圍照實輸出（規劃書第 0 節決策）。
    /// 完全伸直時 theta 會落到負值是增益補償的預期行為，不是錯誤。
    static func liveAngle(
        thigh: BLESample, calf: BLESample,
        side: Int, oThigh: Double, oCalf: Double
    ) -> Double {
        let thighRaw = alphaThighRaw(thigh, side: side)
        let shankRaw = alphaShankRaw(calf, side: side) * calfCoefficient(side: side)
        return (thighRaw - oThigh) - (shankRaw - oCalf)
    }

    // MARK: - 校正主流程

    static func computeOffsets(
        thighSamples: [BLESample], calfSamples: [BLESample], side: Int,
        thighFit: BLEClockFit, calfFit: BLEClockFit,
        thighPacketCount: Int, calfPacketCount: Int
    ) -> TKECalibrationResult {

        // ---- 步驟 1：連線檢查（Python 沒有這一步）----
        // 沒有這一步的話，斷線會落入下面的「姿勢皆不符合門檻」，使用者會被誤導去反覆調整擺位。
        // 註：樣本要通過 N=30 平滑暖機才進 buffer，所以「完全無樣本」的實際門檻是未送滿 2 個封包。
        if thighSamples.isEmpty || calfSamples.isEmpty {
            let msg: String
            if thighSamples.isEmpty && calfSamples.isEmpty {
                msg = "大腿與小腿感測器都沒有資料，請確認裝置連線"
            } else if thighSamples.isEmpty {
                msg = "大腿感測器沒有資料，請確認裝置連線"
            } else {
                msg = "小腿感測器沒有資料，請確認裝置連線"
            }
            printDiagnostics(side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                             thighFit: thighFit, calfFit: calfFit,
                             thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                             pairedCount: 0, thighOnlyPass: 0, calfOnlyPass: 0, qualified: 0,
                             message: msg)
            return TKECalibrationResult(thigh: nil, calf: nil, message: msg, side: side)
        }

        // ---- 步驟 2/3：逐筆配對並套姿勢門檻 ----
        var pairedCount = 0
        var thighOnlyPass = 0
        var calfOnlyPass = 0
        var qualifiedThighAlpha: [Double] = []
        var qualifiedShankAlpha: [Double] = []

        for t in thighSamples {
            guard let c = findPair(kThigh: t.k, thighFit: thighFit,
                                   calfSamples: calfSamples, calfFit: calfFit) else { continue }
            pairedCount += 1

            let thighOK = checkThigh(t, side: side)
            let calfOK = checkCalf(c, side: side)
            if thighOK { thighOnlyPass += 1 }
            if calfOK { calfOnlyPass += 1 }
            // 兩邊同時合格才採計
            if thighOK && calfOK {
                qualifiedThighAlpha.append(alphaThighRaw(t, side: side))
                qualifiedShankAlpha.append(alphaShankRaw(c, side: side))
            }
        }

        let qualified = qualifiedThighAlpha.count

        // ---- 步驟 4：合格數達標 ----
        if qualified >= minQualifiedSamples {
            let C = calfCoefficient(side: side)
            let meanThigh = qualifiedThighAlpha.reduce(0, +) / Double(qualified)
            let meanShank = qualifiedShankAlpha.reduce(0, +) / Double(qualified)
            let oThigh = meanThigh - alphaThighTrueDeg
            let oCalf = meanShank * C - alphaShankTrueDeg

            let msg = "校正成功"
            printDiagnostics(side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                             thighFit: thighFit, calfFit: calfFit,
                             thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                             pairedCount: pairedCount, thighOnlyPass: thighOnlyPass,
                             calfOnlyPass: calfOnlyPass, qualified: qualified, message: msg,
                             extra: String(format: "meanThigh=%.2f° meanShank=%.2f° C=%.3f → o_thigh=%.2f° o_calf=%.2f°",
                                           meanThigh, meanShank, C, oThigh, oCalf))
            return TKECalibrationResult(thigh: oThigh, calf: oCalf, message: msg, side: side)
        }

        // ---- 步驟 5：合格數不足，依序判斷原因 ----
        // ⚠️ 順序很重要：一定要「先看合格數，不足時才判斷原因」。
        // 若把封包數檢查放在合格數之前當閘門，會誤殺原本能成功的校正
        // （例如只收到 50% 封包仍遠高於 250 門檻）。
        let msg: String
        if thighFit.pointCount < minRegressionPoints || calfFit.pointCount < minRegressionPoints {
            // 5a：回歸不可信
            msg = "收到的資料量不足以完成校正，請確認裝置連線後重新校正"
        } else if thighPacketCount < minPacketCount || calfPacketCount < minPacketCount {
            // 5b：封包遺失嚴重。並列兩側實收數，兩側共用同一收集窗，彼此就是最好的參照。
            msg = "封包遺失嚴重（大腿 \(thighPacketCount) 包 / 小腿 \(calfPacketCount) 包），請確認裝置距離與電量"
        } else if pairedCount < thighSamples.count / 2 {
            // 5c：配對大量失敗但封包數正常。必須排在 5b 之後（掉包是配對失敗的根因）、
            // 5d 之前（配對失敗會連帶壓低 thighOnlyPass／calfOnlyPass，不先攔會被誤報成姿勢問題）。
            msg = "大腿與小腿資料無法對齊，請重新校正；若持續發生請回報"
        } else {
            // 5d：姿勢問題，四分類（逐字沿用 calibrate_tke_right.py:241-248）
            let thighBad = thighOnlyPass < minQualifiedSamples
            let calfBad = calfOnlyPass < minQualifiedSamples
            if thighBad && calfBad {
                msg = "大腿與小腿姿勢皆不符合門檻，請重新擺位後再校正"
            } else if thighBad {
                msg = "大腿姿勢不符合門檻，小腿正常，請調整大腿擺位"
            } else if calfBad {
                msg = "小腿姿勢不符合門檻，大腿正常，請調整小腿擺位"
            } else {
                msg = "大腿與小腿個別都達到門檻，但沒有同時成立，請確認兩者是否同步靜止在校正姿勢"
            }
        }

        printDiagnostics(side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                         thighFit: thighFit, calfFit: calfFit,
                         thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                         pairedCount: pairedCount, thighOnlyPass: thighOnlyPass,
                         calfOnlyPass: calfOnlyPass, qualified: qualified, message: msg)
        return TKECalibrationResult(thigh: nil, calf: nil, message: msg, side: side)
    }

    // MARK: - 診斷輸出（§5.2）

    /// 整組診斷欄位統一由這裡輸出，不另外定義第二套。
    /// 唯一的例外是回歸殘差標準差 —— 它在 `BLEClockFit` 裡，所以這裡也印得出來。
    private static func printDiagnostics(
        side: Int,
        thighSamples: [BLESample], calfSamples: [BLESample],
        thighFit: BLEClockFit, calfFit: BLEClockFit,
        thighPacketCount: Int, calfPacketCount: Int,
        pairedCount: Int, thighOnlyPass: Int, calfOnlyPass: Int, qualified: Int,
        message: String, extra: String? = nil
    ) {
        print("""

        ========== [TKE-CAL] 校正診斷（side=\(side == 1 ? "右" : "左")）==========
          實收封包       大腿=\(thighPacketCount)  小腿=\(calfPacketCount)（門檻 \(minPacketCount)）
          回歸觀測點     大腿=\(thighFit.pointCount)  小腿=\(calfFit.pointCount)（門檻 \(minRegressionPoints)）
          回歸 b         大腿=\(String(format: "%.4f", thighFit.b))ms  小腿=\(String(format: "%.4f", calfFit.b))ms
          回歸殘差       大腿=\(String(format: "%.1f", thighFit.residualStdMs))ms  小腿=\(String(format: "%.1f", calfFit.residualStdMs))ms
          進入計算樣本   大腿=\(thighSamples.count)  小腿=\(calfSamples.count)
          成功配對       \(pairedCount)（佔大腿樣本 \(thighSamples.isEmpty ? 0 : pairedCount * 100 / thighSamples.count)%）
          姿勢通過       大腿=\(thighOnlyPass)  小腿=\(calfOnlyPass)  同時=\(qualified)（門檻 \(minQualifiedSamples)）
        \(extra.map { "  \($0)\n" } ?? "")  → \(message)
        ==========================================================

        """)
    }
}

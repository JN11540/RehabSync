import Foundation

/// 膝關節校正的**共用引擎** —— 與動作無關。
///
/// 各動作的差異全部收斂到 `KneeCalibrationSpec`（真值、姿勢檢查軸、經驗係數），
/// 流程本身（連線檢查 → 配對 → 姿勢門檻 → 合格數判定 → 失敗分類 → 診斷輸出）只有這一份。
///
/// 動作規格見 `2_Calibration.swift`（TKE 坐姿）、`9_Calibration.swift`（部分蹲站立）。
/// 移植依據見 tke-sitting-calibration-port-plan.md 與 9-calibration-port-plan.md。

// MARK: - 結果

/// 校正結果。
///
/// `thigh`／`calf` 恆同時有值或同時為 nil，呼叫端用 `if let` 判定成功；
/// `message` 不論成功失敗都可直接顯示。
///
/// `side` 一律回填 —— 即時階段必須確認「現在綁定的側」與「校正當時的側」相同，
/// 否則 `k` 值符號相反會產生完全錯誤的角度，而畫面上不會有任何異常徵兆。
struct KneeCalibrationResult {
    let thigh: Double?    // 成功 = o_thigh；失敗 = nil
    let calf: Double?     // 成功 = o_calf； 失敗 = nil
    let message: String   // 成功 = "校正成功"；失敗 = 對應提示
    let side: Int         // 校正當下的綁定側（0=左 1=右）

    var succeeded: Bool { thigh != nil && calf != nil }
}

// MARK: - 動作規格

/// 單一動作的校正規格。新增動作時只需實作這個 protocol，流程不必重寫。
protocol KneeCalibrationSpec {
    /// 診斷輸出用的動作名稱
    static var name: String { get }

    /// 校正姿勢下大腿的真實角度
    static var alphaThighTrueDeg: Double { get }
    /// 校正姿勢下小腿的真實角度
    static var alphaShankTrueDeg: Double { get }

    /// 大腿姿勢檢查：回傳「校正姿勢下應歸零的那一軸」的值。
    /// 例如大腿水平時取 `ay`、大腿鉛直時取 `ax`。
    static func thighPostureAxis(_ s: BLESample) -> Double
    /// 小腿姿勢檢查，同上。
    static func calfPostureAxis(_ s: BLESample) -> Double

    /// 經驗校正係數，回傳套在**大腿**與**小腿**上的倍率；未套用的那一段給 `1.0`。
    ///
    /// 刻意設計成一對而非單一數值 —— 不同動作把係數放在不同肢段
    /// （TKE 坐姿在小腿、部分蹲在大腿），回傳一對之後「係數換邊」變成純資料差異，
    /// 引擎完全不必知道哪個動作把係數放在哪邊。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double)

    /// 姿勢門檻（mg）。站姿動作若實測通過率偏低可個別放寬。
    static var postureThresholdMG: Double { get }
    /// 方向檢查容許範圍（度）
    static var directionToleranceDeg: Double { get }
    /// 最少合格樣本數
    static var minQualifiedSamples: Int { get }
}

extension KneeCalibrationSpec {
    static var postureThresholdMG: Double { 400.0 }
    static var directionToleranceDeg: Double { 30.0 }
    static var minQualifiedSamples: Int { 250 }
}

// MARK: - 引擎

enum KneeCalibration {

    /// 因果移動平均視窗（≈0.29 秒 @104Hz）。
    ///
    /// 目前所有動作都用 30，所以放在引擎層。**這不是「不能各動作不同」，而是
    /// 平滑器在 TKE 路徑啟用當下就要建立，那時還不知道要跑哪個動作** ——
    /// 若日後某動作需要不同視窗，得先讓路徑啟用時就帶入動作資訊。
    static let smoothWindow = 30

    /// 回歸觀測點少於這個數就視為不可信（與 `BLEDeviceClock.minPointsForFit` 一致）
    static let minRegressionPoints = 10
    /// 實收封包數低於這個值就視為封包遺失嚴重。
    /// 只在失敗後用來解釋原因，訂寬訂窄都不會誤殺。
    static let minPacketCount = 20

    /// 左腳 k=+1、右腳 k=−1（膝關節矢狀面傾角量測_方法學 §4.4）
    static func kValue(side: Int) -> Double { side == 1 ? -1.0 : 1.0 }

    /// alpha_thigh_raw = atan2(k·ax, −ay)
    static func alphaThighRaw(_ s: BLESample, side: Int) -> Double {
        atan2(kValue(side: side) * s.x, -s.y) * 180 / .pi
    }

    /// alpha_shank_raw = atan2(−k·ax, ay)
    static func alphaShankRaw(_ s: BLESample, side: Int) -> Double {
        atan2(-kValue(side: side) * s.x, s.y) * 180 / .pi
    }

    /// 角度差正規化到 (−180, 180]。
    ///
    /// 方向檢查用。目前兩個動作的真值是 90° 與 0°，離 ±180 很遠，直接相減也不會出錯；
    /// 但若日後有動作的真值接近 ±180，直接相減會因環繞而誤判，所以在這裡先處理掉。
    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    // MARK: - 姿勢判定

    /// 大腿是否處於校正姿勢。
    ///
    /// 方向檢查**併入**這裡而非獨立一層 —— 失敗分類的訊息是依 `thighOnlyPass` 計數決定的，
    /// 方向檢查若在計數之外，會出現「計數說合格、實際卻被剔除」的不一致。
    static func checkThigh(_ spec: any KneeCalibrationSpec.Type, _ s: BLESample, side: Int) -> Bool {
        guard abs(spec.thighPostureAxis(s)) < spec.postureThresholdMG,
              abs(s.z) < spec.postureThresholdMG else { return false }
        return abs(angleDiff(alphaThighRaw(s, side: side), spec.alphaThighTrueDeg)) < spec.directionToleranceDeg
    }

    /// 小腿是否處於校正姿勢。方向檢查同樣併入。
    static func checkCalf(_ spec: any KneeCalibrationSpec.Type, _ s: BLESample, side: Int) -> Bool {
        guard abs(spec.calfPostureAxis(s)) < spec.postureThresholdMG,
              abs(s.z) < spec.postureThresholdMG else { return false }
        return abs(angleDiff(alphaShankRaw(s, side: side), spec.alphaShankTrueDeg)) < spec.directionToleranceDeg
    }

    // MARK: - 跨裝置配對（完全與動作無關）

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

    /// theta = (alpha_thigh_raw × C_thigh − o_thigh) − (alpha_shank_raw × C_calf − o_calf)
    ///
    /// **不做夾限**，超出範圍照實輸出。動作 2 完全伸直時 theta 會落到負值，
    /// 那是增益補償的預期行為，不是錯誤。
    static func liveAngle(
        spec: any KneeCalibrationSpec.Type,
        thigh: BLESample, calf: BLESample,
        side: Int, oThigh: Double, oCalf: Double
    ) -> Double {
        let c = spec.coefficients(side: side)
        let thighRaw = alphaThighRaw(thigh, side: side) * c.thigh
        let shankRaw = alphaShankRaw(calf, side: side) * c.calf
        return (thighRaw - oThigh) - (shankRaw - oCalf)
    }

    // MARK: - 校正主流程

    static func computeOffsets(
        spec: any KneeCalibrationSpec.Type,
        thighSamples: [BLESample], calfSamples: [BLESample], side: Int,
        thighFit: BLEClockFit, calfFit: BLEClockFit,
        thighPacketCount: Int, calfPacketCount: Int
    ) -> KneeCalibrationResult {

        // ---- 步驟 1：連線檢查（Python 沒有這一步）----
        // 沒有這一步的話，斷線會落入下面的「姿勢皆不符合門檻」，使用者會被誤導去反覆調整擺位。
        // 註：樣本要通過平滑暖機才進 buffer，所以「完全無樣本」的實際門檻是未送滿 2 個封包。
        if thighSamples.isEmpty || calfSamples.isEmpty {
            let msg: String
            if thighSamples.isEmpty && calfSamples.isEmpty {
                msg = "大腿與小腿感測器都沒有資料，請確認裝置連線"
            } else if thighSamples.isEmpty {
                msg = "大腿感測器沒有資料，請確認裝置連線"
            } else {
                msg = "小腿感測器沒有資料，請確認裝置連線"
            }
            printDiagnostics(spec: spec, side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                             thighFit: thighFit, calfFit: calfFit,
                             thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                             pairedCount: 0, thighOnlyPass: 0, calfOnlyPass: 0, qualified: 0, message: msg)
            return KneeCalibrationResult(thigh: nil, calf: nil, message: msg, side: side)
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

            let thighOK = checkThigh(spec, t, side: side)
            let calfOK = checkCalf(spec, c, side: side)
            if thighOK { thighOnlyPass += 1 }
            if calfOK { calfOnlyPass += 1 }
            if thighOK && calfOK {
                qualifiedThighAlpha.append(alphaThighRaw(t, side: side))
                qualifiedShankAlpha.append(alphaShankRaw(c, side: side))
            }
        }

        let qualified = qualifiedThighAlpha.count

        // ---- 步驟 4：合格數達標 ----
        if qualified >= spec.minQualifiedSamples {
            let coef = spec.coefficients(side: side)
            let meanThigh = qualifiedThighAlpha.reduce(0, +) / Double(qualified)
            let meanShank = qualifiedShankAlpha.reduce(0, +) / Double(qualified)
            // 係數乘在平均上與乘在每一筆上等價（mean(C·x) = C·mean(x)）
            let oThigh = meanThigh * coef.thigh - spec.alphaThighTrueDeg
            let oCalf = meanShank * coef.calf - spec.alphaShankTrueDeg

            let msg = "校正成功"
            printDiagnostics(spec: spec, side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                             thighFit: thighFit, calfFit: calfFit,
                             thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                             pairedCount: pairedCount, thighOnlyPass: thighOnlyPass,
                             calfOnlyPass: calfOnlyPass, qualified: qualified, message: msg,
                             extra: String(format: "meanThigh=%.2f° meanShank=%.2f° C=(%.3f, %.3f) → o_thigh=%.2f° o_calf=%.2f°",
                                           meanThigh, meanShank, coef.thigh, coef.calf, oThigh, oCalf))
            return KneeCalibrationResult(thigh: oThigh, calf: oCalf, message: msg, side: side)
        }

        // ---- 步驟 5：合格數不足，依序判斷原因 ----
        // ⚠️ 順序很重要：一定要「先看合格數，不足時才判斷原因」。
        // 若把封包數檢查放在合格數之前當閘門，會誤殺原本能成功的校正
        // （例如只收到 50% 封包仍遠高於門檻）。
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
            // 5d：姿勢問題，四分類
            let thighBad = thighOnlyPass < spec.minQualifiedSamples
            let calfBad = calfOnlyPass < spec.minQualifiedSamples
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

        printDiagnostics(spec: spec, side: side, thighSamples: thighSamples, calfSamples: calfSamples,
                         thighFit: thighFit, calfFit: calfFit,
                         thighPacketCount: thighPacketCount, calfPacketCount: calfPacketCount,
                         pairedCount: pairedCount, thighOnlyPass: thighOnlyPass,
                         calfOnlyPass: calfOnlyPass, qualified: qualified, message: msg)
        return KneeCalibrationResult(thigh: nil, calf: nil, message: msg, side: side)
    }

    // MARK: - 診斷輸出

    /// 整組診斷欄位統一由這裡輸出，不另外定義第二套。
    private static func printDiagnostics(
        spec: any KneeCalibrationSpec.Type, side: Int,
        thighSamples: [BLESample], calfSamples: [BLESample],
        thighFit: BLEClockFit, calfFit: BLEClockFit,
        thighPacketCount: Int, calfPacketCount: Int,
        pairedCount: Int, thighOnlyPass: Int, calfOnlyPass: Int, qualified: Int,
        message: String, extra: String? = nil
    ) {
        print("""

        ========== [KNEE-CAL] \(spec.name) 校正診斷（side=\(side == 1 ? "右" : "左")）==========
          實收封包       大腿=\(thighPacketCount)  小腿=\(calfPacketCount)（門檻 \(minPacketCount)）
          回歸觀測點     大腿=\(thighFit.pointCount)  小腿=\(calfFit.pointCount)（門檻 \(minRegressionPoints)）
          回歸 b         大腿=\(String(format: "%.4f", thighFit.b))ms  小腿=\(String(format: "%.4f", calfFit.b))ms
          回歸殘差       大腿=\(String(format: "%.1f", thighFit.residualStdMs))ms  小腿=\(String(format: "%.1f", calfFit.residualStdMs))ms
          進入計算樣本   大腿=\(thighSamples.count)  小腿=\(calfSamples.count)
          成功配對       \(pairedCount)（佔大腿樣本 \(thighSamples.isEmpty ? 0 : pairedCount * 100 / thighSamples.count)%）
          姿勢通過       大腿=\(thighOnlyPass)  小腿=\(calfOnlyPass)  同時=\(qualified)（門檻 \(spec.minQualifiedSamples)）
        \(extra.map { "  \($0)\n" } ?? "")  → \(message)
        ==========================================================

        """)
    }
}

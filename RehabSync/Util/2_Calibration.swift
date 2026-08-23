import Foundation

/// 動作 2（TKE 終端膝伸展．坐姿）的校正規格。
///
/// 校正姿勢：**坐姿，大腿水平、小腿鉛直**（真值 `alpha_thigh = 90°`、`alpha_shank = 0°`）。
///
/// 流程本身在 `KneeCalibration`（共用引擎），這裡只宣告本動作與其他動作不同的部分。
/// 移植依據見 tke-sitting-calibration-port-plan.md 與 tke-sitting-calibration-script.md。
enum TKESpec: KneeCalibrationSpec {

    static let name = "動作2 TKE坐姿"

    /// 大腿水平
    static let alphaThighTrueDeg = 90.0
    /// 小腿鉛直
    static let alphaShankTrueDeg = 0.0

    /// 大腿水平 → `|ay|` 應歸零
    static func thighPostureAxis(_ s: BLESample) -> Double { s.y }
    /// 小腿鉛直 → `|ax|` 應歸零
    static func calfPostureAxis(_ s: BLESample) -> Double { s.x }

    /// 經驗係數**主要**套在小腿：坐姿 TKE 時大腿固定水平，小腿從鉛直掃到水平，
    /// 掃過大範圍的那一段才需要增益補償。
    ///
    /// | | C_thigh | C_calf |
    /// |---|---|---|
    /// | 左（side 0） | 1.0 | 1.167 |
    /// | 右（side 1） | 1.0 | 1.167 |
    ///
    /// **左右同值**，側別分支因此拿掉。
    ///
    /// ⚠️ 1.167 是實測經驗值，沒有文件依據，
    /// 見 tke-sitting-calibration-port-plan.md 第 8 節。
    ///
    /// 🔴 **改動這裡會同時改變 `o_thigh` 與即時 theta**
    /// （`o_thigh = mean × C_thigh − 真值`，即時再乘一次同樣的 C）——
    /// 兩邊用的是同一個函式，所以不會不一致；但**既有的校正結果會失效**。
    /// 實務上不影響：`tkeResult` 不跨頁面保存，離開 `PreWorking` 就被 `stopTKEPath` 清掉，
    /// 每次進入都必須重新校正。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double) {
        (1.0, 1.167)
    }

    // MARK: - 小腿分項改用膝屈曲角（tke-sitting-calibration-port-plan.md §11）
    //
    // 小腿分項從「與鉛直的夾角」改成**膝屈曲角**：
    //   小腿垂直地面（＝校正姿勢） → 90
    //   完全伸直（小腿水平）        → 接近 0（實際值含校正殘差，見下）
    //
    // 🔴 `alphaShankTrueDeg` 維持 0，不可改成 90 —— 它同時被校正的方向檢查使用
    //（比對的是未乘係數的原始 alpha，校正姿勢時物理上就在 0 附近）。
    // 改了會讓校正永遠失敗，而且訊息是「小腿姿勢不符合門檻」，看起來像擺位問題。
    //
    // 用 sign 而不是把 C_calf 改成負數：C 會顯示在 Test 頁，負值會被誤認為 bug，
    // 而且 C 的語意是「增益倍率」。
    static let calfReportAtCalibrationDeg = 90.0
    static let calfReportSign = -1.0

    // 大腿維持預設（報告值 = alphaThighTrueDeg = 90、方向 +1）——
    // 「大腿水平 = 90、往上抬遞增」本來就是既有行為，不需要改。

    // postureThresholdMG / directionToleranceDeg / minQualifiedSamples 沿用 protocol 預設值
    // （400mg / 30° / 250），與 Python 腳本一致。
}

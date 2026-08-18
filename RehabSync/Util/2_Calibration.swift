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

    /// 經驗係數套在**小腿**：坐姿 TKE 時大腿固定水平，小腿從鉛直掃到水平，
    /// 掃過大範圍的那一段才需要增益補償。
    ///
    /// ⚠️ 1.167／1.2 的來源不明，見 tke-sitting-calibration-port-plan.md 第 8 節。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double) {
        (1.0, side == 1 ? 1.2 : 1.167)
    }

    // postureThresholdMG / directionToleranceDeg / minQualifiedSamples 沿用 protocol 預設值
    // （400mg / 30° / 250），與 Python 腳本一致。
}

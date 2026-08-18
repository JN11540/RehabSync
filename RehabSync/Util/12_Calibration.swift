import Foundation

/// 動作 12（登階．站立基準）的校正規格。
///
/// 校正姿勢：**站立，大腿與小腿都鉛直**（真值 `alpha_thigh = 0°`、`alpha_shank = 0°`）——
/// 與動作 9（部分蹲）完全相同。
///
/// **與動作 9 的唯一差異是經驗係數：左右腳都是 1.7**（動作 9 是左 1.7／右 1.55）。
///
/// 流程本身在 `KneeCalibration`（共用引擎）。
enum StepUpSpec: KneeCalibrationSpec {

    static let name = "動作12 登階"

    static let alphaThighTrueDeg = 0.0
    static let alphaShankTrueDeg = 0.0

    /// 大腿鉛直 → `|ax|` 應歸零
    static func thighPostureAxis(_ s: BLESample) -> Double { s.x }
    /// 小腿鉛直 → `|ax|` 應歸零
    static func calfPostureAxis(_ s: BLESample) -> Double { s.x }

    /// 經驗係數套在**大腿**，且**左右腳同值 1.7**。
    ///
    /// 動作 9 的右腳是 1.55、左腳 1.7；本動作兩側都是 1.7。
    /// ⚠️ 來源同樣不明，見 9-calibration-port-plan.md 第 4.3 節。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double) {
        (1.7, 1.0)
    }
}

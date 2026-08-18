import Foundation

/// 動作 9（部分蹲．站立基準）的校正規格。
///
/// 校正姿勢：**站立，大腿與小腿都鉛直**（真值 `alpha_thigh = 0°`、`alpha_shank = 0°`）。
///
/// 流程本身在 `KneeCalibration`（共用引擎），這裡只宣告本動作與其他動作不同的部分。
/// 移植依據見 9-calibration-port-plan.md 與 9-calibration-script.md。
enum SquatSpec: KneeCalibrationSpec {

    static let name = "動作9 部分蹲"

    /// 大腿鉛直（站立）
    static let alphaThighTrueDeg = 0.0
    /// 小腿鉛直（站立）
    static let alphaShankTrueDeg = 0.0

    /// 大腿鉛直 → `|ax|` 應歸零（動作 2 是水平，取 `|ay|`）
    static func thighPostureAxis(_ s: BLESample) -> Double { s.x }
    /// 小腿鉛直 → `|ax|` 應歸零（與動作 2 相同）
    static func calfPostureAxis(_ s: BLESample) -> Double { s.x }

    /// 經驗係數套在**大腿** —— 與動作 2 相反。
    ///
    /// 部分蹲時大腿從鉛直掃到前傾、小腿相對變化小，所以增益補償在大腿。
    /// 倍率也遠大於動作 2（1.55／1.7 vs 1.2／1.167），代表大腿角度低估約 40%。
    ///
    /// ⚠️ 來源同樣不明，見 9-calibration-port-plan.md 第 4.3 節。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double) {
        (side == 1 ? 1.55 : 1.7, 1.0)
    }

    // ⚠️ 站立會有自然晃動，合格率可能低於坐姿。門檻先沿用 protocol 預設值（400mg / 30° / 250），
    // 待實測站立情境的實際通過率後再決定是否放寬（見 9-calibration-port-plan.md 第 4.2 節）。
}

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
    /// 部分蹲時大腿從鉛直掃到前傾、小腿相對變化小，所以增益補償在大腿。
    ///
    /// | | C_thigh | C_calf |
    /// |---|---|---|
    /// | 左（side 0） | **1.167** | 1.0 |
    /// | 右（side 1） | **1.167** | 1.0 |
    ///
    /// 增益**只放在大腿**，小腿兩側都是 1.0 —— 與動作 12／22 一致
    /// （站姿三個動作的共同規律）。動作 2 相反，增益放小腿。
    ///
    /// **站姿三個動作（9／12／22）目前用同一組值，左右也相同**：兩側皆 1.167。
    /// 三者校正姿勢完全相同（站立、大腿與小腿都鉛直、真值皆 0°、檢查軸皆 `ax`），
    /// 修正值一致是合理的。
    ///
    /// ⚠️ 這些倍率都是實測經驗值，沒有文件依據，見 9-calibration-port-plan.md 第 4.3 節。
    static func coefficients(side: Int) -> (thigh: Double, calf: Double) {
        (1.167, 1.0)
    }

    // MARK: - 小腿分項取負號（tke-sitting-calibration-port-plan.md §11 的機制）
    //
    // 分項改成 -(alpha_shank × C_calf − o_calf)，也就是相對校正姿勢的變化量取反向。
    //
    // 校正姿勢（站立）時分項仍是 0（report 值維持預設的 alphaShankTrueDeg = 0），
    // 離開校正姿勢後符號與改動前相反。
    //
    // 🔴 連帶：theta = 大腿分項 − 小腿分項，小腿取負之後等於
    //    theta = 大腿分項 + (alpha_shank × C_calf − o_calf)，
    //    亦即從「兩段相減」變成「兩段相加」。校正姿勢仍為 0，但離開校正姿勢後的值會改變，
    //    遊戲門檻需要重新確認（動作 9 `>= 45`、動作 22 `>= 50`、動作 12 狀態機 `+40`）。
    //
    // 🔴 alphaShankTrueDeg 維持 0 不可改 —— 它是校正方向檢查比對原始 alpha 用的，
    //    與分項的報告慣例是兩件獨立的事。
    static let calfReportSign = -1.0

    // ⚠️ 站立會有自然晃動，合格率可能低於坐姿。門檻先沿用 protocol 預設值（400mg / 30° / 250），
    // 待實測站立情境的實際通過率後再決定是否放寬（見 9-calibration-port-plan.md 第 4.2 節）。
}

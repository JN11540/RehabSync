import Foundation

/// 動作 12（登階．站立基準）的校正規格。
///
/// 校正姿勢：**站立，大腿與小腿都鉛直**（真值 `alpha_thigh = 0°`、`alpha_shank = 0°`）——
/// 與動作 9（部分蹲）完全相同。
///
/// **經驗係數與動作 9／22 完全相同**（兩側皆 1.167）——
/// 三者校正姿勢一樣，實測下來的修正值也一樣。
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

    /// 經驗係數套在**大腿**，小腿兩側都是 1.0（站姿三個動作的共同規律）。
    ///
    /// | | C_thigh | C_calf |
    /// |---|---|---|
    /// | 左（side 0） | **1.167** | 1.0 |
    /// | 右（side 1） | **1.167** | 1.0 |
    ///
    /// 原本兩側同值 1.7，實測後**兩側都改成 1.167**。
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
}

import GRDB

struct ExerciseDTO: Decodable {
    let id: Int
    let name: String
    let info: String
    let device: String?
    let target: String
    let joint: String
    let rep_stage1: Int?
    let act_stage1: String?
    let rep_stage2: Int?
    let act_stage2: String?
    let rep_stage3: Int?
    let act_stage3: String?
    let rep_stage4: Int?
    let act_stage4: String?
}

struct Exercise: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exercise"

    var id: Int64?
    var name: String
    var info: String
    var device: String?
    var target: String
    var joint: String
    var rep_stage1: Int?
    var act_stage1: String?
    var rep_stage2: Int?
    var act_stage2: String?
    var rep_stage3: Int?
    var act_stage3: String?
    var rep_stage4: Int?
    var act_stage4: String?
    /// 目標角度（度），v12 新增。遊戲判定用的門檻，`Working2／9／22` 直接讀它。
    ///
    /// 🔴 **型別是 `Double`，但資料庫欄位是 INTEGER** —— 刻意的，
    /// 為了讓程式碼裡一個 `Int(...)`／`Double(...)` 都不出現
    /// （working2-database-port-plan.md §22.3.1）。GRDB 自動處理讀寫。
    /// ⚠️ 代價：SQLite 的 INTEGER 親和性只在**無損**時才把 REAL 轉成整數，
    /// 所以 `45.0` 存成整數 45，但若哪天寫入 `45.5`，它會原封存成 REAL、
    /// 放在一個宣告為 INTEGER 的欄位裡。要支援半度門檻的話欄位型別要一起改。
    ///
    /// ⚠️ `ExerciseDTO`／`exercise.json` **沒有這個欄位** —— seed 時依 id 現算
    /// （22 → 50、其餘 → 45，見 `ExerciseViewModel.seed`），與 migration v12 的
    /// 填值規則必須一致。改規則要兩邊一起改。
    var target_angle: Double

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Exercise {
    /// 查不到 exercise 時的保底目標角度（度）。
    ///
    /// 🔴 只有 `2／9／12／22_Working.swift` 這四個檔案會用到它 ——
    /// 判定時（各自的 `targetAngle` 計算屬性）與寫入
    /// `treatment_result.target_angle` 時。全部讀這一個常數，不要各自寫 45。
    ///
    /// ✅ 顯示端（`PostWorking_*`）與匯出**不需要保底值**：它們讀的是
    /// `treatment_result.target_angle`，遊戲當時已經把值（含保底值）存進去了。
    ///
    /// ⚠️ 這不是任何動作的門檻定義 —— 判定的權威是 `exercise.target_angle`
    /// （`treatment_result.target_angle` 是快照，不是權威）。
    /// 走到保底值代表 `exercise` 查不到，屬於資料異常。
    ///
    /// 🔴 **45 對動作 22 是錯的**（正確值 50）。走到 fallback 時動作 22 的門檻會
    /// 變成 45 = 遊戲比應有標準寬鬆 5 度，而且畫面上看不出異常
    /// （快照也會存 45，卡片跟著顯示 45）。唯一的痕跡是 `Working*` 印的 log。
    static let fallbackTargetAngle: Double = 45
}

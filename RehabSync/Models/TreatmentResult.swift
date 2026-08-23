import GRDB

struct TreatmentReportPayload: Encodable {
    let treatment_id: Int
    let contents: [TreatmentResultItem]
}

struct TreatmentResultItem: Encodable {
    let treatment_content_id: Int
    let reps: [Int]
    let extension_length: [Int]
    let set_start_time: [Int]
    let set_end_time: [Int]
    let date: Int
}

struct TreatmentResultDTO: Decodable {
    let id: Int
    let treatment_id: Int
    let treatment_content_id: Int
    let reps: [Int]
    let extension_length: [Int]
    let set_start_time: [Int]
    let set_end_time: [Int]
    let date: Int
}

struct TreatmentResult: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_result"

    var id: Int64?
    var treatment_id: Int
    var treatment_content_id: Int
    var reps: [Int]
    var extension_length: [Int]
    var set_start_time: [Int]
    var set_end_time: [Int]
    var date: Int
    /// 這一場是哪個動作（v13 新增）。
    ///
    /// ⚠️ **可為 NULL** —— 不是疏漏：既有列靠 v13 的 UPDATE 從 `treatment_content`
    /// 回填，若有孤兒列，`NOT NULL` 會讓整個 migration 失敗、使用者 app 開不起來
    /// （working2-database-port-plan.md §22.5.3）。實務上只有孤兒列會是 nil。
    ///
    /// ⚠️ 這是既有事實的第二份（`treatment_content_id` → `treatment_content.exercise_id`
    /// 本來就查得到），存它只為了查詢／匯出方便。兩者必須永遠相等，但沒有機制保證。
    var exercise_id: Int?
    /// 這一場**當時**的目標角度（度，v13 新增）。結果頁的「目標角度」卡片讀這一欄。
    ///
    /// 🔴 **不要改成讀 `exercise.target_angle`** —— 那是「現在設定的值」，
    /// 一次 `UPDATE` 就會讓所有歷史場次的顯示跟著變。這一欄是快照，寫下去就不動。
    ///
    /// ⚠️ `0` = **這一場沒有記錄目標角度**（v13 之前的既有列），不是「目標 0 度」。
    /// 顯示時要畫成「－」。
    ///
    /// 🔴 型別是 `Double` 但資料庫欄位是 INTEGER，理由同 `Exercise.target_angle`。
    var target_angle: Double

    /// 🔴 **自訂 init，`exercise_id` 刻意不給預設值。**
    ///
    /// Swift 的 memberwise init 會替 Optional 屬性自動補 `= nil` ——
    /// 那樣四個 `Working*.createTreatmentResultIfNeeded()` 漏傳一個**不會編譯錯誤**，
    /// 那個動作往後所有場次的 `exercise_id` 都是 NULL，匯出檔案的動作身分變成
    /// `null`，而且完全沒有症狀。列成必填參數，漏傳就是編譯錯誤。
    ///
    /// `id` 保留 `= nil`：它本來就是「插入前未知、`didInsert` 才填」。
    ///
    /// ✅ GRDB 解碼不走這個 init（用 `Decodable` 合成的），所以讀取既有列
    /// （含 `exercise_id` 為 NULL 的孤兒列）照常運作。
    ///
    /// ⚠️ 副作用：日後新增欄位時這個 init 要手動加參數，memberwise init 沒有這個問題。
    /// 這是換取編譯期保護的代價。
    init(id: Int64? = nil,
         treatment_id: Int,
         treatment_content_id: Int,
         reps: [Int],
         extension_length: [Int],
         set_start_time: [Int],
         set_end_time: [Int],
         date: Int,
         exercise_id: Int?,
         target_angle: Double) {
        self.id = id
        self.treatment_id = treatment_id
        self.treatment_content_id = treatment_content_id
        self.reps = reps
        self.extension_length = extension_length
        self.set_start_time = set_start_time
        self.set_end_time = set_end_time
        self.date = date
        self.exercise_id = exercise_id
        self.target_angle = target_angle
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

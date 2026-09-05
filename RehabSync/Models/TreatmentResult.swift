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
    /// 這一場的 VAS 疼痛評分（v14 新增）。
    ///
    /// ⚠️ **可為 NULL，而且 `nil` 與 `0` 是兩件事** —— VAS 的 0 是「完全不痛」，
    /// `nil` 是「這一場沒有記錄」。當初若用 `NOT NULL DEFAULT 0`，既有列全部補 0，
    /// 「沒記錄」與「真的評 0 分」就永遠分不出來了。
    var vas: Int?
    /// 這一場的備註編號（v14 新增）。元素對應 `notes` 表的 `id`，文字是 `notes.name`。
    ///
    /// ⚠️ **三種狀態，不是兩種**：
    /// - `nil` —— 這一場沒有記錄（v14 之前的既有列、以及還沒有輸入介面的期間）
    /// - `[]` —— 有記錄，但治療師明確表示沒有任何備註
    /// - `[2, 6]` —— 這一場有兩則備註
    ///
    /// 🔴 `nil` 與 `[]` 不可以互相取代。兩者在程式裡都很容易寫成「沒有備註」，
    /// 但前者是「沒問過」、後者是「問了、答案是沒有」。UI 圖方便把沒勾任何項目
    /// 存成 `nil`，那條區分就永久消失了。
    ///
    /// 🔴 **沒有外鍵** —— 外鍵只能建在單一純量欄位上。SQLite 不檢查陣列裡的編號
    /// 存不存在、不擋刪除被引用的備註、不管重複與排序。寫入前要去重＋排序，
    /// 顯示時查不到的編號要有佔位，不要 `compactMap` 掉（病歷會少一項而畫面正常）。
    ///
    /// ⚠️ 是 `[Int]?` 不是 `[Int]`，跟 `reps` 那幾個陣列欄位多一層 Optional。
    var notes: [Int]?

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
    ///
    /// `vas`／`notes`（v14）同樣不給預設值，理由相同：漏傳就是編譯錯誤，
    /// 不是靜默寫入 NULL。目前四個 `Working*` 都傳 `nil`（還沒有輸入介面），
    /// 但那是**明確寫出來的 nil**，不是自動補的。
    init(id: Int64? = nil,
         treatment_id: Int,
         treatment_content_id: Int,
         reps: [Int],
         extension_length: [Int],
         set_start_time: [Int],
         set_end_time: [Int],
         date: Int,
         exercise_id: Int?,
         target_angle: Double,
         vas: Int?,
         notes: [Int]?) {
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
        self.vas = vas
        self.notes = notes
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

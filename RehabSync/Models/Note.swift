import GRDB

/// 備註選項（v14 新增）。內容由 `NoteViewModel.seedIfNeeded()` 從 `Util/note.json` 填入。
///
/// 被 `TreatmentResult.notes`（`[Int]?`）裡的元素引用 —— 🔴 **那是純數字引用、沒有外鍵**。
/// 外鍵只能建在單一純量欄位上，陣列裡的編號 SQLite 不會檢查，所以：
/// 刪掉這裡的一列不會被擋，指著它的場次會留下查不到文字的孤兒編號。
/// 顯示端要能處理「查不到」，不要靜默丟掉（`compactMap` 掉會讓病歷少一項而畫面看起來正常）。
///
/// ⚠️ 沒有 DTO：`note.json` 的欄位與這個 model 完全一致（不像 `Exercise` 有 JSON
/// 沒有的 `target_angle`、`Bluetooth` 有 `is_default`），直接 decode 成 `[Note]`。
struct Note: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    /// 備註編號。🔴 **自己指定，不是 autoincrement** —— 值來自 `note.json`，
    /// 比照 `exercise.id` 就是動作編號的既有做法。
    ///
    /// 非 Optional：一筆備註沒有編號沒有意義。也因此用 `PersistableRecord`
    /// 而不是 `MutablePersistableRecord` —— 不需要 `didInsert` 回填 rowid。
    var id: Int
    /// 備註文字。
    var name: String
}

import GRDB
import Observation
import Foundation

@Observable
class NoteViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var notes: [Note] = []

    func fetchAll() {
        notes = (try? db.read { db in
            try Note.fetchAll(db)
        }) ?? []
    }

    func fetch(by id: Int) -> Note? {
        try? db.read { db in
            try Note.fetchOne(db, key: id)
        }
    }

    // MARK: - Seed

    /// 把 `Util/note.json` 的備註選項填進 `notes` 表（v14 新增）。
    ///
    /// 🔴 **判斷條件是「表是空的」，不是「表存不存在」。**
    /// 建表是 migration `v14` 的事，`DatabaseMigrator` 用 `grdb_migrations` 記錄跑過哪些版本，
    /// 這裡再去問一次表在不在，是重複而且會不同步的第二套機制。
    /// 更重要的是：用 `count == 0` 才處理得了「表建好了、但 seed 那次讀檔失敗」——
    /// 下次啟動會自動補；用「表存不存在」判斷則永遠補不回來。
    ///
    /// ⚠️ 已知限制（與 `ExerciseViewModel.seedIfNeeded` 相同）：`count != 0` 就整段跳過，
    /// 所以日後改 `note.json`（加一則、改錯字）**既有安裝拿不到**，只有全新安裝會有。
    /// 反過來，治療師若把備註全部刪光，下次啟動會用**當前版本的** `note.json` 全部長回來。
    func seedIfNeeded() {
        let count = (try? db.read { db in
            try Note.fetchCount(db)
        }) ?? 0

        guard count == 0 else {
            print("[seed] notes 已有資料，跳過 seed")
            return
        }

        guard let url = Bundle.main.url(forResource: "note", withExtension: "json") else {
            print("[seed] ❌ 找不到 note.json")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[seed] ❌ 無法讀取 note.json")
            return
        }

        // `note.json` 的欄位與 `Note` 完全一致，不需要中間的 DTO。
        let decoded: [Note]
        do {
            decoded = try JSONDecoder().decode([Note].self, from: data)
        } catch {
            print("[seed] ❌ JSON 解析失敗：\(error)")
            return
        }

        let sorted = decoded.sorted { $0.id < $1.id }

        do {
            try db.write { db in
                for note in sorted {
                    // 🔴 用 upsert，不要用 `insert(onConflict: .replace)`。
                    // INSERT OR REPLACE 遇主鍵衝突是「先刪除既有列、再插入」——
                    // 見 `ExerciseViewModel.seedIfNeeded` 記錄的同一個坑。
                    // `treatment_result.notes` 雖然沒有外鍵擋這件事（陣列建不了外鍵），
                    // 但刪列會讓歷史場次的陣列瞬間指向孤兒編號，一樣不能刪。
                    // upsert 是 UPDATE、不刪列。
                    try note.upsert(db)
                }
            }
            print("[seed] ✅ 成功寫入 \(sorted.count) 筆 note")
        } catch {
            // 🔴 只 print、不 throw —— seed 失敗只該讓 notes 空著，
            // 不該讓 app 開不起來（這個函式是從 `RehabSyncApp.init()` 呼叫的）。
            print("[seed] ❌ 寫入失敗：\(error)")
        }
    }
}

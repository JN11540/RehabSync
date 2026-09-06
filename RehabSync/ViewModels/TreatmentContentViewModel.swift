import GRDB
import Observation

@Observable
class TreatmentContentViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var contents: [TreatmentContent] = []

    /// 載入**所有**菜單的內容，不分 `treatment_id`（settings-plan.md A.9.1）。
    ///
    /// 🔴 總覽頁的三個過濾點（今天／週曆選取日／鈴鐺）**只看 `date`、從不看 `treatment_id`**，
    /// 所以合併多份菜單之後不需要改它們，只要把資料池從一份換成全部。
    /// A.5 的重疊檢查保證任兩份菜單的時間區間不重疊，任一天最多落在一份菜單裡。
    ///
    /// ⚠️ 這是**不分日期**的全撈。A.9.1.2 原本建議改成日期範圍版，
    /// 但週曆的 `weekOffset` 可以往前後瀏覽任意週、而鈴鐺永遠要看「真正的今天」，
    /// 單一個日期範圍同時滿足不了這兩者。資料量可接受（一份菜單 368 筆），
    /// 若日後菜單累積到有感，正確的方向是拆成「瀏覽週」與「今天」兩份查詢，
    /// 不是把這裡改窄。
    func fetchAll() {
        contents = (try? db.read { db in
            try TreatmentContent.fetchAll(db)
        }) ?? []
    }

    func fetchAll(for treatmentId: Int) {
        contents = (try? db.read { db in
            try TreatmentContent
                .filter(Column("treatment_id") == treatmentId)
                .fetchAll(db)
        }) ?? []
    }

    func insert(_ content: inout TreatmentContent) {
        try? db.write { db in
            try content.insert(db)
        }
        fetchAll(for: content.treatment_id)
    }

    func update(_ content: TreatmentContent) {
        try? db.write { db in
            try content.update(db)
        }
        fetchAll(for: content.treatment_id)
    }

    func delete(_ content: TreatmentContent) {
        try? db.write { db in
            try content.delete(db)
        }
        fetchAll(for: content.treatment_id)
    }

    func deleteAll() {
        try? db.write { db in
            try TreatmentContent.deleteAll(db)
        }
        contents = []
    }

    static func totalSeconds(content: TreatmentContent, exercise: Exercise?) -> Int {
        let repTotal = [exercise?.rep_stage1, exercise?.rep_stage2,
                        exercise?.rep_stage3, exercise?.rep_stage4]
            .compactMap { $0 }.reduce(0, +)
        return 10 + content.sets * content.reps * repTotal
            + content.set_rest_time * (content.sets - 1)
    }
}

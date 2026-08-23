import GRDB
import Observation
import Foundation

@Observable
class ExerciseViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var exercises: [Exercise] = []

    func fetchAll() {
        exercises = (try? db.read { db in
            try Exercise.fetchAll(db)
        }) ?? []
    }

    func fetch(by id: Int) -> Exercise? {
        try? db.read { db in
            try Exercise.fetchOne(db, key: id)
        }
    }

    func imageName(forExerciseId id: Int64?) -> String? {
        guard let id else { return nil }
        return "Exercise\(id)"
    }

    func insert(_ exercise: inout Exercise) {
        try? db.write { db in
            try exercise.insert(db)
        }
        fetchAll()
    }

    func update(_ exercise: Exercise) {
        try? db.write { db in
            try exercise.update(db)
        }
        fetchAll()
    }

    func delete(_ exercise: Exercise) {
        try? db.write { db in
            try exercise.delete(db)
        }
        fetchAll()
    }

    func seedIfNeeded() {
        let count = (try? db.read { db in
            try Exercise.fetchCount(db)
        }) ?? 0

        guard count == 0 else {
            print("[seed] 已有資料，跳過 seed")
            return
        }

        guard let url = Bundle.main.url(forResource: "exercise", withExtension: "json") else {
            print("[seed] ❌ 找不到 exercise.json，請確認 Target Membership 有勾選")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[seed] ❌ 無法讀取檔案內容")
            return
        }

        let dtos: [ExerciseDTO]
        do {
            dtos = try JSONDecoder().decode([ExerciseDTO].self, from: data)
        } catch {
            print("[seed] ❌ JSON 解析失敗：\(error)")
            return
        }
        print("[seed] 解析到 \(dtos.count) 筆資料")

        let sorted = dtos.sorted { $0.id < $1.id }

        do {
            try db.write { db in
                for dto in sorted {
                    var exercise = Exercise(
                        id: Int64(dto.id),
                        name: dto.name,
                        info: dto.info,
                        device: dto.device,
                        target: dto.target,
                        joint: dto.joint,
                        rep_stage1: dto.rep_stage1,
                        act_stage1: dto.act_stage1,
                        rep_stage2: dto.rep_stage2,
                        act_stage2: dto.act_stage2,
                        rep_stage3: dto.rep_stage3,
                        act_stage3: dto.act_stage3,
                        rep_stage4: dto.rep_stage4,
                        act_stage4: dto.act_stage4,
                        // exercise.json 沒有 target_angle 欄位，依 id 現算。
                        // 🔴 規則必須與 migration v12 一致（22 → 50、其餘 → 45）：
                        // 這裡走的是「全新安裝」路徑，v12 走的是「既有安裝」路徑，
                        // 兩條路徑填出不同的值就會變成同一個 app 兩種資料。
                        target_angle: dto.id == 22 ? 50 : 45
                    )
                    // 🔴 用 upsert，不要用 `insert(onConflict: .replace)`。
                    // INSERT OR REPLACE 遇到主鍵衝突是「先刪除既有列、再插入」——
                    // 而 v13 之後 treatment_result.exercise_id 是 ON DELETE RESTRICT，
                    // 一旦有訓練紀錄指向這個 exercise，刪除就會被擋下、整個 seed 失敗，
                    // 而且錯誤訊息會指向外鍵、不會指向這裡。
                    // upsert 是 UPDATE、不刪列，外鍵完全不受影響。
                    //
                    // ⚠️ 今天踩不到（上面有 `count == 0` 保護，只在空資料庫跑），
                    // 但那個保護一旦被拿掉就會立刻炸。
                    try exercise.upsert(db)
                }
            }
            print("[seed] ✅ 成功寫入 \(sorted.count) 筆 exercise")
        } catch {
            print("[seed] ❌ 寫入失敗：\(error)")
        }
    }
}

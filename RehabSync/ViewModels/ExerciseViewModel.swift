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

        let staleCount = (try? db.read { db in
            try Exercise.filter(Column("info") == "").fetchCount(db)
        }) ?? 0

        let needsSeed = count == 0
        let needsReseed = count > 0 && staleCount > 0

        guard needsSeed || needsReseed else {
            print("[seed] 已有完整資料，跳過 seed")
            return
        }

        if needsReseed {
            print("[seed] 偵測到 v2 migration 後欄位為空，執行 reseed（\(staleCount) 筆）")
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
                        act_stage4: dto.act_stage4
                    )
                    try exercise.insert(db, onConflict: .replace)
                }
            }
            print("[seed] ✅ 成功寫入 \(sorted.count) 筆 exercise")
        } catch {
            print("[seed] ❌ 寫入失敗：\(error)")
        }
    }
}

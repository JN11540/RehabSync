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
        print("[seed] exercise 表目前筆數：\(count)")

        guard count == 0 else {
            print("[seed] 已有資料，跳過 seed")
            return
        }

        guard let url = Bundle.main.url(forResource: "exercise", withExtension: "json") else {
            print("[seed] ❌ 找不到 exercise.json，請確認 Target Membership 有勾選")
            return
        }
        print("[seed] ✅ 找到 exercise.json：\(url)")

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
                    var exercise = Exercise(id: Int64(dto.id), name: dto.name)
                    try exercise.insert(db, onConflict: .ignore)
                }
            }
            print("[seed] ✅ 成功寫入 \(sorted.count) 筆 exercise")
        } catch {
            print("[seed] ❌ 寫入失敗：\(error)")
        }
    }
}

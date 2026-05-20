import GRDB
import Observation

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

        guard count == 0 else { return }

        guard let url = Bundle.main.url(forResource: "exercise", withExtension: "json", subdirectory: "Util"),
              let data = try? Data(contentsOf: url),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data) else { return }

        let sorted = exercises.sorted { ($0.id ?? 0) < ($1.id ?? 0) }

        try? db.write { db in
            for var exercise in sorted {
                try exercise.insert(db, onConflict: .ignore)
            }
        }
    }
}

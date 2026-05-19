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
}

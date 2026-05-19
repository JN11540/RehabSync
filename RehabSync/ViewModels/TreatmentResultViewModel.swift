import GRDB
import Observation

@Observable
class TreatmentResultViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var results: [TreatmentResult] = []

    func fetchAll(for treatmentId: Int) {
        results = (try? db.read { db in
            try TreatmentResult
                .filter(Column("treatment_id") == treatmentId)
                .fetchAll(db)
        }) ?? []
    }

    func insert(_ result: inout TreatmentResult) {
        try? db.write { db in
            try result.insert(db)
        }
        fetchAll(for: result.treatmentId)
    }

    func update(_ result: TreatmentResult) {
        try? db.write { db in
            try result.update(db)
        }
        fetchAll(for: result.treatmentId)
    }

    func delete(_ result: TreatmentResult) {
        try? db.write { db in
            try result.delete(db)
        }
        fetchAll(for: result.treatmentId)
    }
}

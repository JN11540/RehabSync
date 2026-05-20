import GRDB
import Observation

@Observable
class TreatmentContentViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var contents: [TreatmentContent] = []

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
}

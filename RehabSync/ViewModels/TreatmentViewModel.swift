import Foundation
import GRDB
import Observation

@Observable
class TreatmentViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var treatments: [Treatment] = []

    func fetchAll() {
        treatments = (try? db.read { db in
            try Treatment.fetchAll(db)
        }) ?? []
    }

    func insert(_ treatment: inout Treatment) {
        try? db.write { db in
            try treatment.insert(db)
        }
        fetchAll()
    }

    func update(_ treatment: Treatment) {
        try? db.write { db in
            try treatment.update(db)
        }
        fetchAll()
    }

    func delete(_ treatment: Treatment) {
        try? db.write { db in
            try treatment.delete(db)
        }
        fetchAll()
    }

    func importTreatment(from url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw URLError(.fileDoesNotExist)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: data)

        try checkDuplicate(id: dto.id)

        try db.write { db in
            var treatment = Treatment(
                id: Int64(dto.id),
                name: dto.name,
                patient_id: dto.patient_id,
                start_time: dto.start_time,
                end_time: dto.end_time
            )
            try treatment.upsert(db)

            for item in dto.contents {
                var content = TreatmentContent(
                    id: Int64(item.id),
                    treatment_id: dto.id,
                    exercise_id: item.exercise_id,
                    sets: item.sets,
                    set_rest_time: item.set_rest_time,
                    reps: item.reps,
                    rep_training_time: item.rep_training_time,
                    rep_rest_time: item.rep_rest_time,
                    date: item.date
                )
                try content.upsert(db)
            }
        }

        fetchAll()
    }

    func deleteAll() {
        TreatmentResultViewModel().deleteAll()
        TreatmentContentViewModel().deleteAll()
        try? db.write { db in
            try Treatment.deleteAll(db)
        }
        fetchAll()
    }

    private func checkDuplicate(id: Int) throws {
        let exists = (try? db.read { db in
            try Treatment.filter(Column("id") == Int64(id)).fetchCount(db) > 0
        }) ?? false
        if exists {
            throw ImportError.duplicateId(id)
        }
    }

    enum ImportError: LocalizedError {
        case duplicateId(Int)

        var errorDescription: String? {
            switch self {
            case .duplicateId(let id):
                return "治療計畫 ID \(id) 已存在，無法重複匯入"
            }
        }
    }
}

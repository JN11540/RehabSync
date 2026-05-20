import Foundation
import GRDB

// MARK: - DTO

struct TreatmentImportDTO: Codable {
    let id: Int
    let name: String
    let patientId: Int
    let startTime: Int
    let endTime: Int
    let contents: [TreatmentContentImportDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, contents
        case patientId = "patient_id"
        case startTime = "start_time"
        case endTime   = "end_time"
    }
}

struct TreatmentContentImportDTO: Codable {
    let id: Int
    let exerciseId: Int
    let sets: Int
    let reps: Int
    let setRestTime: Int
    let repTrainingTime: Int
    let repRestTime: Int
    let date: Int

    enum CodingKeys: String, CodingKey {
        case id, sets, reps, date
        case exerciseId      = "exercise_id"
        case setRestTime     = "set_rest_time"
        case repTrainingTime = "rep_training_time"
        case repRestTime     = "rep_rest_time"
    }
}

// MARK: - Import

class ImportJSON {
    static let shared = ImportJSON()
    private let db = DatabaseManager.shared.dbQueue

    func importTreatment(from url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: data)

        try db.write { db in
            var treatment = Treatment(
                id: Int64(dto.id),
                name: dto.name,
                patientId: dto.patientId,
                startTime: dto.startTime,
                endTime: dto.endTime
            )
            try treatment.upsert(db)

            for item in dto.contents {
                var content = TreatmentContent(
                    id: Int64(item.id),
                    treatmentId: dto.id,
                    exerciseId: item.exerciseId,
                    sets: item.sets,
                    setRestTime: item.setRestTime,
                    reps: item.reps,
                    repTrainingTime: item.repTrainingTime,
                    repRestTime: item.repRestTime,
                    date: item.date
                )
                try content.upsert(db)
            }
        }
    }
}

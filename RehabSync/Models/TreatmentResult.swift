import GRDB

struct TreatmentResult: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_result"

    var id: Int64?
    var treatmentId: Int
    var treatmentContentId: Int
    var reps: Int
    var totalTime: Int
    var date: Int

    enum CodingKeys: String, CodingKey {
        case id, reps, date
        case treatmentId        = "treatment_id"
        case treatmentContentId = "treatment_content_id"
        case totalTime          = "total_time"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

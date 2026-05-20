import GRDB

struct TreatmentContent: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_content"

    var id: Int64?
    var treatmentId: Int
    var exerciseId: Int
    var sets: Int
    var setRestTime: Int
    var reps: Int
    var repTrainingTime: Int
    var repRestTime: Int
    var date: Int

    enum CodingKeys: String, CodingKey {
        case id, sets, reps, date
        case treatmentId     = "treatment_id"
        case exerciseId      = "exercise_id"
        case setRestTime     = "set_rest_time"
        case repTrainingTime = "rep_training_time"
        case repRestTime     = "rep_rest_time"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

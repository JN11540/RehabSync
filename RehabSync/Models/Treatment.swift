import GRDB

struct Treatment: Codable, FetchableRecord, MutablePersistableRecord {
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

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

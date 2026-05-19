import GRDB

struct TreatmentResult: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_result"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var treatmentId: Int
    var treatmentContentId: Int
    var reps: Int
    var totalTime: Int
    var date: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

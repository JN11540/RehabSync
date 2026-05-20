import GRDB

struct TreatmentResult: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_result"

    var id: Int64?
    var treatment_id: Int
    var treatment_content_id: Int
    var reps: Int
    var total_time: Int
    var date: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

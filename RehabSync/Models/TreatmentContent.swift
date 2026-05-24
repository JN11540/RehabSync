import GRDB

struct TreatmentContentImportDTO: Codable {
    let id: Int
    let exercise_id: Int
    let sets: Int
    let reps: Int
    let set_rest_time: Int
    let date: Int
}

struct TreatmentContent: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_content"

    var id: Int64?
    var treatment_id: Int
    var exercise_id: Int
    var sets: Int
    var set_rest_time: Int
    var reps: Int
    var date: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

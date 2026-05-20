import GRDB

struct TreatmentImportDTO: Codable {
    let id: Int
    let name: String
    let patient_id: Int
    let start_time: Int
    let end_time: Int
    let contents: [TreatmentContentImportDTO]
}

struct Treatment: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment"

    var id: Int64?
    var name: String
    var patient_id: Int
    var start_time: Int
    var end_time: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

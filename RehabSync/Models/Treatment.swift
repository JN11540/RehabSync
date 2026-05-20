import GRDB

struct Treatment: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment"

    var id: Int64?
    var name: String
    var patientId: Int
    var startTime: Int
    var endTime: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case patientId = "patient_id"
        case startTime = "start_time"
        case endTime   = "end_time"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

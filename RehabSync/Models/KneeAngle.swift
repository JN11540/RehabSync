import GRDB

struct KneeAngle: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "knee_angle"

    var id: Int64?
    var treatment_result_id: Int64?
    var timestamp: Int64
    var angle: Double

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

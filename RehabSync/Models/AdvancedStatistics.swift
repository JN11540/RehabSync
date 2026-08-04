import GRDB

struct AdvancedStatistics: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "advanced_statistics"

    var id: Int64?
    var treatment_result_id: Int64?
    var timestamp: Int64
    var angle: Double
    var emg: Double?

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

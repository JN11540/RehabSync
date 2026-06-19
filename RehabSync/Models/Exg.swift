import GRDB

struct Exg: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exg"

    var id: Int64?
    var device_id: Int64
    var timestamp: Int64
    var channel: Int
    var value: Int

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

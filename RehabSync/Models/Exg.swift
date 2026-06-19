import GRDB

struct Exg: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exg"

    var id: Int64?
    var device_id: Int64
    var timestamp: Int64
    var value: Int

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

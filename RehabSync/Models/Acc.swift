import GRDB

struct Acc: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "acc"

    var id: Int64?
    var device_id: Int64
    var timestamp: Int64
    var x: Double
    var y: Double
    var z: Double

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

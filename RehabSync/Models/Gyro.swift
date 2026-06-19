import GRDB

struct Gyro: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "gyro"

    var id: Int64?
    var device_id: Int64
    var timestamp: Int64
    var pitch: Double
    var roll: Double
    var yaw: Double

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

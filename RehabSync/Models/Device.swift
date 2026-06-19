import Foundation
import GRDB

struct Device: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "device"

    var id: Int64?
    var device_uuid: String
    var device_name: String
    var limb: Int
    var bluetooth_id: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

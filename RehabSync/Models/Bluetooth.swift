import Foundation
import GRDB

struct BluetoothDTO: Decodable {
    let write_uuid: String
    let sub_acc_uuid: String
    let sub_gyro_uuid: String
    let sub_exg_uuid: String
    let acc_sensitivity: Double
    let gyro_sensitivity: Double
    let cmd_a0: [UInt8]
    let cmd_a1: [UInt8]
    let is_default: Int
}

struct Bluetooth: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "bluetooth"

    var id: Int64?
    var write_uuid: String
    var sub_acc_uuid: String
    var sub_gyro_uuid: String
    var sub_exg_uuid: String
    var acc_sensitivity: Double
    var gyro_sensitivity: Double
    var cmd_a0: Data
    var cmd_a1: Data
    var is_default: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

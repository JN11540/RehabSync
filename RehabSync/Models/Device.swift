import Foundation
import GRDB

struct Device: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "device"

    var id: Int64?
    var device_uuid: String
    var device_name: String
    var limb: Int
    /// 0 = 左, 1 = 右。舊資料（Test1 等仍只用單一大腿/小腿裝置的畫面）一律預設為 0。
    var side: Int
    var bluetooth_id: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

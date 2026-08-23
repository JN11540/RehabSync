import GRDB

struct AdvancedStatistics: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "advanced_statistics"

    var id: Int64?
    var treatment_result_id: Int64?
    var timestamp: Int64
    var angle: Double
    var emg: Double?
    /// 小腿分項（膝屈曲角）。v11 新增，既有列為 0。
    var knee_flexion: Double
    /// 大腿分項（髖屈曲角）。v11 新增，既有列為 0。
    /// 恆等式：`angle == hip_flexion - knee_flexion`
    var hip_flexion: Double

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

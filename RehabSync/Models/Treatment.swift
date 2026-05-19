import GRDB

struct Treatment: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var name: String
    var patientId: Int
    var startTime: Int
    var endTime: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

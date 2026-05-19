import GRDB

struct Exercise: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exercise"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var name: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

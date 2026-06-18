import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    let dbQueue: DatabaseQueue

    private init() {
        dbQueue = try! createAppDatabase()
    }
}

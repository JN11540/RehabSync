import GRDB

struct ExerciseDTO: Decodable {
    let id: Int
    let name: String
    let info: String
    let device: String?
    let target: String
    let joint: String
    let rep_stage1: Int?
    let act_stage1: String?
    let rep_stage2: Int?
    let act_stage2: String?
    let rep_stage3: Int?
    let act_stage3: String?
    let rep_stage4: Int?
    let act_stage4: String?
}

struct Exercise: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exercise"

    var id: Int64?
    var name: String
    var info: String
    var device: String?
    var target: String
    var joint: String
    var rep_stage1: Int?
    var act_stage1: String?
    var rep_stage2: Int?
    var act_stage2: String?
    var rep_stage3: Int?
    var act_stage3: String?
    var rep_stage4: Int?
    var act_stage4: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

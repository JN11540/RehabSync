import GRDB

struct TreatmentReportPayload: Encodable {
    let treatment_id: Int
    let contents: [TreatmentResultItem]
}

struct TreatmentResultItem: Encodable {
    let treatment_content_id: Int
    let reps: [Int]
    let total_time: [Int]
    let extension_length: [Int]
    let set_start_time: [Int]
    let set_end_time: [Int]
    let date: Int
}

struct TreatmentResultDTO: Decodable {
    let id: Int
    let treatment_id: Int
    let treatment_content_id: Int
    let reps: [Int]
    let total_time: [Int]
    let extension_length: [Int]
    let set_start_time: [Int]
    let set_end_time: [Int]
    let date: Int
}

struct TreatmentResult: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "treatment_result"

    var id: Int64?
    var treatment_id: Int
    var treatment_content_id: Int
    var reps: [Int]
    var total_time: [Int]
    var extension_length: [Int]
    var set_start_time: [Int]
    var set_end_time: [Int]
    var date: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

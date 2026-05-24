import GRDB
import Observation
import Foundation

@Observable
class TreatmentResultViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var results: [TreatmentResult] = []

    func fetchAll(for treatmentId: Int) {
        results = (try? db.read { db in
            try TreatmentResult
                .filter(Column("treatment_id") == treatmentId)
                .fetchAll(db)
        }) ?? []
    }

    func insert(_ result: inout TreatmentResult) {
        try? db.write { db in
            try result.insert(db)
        }
        fetchAll(for: result.treatment_id)
    }

    func update(_ result: TreatmentResult) {
        try? db.write { db in
            try result.update(db)
        }
        fetchAll(for: result.treatment_id)
    }

    func delete(_ result: TreatmentResult) {
        try? db.write { db in
            try result.delete(db)
        }
        fetchAll(for: result.treatment_id)
    }

    func fetchCompletedContentIds(for treatmentId: Int) -> Set<Int> {
        let fetched = (try? db.read { db in
            try TreatmentResult
                .filter(Column("treatment_id") == treatmentId)
                .fetchAll(db)
        }) ?? []
        return Set(fetched.map { $0.treatment_content_id })
    }

    func deleteAll() {
        try? db.write { db in
            try TreatmentResult.deleteAll(db)
        }
        results = []
    }

    func postReport(ip: String, payload: TreatmentReportPayload) async throws {
        guard let url = URL(string: "http://\(ip):8080/treatment-results") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "伺服器回應 \(code)"])
        }
    }
}

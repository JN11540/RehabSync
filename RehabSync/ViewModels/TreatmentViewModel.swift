import Foundation
import GRDB
import Observation

@Observable
class TreatmentViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var treatments: [Treatment] = []

    func fetchAll() {
        treatments = (try? db.read { db in
            try Treatment.fetchAll(db)
        }) ?? []
    }

    func insert(_ treatment: inout Treatment) {
        try? db.write { db in
            try treatment.insert(db)
        }
        fetchAll()
    }

    func update(_ treatment: Treatment) {
        try? db.write { db in
            try treatment.update(db)
        }
        fetchAll()
    }

    func delete(_ treatment: Treatment) {
        try? db.write { db in
            try treatment.delete(db)
        }
        fetchAll()
    }

    func importTreatment(from url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw URLError(.fileDoesNotExist)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: data)
        try checkDuplicate(id: dto.id)
        try writeTreatmentDTO(dto)
        fetchAll()
    }

    func importFromQRCode(_ scannedStr: String) throws {
        let result = QRCodeService().verifyQRCode(qrRaw: scannedStr)
        guard result.valid, let data = result.data else {
            throw QRImportError.verificationFailed(result.reason ?? "未知錯誤")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: jsonData)
        try checkDuplicate(id: dto.id)
        try writeTreatmentDTO(dto)
        fetchAll()
    }

    func verifyQRCode(_ scannedStr: String) -> QRCodeService.VerifyResult {
        QRCodeService().verifyQRCode(qrRaw: scannedStr)
    }

    func deleteAll() {
        TreatmentResultViewModel().deleteAll()
        TreatmentContentViewModel().deleteAll()
        try? db.write { db in
            try Treatment.deleteAll(db)
        }
        fetchAll()
    }

    private func writeTreatmentDTO(_ dto: TreatmentImportDTO) throws {
        try db.write { db in
            var treatment = Treatment(
                id: Int64(dto.id),
                name: dto.name,
                patient_id: dto.patient_id,
                start_time: dto.start_time,
                end_time: dto.end_time
            )
            try treatment.upsert(db)

            for item in dto.contents {
                var content = TreatmentContent(
                    id: Int64(item.id),
                    treatment_id: dto.id,
                    exercise_id: item.exercise_id,
                    sets: item.sets,
                    set_rest_time: item.set_rest_time,
                    reps: item.reps,
                    date: item.date
                )
                try content.upsert(db)
            }
        }
    }

    private func checkDuplicate(id: Int) throws {
        let exists = (try? db.read { db in
            try Treatment.filter(Column("id") == Int64(id)).fetchCount(db) > 0
        }) ?? false
        if exists {
            throw ImportError.duplicateId(id)
        }
    }

    enum ImportError: LocalizedError {
        case duplicateId(Int)

        var errorDescription: String? {
            switch self {
            case .duplicateId(let id):
                return "治療計畫 ID \(id) 已存在，無法重複匯入"
            }
        }
    }

    enum QRImportError: LocalizedError {
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .verificationFailed(let reason):
                return "QR Code 驗證失敗：\(reason)"
            }
        }
    }
}

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

    /// 匯入訓練菜單。**在背景執行緒**做檔案讀取、解碼與寫入，完成後回主執行緒重載 `treatments`。
    ///
    /// 🔴 **不可以改回同步版本。** 原本這是一個同步函式，整段卡在主執行緒跑完，
    /// 畫面在它結束之前不會有任何更新——匯入時的倒數計時器一格都不會顯示
    /// （settings-plan.md A.2.3）。倒數要能真的跑，工作就必須離開主執行緒。
    @MainActor
    func importTreatment(from url: URL) async throws {
        let dbQueue = db
        try await Task.detached(priority: .userInitiated) {
            try Self.performImport(from: url, db: dbQueue)
        }.value
        fetchAll()
    }

    /// ⚠️ `static`：在背景執行緒跑，**不碰任何 instance 狀態**（尤其是 `treatments`，
    /// 那是 `@Observable` 的屬性，在背景改它會從非主執行緒觸發 UI 更新）。
    private static func performImport(from url: URL, db: DatabaseQueue) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw URLError(.fileDoesNotExist)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: data)

        // 🔴 **不再 `clearAll()`** —— 改成追加／合併（settings-plan.md A.4）。
        // 既有的 treatment／treatment_content／treatment_result 一律保留。
        //
        // 🔴 檢查與寫入**必須在同一個交易裡**（A.5.3.1 前提 2）：分開做的話，
        // 檢查通過到實際寫入之間資料庫若有變動，結論就過期了。
        // ⚠️ 也因此 `writeTreatmentDTO` 改成接收 `db`、自己不再開交易 ——
        // 它原本自帶 `db.write`，包在這個 `db.write` 裡會變成巢狀，
        // 而 GRDB 的 `DatabaseQueue.write` 不可重入，會死鎖。
        try db.write { db in
            try assertNoOverlap(dto, in: db)
            try writeTreatmentDTO(dto, in: db)
        }
    }

    /// 匯入前的時間區間重疊檢查（settings-plan.md A.5）。
    ///
    /// 🔴 **判定的是「分離」，再取反得到重疊**（A.5.2.1）。
    /// 不要改成「既有的端點有沒有落在新區間內」那種端點包含測試 ——
    /// 那會漏掉「既有區間完全包住新區間」的情況（A.5.2 第 4 種）。
    /// 分離判定是二分的，沒有第三種可能，所以涵蓋率是 100%。
    ///
    /// 🔴 **區間一律當半開區間 `[start_time, end_time)`**，含起點、不含終點，
    /// 所以「端點相接」算分離、可以通過（既有 3/31 結束、新的 3/31 開始）。
    /// ⚠️ 因此分離判定用 `<=` 而不是 `<` —— 寫成 `<` 會把合法的連續療程擋掉（A.5.3）。
    private static func assertNoOverlap(_ dto: TreatmentImportDTO, in db: Database) throws {
        // 前提 1：新進區間必須是正的。反向或零長度的區間會讓判定式得出
        // 「看起來通過」的錯誤結果，直接擋掉（A.5.3.1）。
        guard dto.start_time < dto.end_time else {
            throw TreatmentImportError.invalidRange(start: dto.start_time, end: dto.end_time)
        }

        for existing in try Treatment.fetchAll(db) {
            // 前提 1：既有列**不保證**是正的 —— `start_time`／`end_time` 從來沒有
            // 被任何程式讀過、也沒被驗證過（A.5.4），資料庫裡可能已經有反向的列。
            let lo = min(existing.start_time, existing.end_time)
            let hi = max(existing.start_time, existing.end_time)

            let separated = hi <= dto.start_time || dto.end_time <= lo
            if !separated {
                throw TreatmentImportError.overlapping(name: existing.name, start: lo, end: hi)
            }
        }
    }

    func importFromQRCode(_ scannedStr: String) throws {
        let result = QRCodeService().verifyQRCode(qrRaw: scannedStr)
        guard result.valid, let data = result.data else {
            throw QRImportError.verificationFailed(result.reason ?? "未知錯誤")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let dto = try JSONDecoder().decode(TreatmentImportDTO.self, from: jsonData)
        // ⚠️ 這條路徑**目前沒有任何呼叫者**（settings-plan.md A.8），
        // 所以維持原本的「整包取代」語意，沒有跟著改成追加＋重疊檢查。
        // 🔴 日後若接上 QR 匯入的入口，這裡要一併套用 `assertNoOverlap`。
        clearAll()
        try db.write { db in
            try Self.writeTreatmentDTO(dto, in: db)
        }
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

    /// ⚠️ **自己不開交易**，由呼叫端提供 `db`。
    /// 原本這裡有 `try db.write { }`，但那樣就無法跟 `assertNoOverlap` 共用同一個交易
    /// （包起來會巢狀、GRDB 不可重入會死鎖，見 `importTreatment`）。
    private static func writeTreatmentDTO(_ dto: TreatmentImportDTO, in db: Database) throws {
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

    private func clearAll() {
        TreatmentResultViewModel().deleteAll()
        TreatmentContentViewModel().deleteAll()
        try? db.write { db in try Treatment.deleteAll(db) }
    }

    /// 匯入前檢查失敗的原因（settings-plan.md A.5）。
    ///
    /// ⚠️ 訊息裡的時間直接印原始整數，**沒有格式化成日期** ——
    /// `start_time`／`end_time` 的單位至今沒有任何程式讀過、無從確認是秒還是毫秒
    /// （A.5.4），猜錯的話格式化出來的日期會比原始數字更誤導。
    enum TreatmentImportError: LocalizedError {
        case invalidRange(start: Int, end: Int)
        case overlapping(name: String, start: Int, end: Int)

        var errorDescription: String? {
            switch self {
            case .invalidRange(let start, let end):
                return "JSON 的時間範圍不合法：start_time（\(start)）必須小於 end_time（\(end)）。"
            case .overlapping(let name, let start, let end):
                return "訓練期間與既有菜單「\(name)」（\(start) – \(end)）重疊，無法匯入。"
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

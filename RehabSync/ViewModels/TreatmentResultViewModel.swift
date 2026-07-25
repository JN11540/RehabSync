import GRDB
import Observation
import Foundation

@Observable
class TreatmentResultViewModel {
    private let db = DatabaseManager.shared.dbQueue
    var results: [TreatmentResult] = []

    func fetchLatest() -> TreatmentResult? {
        try? db.read { db in
            try TreatmentResult.order(Column("id").desc).fetchOne(db)
        }
    }

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

    func postReport(payload: TreatmentReportPayload) async throws {
        let url = URL(string: "https://therapistclinical-production.up.railway.app/treatment-results")!
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

// MARK: - ExportDestinationStore（database-export-implementation-steps.md 階段 7）

/// 使用者在「匯出」設定頁指定的資料夾（見 database-export-implementation-steps.md 階段 7）。
/// 用 security-scoped bookmark 存進 UserDefaults，讓遊戲完成視窗匯出時可以直接解析回同一個資料夾寫檔，
/// 不用每次匯出都重新跳資料夾選擇器。
enum ExportDestinationStore {

    private static let bookmarkKey = "exportDestinationFolderBookmark"

    /// 只檢查 UserDefaults 有沒有存過 bookmark data，不嘗試真的解析——供階段 8 卡片點擊時的「是否已設定」判斷用。
    static func hasDesignatedFolder() -> Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// 把存起來的 bookmark data 解析回 URL；解析失敗（bookmark 壞掉/資料夾被移除）回傳 nil。
    /// 解析成功但已經過期（`isStale`）時，順手用這次解析出來的 URL 重新存一份新 bookmark 蓋掉舊的，
    /// 避免放著不管、之後真的失效——這一步不會動到資料夾本身或裡面的檔案。
    static func resolveDesignatedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            save(folderURL: url)
        }

        return url
    }

    /// 使用者選定（或重新選定）資料夾後呼叫：建立 security-scoped bookmark 並存進 UserDefaults，覆蓋舊的設定。
    /// iOS 上要用預設／空白 options（或 `.minimalBookmark`），不要加 `.withSecurityScope`——
    /// 那是 macOS 專屬的 BookmarkCreationOptions，iOS 沒有這個選項；從 UIDocumentPickerViewController
    /// 拿到的 URL 在 iOS 上本身就已經是 security-scoped，用預設選項建立 bookmark 就會自動保留這個安全範圍。
    static func save(folderURL url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

// MARK: - GameDataExporter（database-update-plan.md「4. 完成視窗『匯出JSON』功能」）

/// 匯出功能專用：組裝「7 個 CSV 檔 + 1 個 JSON 檔」的內容，對應 database-update-plan.md
/// 「4. 完成視窗『匯出JSON』功能」的規劃（exg 依 exg-csv-split-plan.md 拆成 4 個檔案）。
/// 只負責產生檔名＋內容字串，不負責寫檔／分享（見階段 4、5）。
enum GameDataExporter {

    struct ExportFile {
        let filename: String
        let content: String
    }

    /// 產生這局遊戲（`treatmentResult`）對應的 8 個匯出檔案。
    static func export(treatmentResult: TreatmentResult, deviceVM: DeviceViewModel) -> [ExportFile] {
        guard let treatmentResultId = treatmentResult.id else { return [] }

        let side = deviceVM.fetchAnySide() ?? 0
        let thighDeviceId = deviceVM.fetch(side: side, limb: 0)?.id
        let calfDeviceId = deviceVM.fetch(side: side, limb: 1)?.id
        let date = treatmentResult.date
        let setStartTimes = treatmentResult.set_start_time
        let setEndTimes = treatmentResult.set_end_time

        let accCSV = buildAccCSV(
            treatmentResultId: treatmentResultId, thighDeviceId: thighDeviceId, calfDeviceId: calfDeviceId,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let gyroCSV = buildGyroCSV(
            treatmentResultId: treatmentResultId, thighDeviceId: thighDeviceId, calfDeviceId: calfDeviceId,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let exgThighCh0CSV = buildExgChannelCSV(
            treatmentResultId: treatmentResultId, deviceId: thighDeviceId, channel: 0,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let exgThighCh1CSV = buildExgChannelCSV(
            treatmentResultId: treatmentResultId, deviceId: thighDeviceId, channel: 1,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let exgCalfCh0CSV = buildExgChannelCSV(
            treatmentResultId: treatmentResultId, deviceId: calfDeviceId, channel: 0,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let exgCalfCh1CSV = buildExgChannelCSV(
            treatmentResultId: treatmentResultId, deviceId: calfDeviceId, channel: 1,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let statsCSV = buildAdvancedStatisticsCSV(treatmentResultId: treatmentResultId, deviceVM: deviceVM)
        let resultJSON = buildTreatmentResultJSON(treatmentResult, side: side)

        return [
            ExportFile(filename: "acc_\(date).csv", content: accCSV),
            ExportFile(filename: "gyro_\(date).csv", content: gyroCSV),
            ExportFile(filename: "exg_thigh_ch0_\(date).csv", content: exgThighCh0CSV),
            ExportFile(filename: "exg_thigh_ch1_\(date).csv", content: exgThighCh1CSV),
            ExportFile(filename: "exg_calf_ch0_\(date).csv", content: exgCalfCh0CSV),
            ExportFile(filename: "exg_calf_ch1_\(date).csv", content: exgCalfCh1CSV),
            ExportFile(filename: "advanced_statistics_\(date).csv", content: statsCSV),
            ExportFile(filename: "treatment_result_\(date).json", content: resultJSON)
        ]
    }

    // MARK: - acc

    private static func buildAccCSV(
        treatmentResultId: Int64, thighDeviceId: Int64?, calfDeviceId: Int64?,
        setStartTimes: [Int], setEndTimes: [Int], deviceVM: DeviceViewModel
    ) -> String {
        let header = "timestamp,thigh_x,thigh_y,thigh_z,calf_x,calf_y,calf_z"
        guard let thighDeviceId, let calfDeviceId else { return header }

        let thigh = deviceVM.fetchACC(treatmentResultId: treatmentResultId, deviceId: thighDeviceId)
        let calf = deviceVM.fetchACC(treatmentResultId: treatmentResultId, deviceId: calfDeviceId)
        let merged = GameDataMerger.mergeByIndexPerSet(
            sequences: [thigh, calf], setStartTimes: setStartTimes, setEndTimes: setEndTimes,
            timestamp: { $0.timestamp }
        )
        guard merged.count == 2 else { return header }
        let thighMerged = merged[0], calfMerged = merged[1]

        var lines = [header]
        for i in 0..<thighMerged.count {
            let t = thighMerged[i], c = calfMerged[i]
            lines.append("\(t.timestamp),\(t.x),\(t.y),\(t.z),\(c.x),\(c.y),\(c.z)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - gyro

    private static func buildGyroCSV(
        treatmentResultId: Int64, thighDeviceId: Int64?, calfDeviceId: Int64?,
        setStartTimes: [Int], setEndTimes: [Int], deviceVM: DeviceViewModel
    ) -> String {
        let header = "timestamp,thigh_pitch,thigh_roll,thigh_yaw,calf_pitch,calf_roll,calf_yaw"
        guard let thighDeviceId, let calfDeviceId else { return header }

        let thigh = deviceVM.fetchGYRO(treatmentResultId: treatmentResultId, deviceId: thighDeviceId)
        let calf = deviceVM.fetchGYRO(treatmentResultId: treatmentResultId, deviceId: calfDeviceId)
        let merged = GameDataMerger.mergeByIndexPerSet(
            sequences: [thigh, calf], setStartTimes: setStartTimes, setEndTimes: setEndTimes,
            timestamp: { $0.timestamp }
        )
        guard merged.count == 2 else { return header }
        let thighMerged = merged[0], calfMerged = merged[1]

        var lines = [header]
        for i in 0..<thighMerged.count {
            let t = thighMerged[i], c = calfMerged[i]
            lines.append("\(t.timestamp),\(t.pitch),\(t.roll),\(t.yaw),\(c.pitch),\(c.roll),\(c.yaw)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - exg

    /// μV 換算係數：實驗校正得出的數值，不是感測器規格書上標示的 LSB 大小（見 exg-csv-split-plan.md）。
    private static let exgMicrovoltScale = 0.00003

    /// 單一裝置＋單一 channel 的 exg 匯出，欄位固定只有 `timestamp,uv`（見 exg-csv-split-plan.md）。
    private static func buildExgChannelCSV(
        treatmentResultId: Int64, deviceId: Int64?, channel: Int,
        setStartTimes: [Int], setEndTimes: [Int], deviceVM: DeviceViewModel
    ) -> String {
        let header = "timestamp,uv"
        guard let deviceId else { return header }

        let rows: [Exg] = deviceVM.fetchEXG(treatmentResultId: treatmentResultId, deviceId: deviceId, channel: channel)
        let merged = GameDataMerger.mergeByIndexPerSet(
            sequences: [rows], setStartTimes: setStartTimes, setEndTimes: setEndTimes,
            timestamp: { $0.timestamp }
        )
        guard merged.count == 1 else { return header }
        let filtered: [Exg] = merged[0]

        var lines = [header]
        for row in filtered {
            lines.append("\(row.timestamp),\(Double(row.value) * exgMicrovoltScale)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - advanced_statistics

    private static func buildAdvancedStatisticsCSV(treatmentResultId: Int64, deviceVM: DeviceViewModel) -> String {
        let header = "timestamp,angle,emg"
        let rows = deviceVM.fetchAdvancedStatistics(treatmentResultId: treatmentResultId)

        var lines = [header]
        for row in rows {
            let emgStr = row.emg.map { "\($0)" } ?? ""
            lines.append("\(row.timestamp),\(row.angle),\(emgStr)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - treatment_result

    private struct TreatmentResultExport: Encodable {
        let id: Int64?
        let treatment_id: Int
        let treatment_content_id: Int
        let reps: [Int]
        let extension_length: [Int]
        let set_start_time: [Int]
        let set_end_time: [Int]
        /// 0 = 左腳、1 = 右腳；只存在於匯出的 JSON，不落地到 `treatment_result` 表（schema 不變）。
        let side: Int
    }

    private static func buildTreatmentResultJSON(_ result: TreatmentResult, side: Int) -> String {
        let export = TreatmentResultExport(
            id: result.id,
            treatment_id: result.treatment_id,
            treatment_content_id: result.treatment_content_id,
            reps: result.reps,
            extension_length: result.extension_length,
            set_start_time: result.set_start_time,
            set_end_time: result.set_end_time,
            side: side
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(export), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

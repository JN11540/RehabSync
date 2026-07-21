import Foundation

/// 匯出功能專用：組裝「4 個 CSV 檔 + 1 個 JSON 檔」的內容，對應 database-update-plan.md
/// 「4. 完成視窗『匯出JSON』功能」的規劃。只負責產生檔名＋內容字串，不負責寫檔／分享（見階段 4、5）。
enum GameDataExporter {

    struct ExportFile {
        let filename: String
        let content: String
    }

    /// 產生這局遊戲（`treatmentResult`）對應的 5 個匯出檔案。
    static func export(treatmentResult: TreatmentResult, deviceVM: DeviceViewModel) -> [ExportFile] {
        guard let treatmentResultId = treatmentResult.id else { return [] }

        let thighDeviceId = deviceVM.fetch(limb: 0)?.id
        let calfDeviceId = deviceVM.fetch(limb: 1)?.id
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
        let exgCSV = buildExgCSV(
            treatmentResultId: treatmentResultId, thighDeviceId: thighDeviceId, calfDeviceId: calfDeviceId,
            setStartTimes: setStartTimes, setEndTimes: setEndTimes, deviceVM: deviceVM
        )
        let statsCSV = buildAdvancedStatisticsCSV(treatmentResultId: treatmentResultId, deviceVM: deviceVM)
        let resultJSON = buildTreatmentResultJSON(treatmentResult)

        return [
            ExportFile(filename: "acc_\(date).csv", content: accCSV),
            ExportFile(filename: "gyro_\(date).csv", content: gyroCSV),
            ExportFile(filename: "exg_\(date).csv", content: exgCSV),
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

    private static func buildExgCSV(
        treatmentResultId: Int64, thighDeviceId: Int64?, calfDeviceId: Int64?,
        setStartTimes: [Int], setEndTimes: [Int], deviceVM: DeviceViewModel
    ) -> String {
        let header = "timestamp,thigh_channel0,thigh_channel1,calf_channel0,calf_channel1"
        guard let thighDeviceId, let calfDeviceId else { return header }

        let thighCh0 = deviceVM.fetchEXG(treatmentResultId: treatmentResultId, deviceId: thighDeviceId, channel: 0)
        let thighCh1 = deviceVM.fetchEXG(treatmentResultId: treatmentResultId, deviceId: thighDeviceId, channel: 1)
        let calfCh0 = deviceVM.fetchEXG(treatmentResultId: treatmentResultId, deviceId: calfDeviceId, channel: 0)
        let calfCh1 = deviceVM.fetchEXG(treatmentResultId: treatmentResultId, deviceId: calfDeviceId, channel: 1)

        let merged = GameDataMerger.mergeByIndexPerSet(
            sequences: [thighCh0, thighCh1, calfCh0, calfCh1], setStartTimes: setStartTimes, setEndTimes: setEndTimes,
            timestamp: { $0.timestamp }
        )
        guard merged.count == 4 else { return header }
        let mThighCh0 = merged[0], mThighCh1 = merged[1], mCalfCh0 = merged[2], mCalfCh1 = merged[3]

        var lines = [header]
        for i in 0..<mThighCh0.count {
            let a = mThighCh0[i], b = mThighCh1[i], c = mCalfCh0[i], d = mCalfCh1[i]
            lines.append("\(a.timestamp),\(a.value),\(b.value),\(c.value),\(d.value)")
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
    }

    private static func buildTreatmentResultJSON(_ result: TreatmentResult) -> String {
        let export = TreatmentResultExport(
            id: result.id,
            treatment_id: result.treatment_id,
            treatment_content_id: result.treatment_content_id,
            reps: result.reps,
            extension_length: result.extension_length,
            set_start_time: result.set_start_time,
            set_end_time: result.set_end_time
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(export), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

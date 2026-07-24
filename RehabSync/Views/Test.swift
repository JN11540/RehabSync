import SwiftUI
import GRDB
import CoreBluetooth
import UIKit

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    @State private var treatmentResultIdInput: String = ""
    @State private var debugAccRows: [Acc] = []
    @State private var debugGyroRows: [Gyro] = []
    @State private var debugExgRows: [Exg] = []
    @State private var hasQueriedDebugRows = false

    private var bothConnected: Bool {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid)
        else { return false }
        return btVM.connectedPeripherals[thighUUID] != nil &&
               btVM.connectedPeripherals[calfUUID]  != nil
    }

    private var canExport: Bool {
        btVM.recordingStartTime != nil && btVM.recordingEndTime != nil
    }

    private var canEstimateRealAngle: Bool {
        bothConnected && btVM.baselineResult != nil
    }

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            VStack(spacing: 16) {
                // 共用按鈕列
                HStack(spacing: 12) {
                    Button("開始收集") { btVM.startRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(bothConnected && !btVM.isRecording
                            ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!bothConnected || btVM.isRecording)

                    Button("停止收集") { btVM.stopRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(btVM.isRecording ? Color.red.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!btVM.isRecording)

                    Button("匯出") { exportCSV() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canExport ? Color.blue.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!canExport)

                    Button("校正") {
                        if let pair = thighAndCalfPeripherals {
                            btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(bothConnected && !btVM.isCollectingBaseline
                        ? Color.orange.opacity(0.85) : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!bothConnected || btVM.isCollectingBaseline || btVM.isLiveEstimating)

                    if btVM.isCollectingBaseline {
                        Text("收集中…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else if let result = btVM.baselineResult {
                        Text(String(format: "%.1f°", result))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Button(btVM.isLiveEstimating ? "停止坐姿即時預估" : "開始坐姿即時預估") {
                        guard let pair = thighAndCalfPeripherals else { return }
                        if btVM.isLiveEstimating {
                            btVM.stopLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                        } else if let baseline = btVM.baselineResult {
                            btVM.startLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(btVM.isLiveEstimating ? Color.red.opacity(0.85)
                        : (canEstimateRealAngle ? Color.teal.opacity(0.85) : Color.gray.opacity(0.3)))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!btVM.isLiveEstimating && (!canEstimateRealAngle || btVM.isCollectingBaseline))

                    Button(btVM.isLiveEstimating ? "停止站立即時預估" : "開始站立即時預估") {
                        guard let pair = thighAndCalfPeripherals else { return }
                        if btVM.isLiveEstimating {
                            btVM.stopLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                        } else if let baseline = btVM.baselineResult {
                            btVM.startLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline, posture: .standing)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(btVM.isLiveEstimating ? Color.red.opacity(0.85)
                        : (canEstimateRealAngle ? Color.teal.opacity(0.85) : Color.gray.opacity(0.3)))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!btVM.isLiveEstimating && (!canEstimateRealAngle || btVM.isCollectingBaseline))

                    if let angle = btVM.currentEstimatedRealAngle {
                        Text(String(format: "%.1f°", angle))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                    } else if btVM.isLiveEstimating {
                        Text("等待資料…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    Button(btVM.isEstimatingStepStatus ? "停止預估登階狀態" : "開始預估登階狀態") {
                        guard let pair = thighAndCalfPeripherals else { return }
                        if btVM.isEstimatingStepStatus {
                            btVM.stopStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                        } else if let baseline = btVM.baselineResult {
                            btVM.startStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(btVM.isEstimatingStepStatus ? Color.red.opacity(0.85)
                        : (canEstimateRealAngle ? Color.purple.opacity(0.85) : Color.gray.opacity(0.3)))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!btVM.isEstimatingStepStatus && (!canEstimateRealAngle || btVM.isCollectingBaseline))

                    if let status = btVM.currentStepStatus {
                        Text(stepStatusText(status))
                            .font(.system(size: 20, weight: .bold))
                    } else if btVM.isEstimatingStepStatus {
                        Text("等待資料…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // 除錯用：輸入 treatment_result_id，查 acc/gyro/exg 三張表各 10 筆原始資料，
                // 不經過匯出查詢（不需要先查到 device_id），方便直接確認資料庫裡到底有沒有資料。
                HStack(spacing: 12) {
                    TextField("輸入 treatment_result_id", text: $treatmentResultIdInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button("查詢") { queryDebugRows() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Int64(treatmentResultIdInput) != nil ? Color.blue.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(Int64(treatmentResultIdInput) == nil)
                }
                .padding(.horizontal, 24)

                if hasQueriedDebugRows {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            debugRowsSection(title: "acc（\(debugAccRows.count) 筆）") {
                                ForEach(debugAccRows) { row in
                                    Text("id:\(row.id ?? -1) device:\(row.device_id) ts:\(row.timestamp) x:\(row.x) y:\(row.y) z:\(row.z)")
                                }
                            }
                            debugRowsSection(title: "gyro（\(debugGyroRows.count) 筆）") {
                                ForEach(debugGyroRows) { row in
                                    Text("id:\(row.id ?? -1) device:\(row.device_id) ts:\(row.timestamp) pitch:\(row.pitch) roll:\(row.roll) yaw:\(row.yaw)")
                                }
                            }
                            debugRowsSection(title: "exg（\(debugExgRows.count) 筆）") {
                                ForEach(debugExgRows) { row in
                                    Text("id:\(row.id ?? -1) device:\(row.device_id) ts:\(row.timestamp) ch:\(row.channel) value:\(row.value)")
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private func debugRowsSection<Content: View>(title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            rows()
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func queryDebugRows() {
        guard let treatmentResultId = Int64(treatmentResultIdInput) else { return }
        let dvm = DeviceViewModel()
        debugAccRows = dvm.fetchACC(treatmentResultId: treatmentResultId, limit: 10)
        debugGyroRows = dvm.fetchGYRO(treatmentResultId: treatmentResultId, limit: 10)
        debugExgRows = dvm.fetchEXG(treatmentResultId: treatmentResultId, limit: 10)
        hasQueriedDebugRows = true
    }

    private func stepStatusText(_ status: Int) -> String {
        switch status {
        case 0: return "站立"
        case 1: return "上階"
        case 2: return "下階"
        default: return ""
        }
    }

    private func exportCSV() {
        guard let from = btVM.recordingStartTime,
              let to   = btVM.recordingEndTime else { return }

        let dvm = DeviceViewModel()
        var thighAcc  = dvm.fetchACC(deviceId: 0, from: from, to: to)
        var calfAcc   = dvm.fetchACC(deviceId: 1, from: from, to: to)

        guard !thighAcc.isEmpty, !calfAcc.isEmpty else { return }

        let windowStart = max(thighAcc.first!.timestamp, calfAcc.first!.timestamp)
        let windowEnd   = min(thighAcc.last!.timestamp,  calfAcc.last!.timestamp)

        guard windowStart <= windowEnd else { return }

        thighAcc  = thighAcc.filter  { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        calfAcc   = calfAcc.filter   { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }

        let count = min(thighAcc.count, calfAcc.count)
        guard count > 0 else { return }

        var lines = ["timestamp,thigh_ax,thigh_ay,thigh_az,calf_ax,calf_ay,calf_az"]
        for i in 0..<count {
            let ts = thighAcc[i].timestamp
            let ta = thighAcc[i]
            let ca = calfAcc[i]
            lines.append("\(ts),\(ta.x),\(ta.y),\(ta.z),\(ca.x),\(ca.y),\(ca.z)")
        }

        let csv = lines.joined(separator: "\n")
        let filename = "rehabsync_\(from).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root  = scene.windows.first?.rootViewController {
            if let popover = av.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            root.present(av, animated: true)
        }
    }
}

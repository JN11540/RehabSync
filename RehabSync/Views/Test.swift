import SwiftUI
import GRDB
import CoreBluetooth
import UIKit

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

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

                // 裝置卡片
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 20) {
                        DeviceTestCard(btVM: btVM, limb: 0, label: "大腿裝置")
                        DeviceTestCard(btVM: btVM, limb: 1, label: "小腿裝置")
                    }
                    .padding(.horizontal, 24)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .padding(.top, 20)
        }
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

// MARK: - DeviceTestCard

struct DeviceTestCard: View {
    let btVM: BluetoothViewModel
    let limb: Int
    let label: String

    @State private var device: Device? = nil
    @State private var exgCh0Rows: [Exg] = []
    @State private var exgCh1Rows: [Exg] = []
    @State private var exgCh0Obs: AnyDatabaseCancellable? = nil
    @State private var exgCh1Obs: AnyDatabaseCancellable? = nil

    private var peripheral: CBPeripheral? {
        guard let uuidStr = device?.device_uuid,
              let uuid = UUID(uuidString: uuidStr) else { return nil }
        return btVM.connectedPeripherals[uuid]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
                Text(label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(peripheral != nil ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(peripheral != nil ? "已連線" : "未連線")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, 10)

            Divider().background(.white.opacity(0.3)).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // EXG Channel 0
                    SensorSection(title: "EXG CH0") {
                        if let r = exgCh0Rows.first {
                            Text("Value: \(r.value)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(exgCh0Rows) { r in
                            Text("\(r.timestamp)  \(r.value)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    // EXG Channel 1
                    SensorSection(title: "EXG CH1") {
                        if let r = exgCh1Rows.first {
                            Text("Value: \(r.value)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(exgCh1Rows) { r in
                            Text("\(r.timestamp)  \(r.value)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.1, green: 0.25, blue: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
    }

    private func startObserving() {
        device = DeviceViewModel().fetch(limb: limb)
        guard let deviceId = device?.id else { return }
        let db = DatabaseManager.shared.dbQueue

        exgCh0Obs = ValueObservation.tracking {
            try Exg.filter(Column("device_id") == deviceId && Column("channel") == 0)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { exgCh0Rows = $0 })

        exgCh1Obs = ValueObservation.tracking {
            try Exg.filter(Column("device_id") == deviceId && Column("channel") == 1)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { exgCh1Rows = $0 })
    }

    private func stopObserving() {
        exgCh0Obs = nil
        exgCh1Obs = nil
    }
}

// MARK: - SensorSection

private struct SensorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(1)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

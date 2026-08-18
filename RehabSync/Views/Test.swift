import SwiftUI
import GRDB
import CoreBluetooth
import UIKit
import Charts

// MARK: - EXG Display Mode

private enum EXGDisplayMode: Equatable {
    case raw, microvolt, smoothed
}

private struct SmoothedPoint: Identifiable {
    let id = UUID()
    let timestamp: Int64
    let value: Double
}

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    @Environment(\.goHome) private var goHome
    @State private var exgDisplayMode: EXGDisplayMode = .raw

    /// 裝置目前實際綁定在哪一側（左/右）——比照 `PreWorking_X.swift` 的做法，不是寫死左腳；
    /// 這個 app 一次最多只會綁 2 顆裝置（同一側大腿＋小腿），所以「隨便查一顆裝置的 side」就能知道目前是哪一側在用。
    private var side: Int {
        DeviceViewModel().fetchAnySide() ?? 0
    }

    private var bothConnected: Bool {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid)
        else { return false }
        return btVM.connectedPeripherals[thighUUID] != nil &&
               btVM.connectedPeripherals[calfUUID]  != nil
    }

    /// 除錯用：只要求至少一個裝置有連線，不像 `bothConnected` 要求兩個都連——
    /// 用來測試「只連大腿（或只連小腿）」單一裝置時的記錄行為，正常遊戲流程（PreWorking／Working）
    /// 需要兩個裝置都配對才能進去，這裡繞過這個限制方便單獨測試。
    private var anyConnected: Bool {
        !btVM.connectedPeripherals.isEmpty
    }

    private var canExport: Bool {
        btVM.recordingStartTime != nil && btVM.recordingEndTime != nil
    }

    private var canEstimateRealAngle: Bool {
        bothConnected && btVM.baselineResult != nil
    }

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    // MARK: - EXG 即時 4 通道監控（test-exg-realtime-monitor-plan.md）

    private var thighDeviceId: Int64? {
        DeviceViewModel().fetch(side: side, limb: 0)?.id
    }
    private var calfDeviceId: Int64? {
        DeviceViewModel().fetch(side: side, limb: 1)?.id
    }

    private func exgStatus(deviceId: Int64?, channel: Int) -> EXGChannelStatus? {
        guard let deviceId else { return nil }
        return btVM.exgChannelStatus["\(deviceId)-\(channel)"]
    }

    @ViewBuilder
    private func exgChannelPanel(title: String, status: EXGChannelStatus?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("掉包：\(status == nil ? "－" : "\(status!.droppedPacketCount)")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                exgChart(status)
                if status == nil || status?.recentSamples.isEmpty == true {
                    Text("尚無資料")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exgChart(_ status: EXGChannelStatus?) -> some View {
        let samples = status?.recentSamples ?? []
        let latest = samples.last?.timestamp ?? Int64(Date().timeIntervalSince1970 * 1000)

        return Group {
            if exgDisplayMode == .smoothed {
                Chart(smoothedPoints(samples)) { point in
                    LineMark(
                        x: .value("時間", point.timestamp),
                        y: .value("數值", point.value)
                    )
                }
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("時間", sample.timestamp),
                        y: .value("數值", displayValue(sample.value))
                    )
                }
            }
        }
        .chartXScale(domain: (latest - 10_000) ... latest)
        .chartXAxis(.hidden)
        .frame(height: 100)
    }

    private func displayValue(_ raw: Int) -> Double {
        switch exgDisplayMode {
        case .raw: Double(raw)
        case .microvolt, .smoothed: Double(raw) * GameDataExporter.exgMicrovoltScale
        }
    }

    /// 原始樣本 → μV → EMGAlgo.movingAverage(window/overlap 移動平均)。
    /// centerIndices（小數索引）四捨五入回 recentSamples 的整數索引，直接借用該筆樣本既有的合成時間戳，
    /// 避免用「假設樣本間隔固定」反推時間戳、隨封包間隔不規律累積誤差（test-exg-realtime-monitor-plan.md 第 10.3 節）。
    private func smoothedPoints(_ samples: [EXGSample]) -> [SmoothedPoint] {
        let uvValues = samples.map { Double($0.value) * GameDataExporter.exgMicrovoltScale }
        guard let (avgValues, centerIndices) = try? EMGAlgo.movingAverage(uv: uvValues) else { return [] }

        return zip(avgValues, centerIndices).compactMap { avg, centerIndex in
            let idx = Int(centerIndex.rounded())
            guard samples.indices.contains(idx) else { return nil }
            return SmoothedPoint(timestamp: samples[idx].timestamp, value: avg)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()

            Button(action: goHome) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("返回總覽")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(1)

            VStack(spacing: 16) {
                if bothConnected || anyConnected {
                    Text("目前偵測到裝置綁定在：\(side == 1 ? "右腳" : "左腳")")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }

                // 共用按鈕列
                HStack(spacing: 12) {
                    Button("開始收集") { btVM.startRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(anyConnected && !btVM.isRecording
                            ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!anyConnected || btVM.isRecording)

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
                            btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, durationSec: 8)
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

                    // TKE 路徑開關（tke-sitting-calibration-port-plan.md §9 階段 0 鷹架）：
                    // 暫時的 toggle，階段 5 會由正式的「TKE校正」按鈕取代。診斷印在 Xcode console。
                    Button(btVM.isTKEPathActive ? "停用 TKE 路徑" : "啟用 TKE 路徑") {
                        if btVM.isTKEPathActive {
                            btVM.stopTKEPath()
                        } else if let pair = thighAndCalfPeripherals {
                            btVM.startTKEPath(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(btVM.isTKEPathActive ? Color.red.opacity(0.85)
                        : (bothConnected ? Color.brown.opacity(0.85) : Color.gray.opacity(0.3)))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    // 停用不需要 bothConnected——裝置斷線時更需要能關掉，否則狀態會卡住
                    .disabled(btVM.isTKEPathActive ? false : (!bothConnected || btVM.isCollectingBaseline))

                    if btVM.isTKEPathActive {
                        Text("TKE 路徑啟用中…看 console")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // EXG 即時 4 通道監控（test-exg-realtime-monitor-plan.md）
                HStack(spacing: 12) {
                    Button("原始樣本") { exgDisplayMode = .raw }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(exgDisplayMode == .raw ? Color.indigo.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("μV 換算") { exgDisplayMode = .microvolt }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(exgDisplayMode == .microvolt ? Color.indigo.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("平滑") { exgDisplayMode = .smoothed }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(exgDisplayMode == .smoothed ? Color.indigo.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    exgChannelPanel(title: "大腿 CH0", status: exgStatus(deviceId: thighDeviceId, channel: 0))
                    exgChannelPanel(title: "大腿 CH1", status: exgStatus(deviceId: thighDeviceId, channel: 1))
                    exgChannelPanel(title: "小腿 CH0", status: exgStatus(deviceId: calfDeviceId, channel: 0))
                    exgChannelPanel(title: "小腿 CH1", status: exgStatus(deviceId: calfDeviceId, channel: 1))
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 20)
        }
        // TKE 路徑必須在離開頁面時收尾（tke-sitting-calibration-port-plan.md §4.4）：
        // notify 是刻意保持開啟到離開頁面才關的，若這裡不關，ACC 會持續傳輸；
        // 而 tkeCollecting 若殘留，封包會被永久攔截、正式流程的 acc 寫入也會受影響。
        // stopTKEPath() 不需要 peripheral 參數，裝置已斷線時一樣能清空狀態。
        .onDisappear {
            if btVM.isTKEPathActive { btVM.stopTKEPath() }
        }
    }

    private func exportCSV() {
        guard let from = btVM.recordingStartTime,
              let to   = btVM.recordingEndTime else { return }

        // `fetchACC(deviceId:)` 要的是 device 表的真實主鍵，不是寫死的 0/1；
        // 必須先用 side/limb 查出目前實際綁定裝置的 id，才能兼顧左右腳。
        let dvm = DeviceViewModel()
        guard let thighDeviceId = dvm.fetch(side: side, limb: 0)?.id,
              let calfDeviceId  = dvm.fetch(side: side, limb: 1)?.id
        else { return }

        var thighAcc  = dvm.fetchACC(deviceId: thighDeviceId, from: from, to: to)
        var calfAcc   = dvm.fetchACC(deviceId: calfDeviceId, from: from, to: to)

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


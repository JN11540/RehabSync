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

    /// 四個動作的校正規格。收集層完全共用，差異只在真值、姿勢檢查軸、經驗係數。
    /// 動作 9／12／22 的校正姿勢都是站立，僅係數不同（9 是左1.7/右1.55，12 與 22 兩側都 1.7）。
    private static let exercises: [(label: String, spec: any KneeCalibrationSpec.Type)] = [
        ("2",  TKESpec.self),
        ("9",  SquatSpec.self),
        ("12", StepUpSpec.self),
        ("22", Exercise22Spec.self),
    ]

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

    /// TKE 即時角度的啟用條件（tke-sitting-calibration-port-plan.md §4.5②）：
    /// 校正成功，**且 `tkeResult.side` 等於目前綁定側**。
    ///
    /// side 一致性檢查不是選配——換綁裝置後用舊 offset 搭配新的 side，k 值符號相反、
    /// 角度會完全錯誤，而畫面上不會有任何異常徵兆，只會看到一個看似合理但錯的數字。
    private var canStartTKELive: Bool {
        // !btVM.isLiveEstimating：新舊兩條 tick 都發布到 currentEstimatedRealAngle，
        // 不可同時運作（§20.2）。ViewModel 內另有 guard，這裡是 UI 層的同一道互斥。
        guard bothConnected, !btVM.isCollectingTKE, !btVM.isLiveEstimating,
              let r = btVM.tkeResult, r.succeeded else { return false }
        return r.side == side
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

    /// 分項的顯示格式。nil（未校正／未啟動即時／已清空）一律顯示 `--`，
    /// **不顯示 0** —— 0 是合法角度，用它代表「沒有值」會誤判（§10.6）。
    private func fmtComponent(_ v: Double?) -> String {
        v.map { String(format: "%.1f°", $0) } ?? "--"
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

            // 內容比畫面高（四動作校正各自一列 + EXG 四通道面板），改成可上下捲動。
            // 「返回總覽」是同一個 ZStack 裡 zIndex(1) 的獨立圖層，會固定在左上角不跟著捲，
            // 所以下面用 .padding(.top, 72) 讓開它的高度，避免第一列被蓋住。
            ScrollView {
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
                        // 新舊兩條 tick 都發布到 currentEstimatedRealAngle，不可同時運作（§20.2）——
                        // ViewModel 內已有 guard 擋住，這裡一併 disable，讓使用者看得出來是互斥而不是壞掉。
                        .disabled(!btVM.isLiveEstimating
                                  && (!canEstimateRealAngle || btVM.isCollectingBaseline || btVM.isTKELiveEstimating))

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
                        .disabled(!btVM.isLiveEstimating
                                  && (!canEstimateRealAngle || btVM.isCollectingBaseline || btVM.isTKELiveEstimating))

                        if let angle = btVM.currentEstimatedRealAngle {
                            Text(String(format: "%.1f°", angle))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                        } else if btVM.isLiveEstimating {
                            Text("等待資料…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    // 第二排：四動作校正 + 即時角度（tke-sitting-calibration-port-plan.md §4.5）
                    // 收集層與四個動作完全共用，只有規格（真值／檢查軸／係數）不同。
                    //
                    // 版面：五顆按鈕各自一列（VStack），不再擠在同一列。
                    // 按鈕統一寬度，左緣對齊；即時角度的讀數與它的按鈕同列，其餘狀態文字各自成列。
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.exercises.indices, id: \.self) { i in
                            let ex = Self.exercises[i]
                            let coef = ex.spec.coefficients(side: side)
                            // 分項只有一組（取決於目前生效的 tkeSpec），只在「這一列的規格 == 生效的規格」
                            // 時才顯示，避免誤讀成別的動作的值（§10.5 方案 B）。
                            let isActiveSpec = btVM.tkeSpecName == ex.spec.name

                            HStack(spacing: 12) {
                            // 按下即啟用 TKE 路徑並收集 8 秒。校正結束後路徑維持啟用、notify 不關（§4.4），
                            // 一路到離開頁面才由 .onDisappear 收尾。
                            Button("動作\(ex.label)校正") {
                                guard let pair = thighAndCalfPeripherals else { return }
                                // ownsConnectionRecovery: true 是測試頁專屬 —— 這裡沒有
                                // preTestFreshnessTimer／freshnessTimer，TKE 路徑必須自己跑斷線修復。
                                // 正式流程一律用預設 false，見 startTKEPath 的說明。
                                btVM.startKneeCalibration(spec: ex.spec,
                                                          thighPeripheral: pair.thigh, calfPeripheral: pair.calf,
                                                          ownsConnectionRecovery: true)
                            }
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 150)
                            .padding(.vertical, 10)
                            .background(bothConnected && !btVM.isCollectingTKE
                                ? Color.brown.opacity(0.85) : Color.gray.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            // 必須排除「即時進行中」——校正與即時的 buffer 保留規則衝突（§4.5①）
                            .disabled(!bothConnected || btVM.isCollectingTKE || btVM.isTKELiveEstimating)

                            // 經驗係數：靜態值，四列一直顯示。同時也是「動作 2 把增益放小腿、
                            // 9／12／22 放大腿」這個關鍵差異的視覺對照（§10.6）。
                            Text(String(format: "C_thigh %.3f", coef.thigh))
                            Text(String(format: "C_calf %.3f", coef.calf))

                            // theta 的兩個分項，相減即為即時角度。
                            Text("大腿 " + (isActiveSpec ? fmtComponent(btVM.currentTKEThighComponent) : "--"))
                            Text("小腿 " + (isActiveSpec ? fmtComponent(btVM.currentTKECalfComponent) : "--"))
                            }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(isActiveSpec ? Color.primary : Color.secondary)
                        }

                        // 第 5 列：即時角度按鈕 + 讀數（讀數與按鈕同列，兩者是一組）
                        HStack(spacing: 12) {
                            Button(btVM.isTKELiveEstimating ? "停止即時角度" : "開始即時角度") {
                                if btVM.isTKELiveEstimating {
                                    btVM.stopTKELiveAngle()
                                } else {
                                    btVM.startTKELiveAngle()
                                }
                            }
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 150)
                            .padding(.vertical, 10)
                            .background(btVM.isTKELiveEstimating ? Color.red.opacity(0.85)
                                : (canStartTKELive ? Color.teal.opacity(0.85) : Color.gray.opacity(0.3)))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(!btVM.isTKELiveEstimating && !canStartTKELive)

                            // 刻意讀未夾限的 currentEstimatedRealAngle（不是 displayKneeAngle）——
                            // 測試頁的用途是與 Python 逐值比對，夾限到 0 會掩蓋校正殘差。
                            if let theta = btVM.currentEstimatedRealAngle {
                                Text(String(format: "%.1f°", theta))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                            } else if btVM.isTKELiveEstimating {
                                Text("等待資料…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            } else if let r = btVM.tkeResult, r.succeeded, r.side != side {
                                Text("綁定裝置已變更，請重新校正")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red)
                            }
                        }

                        // 結果：大腿 / 小腿 / 訊息。失敗時 offset 顯示 --，只有訊息有內容。
                        if btVM.isCollectingTKE {
                            Text("收集中…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        } else if let r = btVM.tkeResult {
                            HStack(spacing: 8) {
                                Text("大腿 \(r.thigh.map { String(format: "%.2f°", $0) } ?? "--")")
                                Text("/")
                                Text("小腿 \(r.calf.map { String(format: "%.2f°", $0) } ?? "--")")
                                Text("/")
                                Text(r.message)
                                    .foregroundStyle(r.succeeded ? Color.green : Color.red)
                            }
                            .font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    // 第三排：EXG 即時 4 通道監控（test-exg-realtime-monitor-plan.md）
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
                .padding(.top, 72)
                .padding(.bottom, 40)
            }
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


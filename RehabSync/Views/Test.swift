import SwiftUI
import GRDB
import CoreBluetooth
import UIKit
import AVFoundation

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    @State private var treatmentResultIdInput: String = ""
    @State private var debugAccRows: [Acc] = []
    @State private var debugGyroRows: [Gyro] = []
    @State private var debugExgRows: [Exg] = []
    @State private var hasQueriedDebugRows = false
    @State private var isVideoCircleVisible = true
    @State private var selectedGuideVideo: GuideVideoOption = .exercise2Left

    private var bothConnected: Bool {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid)
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
                HStack {
                    Spacer()
                    Picker("引導影片", selection: $selectedGuideVideo) {
                        ForEach(GuideVideoOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 24)

                HStack {
                    Spacer()
                    if isVideoCircleVisible {
                        ZStack(alignment: .leading) {
                            VideoCircleToggleButton(systemName: "chevron.right") {
                                isVideoCircleVisible = false
                            }
                            .offset(x: -30)

                            CircularLoopingVideo(resourceName: selectedGuideVideo.resourceName)
                                .frame(width: 400, height: 400)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color(red: 0.45, green: 0.35, blue: 0.85), lineWidth: 6))
                                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        }
                    } else {
                        VideoCircleToggleButton(systemName: "chevron.left") {
                            isVideoCircleVisible = true
                        }
                    }
                }
                .padding(.horizontal, 24)

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

// MARK: - Video Circle Toggle Button

/// 圓圈左邊緣的收合按鈕：顯示時是向右箭頭（點擊收合圓圈），收合後變成向左箭頭（點擊還原）。
/// 外層是直式膠囊（比圓圈本身還小一圈，疊在圓圈左邊緣時被圓圈裁掉一部分邊邊沒關係）。
private struct VideoCircleToggleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 110)
                .background(Color(red: 0.45, green: 0.35, blue: 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guide Video Option

/// 下拉式選單的選項，對應 `RehabSync/Videos/` 底下 8 支引導影片（4 個動作各左右腳）。
private enum GuideVideoOption: String, CaseIterable, Identifiable {
    case exercise2Left, exercise2Right
    case exercise9Left, exercise9Right
    case exercise12Left, exercise12Right
    case exercise22Left, exercise22Right

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        case .exercise2Left: "2_left_video"
        case .exercise2Right: "2_right_video"
        case .exercise9Left: "9_left_video"
        case .exercise9Right: "9_right_video"
        case .exercise12Left: "12_left_video"
        case .exercise12Right: "12_right_video"
        case .exercise22Left: "22_left_video"
        case .exercise22Right: "22_right_video"
        }
    }

    var title: String {
        switch self {
        case .exercise2Left: "動作 2（左腳）"
        case .exercise2Right: "動作 2（右腳）"
        case .exercise9Left: "動作 9（左腳）"
        case .exercise9Right: "動作 9（右腳）"
        case .exercise12Left: "動作 12（左腳）"
        case .exercise12Right: "動作 12（右腳）"
        case .exercise22Left: "動作 22（左腳）"
        case .exercise22Right: "動作 22（右腳）"
        }
    }
}

// MARK: - Circular Looping Video

/// 播放 bundle 裡的影片並自動循環（用 AVQueuePlayer + AVPlayerLooper 做無縫 loop），
/// 給圓形展示區塊用，videoGravity 用 .resizeAspectFill 讓影片填滿圓形、多餘部分被裁掉。
private struct CircularLoopingVideo: View {
    let resourceName: String

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            CircularLoopingVideoPlayer(url: url)
        } else {
            Color.clear
        }
    }
}

private struct CircularLoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> CircularLoopingVideoUIView {
        CircularLoopingVideoUIView(url: url)
    }

    func updateUIView(_ uiView: CircularLoopingVideoUIView, context: Context) {
        uiView.update(url: url)
    }
}

private final class CircularLoopingVideoUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        update(url: url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func update(url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        let player = AVQueuePlayer()
        player.isMuted = true
        playerLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }
}

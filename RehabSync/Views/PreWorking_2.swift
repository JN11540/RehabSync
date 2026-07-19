import SwiftUI
import UIKit
import CoreBluetooth
import AVFoundation

/// 訓練前的準備流程，依序為：確認裝備 → 準備椅子 → 放置平板 → 成果數據頁 → 校正 → 動作測試。
private enum PreWorkingStep: Equatable {
    case equipment
    case chair
    case tablet
    case numbers
    case calibration
    case motionTest

    var title: String {
        switch self {
        case .equipment: "確認裝備齊全"
        case .chair: "準備椅子"
        case .tablet: "放置平板"
        case .numbers: ""
        case .calibration: "校正"
        case .motionTest: "動作測試"
        }
    }

    var subtitle: String {
        switch self {
        case .equipment: "請確認是否都已準備就緒"
        case .chair: "請先找一張高度剛好到您膝蓋的椅子"
        case .tablet: "請將平板放置於桌面上"
        case .numbers: ""
        case .calibration: "請先擺出圖片中的姿勢，點擊『校正』後保持不動，等待系統完成校正。"
        case .motionTest: "請依照引導動作進行操作，測試確認無誤後，即可點擊「遊戲」按鈕。"
        }
    }

    var next: PreWorkingStep? {
        switch self {
        case .equipment: .chair
        case .chair: .tablet
        case .tablet: .numbers
        case .numbers: .calibration
        case .calibration: .motionTest
        case .motionTest: nil
        }
    }

    var previous: PreWorkingStep? {
        switch self {
        case .equipment: nil
        case .chair: .equipment
        case .tablet: .chair
        case .numbers: .tablet
        case .calibration: .numbers
        case .motionTest: .calibration
        }
    }
}

struct PreWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: PreWorkingStep = .equipment
    @State private var navigateToWorking2 = false

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if step == .numbers {
                    PreWorking2ImpactPage(
                        onExitToPreviousStep: {
                            if let previous = step.previous { step = previous }
                        },
                        onAdvanceToNextStep: {
                            if let next = step.next { step = next }
                        }
                    )
                } else {
                    HStack(spacing: 24) {
                        PreWorking2EquipmentPanel(step: step)
                            .frame(maxWidth: .infinity)

                        if step == .calibration {
                            PreWorking2CalibrationAboutPanel(
                                title: step.title,
                                subtitle: step.subtitle,
                                onCalibrated: { if let next = step.next { step = next } }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if step == .motionTest {
                            PreWorking2MotionTestAboutPanel(
                                title: step.title,
                                subtitle: step.subtitle,
                                onPlayGame: { navigateToWorking2 = true }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            PreWorking2AboutPanel(
                                title: step.title,
                                subtitle: step.subtitle,
                                onPrevious: step.previous.map { previous in { step = previous } } ?? { dismiss() },
                                onNext: { if let next = step.next { step = next } }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Self.midPurple)
                    .frame(width: 50, height: 50)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
            .offset(x: 20, y: 20)
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $navigateToWorking2) {
            Working2(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)
        }
    }
}

// MARK: - Equipment Check Panel

private struct PreWorking2EquipmentPanel: View {
    let step: PreWorkingStep

    @State private var side: Int = 0

    /// side = 0（左，含資料庫查無資料時的預設值）或 1（右），對應到匯入的示範圖 asset 名稱。
    private var calibrationImageName: String {
        side == 1 ? "Exercise2SideViewReadyRight" : "Exercise2SideViewReadyLeft"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.80, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch step {
            case .equipment:
                VStack(spacing: 40) {
                    PreWorking2EquipmentItem(label: "裝置連線了嗎？") {
                        BluetoothIcon()
                            .stroke(PreWorking_2.midPurple, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .frame(width: 60, height: 88)
                    }
                    PreWorking2EquipmentItem(label: "護膝穿戴了嗎？") {
                        Image("WearPadAndGearsIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .chair:
                Image("ChairIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 500)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .tablet:
                Image("TabletDeskIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 500)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .numbers:
                EmptyView()
            case .motionTest:
                PreWorkingLoopingVideo(resourceName: side == 1 ? "2_right_video" : "2_left_video")
                    .frame(maxWidth: 500, maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .calibration:
                Image(calibrationImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 500)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
        }
    }
}

// MARK: - Looping Video

/// 播放 bundle 裡的影片並自動循環（用 AVQueuePlayer + AVPlayerLooper 做無縫 loop），
/// 目前給「動作測試」頁左側欄依 side 播放 2_left_video.mp4 / 2_right_video.mp4 用。
private struct PreWorkingLoopingVideo: View {
    let resourceName: String

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            PreWorkingLoopingVideoPlayer(url: url)
        } else {
            Color.clear
        }
    }
}

private struct PreWorkingLoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PreWorkingLoopingVideoUIView {
        PreWorkingLoopingVideoUIView(url: url)
    }

    func updateUIView(_ uiView: PreWorkingLoopingVideoUIView, context: Context) {
        uiView.update(url: url)
    }
}

private final class PreWorkingLoopingVideoUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspect
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

private struct PreWorking2EquipmentItem<Icon: View>: View {
    let label: String
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.white)
                .frame(width: 200, height: 200)
                .overlay { icon() }
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.75, green: 0.68, blue: 0.95), lineWidth: 3))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Text(label)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(PreWorking_2.darkPurple)
        }
    }
}

extension PreWorking2EquipmentItem where Icon == EmptyView {
    init(label: String) {
        self.label = label
        self.icon = { EmptyView() }
    }
}

/// 藍牙標誌（SF Symbols 沒有官方藍牙圖示，改用路徑手繪經典的藍牙符文外形）。
private struct BluetoothIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.24))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.38))
        path.closeSubpath()
        return path
    }
}

// MARK: - About Us Panel

private struct PreWorking2AboutPanel: View {
    let title: String
    let subtitle: String
    var onPrevious: (() -> Void)? = nil
    var onNext: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text(title)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(PreWorking_2.darkPurple)

            Text(subtitle)
                .font(.system(size: 25))
                .foregroundStyle(Color.black.opacity(0.75))
                .lineSpacing(8)
                .padding(.leading, 16)
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(PreWorking_2.midPurple)
                        .frame(width: 4)
                }

            HStack(spacing: 16) {
                if let onPrevious {
                    PreWorkingStepCapsuleButton(text: "上一步", icon: "arrow.left", iconLeading: true, action: onPrevious)
                }
                PreWorkingStepCapsuleButton(text: "下一步", icon: "arrow.right", iconLeading: false, action: onNext)
            }

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Step Navigation Capsule Button

private struct PreWorkingStepCapsuleButton: View {
    let text: String
    var icon: String? = nil
    var iconLeading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if iconLeading, let icon { Image(systemName: icon) }
                Text(text)
                if !iconLeading, let icon { Image(systemName: icon) }
            }
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(PreWorking_2.darkPurple)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color(red: 0.90, green: 0.87, blue: 0.98))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calibration About Panel

private struct PreWorking2CalibrationAboutPanel: View {
    let title: String
    let subtitle: String
    var onCalibrated: () -> Void = {}

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var side: Int = 0
    @State private var isCalibrating = false
    @State private var calibrationCountdown = 5
    @State private var countdownTimer: Timer?
    @State private var calibrationSucceeded = false
    @State private var calibrationFailed = false

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    /// 圓形按鈕的文字：閒置時是「校正」，倒數中換成數字，成功後改用膠囊「下一步」不會用到這個。
    private var circleButtonLabel: String {
        isCalibrating ? "\(calibrationCountdown)" : "校正"
    }

    private var sideLabelText: String {
        "\(side == 1 ? "右" : "左")腳版本"
    }

    /// 按下「校正」開始 5 秒倒數，同時呼叫真正的校正演算法（收集 5 秒加速度計算基準角）；
    /// 倒數結束後看 btVM.baselineResult 有沒有值決定成功或失敗，失敗要讓使用者能再按一次「校正」重試。
    private func startCalibration() {
        guard let pair = thighAndCalfPeripherals else { return }
        calibrationFailed = false
        isCalibrating = true
        calibrationCountdown = 5
        countdownTimer?.invalidate()
        btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if calibrationCountdown > 1 {
                calibrationCountdown -= 1
            } else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    evaluateCalibrationResult()
                }
            }
        }
    }

    private func evaluateCalibrationResult() {
        isCalibrating = false
        if btVM.baselineResult != nil {
            calibrationSucceeded = true
        } else {
            calibrationFailed = true
        }
    }

    private func handleButtonTap() {
        if calibrationSucceeded {
            onCalibrated()
        } else if !isCalibrating {
            startCalibration()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)

                Text(sideLabelText)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PreWorking_2.midPurple)
            }

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_2.midPurple)
                    .frame(width: 4)
                Text(subtitle)
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            if calibrationSucceeded {
                PreWorkingStepCapsuleButton(text: "下一步", icon: "arrow.right", action: handleButtonTap)
            } else {
                Button(action: handleButtonTap) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.90, green: 0.87, blue: 0.98))
                        Circle()
                            .strokeBorder(PreWorking_2.midPurple, lineWidth: 4)
                        Text(circleButtonLabel)
                            .font(.system(size: isCalibrating ? 60 : 25, weight: .bold))
                            .foregroundStyle(PreWorking_2.darkPurple)
                    }
                    .frame(width: 200, height: 200)
                }
                .buttonStyle(.plain)
                .disabled(isCalibrating || thighAndCalfPeripherals == nil)
                .opacity(thighAndCalfPeripherals == nil ? 0.4 : 1)
            }

            if calibrationFailed {
                Text("校正失敗，請重新嘗試")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.red)
            }

            if !calibrationSucceeded && thighAndCalfPeripherals == nil {
                Text("裝置未連線")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(40)
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }
}

// MARK: - Motion Test About Panel

private struct PreWorking2MotionTestAboutPanel: View {
    let title: String
    let subtitle: String
    var onPlayGame: () -> Void = {}

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var side: Int = 0

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    /// 呼叫即時角度預估（坐姿），圓圈裡的數字就是靠 btVM.currentEstimatedRealAngle 即時更新。
    private func startLiveTestIfNeeded() {
        guard !btVM.isLiveEstimating,
              let pair = thighAndCalfPeripherals,
              let baseline = btVM.baselineResult
        else { return }
        btVM.startLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline, posture: .sitting)
    }

    private func stopLiveTestIfNeeded() {
        guard btVM.isLiveEstimating, let pair = thighAndCalfPeripherals else { return }
        btVM.stopLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
    }

    private var sideLabelText: String {
        "\(side == 1 ? "右" : "左")腳版本"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)

                Text(sideLabelText)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PreWorking_2.midPurple)
            }

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_2.midPurple)
                    .frame(width: 4)
                Text(subtitle)
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            ZStack {
                Circle()
                    .fill(Color(red: 0.90, green: 0.87, blue: 0.98))
                Circle()
                    .strokeBorder(PreWorking_2.midPurple, lineWidth: 4)
                if let angle = btVM.currentEstimatedRealAngle {
                    Text(String(format: "%.1f°", angle))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(PreWorking_2.darkPurple)
                } else {
                    Text("等待資料…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PreWorking_2.darkPurple.opacity(0.6))
                }
            }
            .frame(width: 200, height: 200)

            PreWorkingStepCapsuleButton(text: "遊戲", icon: "gamecontroller.fill", action: onPlayGame)

            Spacer()
        }
        .padding(40)
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
            startLiveTestIfNeeded()
        }
        .onDisappear {
            stopLiveTestIfNeeded()
        }
    }
}

// MARK: - Impact / Numbers Page

/// 「動作逐步指南」內部的分頁，之後每新增一頁指南就在這裡加一個 case。
private enum PreWorkingGuideStep {
    case prepare
    case extendKnee
    case holdAndLower

    var title: String {
        switch self {
        case .prepare: "動作逐步指南\n1. 準備姿勢"
        case .extendKnee: "動作逐步指南\n2. 伸展膝蓋"
        case .holdAndLower: "動作逐步指南\n3. 保持並放下"
        }
    }

    var bodyText: String {
        switch self {
        case .prepare:
            "首先舒適地坐在穩固的椅子上。雙腳平放在地面上，確保背部挺直並得到支撐。雙手放在椅子兩側以穩定上半身，並將注意力集中在腿部肌肉上。"
        case .extendKnee:
            "慢慢伸直膝蓋，抬起腳，直到腿與地面平行。伸展時，保持腳尖繃直－這樣可以啟動股四頭肌，這是這個動作的主要目標肌群。重點在於控制動作，而不是追求速度。"
        case .holdAndLower:
            "保持伸展姿勢 2-3 秒，感受大腿肌肉的收縮。緩慢地將腿放回起始位置，保持動作控制。避免腿放下太快，因為這會降低肌肉參與並拉傷膝蓋。"
        }
    }

    var hasPoseImages: Bool {
        switch self {
        case .prepare: true
        case .extendKnee: true
        case .holdAndLower: true
        }
    }

    /// 對應匯入的示範圖 asset 名稱中間那段角度字樣（Exercise2SideView{stage}Left 之類）。
    var poseImageStage: String {
        switch self {
        case .prepare: "Ready"
        case .extendKnee: "45"
        case .holdAndLower: "90"
        }
    }

    var next: PreWorkingGuideStep? {
        switch self {
        case .prepare: .extendKnee
        case .extendKnee: .holdAndLower
        case .holdAndLower: nil
        }
    }

    var previous: PreWorkingGuideStep? {
        switch self {
        case .prepare: nil
        case .extendKnee: .prepare
        case .holdAndLower: .extendKnee
        }
    }
}

private struct PreWorking2ImpactPage: View {
    private enum PoseAngle {
        case side
        case front
    }

    @State private var side: Int = 0
    @State private var selectedAngle: PoseAngle = .side
    @State private var guideStep: PreWorkingGuideStep = .prepare
    /// 從第一頁「準備姿勢」再按上一步時，回到外層的「放置平板」頁。
    var onExitToPreviousStep: () -> Void = {}
    /// 從最後一頁「保持並放下」再按下一步時，前進到外層的「校正」頁。
    var onAdvanceToNextStep: () -> Void = {}

    /// side = 0（左，含資料庫查無資料時的預設值）或 1（右），對應到匯入的示範圖 asset 名稱。
    private var sideViewImageName: String {
        let stage = guideStep.poseImageStage
        return side == 1 ? "Exercise2SideView\(stage)Right" : "Exercise2SideView\(stage)Left"
    }

    private var frontViewImageName: String {
        let stage = guideStep.poseImageStage
        return side == 1 ? "Exercise2FrontView\(stage)Right" : "Exercise2FrontView\(stage)Left"
    }

    private var sideLabelText: String {
        "\(side == 1 ? "右" : "左")腳版本"
    }

    private var mainImageName: String {
        switch selectedAngle {
        case .side: sideViewImageName
        case .front: frontViewImageName
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                Text(guideStep.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)
                    .lineSpacing(6)

                Text(guideStep.bodyText)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineSpacing(6)
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 180, alignment: .topLeading)

                HStack(spacing: 16) {
                    PreWorkingStepCapsuleButton(text: "上一步", icon: "arrow.left", iconLeading: true) {
                        if let previous = guideStep.previous {
                            guideStep = previous
                            selectedAngle = .side
                        } else {
                            onExitToPreviousStep()
                        }
                    }

                    PreWorkingStepCapsuleButton(text: "下一步", icon: "arrow.right", iconLeading: false) {
                        if let next = guideStep.next {
                            guideStep = next
                            selectedAngle = .side
                        } else {
                            onAdvanceToNextStep()
                        }
                    }
                }
            }
            .frame(maxWidth: 380, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                if guideStep.hasPoseImages {
                    Text(sideLabelText)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PreWorking_2.midPurple)
                }

                PreWorking2PoseImageCard(imageName: guideStep.hasPoseImages ? mainImageName : nil)
                    .frame(width: 500, height: 500)

                HStack(spacing: 16) {
                    PreWorking2PoseImageCard(
                        imageName: guideStep.hasPoseImages ? sideViewImageName : nil,
                        isSelected: selectedAngle == .side
                    )
                    .frame(width: 100, height: 100)
                    .onTapGesture { if guideStep.hasPoseImages { selectedAngle = .side } }

                    PreWorking2PoseImageCard(
                        imageName: guideStep.hasPoseImages ? frontViewImageName : nil,
                        isSelected: selectedAngle == .front
                    )
                    .frame(width: 100, height: 100)
                    .onTapGesture { if guideStep.hasPoseImages { selectedAngle = .front } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
        }
    }
}

private struct PreWorking2PoseImageCard: View {
    let imageName: String?
    var isSelected: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(PreWorking_2.midPurple, lineWidth: isSelected ? 3 : 0)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

#Preview {
    PreWorking_2(
        content: TreatmentContent(treatment_id: 1, exercise_id: 2, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil,
        onReturnToDashboard: {}
    )
}

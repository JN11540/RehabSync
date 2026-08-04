import SwiftUI
import UIKit
import CoreBluetooth
import AVFoundation

/// 訓練前的準備流程，依序為：確認裝備 → 準備踏板 → 放置平板 → 動作逐步指南 → 校正 → 動作測試。
private enum PreWorking12Step: Equatable {
    case equipment
    case stool
    case tablet
    case guide
    case calibration
    case motionTest

    var title: String {
        switch self {
        case .equipment: "確認裝備齊全"
        case .stool: "準備踏板或凳子"
        case .tablet: "放置平板"
        case .guide: ""
        case .calibration: "校正"
        case .motionTest: "動作測試"
        }
    }

    var subtitle: String {
        switch self {
        case .equipment: "請確認是否都已準備就緒"
        case .stool: "請先準備一階穩固的踏板或凳子"
        case .tablet: "請將平板放置於桌面上"
        case .guide: ""
        case .calibration: "請先擺出圖片中的姿勢，點擊『校正』後保持不動，等待系統完成校正。"
        case .motionTest: "請依照引導動作進行操作，測試確認無誤後，即可點擊「遊戲」按鈕。"
        }
    }

    var next: PreWorking12Step? {
        switch self {
        case .equipment: .stool
        case .stool: .tablet
        case .tablet: .guide
        case .guide: .calibration
        case .calibration: .motionTest
        case .motionTest: nil
        }
    }

    var previous: PreWorking12Step? {
        switch self {
        case .equipment: nil
        case .stool: .equipment
        case .tablet: .stool
        case .guide: .tablet
        case .calibration: .guide
        case .motionTest: .calibration
        }
    }
}

struct PreWorking_12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var step: PreWorking12Step = .equipment
    @State private var navigateToWorking12 = false

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if step == .guide {
                    PreWorking12GuidePage(
                        onExitToPreviousStep: {
                            if let previous = step.previous { step = previous }
                        },
                        onAdvanceToNextStep: {
                            if let next = step.next { step = next }
                        }
                    )
                } else {
                    HStack(spacing: 24) {
                        PreWorking12EquipmentPanel(step: step)
                            .frame(maxWidth: .infinity)

                        if step == .calibration {
                            PreWorking12CalibrationAboutPanel(
                                title: step.title,
                                subtitle: step.subtitle,
                                onCalibrated: { if let next = step.next { step = next } }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if step == .motionTest {
                            PreWorking12MotionTestAboutPanel(
                                title: step.title,
                                subtitle: step.subtitle,
                                onPlayGame: { navigateToWorking12 = true }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            PreWorking12AboutPanel(
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
        .fullScreenCover(isPresented: $navigateToWorking12) {
            Working12(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)
        }
        .overlay {
            if btVM.isCleaningUp {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("正在刪除舊資料")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("請稍候，完成後自動關閉")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(32)
                .background(Color(red: 0.1, green: 0.25, blue: 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Equipment Check Panel

private struct PreWorking12EquipmentPanel: View {
    let step: PreWorking12Step

    @State private var side: Int = 0

    /// side = 0（左，含資料庫查無資料時的預設值）或 1（右），對應到匯入的示範圖 asset 名稱。
    private var calibrationImageName: String {
        side == 1 ? "Exercise12SideViewReadyRight" : "Exercise12SideViewReadyLeft"
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
                    PreWorking12EquipmentItem(label: "裝置連線了嗎？") {
                        BluetoothIcon12()
                            .stroke(PreWorking_12.midPurple, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .frame(width: 60, height: 88)
                    }
                    PreWorking12EquipmentItem(label: "護膝穿戴了嗎？") {
                        Image("WearPadAndGearsIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .stool:
                Image("StoolIcon")
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
            case .guide:
                EmptyView()
            case .motionTest:
                PreWorking12LoopingVideo(resourceName: side == 1 ? "12_right_video" : "12_left_video")
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
/// 目前給「動作測試」頁左側欄依 side 播放 12_left_video.mp4 / 12_right_video.mp4 用。
private struct PreWorking12LoopingVideo: View {
    let resourceName: String

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            PreWorking12LoopingVideoPlayer(url: url)
        } else {
            Color.clear
        }
    }
}

private struct PreWorking12LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PreWorking12LoopingVideoUIView {
        PreWorking12LoopingVideoUIView(url: url)
    }

    func updateUIView(_ uiView: PreWorking12LoopingVideoUIView, context: Context) {
        uiView.update(url: url)
    }
}

private final class PreWorking12LoopingVideoUIView: UIView {
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

private struct PreWorking12EquipmentItem<Icon: View>: View {
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
                .foregroundStyle(PreWorking_12.darkPurple)
        }
    }
}

extension PreWorking12EquipmentItem where Icon == EmptyView {
    init(label: String) {
        self.label = label
        self.icon = { EmptyView() }
    }
}

/// 藍牙標誌（SF Symbols 沒有官方藍牙圖示，改用路徑手繪經典的藍牙符文外形）。
private struct BluetoothIcon12: Shape {
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

// MARK: - About Panel

private struct PreWorking12AboutPanel: View {
    let title: String
    let subtitle: String
    var onPrevious: (() -> Void)? = nil
    var onNext: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text(title)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(PreWorking_12.darkPurple)

            Text(subtitle)
                .font(.system(size: 25))
                .foregroundStyle(Color.black.opacity(0.75))
                .lineSpacing(8)
                .padding(.leading, 16)
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(PreWorking_12.midPurple)
                        .frame(width: 4)
                }

            HStack(spacing: 16) {
                if let onPrevious {
                    PreWorking12StepCapsuleButton(text: "上一步", icon: "arrow.left", iconLeading: true, action: onPrevious)
                }
                PreWorking12StepCapsuleButton(text: "下一步", icon: "arrow.right", iconLeading: false, action: onNext)
            }

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Step Navigation Capsule Button

private struct PreWorking12StepCapsuleButton: View {
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
            .foregroundStyle(PreWorking_12.darkPurple)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color(red: 0.90, green: 0.87, blue: 0.98))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calibration About Panel

private struct PreWorking12CalibrationAboutPanel: View {
    let title: String
    let subtitle: String
    var onCalibrated: () -> Void = {}

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var side: Int = 0
    @State private var isPreparing = false
    @State private var prepMessageVisible = false
    @State private var prepTickCount = 0
    @State private var prepTimer: Timer?
    @State private var isCalibrating = false
    @State private var calibrationCountdown = 5
    @State private var countdownTimer: Timer?
    @State private var calibrationSucceeded = false
    @State private var calibrationFailed = false

    private let prepMessage = "請站好\n不要動"

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(side: side, limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(side: side, limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    /// 圓形按鈕的文字：準備階段是提示文字，倒數中換成數字，閒置時是「校正」，成功後改用膠囊「下一步」不會用到這個。
    private var circleButtonLabel: String {
        if isPreparing { return prepMessage }
        if isCalibrating { return "\(calibrationCountdown)" }
        return "校正"
    }

    private var sideLabelText: String {
        "\(side == 1 ? "右" : "左")腳版本"
    }

    /// 按下「校正」開始 5 秒倒數（純視覺），同時呼叫真正的校正演算法（收集 5 秒加速度計算基準角）；
    /// 成功或失敗的判定改成由 `startBaselineCalibration` 的 completion 觸發（後端真正算完的那一刻），
    /// 不再用「倒數結束 + 0.3 秒緩衝」去猜後端是否已經算完——猜測秒數在系統忙碌時會不準，
    /// 曾經發生過後端其實已經算出結果、但 UI 因為猜測時間到了而提早判定失敗的競爭情況。
    private func startCalibration() {
        guard let pair = thighAndCalfPeripherals else { return }
        calibrationFailed = false
        isCalibrating = true
        calibrationCountdown = 5
        countdownTimer?.invalidate()
        btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf) { _ in
            evaluateCalibrationResult()
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if calibrationCountdown > 1 {
                calibrationCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    /// 由 `startBaselineCalibration` 的 completion 呼叫，這時 `btVM.baselineResult` 保證已經寫入完成。
    private func evaluateCalibrationResult() {
        countdownTimer?.invalidate()
        isCalibrating = false
        if btVM.baselineResult != nil {
            calibrationSucceeded = true
        } else {
            calibrationFailed = true
        }
    }

    /// 按下「校正」先進入 3 秒準備階段，畫面每秒閃爍一次「請站好，不要動」（共 3 次），
    /// 3 秒後才真正呼叫既有的 startCalibration()（5 秒倒數＋收集，秒數不變）。
    private func startPreparing() {
        guard thighAndCalfPeripherals != nil else { return }
        calibrationFailed = false
        isPreparing = true
        prepTickCount = 0
        prepTimer?.invalidate()

        triggerPrepBlink()
        prepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            prepTickCount += 1
            if prepTickCount >= 3 {
                timer.invalidate()
                isPreparing = false
                startCalibration()
            } else {
                triggerPrepBlink()
            }
        }
    }

    /// 提示文字「閃一下」：淡入、短暫停留、淡出，配合每秒觸發一次的 Timer，做出「每秒重新出現一次」的效果。
    private func triggerPrepBlink() {
        prepMessageVisible = false
        withAnimation(.easeIn(duration: 0.15)) {
            prepMessageVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                prepMessageVisible = false
            }
        }
    }

    private func handleButtonTap() {
        if calibrationSucceeded {
            onCalibrated()
        } else if !isCalibrating && !isPreparing {
            startPreparing()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_12.darkPurple)

                Text(sideLabelText)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PreWorking_12.midPurple)
            }

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_12.midPurple)
                    .frame(width: 4)
                Text(subtitle)
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            if calibrationSucceeded {
                PreWorking12StepCapsuleButton(text: "下一步", icon: "arrow.right", action: handleButtonTap)
            } else {
                Button(action: handleButtonTap) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.90, green: 0.87, blue: 0.98))
                        Circle()
                            .strokeBorder(PreWorking_12.midPurple, lineWidth: 4)
                        Text(circleButtonLabel)
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(PreWorking_12.darkPurple)
                            .multilineTextAlignment(.center)
                            .opacity(isPreparing ? (prepMessageVisible ? 1 : 0) : 1)
                    }
                    .frame(width: 200, height: 200)
                }
                .buttonStyle(.plain)
                .disabled(isCalibrating || isPreparing || thighAndCalfPeripherals == nil)
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
            prepTimer?.invalidate()
        }
    }
}

// MARK: - Motion Test About Panel

private struct PreWorking12MotionTestAboutPanel: View {
    let title: String
    let subtitle: String
    var onPlayGame: () -> Void = {}

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var side: Int = 0

    private enum GamePrepPhase: Equatable {
        case idle
        case counting(secondsRemaining: Int)
        case waiting
    }

    @State private var prepPhase: GamePrepPhase = .idle
    @State private var prepTimer: Timer?

    private var playButtonText: String {
        switch prepPhase {
        case .idle: return "遊戲"
        case .counting(let remaining): return "清理中(\(remaining))"
        case .waiting: return "再等待一下..."
        }
    }

    /// 點擊「遊戲」後，先在畫面上顯示 3 秒的視覺倒數（清理中(3)→(2)→(1)→(0)）；
    /// 倒數顯示到 0 的同時就在背景開始真正判斷／執行清理，如果又過了 1 秒還沒處理完，
    /// 文字才改成「再等待一下...」，避免卡在「清理中(0)」不動看起來像當掉了。
    private func startGamePreparation() {
        guard prepPhase == .idle else { return }
        prepPhase = .counting(secondsRemaining: 3)
        prepTimer?.invalidate()
        prepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            switch prepPhase {
            case .counting(let remaining) where remaining > 0:
                let next = remaining - 1
                prepPhase = .counting(secondsRemaining: next)
                if next == 0 { performCleanupThenPlay() }
            case .counting:
                prepPhase = .waiting
            case .waiting:
                break
            case .idle:
                timer.invalidate()
                prepTimer = nil
            }
        }
    }

    private func performCleanupThenPlay() {
        DeviceViewModel().cleanupIfNeeded(
            onStart: { btVM.isCleaningUp = true },
            onFinish: {
                btVM.isCleaningUp = false
                prepTimer?.invalidate()
                prepTimer = nil
                prepPhase = .idle
                onPlayGame()
            }
        )
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

    /// 呼叫即時登階狀態估計，讓感測管線在進入遊戲前先暖機。
    private func startLiveTestIfNeeded() {
        guard !btVM.isEstimatingStepStatus,
              let pair = thighAndCalfPeripherals,
              let baseline = btVM.baselineResult
        else { return }
        btVM.startStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline)
    }

    private func stopLiveTestIfNeeded() {
        guard btVM.isEstimatingStepStatus, let pair = thighAndCalfPeripherals else { return }
        btVM.stopStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
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
                    .foregroundStyle(PreWorking_12.darkPurple)

                Text(sideLabelText)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PreWorking_12.midPurple)
            }

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_12.midPurple)
                    .frame(width: 4)
                Text(subtitle)
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            PreWorking12StepCapsuleButton(text: playButtonText, icon: "arrow.right", action: {
                startGamePreparation()
            })

            Spacer()
        }
        .padding(40)
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
            startLiveTestIfNeeded()
        }
        .onDisappear {
            stopLiveTestIfNeeded()
            prepTimer?.invalidate()
            prepTimer = nil
        }
    }
}

// MARK: - Guide Page

/// 「動作逐步指南」內部的分頁，之後每新增一頁指南就在這裡加一個 case。
private enum PreWorking12GuideStep {
    case ready
    case ing
    case stair

    var title: String {
        switch self {
        case .ready: "動作逐步指南\n1. 準備姿勢"
        case .ing: "動作逐步指南\n2. 向上登階"
        case .stair: "動作逐步指南\n3. 下降回到起始位置"
        }
    }

    var bodyText: String {
        switch self {
        case .ready:
            "雙腳站立於台階前，約與髖部同寬，腳尖朝向正前方，與台階保持數吋距離。抬起一腳，將整隻腳掌完全踏上台階，確保腳跟沒有懸空。從正面觀察，髖、膝、腳踝應呈一直線對齊。"
        case .ing:
            "利用前腳（踏在台階上的那隻腳）發力，將身體驅動向上，同時保持軀幹直立、姿勢良好，避免身體前傾。"
        case .stair:
            "登上台階後，將剛抬起的那隻腳放下，並以受控的方式緩慢下降，全程維持良好姿勢。重複此動作，換腿進行，完成所需的組數與次數。"
        }
    }

    /// 對應匯入的示範圖 asset 名稱中間那段字樣（Exercise12SideView{stage}Left 之類）。
    var poseImageStage: String {
        switch self {
        case .ready: "Ready"
        case .ing: "Ing"
        case .stair: "Stair"
        }
    }

    var next: PreWorking12GuideStep? {
        switch self {
        case .ready: .ing
        case .ing: .stair
        case .stair: nil
        }
    }

    var previous: PreWorking12GuideStep? {
        switch self {
        case .ready: nil
        case .ing: .ready
        case .stair: .ing
        }
    }
}

extension PreWorking12GuideStep: Equatable {}

private struct PreWorking12GuidePage: View {
    @State private var side: Int = 0
    @State private var guideStep: PreWorking12GuideStep = .ready
    /// 從第一頁「準備站立」再按上一步時，回到外層的「放置平板」頁。
    var onExitToPreviousStep: () -> Void = {}
    /// 從最後一頁「站穩後下階」再按下一步時，前進到外層的「校正」頁。
    var onAdvanceToNextStep: () -> Void = {}

    /// side = 0（左，含資料庫查無資料時的預設值）或 1（右），對應到匯入的示範圖 asset 名稱。
    private var sideViewImageName: String {
        let stage = guideStep.poseImageStage
        return side == 1 ? "Exercise12SideView\(stage)Right" : "Exercise12SideView\(stage)Left"
    }

    private var sideLabelText: String {
        "\(side == 1 ? "右" : "左")腳版本"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                Text(guideStep.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_12.darkPurple)
                    .lineSpacing(6)

                Text(guideStep.bodyText)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineSpacing(6)
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 180, alignment: .topLeading)

                HStack(spacing: 16) {
                    PreWorking12StepCapsuleButton(text: "上一步", icon: "arrow.left", iconLeading: true) {
                        if let previous = guideStep.previous {
                            guideStep = previous
                        } else {
                            onExitToPreviousStep()
                        }
                    }

                    PreWorking12StepCapsuleButton(text: "下一步", icon: "arrow.right", iconLeading: false) {
                        if let next = guideStep.next {
                            guideStep = next
                        } else {
                            onAdvanceToNextStep()
                        }
                    }
                }
            }
            .frame(maxWidth: 380, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                Text(sideLabelText)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PreWorking_12.midPurple)

                PreWorking12PoseImageCard(imageName: sideViewImageName)
                    .frame(width: 500, height: 500)
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

private struct PreWorking12PoseImageCard: View {
    let imageName: String?

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
                .stroke(PreWorking_12.midPurple, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

#Preview {
    PreWorking_12(
        content: TreatmentContent(treatment_id: 1, exercise_id: 12, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil,
        onReturnToDashboard: {}
    )
}

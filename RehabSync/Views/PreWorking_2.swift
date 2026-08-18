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
    @Environment(BluetoothViewModel.self) private var btVM
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
        // 🔴 TKE 路徑的 PreWorking 端停用點**只有這裡**（根 View），兩個子面板都不可以停（§8.4）。
        //
        // 根 View 的語意剛好吻合三種需求，不需要額外的狀態判斷：
        //   校正面板 → 動作測試面板（切換 step）：不觸發（同一個根 View）→ 路徑存活 ✅
        //   按返回離開 PreWorking_2：          觸發                    → 路徑停用 ✅
        //   .fullScreenCover 進 Working2：      不觸發（被覆蓋的那一層）  → 交棒 ✅
        //
        // 少了這一行就會有這個洩漏：校正失敗後使用者直接按返回離開，校正面板依規則不停用、
        // 動作測試面板從未出現所以它的 .onDisappear 永遠不觸發 → 路徑永久殘留 →
        // 接著進 PreWorking_9，TKE 分支在 liveEstimating 之前 return，動作 9 的即時角度完全失效。
        .onDisappear {
            if btVM.isTKEPathActive { btVM.stopTKEPath() }
        }
        .fullScreenCover(isPresented: $navigateToWorking2) {
            Working2(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)
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
    @State private var isPreparing = false
    @State private var prepMessageVisible = false
    @State private var prepTickCount = 0
    @State private var prepTimer: Timer?
    @State private var isCalibrating = false
    @State private var calibrationCountdown = calibrationSeconds
    @State private var countdownTimer: Timer?
    @State private var calibrationSucceeded = false
    /// 校正結果訊息（`KneeCalibrationResult.message`）。11 種：10 種失敗 + 1 種「校正成功」。
    /// 取代原本的 `calibrationFailed: Bool` —— 新流程要把**原因**告訴使用者，不只是成功/失敗。
    @State private var calibrationMessage: String?

    private let prepMessage = "請坐好\n不要動"

    /// 收集秒數。**畫面倒數與 `startKneeCalibration(durationSec:)` 必須是同一個值** ——
    /// 兩邊各寫一次數字就是「有兩份、改了一份」，倒數歸零時後端還沒算完（或反之）。
    ///
    /// 用 5 而不是 `Test.swift` 的 8：TKE 路徑在 3 秒閃爍提示階段（`startPreparing`）就已啟用，
    /// 平滑視窗（N=30 ≈ 0.29 秒）在收集開始前就填滿，所以這 5 秒是**零暖機損耗**的 5 秒 ——
    /// 520 筆全部可用，對 250 門檻佔比 48%，正好還原 Python 原版的門檻嚴格度。
    /// `Test.swift` 的 8 秒是為了補償「收集期包含路徑啟動」才放寬的。詳見 §8.2①。
    private static let calibrationSeconds = 5

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

    /// 按下「校正」開始 5 秒倒數（純視覺），同時呼叫真正的校正演算法；
    /// 成功或失敗的判定由 `startKneeCalibration` 的 completion 觸發（後端真正算完的那一刻），
    /// 不再用「倒數結束 + 0.3 秒緩衝」去猜後端是否已經算完——猜測秒數在系統忙碌時會不準，
    /// 曾經發生過後端其實已經算出結果、但 UI 因為猜測時間到了而提早判定失敗的競爭情況。
    ///
    /// 演算法已從舊的 `startBaselineCalibration`（`ACCCalibration.computeBaseline`，自動偵測穩定平台
    /// + mapping table）換成 offset 模型 `startKneeCalibration`（`KneeCalibration.computeOffsets`）。
    /// **舊函式不可移除** —— 動作 9／12／22 仍在使用（§8.1）。
    private func startCalibration() {
        guard let pair = thighAndCalfPeripherals else { return }
        calibrationMessage = nil
        isCalibrating = true
        calibrationCountdown = Self.calibrationSeconds
        countdownTimer?.invalidate()
        // 路徑已在 startPreparing() 啟用，這裡 startKneeCalibration 內部的 alreadyActive 分支會成立，
        // 因此不會重置 tkeClock 與平滑器（§8.2②）——這正是「5 秒零暖機損耗」的前提。
        // ownsConnectionRecovery 省略不傳：預設 false，正式流程不啟動 tkeFreshnessTimer（§8.3）。
        btVM.startKneeCalibration(spec: TKESpec.self,
                                  thighPeripheral: pair.thigh, calfPeripheral: pair.calf,
                                  durationSec: Double(Self.calibrationSeconds)) { result in
            evaluateCalibrationResult(result)
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if calibrationCountdown > 1 {
                calibrationCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    /// 由 `startKneeCalibration` 的 completion 呼叫（已在主執行緒、且 `btVM.tkeResult` 已寫入完成）。
    ///
    /// 刻意收 `result` 參數而不是回頭讀 `btVM.tkeResult` —— 兩者內容相同，但直接用參數
    /// 就不存在「讀到的是不是這一次的結果」這個問題。
    private func evaluateCalibrationResult(_ result: KneeCalibrationResult) {
        countdownTimer?.invalidate()
        isCalibrating = false
        // succeeded == (thigh != nil && calf != nil)，等價於 §8.2② 的 `if let thigh, let calf`
        calibrationSucceeded = result.succeeded
        // 成功也顯示訊息（"校正成功"），不只失敗才顯示 —— 11 種訊息共用同一個顯示位置（§8.2③）
        calibrationMessage = result.message
    }

    /// 按下「校正」先進入 3 秒準備階段，畫面每秒閃爍一次「請坐好，不要動」（共 3 次），
    /// 3 秒後才真正呼叫既有的 startCalibration()（5 秒倒數＋收集，秒數不變）。
    ///
    /// 🔴 **TKE 路徑在這裡啟用，不是在 `startCalibration()`。**
    /// 3 秒閃爍提示階段真正的作用是**填滿平滑視窗**（N=30 ≈ 0.29 秒）——
    /// 視窗若沒先填滿，收集期的前 29 筆會被丟棄，那才是「520 筆零暖機損耗」的來源。
    /// 順帶累積的約 15 個回歸觀測點不是重點（門檻只有 10，從來不是瓶頸）。詳見 §8.2①。
    ///
    /// 🔴 **路徑的停用點在根 View 的 `.onDisappear`，不在這個面板。**
    /// 校正成功會切換到動作測試面板、本面板隨之消失；若在這裡停用會清掉 clock 與平滑器，
    /// 動作測試面板得重新暖機約 2 秒 —— 而那個症狀看起來像效能問題、不像設定錯誤（§8.4）。
    private func startPreparing() {
        guard let pair = thighAndCalfPeripherals else { return }
        // 已啟用就不重啟：重啟會清掉 tkeClock／平滑器／buffer，重試反而比第一次更沒有暖機餘裕，
        // 也會多送一次 cmd_a0/a1/a2 與 setNotify。比照 startKneeCalibration 自己的 alreadyActive 判斷。
        if !btVM.isTKEPathActive {
            // ownsConnectionRecovery 省略不傳：預設 false。正式流程不可啟動 tkeFreshnessTimer，
            // 否則組間休息時它會把 stopRecordingAll 剛關掉的 notify 重新訂閱回來（§8.3）。
            btVM.startTKEPath(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
        }
        calibrationMessage = nil
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
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(PreWorking_2.darkPurple)
                            .multilineTextAlignment(.center)
                            .opacity(isPreparing ? (prepMessageVisible ? 1 : 0) : 1)
                    }
                    .frame(width: 200, height: 200)
                }
                .buttonStyle(.plain)
                .disabled(isCalibrating || isPreparing || thighAndCalfPeripherals == nil)
                .opacity(thighAndCalfPeripherals == nil ? 0.4 : 1)
            }

            // 校正結果訊息（§8.2③）：11 種共用同一個位置，成功綠、失敗紅。
            //
            // 🔴 高度固定保留，不能只在有訊息時才出現 —— 這個 VStack 上下都是 Spacer，
            // 內容高度一變整組就重新置中，圓圈會上下跳動。版面以最長的 5b 動態字串為準
            //（「封包遺失嚴重（大腿 12 包 / 小腿 38 包），請確認裝置距離與電量」約 30 字），
            // 在半個畫面寬度下會折成兩行，所以固定保留兩行的高度。
            Text(calibrationMessage ?? " ")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(calibrationSucceeded ? Color.green : Color.red)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .opacity(calibrationMessage == nil ? 0 : 1)

            if !calibrationSucceeded && thighAndCalfPeripherals == nil {
                Text("裝置未連線")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(40)
        .onAppear {
            DeviceViewModel().debugDumpAllDevices(tag: "CalibrationAboutPanel.onAppear")
            side = DeviceViewModel().fetchAnySide() ?? 0
            print("[SIDE-DIAG] CalibrationAboutPanel.onAppear side=\(side)")
        }
        .onDisappear {
            countdownTimer?.invalidate()
            prepTimer?.invalidate()
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
    /// 不需要清理的話幾乎立刻接著跳轉；需要清理的話就停留在等待文字直到清理真正完成才跳轉。
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
                // 顯示「清理中(0)」又過了 1 秒，清理判斷／處理還沒完成。
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
                // 明確在導頁進 Working2 前停止 PreWorking 獨立 Channel A（working2-database-port-plan.md
                // 18.2）——這裡是真正觸發 navigateToWorking2 = true 的那一刻，不能依賴 onDisappear
                // （.fullScreenCover 不會觸發底層 onDisappear），否則會一路帶進 Working2 干擾它自己的 Channel A。
                if let pair = thighAndCalfPeripherals {
                    btVM.stopPreTestChannelA(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                }
                // 🔴 TKE 路徑與即時角度刻意**不停用**——採「交棒」模式（§8.4）：
                // 一路帶進 Working2，由 2_Working 的 .onDisappear 收尾（階段 D）。
                // 好處是無轉場空窗、tkeClock 連續、免 2 秒暖機；比照現行 isLiveEstimating 的做法。
                // 這裡只停 Channel A，因為 Working2 有它自己的 Channel A，兩者會互相干擾。
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

    /// 啟動「Channel A（4 訊號連線／新鮮度檢查）」與「即時角度」——**兩者各自獨立判斷，不共用 guard**。
    ///
    /// 🔴 **這對函式最容易照抄成錯的**：名字與呼叫點都不必改，看起來完全不用動，
    /// 但舊版把三件事綁在同一個 guard 底下：
    ///
    /// ```swift
    /// guard !btVM.isLiveEstimating,
    ///       let pair = thighAndCalfPeripherals,
    ///       let baseline = btVM.baselineResult   // ← 新流程不再產生這個值
    /// else { return }
    /// btVM.startLiveEstimateRealAngle(...)
    /// btVM.startPreTestChannelA(...)            // ← 跟著被擋掉
    /// ```
    ///
    /// 動作 2 改用 offset 模型後 `baselineResult` 永遠是 nil、`isLiveEstimating` 永遠是 false，
    /// guard 直接短路 —— `startPreTestChannelA` **一次都不會被呼叫**，
    /// 4 訊號新鮮度檢查、EXG／GYRO 訂閱、連線修復全部消失，
    /// 動作測試階段退化成跟校正階段一樣沒有保護，**而畫面上看不出任何異常**。
    ///
    /// 這與第 14 節「`thighAndCalfPeripherals` 沒帶 `side:` 導致右腳 guard 永遠短路」同型 ——
    /// **把多件事綁在同一個 guard 底下，其中一件的前提改變就會連坐**（§8.3）。
    private func startLiveTestIfNeeded() {
        guard let pair = thighAndCalfPeripherals else { return }

        // ① Channel A：無條件啟動 —— 它監控 ACC／GYRO／EXG_CH0／EXG_CH1 共 4 個訊號，
        //    與校正結果、與用哪個角度模型完全無關。TKE 路徑只訂閱 ACC，取代不了它（§8.3）。
        btVM.startPreTestChannelA(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)

        // ② 角度路徑：另外判斷。含 §8.2④ 的 side 一致性檢查 ——
        //    校正後換綁裝置會讓 k 值符號相反、theta 整個偏 180°，而畫面上只會看到
        //    一個看似合理但錯誤的數字。正常流程走不到（離開頁面會 stopTKEPath 清掉 tkeResult），
        //    但保留為防禦；不做專屬 UI，失敗時印 log 即可。
        guard let r = btVM.tkeResult, r.succeeded else {
            print("[TKE-LIVE] 動作測試面板：尚無成功的校正結果，不啟動即時角度")
            return
        }
        guard r.side == side else {
            print("[TKE-LIVE] ⚠️ 動作測試面板：綁定側已變更（校正時=\(r.side)、目前=\(side)），不啟動即時角度")
            return
        }
        btVM.startTKELiveAngle()
    }

    /// 只停 Channel A。
    ///
    /// 🔴 **這裡不可以呼叫 `stopTKEPath()`**：本函式掛在動作測試面板的 `.onDisappear`，
    /// 使用者從動作測試面板退回校正面板時也會觸發 —— 那會誤殺路徑。
    /// TKE 路徑的停用點統一在**根 View 的 `.onDisappear`**（§8.4，已於階段 B 實作）。
    ///
    /// 📌 **也刻意不呼叫 `stopTKELiveAngle()`**：即時角度要一路交棒進 `Working2`
    /// （`.fullScreenCover` 不觸發底層 `onDisappear`，所以導頁時本函式不會執行）。
    /// 把它放進來會讓整個交棒機制的成立與否，取決於 `fullScreenCover` 的 `onDisappear` 語意。
    /// 唯一沒被涵蓋的情境是「從動作測試面板退回校正面板重新校正」，
    /// 目前 UI 沒有這條路徑（動作測試面板沒有上一步按鈕）；
    /// **日後若要加上一步按鈕，必須在那個 action 裡明確呼叫 `stopTKELiveAngle()`** ——
    /// 否則即時與校正會同時操作 `tkeBuffers`，兩者的 buffer 保留規則是衝突的（§4.5①）。
    private func stopLiveTestIfNeeded() {
        guard let pair = thighAndCalfPeripherals else { return }
        btVM.stopPreTestChannelA(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
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
                // 讀 displayKneeAngle（夾限到 0），不是 currentEstimatedRealAngle。
                // offset 模型完全伸直時 theta 是負值（實測 −12.7°／−15.6°），那是 C 增益補償的
                // 預期行為、對演算法有意義，所以計算與寫入 advanced_statistics 都不夾限；
                // 但顯示「−12.7°」對治療師是異常數字，只有顯示層夾限（§20.3）。
                if let angle = btVM.displayKneeAngle {
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

            PreWorkingStepCapsuleButton(text: playButtonText, icon: "arrow.right", action: {
                startGamePreparation()
            })

            Spacer()
        }
        .padding(40)
        .onAppear {
            DeviceViewModel().debugDumpAllDevices(tag: "MotionTestAboutPanel.onAppear")
            side = DeviceViewModel().fetchAnySide() ?? 0
            print("[SIDE-DIAG] MotionTestAboutPanel.onAppear side=\(side)")
            startLiveTestIfNeeded()
        }
        .onDisappear {
            stopLiveTestIfNeeded()
            prepTimer?.invalidate()
            prepTimer = nil
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

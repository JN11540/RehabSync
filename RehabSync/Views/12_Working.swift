import SwiftUI
import CoreBluetooth
import AVFoundation

// MARK: - Working12

struct Working12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void
    @Environment(BluetoothViewModel.self) private var btVM

    /// 裝置目前實際綁定在哪一側（左/右），給引導圈圈決定播放哪一支示範影片用。
    private var side: Int {
        DeviceViewModel().fetchAnySide() ?? 0
    }

    // 校正/測試階段在 PreWorking 啟動的登階狀態估計，離開這裡時必須主動停止，
    // 否則 btVM.isEstimatingStepStatus 會卡在 true，導致下次進測試頁時
    // guard 擋住重啟，currentStepStatus 永遠是 nil、畫面卡在「等待資料…」。
    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    private func stopStepStatusIfNeeded() {
        guard btVM.isEstimatingStepStatus, let pair = thighAndCalfPeripherals else { return }
        btVM.stopStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
    }

    // MARK: - treatment_result 建立與串接

    private let resultVM = TreatmentResultViewModel()
    @State private var treatmentResult: TreatmentResult?

    /// 遊戲一開始（畫面顯示的那一刻）先建立這局遊戲唯一一筆 treatment_result，
    /// 陣列長度依目標組數/目標次數計算、全部初始化為 0，再把 id 交給 btVM
    /// 讓之後 acc/gyro/exg/advanced_statistics 每一筆寫入都能帶上這個 treatment_result_id。
    /// 建立完成後緊接著視同第一組的起始點，開始記錄。
    /// `extension_length` 這個動作不計算（登階沒有天然對應的「伸展時長」），陣列維持全 0，不再另外更新。
    private func createTreatmentResultIfNeeded() {
        guard treatmentResult == nil else { return }
        var result = TreatmentResult(
            treatment_id: content.treatment_id,
            treatment_content_id: Int(content.id ?? 0),
            reps: Array(repeating: 0, count: content.sets),
            extension_length: Array(repeating: 0, count: content.sets * content.reps),
            set_start_time: Array(repeating: 0, count: content.sets),
            set_end_time: Array(repeating: 0, count: content.sets),
            date: Int(Date().timeIntervalSince1970 * 1000)
        )
        resultVM.insert(&result)
        treatmentResult = result
        btVM.currentTreatmentResultId = result.id
        markSetStart(index: 0)
    }

    @State private var setTimeLimitTimer: Timer?
    /// 這一組 3 分鐘倒數的起訖區間，交給 `Text(timerInterval:)` 顯示畫面上的倒數數字。
    @State private var setCountdownRange: ClosedRange<Date>?

    private static let setTimeLimit: TimeInterval = 180

    /// 某一組的起始點：把當下毫秒時間戳記寫進 set_start_time[index]、打開 acc/gyro/exg 的記錄，
    /// 並啟動這一組的 3 分鐘倒數上限。
    private func markSetStart(index: Int) {
        guard var result = treatmentResult, result.set_start_time.indices.contains(index) else { return }
        result.set_start_time[index] = Int(Date().timeIntervalSince1970 * 1000)
        treatmentResult = result
        resultVM.update(result)
        btVM.startRecordingAll()

        let now = Date()
        setCountdownRange = now...now.addingTimeInterval(Self.setTimeLimit)

        setTimeLimitTimer?.invalidate()
        setTimeLimitTimer = Timer.scheduledTimer(withTimeInterval: Self.setTimeLimit, repeats: false) { _ in
            handleSetTimeLimitReached()
        }
    }

    /// 某一組的結束點：停止 acc/gyro/exg 的記錄、取消該組的 3 分鐘倒數計時器，
    /// 並把結束時間、實際完成次數一併寫回 treatment_result（reps 達標時傳目標次數，
    /// 提前結束／倒數歸零時傳目前實際完成次數）。
    private func finishSet(index: Int, reps: Int) {
        guard var result = treatmentResult, result.set_end_time.indices.contains(index) else { return }
        setTimeLimitTimer?.invalidate()
        setTimeLimitTimer = nil
        setCountdownRange = nil
        btVM.stopRecordingAll()
        result.set_end_time[index] = Int(Date().timeIntervalSince1970 * 1000)
        result.reps[index] = reps
        treatmentResult = result
        resultVM.update(result)
    }

    /// 從起始點起算倒數 3 分鐘歸零，視同該組提前結束。
    private func handleSetTimeLimitReached() {
        cancelInProgressStepCycleWithoutCounting()
        finishSet(index: currentSet - 1, reps: currentRep)
        if currentSet < content.sets {
            startSetRestCountdown()
        } else {
            showCompletionPopup = true
        }
    }

    /// 「提前結束觸發當下正卡在半途的登階循環」的邊界情況：直接取消，不計入 reps。
    private func cancelInProgressStepCycleWithoutCounting() {
        standingTimer?.invalidate()
        standingTimer = nil
        standingElapsed = 0
        pendingCoinCount = nil
    }

    /// 動作品質評分暫時關閉（working12-database-port-plan.md 第 15 節）：`false` 時強制畫面停留在
    /// 「站立」視覺狀態、`standingTimer` 不讀秒，不受真實 BLE `currentStepStatus` 影響；之後要恢復
    /// 只需要把這個值改回 `true`，不需要另外復原程式碼。
    private let isMovementQualityScoringEnabled = false

    @State private var standingElapsed: Double = 0
    @State private var standingTimer: Timer?
    /// 離開站立（開始上階）當下先依站立等待秒數評好分，暫存起來，
    /// 等到下階回到站立那一瞬間才實際觸發送餐／硬幣獎勵動畫。
    @State private var pendingCoinCount: Int?
    @State private var showGiveFood = false
    @State private var showReceive = false
    @State private var showCoinRain = false
    @State private var coinRainElapsed: Double = 0
    @State private var coinRainCount = 0
    @State private var coinRainTimer: Timer?
    @State private var foodScale: CGFloat = 1
    @State private var foodBrightness: Double = 0
    @State private var scoreElapsed: Double = -1
    @State private var scoreTimer: Timer?
    @State private var totalCoins = 0
    @State private var currentSet = 1
    @State private var currentRep = 0
    @State private var comingMoodCount = 0
    @State private var badMoodCount = 0
    @State private var angryMoodCount = 0
    @State private var showExitConfirmPopup = false
    @State private var showSetRestPopup = false
    @State private var setRestCountdown: Int = 0
    @State private var setRestTimer: Timer?
    @State private var navigateToPostWorking12 = false
    @State private var sessionStartDate = Date()
    @State private var finalElapsedSeconds = 0
    @State private var isSessionPaused = false
    @State private var showCompletionPopup = false

    private static let standingDuration: Double = 9
    private static let giveFoodDuration: Double = 1.5
    private static let foodPulseStepDuration: Double = 0.25
    private static let foodPulseScale: CGFloat = 1.3
    private static let foodPulseBrightness: Double = 0.3
    private static let coinLanternPixel = CGPoint(x: 836, y: 190)
    private static let coinFanPixel = CGPoint(x: 630, y: 430)
    private static let scoreLabelPixel = CGPoint(x: 960, y: 250)
    private static let scoreHoldAfterLast: Double = 0.6
    private static let overlayCanvasSize = CGSize(width: 1232, height: 864)

    private static func overlayPosition(for fraction: CGPoint, in size: CGSize, padding: CGFloat = 48) -> CGPoint {
        let frameW = size.width - padding * 2
        let frameH = size.height - padding * 2
        guard frameW > 0, frameH > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let scale = max(frameW / overlayCanvasSize.width, frameH / overlayCanvasSize.height)
        let visibleW = frameW / scale
        let visibleH = frameH / scale
        let cropX = (overlayCanvasSize.width - visibleW) / 2
        let cropY = (overlayCanvasSize.height - visibleH) / 2
        let relX = (fraction.x * overlayCanvasSize.width - cropX) / visibleW
        let relY = (fraction.y * overlayCanvasSize.height - cropY) / visibleH
        return CGPoint(x: padding + relX * frameW, y: padding + relY * frameH)
    }

    private static func canvasFraction(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: x / overlayCanvasSize.width, y: y / overlayCanvasSize.height)
    }

    private var stepStatusLabel: String {
        guard isMovementQualityScoringEnabled else { return "站立" }
        switch btVM.currentStepStatus {
        case 0: return "站立"
        case 1: return "上階"
        case 2: return "下階"
        default: return "—"
        }
    }

    private var characterImageName: String {
        if showGiveFood { return "TakoyakiGiveFoodIcon" }
        guard isMovementQualityScoringEnabled else { return "TakoyakiHelloIcon" }
        switch btVM.currentStepStatus {
        case 1, 2: return "TakoyakiMakeFoodIcon"
        default: return "TakoyakiHelloIcon"
        }
    }

    private var capsuleFillColor: Color {
        if standingElapsed >= 7 { return .red }
        if standingElapsed >= 5 { return .orange }
        return .yellow
    }

    private var customerImageName: String {
        if showReceive { return "TakoyakiCustomerReceiveIcon" }
        if standingElapsed >= 7 { return "TakoyakiCustomerAngryIcon" }
        if standingElapsed >= 5 { return "TakoyakiCustomerBadIcon" }
        return "TakoyakiCustomerComingIcon"
    }

    private func startStandingTimer() {
        guard isMovementQualityScoringEnabled else { return }
        guard standingTimer == nil else { return }
        standingElapsed = 0
        standingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard standingElapsed < Self.standingDuration else { return }
            standingElapsed = min(standingElapsed + 0.1, Self.standingDuration)
        }
    }

    private func stopStandingTimer() {
        standingTimer?.invalidate()
        standingTimer = nil
        standingElapsed = 0
    }

    // takoyaki_food.png 只在 showReceive 的 1.5 秒視窗內出現，期間「放大＋變亮」再「回到原狀」共 3 次，
    // 3 次剛好填滿 1.5 秒（3 * 2 * 0.25s），跟 9_Working.swift 的 startPulse 是同一種節奏排法。
    private func startFoodPulse() {
        foodScale = 1
        foodBrightness = 0
        for i in 0..<3 {
            let upTime = Double(i) * Self.foodPulseStepDuration * 2
            let downTime = upTime + Self.foodPulseStepDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + upTime) {
                withAnimation(.easeInOut(duration: Self.foodPulseStepDuration)) {
                    foodScale = Self.foodPulseScale
                    foodBrightness = Self.foodPulseBrightness
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + downTime) {
                withAnimation(.easeInOut(duration: Self.foodPulseStepDuration)) {
                    foodScale = 1
                    foodBrightness = 0
                }
            }
        }
    }

    // 硬幣用自己的 Timer 依 elapsed 時間驅動（而非固定總長的 withAnimation），
    // 確保不論這次是 3 顆、9 顆還是 15 顆，每一顆都會依序完整跑完拋物線。
    private func startCoinRain(count: Int) {
        coinRainTimer?.invalidate()
        coinRainCount = count
        coinRainElapsed = 0
        showCoinRain = true
        let start = Date()
        let totalDuration = Double(count - 1) * CoinRainBurst.stagger + CoinRainBurst.flightDuration
        coinRainTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let e = Date().timeIntervalSince(start)
            coinRainElapsed = e
            if e >= totalDuration {
                t.invalidate()
                showCoinRain = false
            }
        }
    }

    // 數字累加跟硬幣飛行動畫脫鉤，用自己的 Timer 依固定節奏（CoinBurstScoreLabel.stagger）逐一往上跳，
    // 確保無論硬幣數量多少，一定會完整跑完第一個數字到最後一個數字，不受拋物線飛行時間影響。
    private func startScoreSequence(count: Int) {
        scoreTimer?.invalidate()
        let start = Date()
        scoreElapsed = 0
        var lastAppeared = 0
        let totalDuration = Double(count) * CoinBurstScoreLabel.stagger + Self.scoreHoldAfterLast
        scoreTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let e = Date().timeIntervalSince(start)
            scoreElapsed = e
            let currentAppeared = e >= 0 ? min(count, Int(e / CoinBurstScoreLabel.stagger) + 1) : 0
            if currentAppeared > lastAppeared {
                totalCoins += (currentAppeared - lastAppeared) * 100
                lastAppeared = currentAppeared
            }
            if e >= totalDuration {
                t.invalidate()
                scoreElapsed = -1
            }
        }
    }

    private func pauseSession() {
        isSessionPaused = true
        standingTimer?.invalidate()
        standingTimer = nil
        coinRainTimer?.invalidate()
        coinRainTimer = nil
        scoreTimer?.invalidate()
        scoreTimer = nil
        setRestTimer?.invalidate()
        setRestTimer = nil
    }

    private func resumeSession() {
        isSessionPaused = false
    }

    private func startSetRestCountdown() {
        cancelInProgressStepCycleWithoutCounting()
        setRestTimer?.invalidate()
        setRestCountdown = content.set_rest_time
        showSetRestPopup = true
        setRestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            setRestCountdown -= 1
            if setRestCountdown <= 0 {
                closeSetRestPopup()
            }
        }
    }

    private func closeSetRestPopup() {
        setRestTimer?.invalidate()
        setRestTimer = nil
        showSetRestPopup = false
        if currentSet < content.sets {
            currentSet += 1
        }
        currentRep = 0
        markSetStart(index: currentSet - 1)
    }

    // 每次下階回到站立、送餐動畫觸發時即視為完成一「次」：依這次上階前站立等待了幾秒落在哪個檔位累計對應的心情次數，
    // 次數集滿 content.reps 才算完成一組，這時再判斷是否還有下一組（進組間休息）或已經是最後一組（直接前往 PostWorking12）。
    private func advanceProgress(coinCount: Int) {
        switch coinCount {
        case 15: comingMoodCount += 1
        case 9: badMoodCount += 1
        default: angryMoodCount += 1
        }
        currentRep += 1
        if currentRep >= content.reps {
            finishSet(index: currentSet - 1, reps: content.reps)
            if currentSet < content.sets {
                startSetRestCountdown()
            } else {
                showCompletionPopup = true
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.ignoresSafeArea()

            Image("TakoyakiBackgroundIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: 2)
                )
                .padding(48)
                .opacity(0.4)

            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.72, green: 0.82, blue: 0.82))

                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 1.0, green: 0.85, blue: 0.35))
                            .overlay(
                                HStack(spacing: 10) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.5))
                                        .frame(width: 10, height: 80)
                                        .rotationEffect(.degrees(20))
                                        .offset(x: 6)
                                    Rectangle()
                                        .fill(Color.white.opacity(0.5))
                                        .frame(width: 5, height: 80)
                                        .rotationEffect(.degrees(20))
                                }
                            )
                            .frame(width: 115, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(red: 0.70, green: 0.52, blue: 0.10), lineWidth: 3)
                            )

                        ZStack(alignment: .leading) {
                            Image("CoinIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .offset(x: -16)

                            Text("\(totalCoins)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: 115 - 38, height: 48)
                                .offset(x: 38)
                        }
                        .frame(width: 115, height: 48)
                        .offset(x: -24)
                    }
                    .frame(width: 115, height: 48)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)

                    HStack(spacing: 12) {
                        Button(action: {
                            showExitConfirmPopup = true
                            pauseSession()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                Circle()
                                    .strokeBorder(Color.black, lineWidth: 1.5)
                                Circle()
                                    .strokeBorder(Color.black, lineWidth: 1.5)
                                    .padding(4)
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)

                        if let setCountdownRange {
                            Text(timerInterval: setCountdownRange, countsDown: true)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)

                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Image("TargetIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            Text("\(content.sets) 組 × \(content.reps) 次")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        Rectangle()
                            .fill(Color(white: 0.35))
                            .frame(width: 2, height: 40)

                        HStack(spacing: 4) {
                            Image("WeightliftingIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            Text("第 \(currentSet) 組．第 \(currentRep) 次")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        Rectangle()
                            .fill(Color(white: 0.35))
                            .frame(width: 2, height: 40)

                        HStack(spacing: 4) {
                            Image("TakoyakiCustomerComingMoodIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                            Text("\(comingMoodCount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Image("TakoyakiCustomerBadMoodIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                            Text("\(badMoodCount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Image("TakoyakiCustomerAngryMoodIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                            Text("\(angryMoodCount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(height: 60)
                Rectangle()
                    .fill(Color(white: 0.35))
                    .frame(height: 4)
                    .offset(y: -5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 48)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Group {
                Image(characterImageName)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(48)

                Image(customerImageName)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(48)
            }
            .allowsHitTesting(false)

            if showCoinRain {
                GeometryReader { geo in
                    CoinRainBurst(
                        elapsed: coinRainElapsed,
                        count: coinRainCount,
                        start: Self.overlayPosition(for: Self.canvasFraction(x: Self.coinLanternPixel.x, y: Self.coinLanternPixel.y), in: geo.size),
                        end: Self.overlayPosition(for: Self.canvasFraction(x: Self.coinFanPixel.x, y: Self.coinFanPixel.y), in: geo.size)
                    )
                }
                .allowsHitTesting(false)
            }

            if scoreElapsed >= 0 {
                GeometryReader { geo in
                    CoinBurstScoreLabel(
                        elapsed: scoreElapsed,
                        count: coinRainCount,
                        position: Self.overlayPosition(for: Self.canvasFraction(x: Self.scoreLabelPixel.x, y: Self.scoreLabelPixel.y), in: geo.size)
                    )
                }
                .allowsHitTesting(false)
            }

            if showReceive {
                Image("TakoyakiFoodIcon")
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(foodScale)
                    .brightness(foodBrightness)
                    .padding(48)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                GeometryReader { geo in
                    let h = geo.size.height

                    ZStack {
                        Capsule()
                            .fill(Color(white: 0.35))
                        Capsule()
                            .fill(Color.white)
                            .padding(3)
                        Capsule()
                            .strokeBorder(Color.black, lineWidth: 1.5)
                            .padding(3)
                        GeometryReader { fillGeo in
                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.blue)
                                Rectangle()
                                    .fill(capsuleFillColor)
                                    .frame(height: fillGeo.size.height * CGFloat(standingElapsed / Self.standingDuration))
                            }
                            .clipShape(Capsule())
                        }
                        .padding(6)
                        .clipShape(Capsule())
                        Capsule()
                            .strokeBorder(Color.black, lineWidth: 1.5)
                            .padding(6)

                        ForEach(1..<5) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 28, height: 1.5)
                                .position(x: 20, y: h * CGFloat(i) * 2 / 9)
                        }

                        Text("9")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black)
                            .position(x: -20, y: 0)

                        ForEach(1..<5) { i in
                            Text("\(9 - 2 * i)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.black)
                                .position(x: -20, y: h * CGFloat(i) * 2 / 9)
                        }

                        Image("TakoyakiCustomerBadMoodIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .position(x: 60, y: h * 4 / 9)
                        Image("TakoyakiCustomerAngryMoodIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .position(x: 60, y: h * 2 / 9)
                    }
                }
                .frame(width: 40, height: 400)

                ZStack {
                    Circle()
                        .fill(Color(white: 0.35))
                    Circle()
                        .fill(Color.white)
                        .padding(4)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                        .padding(4)

                    Text(stepStatusLabel)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(isMovementQualityScoringEnabled && (btVM.currentStepStatus == 1 || btVM.currentStepStatus == 2) ? .red : .black)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .padding(12)
                }
                .frame(width: 130, height: 130)
            }
            .padding(24)
            .offset(x: 25, y: -100)

            GuideCircleOverlay(
                resourceName: "12_\(side == 1 ? "right" : "left")_video",
                videoGravity: .resizeAspect,
                circleSize: 500,
                allowsHiding: false,
                onPlaybackCompleted: {
                    // reps 次數改由引導圈圈影片播放完成事件驅動，不再靠 BLE 動作偵測
                    // （working12-database-port-plan.md 第 14 節）；guard 比照 12.6 節既有模式，
                    // 擋掉組間休息／確認視窗顯示中／完成視窗顯示中這三種不該計次的狀態。
                    guard !isSessionPaused, btVM.isRecording else { return }
                    showGiveFood = true
                    showReceive = true
                    startFoodPulse()
                    startCoinRain(count: 15)
                    startScoreSequence(count: 15)
                    advanceProgress(coinCount: 15)
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.giveFoodDuration) {
                        showGiveFood = false
                        showReceive = false
                    }
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if showSetRestPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                SetRestPopup(secondsRemaining: setRestCountdown)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showExitConfirmPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ConfirmPopup(
                    message: "您確定要結束遊戲嗎？",
                    onCancel: {
                        showExitConfirmPopup = false
                        resumeSession()
                        if btVM.currentStepStatus == 0 { startStandingTimer() }
                    },
                    onConfirm: {
                        showExitConfirmPopup = false
                        cancelInProgressStepCycleWithoutCounting()
                        finishSet(index: currentSet - 1, reps: currentRep)
                        showCompletionPopup = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showCompletionPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                CompletionPopup(treatmentResult: treatmentResult, onComplete: {
                    showCompletionPopup = false
                    finalElapsedSeconds = Int(Date().timeIntervalSince(sessionStartDate))
                    navigateToPostWorking12 = true
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            createTreatmentResultIfNeeded()
        }
        .fullScreenCover(isPresented: $navigateToPostWorking12) {
            if let treatmentResult {
                PostWorking_12(
                    content: content,
                    exercise: exercise,
                    totalCoins: totalCoins,
                    totalSets: currentSet,
                    totalElapsedSeconds: finalElapsedSeconds,
                    comingMoodCount: comingMoodCount,
                    badMoodCount: badMoodCount,
                    angryMoodCount: angryMoodCount,
                    treatmentResult: treatmentResult,
                    onReturnToDashboard: onReturnToDashboard
                )
            }
        }
        .onChange(of: btVM.currentStepStatus) { oldValue, newValue in
            guard !isSessionPaused, btVM.isRecording else { return }
            guard isMovementQualityScoringEnabled else { return }
            // 只有站立狀態才計時：一回到站立（含一開始拿到第一筆資料）就開始計時，
            // 上階／下階全程不計時，離開站立時停止並依累計秒數先評好分（存到 pendingCoinCount，
            // 這時角色圖示是 TakoyakiMakeFoodIcon「做食物中」），
            // 等下階回到站立那一瞬間（TakoyakiGiveFoodIcon「送餐」）才真正同時觸發送餐與硬幣獎勵動畫。
            if newValue == 0 {
                startStandingTimer()
            }
            if oldValue == 0 && newValue == 1 {
                if standingElapsed >= 7 {
                    pendingCoinCount = 3
                } else if standingElapsed >= 5 {
                    pendingCoinCount = 9
                } else {
                    pendingCoinCount = 15
                }
                stopStandingTimer()
            }
            // reps 次數改由引導圈圈影片播放完成事件驅動（見上方 GuideCircleOverlay 的
            // onPlaybackCompleted），這裡不再呼叫 advanceProgress／送餐視覺回饋，只維持
            // pendingCoinCount 歸零，避免殘留到下一次循環（working12-database-port-plan.md 第 14 節）。
            if oldValue == 2 && newValue == 0 {
                pendingCoinCount = nil
            }
        }
        .onChange(of: navigateToPostWorking12) { _, newValue in
            if newValue {
                pauseSession()
            }
        }
        .onDisappear {
            pauseSession()
            standingTimer?.invalidate()
            coinRainTimer?.invalidate()
            scoreTimer?.invalidate()
            setRestTimer?.invalidate()
            setTimeLimitTimer?.invalidate()
            setTimeLimitTimer = nil
            setCountdownRange = nil
            btVM.stopRecordingAll()
            btVM.currentTreatmentResultId = nil
            stopStepStatusIfNeeded()
        }
    }
}

// MARK: - CoinRainBurst

// 硬幣一顆一顆從固定起點飛拋物線到固定終點：跟 9_Working.swift 的 CoinConvergeBurst
// 不同的地方是這裡起點終點都固定（不是散開後收斂），純粹依 elapsed 算出每顆各自的發射時間與拋物線進度。
private struct CoinRainBurst: View {
    let elapsed: Double
    let count: Int
    let start: CGPoint
    let end: CGPoint

    fileprivate static let flightDuration = 0.6
    fileprivate static let stagger = 0.15
    private static let arcHeight: CGFloat = 60
    private static let coinSize: CGFloat = 36

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let launchTime = Double(i) * Self.stagger
                let localT = (elapsed - launchTime) / Self.flightDuration

                if localT >= 0 && localT < 1 {
                    let t = CGFloat(localT)
                    let x = start.x + (end.x - start.x) * t
                    let y = start.y + (end.y - start.y) * t - Self.arcHeight * 4 * t * (1 - t)

                    Image("CoinIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.coinSize, height: Self.coinSize)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - CoinBurstScoreLabel

// 累計金額顯示完全參考 9_Working.swift 的 CoinBurstScoreLabel：黑色描邊 + 金黃色文字，
// 用自己的 elapsed（由 Timer 驅動，見 Working12.startScoreSequence）逐一往上跳，
// 跟硬幣飛行動畫脫鉤，確保無論硬幣數量多少都能完整跑完全部數字。
private struct CoinBurstScoreLabel: View {
    let elapsed: Double
    let count: Int
    let position: CGPoint

    fileprivate static let stagger = 0.2
    private static let pulseDuration = 0.15
    private static let baseFontSize: CGFloat = 100

    var body: some View {
        let appearedCount = elapsed >= 0 ? min(count, Int(elapsed / Self.stagger) + 1) : 0
        if appearedCount > 0 {
            let label = "+\(appearedCount * 100)"
            let lastSpawnTime = Double(appearedCount - 1) * Self.stagger
            let timeSincePulse = elapsed - lastSpawnTime
            let pulseProgress = min(max(timeSincePulse / Self.pulseDuration, 0), 1)
            let pulseFactor = sin(pulseProgress * .pi)
            let fontSize = Self.baseFontSize + 20 * CGFloat(pulseFactor)
            let outlineOffsets: [CGSize] = [
                CGSize(width: -2, height: -2), CGSize(width: 2, height: -2),
                CGSize(width: -2, height: 2), CGSize(width: 2, height: 2)
            ]
            ZStack {
                ForEach(0..<outlineOffsets.count, id: \.self) { i in
                    Text(label)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(Color(red: 0.93, green: 0.75, blue: 0.22))
                        .offset(outlineOffsets[i])
                }
                Text(label)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Color(red: 0.933, green: 0.933, blue: 0.0))
            }
            .position(position)
        }
    }
}

// MARK: - ConfirmPopup

private struct ConfirmPopup: View {
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Text(message)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            Button(action: onCancel) {
                ZStack {
                    Circle().fill(Color.white)
                    Circle().strokeBorder(Color.black, lineWidth: 1.5)
                    Circle().strokeBorder(Color.black, lineWidth: 1.5).padding(4)
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(8)
            Button(action: onConfirm) {
                Text("確定")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 1.5))
                    )
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 320, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
    }
}

// MARK: - SetRestPopup

private struct SetRestPopup: View {
    let secondsRemaining: Int

    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 24) {
                Text("組間休息時間")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.black)
                ZStack {
                    Circle().fill(Color.white)
                    Circle().strokeBorder(Color.black, lineWidth: 1.5)
                    Text("\(max(secondsRemaining, 0))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(8)
                }
                .frame(width: 90, height: 90)
            }
        }
        .frame(width: 320, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
    }
}

// MARK: - CompletionPopup

private struct CompletionPopup: View {
    let treatmentResult: TreatmentResult?
    let onComplete: () -> Void

    private enum ExportPhase: Equatable {
        case ready
        case counting(secondsRemaining: Int)
        case waiting
        case done
    }

    @State private var phase: ExportPhase = .ready
    @State private var countdownTimer: Timer?

    private var exportButtonTitle: String {
        switch phase {
        case .ready, .done: return "儲存訓練結果"
        case .counting(let remaining): return "儲存訓練結果(\(remaining))"
        case .waiting: return "再等待一下..."
        }
    }

    private var isExportButtonEnabled: Bool {
        switch phase {
        case .ready, .done: return true
        case .counting, .waiting: return false
        }
    }

    private var isCompleteButtonEnabled: Bool {
        phase == .done
    }

    /// 點擊「儲存訓練結果」：畫面倒數 10 秒（儲存訓練結果(10) → … → 儲存訓練結果(0)）。前 5 秒（10→…→5）純粹是寫入緩衝，
    /// 讓遊戲結束當下還在飛行中的非同步資料庫寫入有時間落地；倒數到剛好顯示「儲存訓練結果(5)」那一次遞減，
    /// 才在背景真正開始查詢資料庫、組裝檔案、寫進使用者在「匯出」設定頁指定好的資料夾——這是全流程唯一
    /// 呼叫 runExport() 的地方，不會因為倒數到 0 又重複觸發一次。後 5 秒（5→0）只是給使用者看的可視倒數：
    /// 背景作業比較快完成就直接切到 .done，不必等文字倒數到 0；倒數到 0 又過了 1 秒背景作業還沒完成，
    /// 文字才改成「再等待一下...」。查詢/組裝/寫檔全程在背景執行緒進行，不卡住主執行緒；沒有分享面板這一步，
    /// 「完成」按鈕解鎖只看檔案寫入呼叫是否都已執行過（見 database-export-implementation-steps.md 階段 4、5）。
    private func performExport() {
        guard phase == .ready || phase == .done else { return }
        phase = .counting(secondsRemaining: 10)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            switch phase {
            case .counting(let remaining) where remaining > 0:
                let next = remaining - 1
                phase = .counting(secondsRemaining: next)
                if next == 5 { runExport() }
            case .counting:
                // 顯示「儲存訓練結果(0)」又過了 1 秒，背景作業還沒完成。
                phase = .waiting
            case .waiting:
                break
            case .ready, .done:
                timer.invalidate()
                countdownTimer = nil
            }
        }
    }

    private func runExport() {
        guard let treatmentResult else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let deviceVM = DeviceViewModel()
            let files = GameDataExporter.export(treatmentResult: treatmentResult, deviceVM: deviceVM)
            if let folderURL = ExportDestinationStore.resolveDesignatedFolder(),
               folderURL.startAccessingSecurityScopedResource() {
                for file in files {
                    let url = folderURL.appendingPathComponent(file.filename)
                    try? file.content.write(to: url, atomically: true, encoding: .utf8)
                }
                folderURL.stopAccessingSecurityScopedResource()
            }
            DispatchQueue.main.async {
                phase = .done
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    Color.white
                    Image("TakoyakiTheEndIcon")
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }

                Color(red: 0.86, green: 0.90, blue: 0.94)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }

            HStack(spacing: 12) {
                if phase != .done {
                    Button(action: performExport) {
                        Text(exportButtonTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.black, lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isExportButtonEnabled)
                    .opacity(isExportButtonEnabled ? 1 : 0.5)
                }

                Button(action: onComplete) {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.black, lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isCompleteButtonEnabled)
                .opacity(isCompleteButtonEnabled ? 1 : 0.5)
            }
            .padding(12)
        }
        .frame(width: 520, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 1.5)
        )
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }
}

#Preview {
    Working12(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 12,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        onReturnToDashboard: {}
    )
    .environment(BluetoothViewModel())
}

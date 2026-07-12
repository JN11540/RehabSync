import SwiftUI

// MARK: - Working12

struct Working12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(BluetoothViewModel.self) private var btVM
    @Environment(\.goHome) private var goHome
    @State private var holdElapsed: Double = 0
    @State private var holdTimer: Timer?
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

    private static let holdDuration: Double = 9
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
        switch btVM.currentStepStatus {
        case 0: return "站立"
        case 1: return "上階"
        case 2: return "下階"
        default: return "—"
        }
    }

    private var characterImageName: String {
        if showGiveFood { return "TakoyakiGiveFoodIcon" }
        switch btVM.currentStepStatus {
        case 1, 2: return "TakoyakiMakeFoodIcon"
        default: return "TakoyakiHelloIcon"
        }
    }

    private var capsuleFillColor: Color {
        if holdElapsed >= 7 { return .red }
        if holdElapsed >= 5 { return .orange }
        return .yellow
    }

    private var customerImageName: String {
        if showReceive { return "TakoyakiCustomerReceiveIcon" }
        if holdElapsed >= 7 { return "TakoyakiCustomerAngryIcon" }
        if holdElapsed >= 5 { return "TakoyakiCustomerBadIcon" }
        return "TakoyakiCustomerComingIcon"
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdElapsed = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard holdElapsed < Self.holdDuration else { return }
            holdElapsed = min(holdElapsed + 0.1, Self.holdDuration)
        }
    }

    private func stopHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdElapsed = 0
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
        let totalDuration = Double(count) * CoinBurstScoreLabel.stagger + Self.scoreHoldAfterLast
        scoreTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let e = Date().timeIntervalSince(start)
            scoreElapsed = e
            if e >= totalDuration {
                t.invalidate()
                scoreElapsed = -1
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
                                    .frame(height: fillGeo.size.height * CGFloat(holdElapsed / Self.holdDuration))
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
                        .foregroundStyle(btVM.currentStepStatus == 1 || btVM.currentStepStatus == 2 ? .red : .black)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .padding(12)
                }
                .frame(width: 130, height: 130)
            }
            .padding(24)
            .offset(x: 25, y: -100)
        }
        .onChange(of: btVM.currentStepStatus) { oldValue, newValue in
            if oldValue == 0 && newValue == 1 {
                startHoldTimer()
            }
            if oldValue == 2 && newValue == 0 {
                let finishedHoldSeconds = holdElapsed
                stopHoldTimer()
                showGiveFood = true
                showReceive = true
                startFoodPulse()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.giveFoodDuration) {
                    showGiveFood = false
                    showReceive = false
                    let coinCount: Int
                    if finishedHoldSeconds >= 7 {
                        coinCount = 3
                    } else if finishedHoldSeconds >= 5 {
                        coinCount = 9
                    } else {
                        coinCount = 15
                    }
                    startCoinRain(count: coinCount)
                    startScoreSequence(count: coinCount)
                }
            }
        }
        .onDisappear {
            holdTimer?.invalidate()
            coinRainTimer?.invalidate()
            scoreTimer?.invalidate()
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

#Preview {
    Working12(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 12,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
    .environment(BluetoothViewModel())
}

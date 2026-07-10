import SwiftUI

// MARK: - Working9

struct Working9: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var holdElapsed: Double = 0
    @State private var holdTimer: Timer?
    @State private var showOutIcon = false
    @State private var showHappyMoment = false
    @State private var showArrow = false
    @State private var arrowProgress: Double = 0
    @State private var arrowStartFraction: CGPoint = .zero
    @State private var arrowEndFraction: CGPoint = .zero
    @State private var blueTargetScale: CGFloat = 1
    @State private var blueTargetBrightness: Double = 0
    @State private var redTargetScale: CGFloat = 1
    @State private var redTargetBrightness: Double = 0
    @State private var yellowTargetScale: CGFloat = 1
    @State private var yellowTargetBrightness: Double = 0

    private static let holdThreshold: Double = 45
    private static let holdDuration: Double = 5
    private static let outIconDuration: Double = 1.5
    private static let pulseStepDuration: Double = 0.3
    private static let pulseScale: CGFloat = 1.15
    private static let pulseBrightness: Double = 0.3

    // archery_background.png（跟其他滿版疊圖共用同一份 1232x864 畫布 + padding(48) + scaledToFill），
    // 座標換算公式跟 2_Working.swift 的 overlayPosition 完全相同。
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

    // 讓對應顏色的靶環在 archery_out.png 消失後（delay 之後）連續 pulse 幾次：
    // 每次 pulse 都是「放大＋變亮」再「回到原狀」，用 asyncAfter 依序排時間，
    // 確保每個 pulse 之間有明確的節奏，而不是單純無限循環動畫。
    private func startPulse(times: Int, delay: Double, scale: Binding<CGFloat>, brightness: Binding<Double>) {
        for i in 0..<times {
            let upTime = delay + Double(i) * Self.pulseStepDuration * 2
            let downTime = upTime + Self.pulseStepDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + upTime) {
                withAnimation(.easeInOut(duration: Self.pulseStepDuration)) {
                    scale.wrappedValue = Self.pulseScale
                    brightness.wrappedValue = Self.pulseBrightness
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + downTime) {
                withAnimation(.easeInOut(duration: Self.pulseStepDuration)) {
                    scale.wrappedValue = 1
                    brightness.wrappedValue = 0
                }
            }
        }
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard holdElapsed < Self.holdDuration else { return }
            withAnimation(.linear(duration: 0.1)) {
                holdElapsed = min(holdElapsed + 0.1, Self.holdDuration)
            }
        }
    }

    private func stopHoldTimer() {
        let wasHolding = holdTimer != nil
        let heldSeconds = holdElapsed
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            holdElapsed = 0
        }
        if wasHolding {
            showOutIcon = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.outIconDuration) {
                showOutIcon = false
            }

            var targetPixel: CGPoint?
            if heldSeconds >= 5 {
                targetPixel = CGPoint(x: 1000, y: 229)
            } else if heldSeconds >= 3 {
                targetPixel = CGPoint(x: 900, y: 228)
            } else if heldSeconds >= 1 {
                targetPixel = CGPoint(x: 850, y: 228)
            }

            if let targetPixel {
                arrowStartFraction = Self.canvasFraction(x: 600, y: 297)
                arrowEndFraction = Self.canvasFraction(x: targetPixel.x, y: targetPixel.y)
                arrowProgress = 0
                showArrow = true
                withAnimation(.linear(duration: Self.outIconDuration)) {
                    arrowProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.outIconDuration) {
                    showArrow = false
                }
            }

            var pulseTimes: Int?
            if heldSeconds >= 5 {
                pulseTimes = 3
                startPulse(times: 3, delay: Self.outIconDuration, scale: $yellowTargetScale, brightness: $yellowTargetBrightness)
            } else if heldSeconds >= 3 {
                pulseTimes = 3
                startPulse(times: 3, delay: Self.outIconDuration, scale: $redTargetScale, brightness: $redTargetBrightness)
            } else if heldSeconds >= 1 {
                pulseTimes = 3
                startPulse(times: 3, delay: Self.outIconDuration, scale: $blueTargetScale, brightness: $blueTargetBrightness)
            }

            if let pulseTimes {
                let pulseTotalDuration = Double(pulseTimes) * Self.pulseStepDuration * 2
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.outIconDuration) {
                    showHappyMoment = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.outIconDuration + pulseTotalDuration) {
                    showHappyMoment = false
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
                .ignoresSafeArea()

            Image("ArcheryBackgroundIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: 2)
                )
                .padding(48)
                .opacity(0.4)

            Group {
                if showOutIcon {
                    Image("ArcheryOutIcon")
                        .resizable()
                } else if showHappyMoment {
                    Image("ArrowHappyMomentIcon")
                        .resizable()
                } else if let angle = btVM.currentEstimatedRealAngle, angle >= Self.holdThreshold {
                    Image("ArcheryFocusIcon")
                        .resizable()
                } else {
                    Image("ArcheryReadyIcon")
                        .resizable()
                }
            }
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(48)

            Image("ArrowBlueTargetIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(blueTargetScale, anchor: UnitPoint(x: 0.853, y: 0.264))
                .brightness(blueTargetBrightness)
                .padding(48)

            Image("ArrowRedTargetIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(redTargetScale, anchor: UnitPoint(x: 0.853, y: 0.264))
                .brightness(redTargetBrightness)
                .padding(48)

            Image("ArrowYellowTargetIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(yellowTargetScale, anchor: UnitPoint(x: 0.853, y: 0.264))
                .brightness(yellowTargetBrightness)
                .padding(48)

            if showArrow {
                GeometryReader { geo in
                    MovingArrow(
                        progress: arrowProgress,
                        start: Self.overlayPosition(for: arrowStartFraction, in: geo.size),
                        end: Self.overlayPosition(for: arrowEndFraction, in: geo.size)
                    )
                }
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
                                    .fill(Color.yellow)
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
                                .position(x: 20, y: h * CGFloat(i) / 5)
                        }

                        Text("5")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black)
                            .position(x: -20, y: 0)

                        ForEach(1..<5) { i in
                            Text("\(5 - i)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.black)
                                .position(x: -20, y: h * CGFloat(i) / 5)
                        }

                        // 靶心配色（藍/紅/黃 對應 arrow_target.png 外圈到內圈），秒數越多越接近靶心
                        Circle()
                            .fill(Color(red: 0.369, green: 0.690, blue: 0.824))
                            .frame(width: 24, height: 24)
                            .position(x: 60, y: h * 4 / 5)
                        Circle()
                            .fill(Color(red: 0.910, green: 0.306, blue: 0.290))
                            .frame(width: 24, height: 24)
                            .position(x: 60, y: h * 2 / 5)
                        Circle()
                            .fill(Color(red: 0.957, green: 0.871, blue: 0.235))
                            .frame(width: 24, height: 24)
                            .position(x: 60, y: 0)
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

                    if let angle = btVM.currentEstimatedRealAngle {
                        Text(String(format: "%.0f°", angle))
                            .font(.system(size: 50, weight: .bold))
                            .foregroundStyle(angle >= Self.holdThreshold ? .red : .black)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding(12)
                    }
                }
                .frame(width: 130, height: 130)
            }
            .padding(24)
            .offset(x: 25, y: -100)
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            if let angle = newValue, angle >= Self.holdThreshold {
                startHoldTimer()
            } else {
                stopHoldTimer()
            }
        }
        .onDisappear {
            holdTimer?.invalidate()
        }
    }
}

// MARK: - MovingArrow

// 讓箭矢從起點直線飛向終點：progress 是唯一會被 SwiftUI 動畫插值的值，
// x/y 在每個插值後的 progress 當下重新計算，才能跟著 withAnimation 平滑移動。
private struct MovingArrow: View, Animatable {
    var progress: Double
    let start: CGPoint
    let end: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress
        Image("ArrowOnlyIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
            .position(x: x, y: y)
    }
}

#Preview {
    Working9(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 9,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
    .environment(BluetoothViewModel())
}

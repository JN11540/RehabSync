import SwiftUI

// MARK: - Working2

struct Working2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var holdElapsed: Double = 0
    @State private var holdTimer: Timer?
    @State private var showCatchAnimation = false
    @State private var caughtFishSize: CaughtFishSize = .small
    @State private var catchProgress: Double = 0
    @State private var bigFishCaught = 0
    @State private var middleFishCaught = 0
    @State private var smallFishCaught = 0
    @State private var bigBucketScale: CGFloat = 1
    @State private var middleBucketScale: CGFloat = 1
    @State private var smallBucketScale: CGFloat = 1
    @State private var showRestPopup = false
    @State private var showExitConfirmPopup = false
    @State private var bigCoinAppeared = 0
    @State private var bigCoinDisappeared = 0
    @State private var middleCoinAppeared = 0
    @State private var middleCoinDisappeared = 0
    @State private var smallCoinAppeared = 0
    @State private var smallCoinDisappeared = 0

    private static let holdThreshold: Double = 20
    private static let holdDuration: Double = 5
    private static let catchQualifyDuration: Double = 1
    private static let catchAnimationDuration: Double = 1.5

    // 這些滿版圖（背景/水桶/水花）都用同樣的 canvas 尺寸與 padding(48) + scaledToFill 處理，
    // 所以水花在原始圖片中的相對位置，套用同一個裁切公式，換算到任何裝置畫面都會對齊。
    private static let overlayCanvasSize = CGSize(width: 1232, height: 864)
    private static let splashFraction = CGPoint(x: 0.7476, y: 0.6644)

    fileprivate static func overlayPosition(for fraction: CGPoint, in size: CGSize, padding: CGFloat = 48) -> CGPoint {
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

    private static func overlayAnchor(for fraction: CGPoint, in size: CGSize, padding: CGFloat = 48) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        let point = overlayPosition(for: fraction, in: size, padding: padding)
        return UnitPoint(x: point.x / size.width, y: point.y / size.height)
    }

    private enum CaughtFishSize {
        case small, middle, big

        var imageName: String {
            switch self {
            case .small:  return "SmallFishIcon"
            case .middle: return "MiddleFishIcon"
            case .big:    return "BigFishIcon"
            }
        }

        var size: CGFloat {
            switch self {
            case .small:  return 75
            case .middle: return 100
            case .big:    return 200
            }
        }

        // 各水桶內容物在 canvas 中的相對中心位置（同一份 1232x864 canvas）
        var bucketFraction: CGPoint {
            switch self {
            case .small:  return CGPoint(x: 0.7821, y: 0.9115)
            case .middle: return CGPoint(x: 0.5308, y: 0.8501)
            case .big:    return CGPoint(x: 0.6615, y: 0.8576)
            }
        }

        var coinCount: Int {
            switch self {
            case .small:  return 3
            case .middle: return 9
            case .big:    return 15
            }
        }
    }

    // 讓魚沿拋物線路徑從水花飛到水桶：progress 是唯一會被 SwiftUI 動畫插值的值，
    // x/y 在每個插值後的 progress 當下重新計算，才能畫出真正的曲線而非直線位移。
    private struct ParabolicPosition: Animatable, ViewModifier {
        var progress: Double
        let start: CGPoint
        let end: CGPoint
        let arcHeight: CGFloat
        let startSize: CGFloat
        let endSize: CGFloat

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let t = CGFloat(progress)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t - arcHeight * 4 * t * (1 - t)
            let size = startSize + (endSize - startSize) * t
            return content
                .frame(width: size, height: size)
                .position(x: x, y: y)
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
        if holdElapsed > Self.catchQualifyDuration {
            triggerCatchAnimation()
        }
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            holdElapsed = 0
        }
    }

    private func triggerCatchAnimation() {
        caughtFishSize = holdElapsed >= 5 ? .big : (holdElapsed >= 3 ? .middle : .small)
        switch caughtFishSize {
        case .big:    bigFishCaught += 1
        case .middle: middleFishCaught += 1
        case .small:  smallFishCaught += 1
        }
        showCatchAnimation = true
        catchProgress = 0
        withAnimation(.easeInOut(duration: Self.catchAnimationDuration)) {
            catchProgress = 1
        }
        let landedSize = caughtFishSize
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.catchAnimationDuration) {
            showCatchAnimation = false
            bounceBucket(for: landedSize)
        }
    }

    private func bounceBucket(for size: CaughtFishSize) {
        withAnimation(.easeOut(duration: 0.15)) {
            setBucketScale(1.3, for: size)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.15)) {
                setBucketScale(1.0, for: size)
            }
        }

        switch size {
        case .big:    playCoinBurst(count: size.coinCount, appeared: $bigCoinAppeared, disappeared: $bigCoinDisappeared)
        case .middle: playCoinBurst(count: size.coinCount, appeared: $middleCoinAppeared, disappeared: $middleCoinDisappeared)
        case .small:  playCoinBurst(count: size.coinCount, appeared: $smallCoinAppeared, disappeared: $smallCoinDisappeared)
        }
    }

    // 金幣一顆接一顆出現，全部出現後再一顆接一顆消失；appeared/disappeared 各自代表
    // 目前已出現/已消失的顆數，視圖用「index < appeared && index >= disappeared」判斷可見範圍。
    private func playCoinBurst(count: Int, appeared: Binding<Int>, disappeared: Binding<Int>) {
        let stagger = 0.1
        let holdAfterAppear = 0.5
        appeared.wrappedValue = 0
        disappeared.wrappedValue = 0

        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stagger) {
                withAnimation(.easeOut(duration: 0.15)) {
                    appeared.wrappedValue = i + 1
                }
            }
        }

        let appearEnd = Double(count) * stagger
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + appearEnd + holdAfterAppear + Double(i) * stagger) {
                withAnimation(.easeIn(duration: 0.15)) {
                    disappeared.wrappedValue = i + 1
                }
            }
        }
    }

    private func setBucketScale(_ scale: CGFloat, for size: CaughtFishSize) {
        switch size {
        case .big:    bigBucketScale = scale
        case .middle: middleBucketScale = scale
        case .small:  smallBucketScale = scale
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("Working2BackgroundIcon")
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
                            .frame(width: 110, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(red: 0.70, green: 0.52, blue: 0.10), lineWidth: 3)
                            )

                        HStack(spacing: 6) {
                            Image("CoinIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .offset(x: -32)

                            Text("0")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                        }
                    }
                    .frame(width: 110, height: 48)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)

                    HStack(spacing: 12) {
                        Button(action: { showExitConfirmPopup = true }) {
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

                        Button(action: { showRestPopup = true }) {
                            Image("RestIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
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
                            Text("0 組 × 0 次")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        Rectangle()
                            .fill(Color(white: 0.35))
                            .frame(width: 2, height: 40)

                        HStack(spacing: 4) {
                            Image("BigFishIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            Text("\(bigFishCaught)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Image("MiddleFishIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            Text("\(middleFishCaught)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Image("SmallFishIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            Text("\(smallFishCaught)")
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
                if showCatchAnimation {
                    Image("GetFishIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)

                    Image("WaterSplashIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)

                    GeometryReader { geo in
                        Image(caughtFishSize.imageName)
                            .resizable()
                            .scaledToFit()
                            .modifier(ParabolicPosition(
                                progress: catchProgress,
                                start: Self.overlayPosition(for: Self.splashFraction, in: geo.size),
                                end: Self.overlayPosition(for: caughtFishSize.bucketFraction, in: geo.size),
                                arcHeight: 150,
                                startSize: caughtFishSize.size,
                                endSize: 50
                            ))
                    }
                } else if let angle = btVM.currentEstimatedRealAngle, angle <= Self.holdThreshold {
                    Image("NoGetFishIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)
                } else {
                    Image("IdleFishingIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)
                }

                GeometryReader { geo in
                    Image("BigBucketOnlyIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)
                        .scaleEffect(bigBucketScale, anchor: Self.overlayAnchor(for: CaughtFishSize.big.bucketFraction, in: geo.size))
                }

                GeometryReader { geo in
                    Image("MiddleBucketOnlyIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)
                        .scaleEffect(middleBucketScale, anchor: Self.overlayAnchor(for: CaughtFishSize.middle.bucketFraction, in: geo.size))
                }

                GeometryReader { geo in
                    Image("SmallBucketOnlyIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(48)
                        .scaleEffect(smallBucketScale, anchor: Self.overlayAnchor(for: CaughtFishSize.small.bucketFraction, in: geo.size))
                }
            }
            .allowsHitTesting(false)

            CoinBurstView(bucketFraction: CaughtFishSize.big.bucketFraction, count: CaughtFishSize.big.coinCount, appeared: bigCoinAppeared, disappeared: bigCoinDisappeared)
            CoinBurstView(bucketFraction: CaughtFishSize.middle.bucketFraction, count: CaughtFishSize.middle.coinCount, appeared: middleCoinAppeared, disappeared: middleCoinDisappeared)
            CoinBurstView(bucketFraction: CaughtFishSize.small.bucketFraction, count: CaughtFishSize.small.coinCount, appeared: smallCoinAppeared, disappeared: smallCoinDisappeared)

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

                        Image("BigFishIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .position(x: 40 + 30, y: 0)

                        Image("MiddleFishIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .position(x: 40 + 30, y: h * 2 / 5)

                        Image("SmallFishIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .position(x: 40 + 30, y: h * 4 / 5)
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
                            .foregroundStyle(angle <= Self.holdThreshold ? .red : .black)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding(12)
                    }
                }
                .frame(width: 130, height: 130)
            }
            .padding(24)
            .offset(x: 25, y: -100)

            if showRestPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ConfirmPopup(
                    message: "您是否要直接跳過，進入組間休息？",
                    onCancel: { showRestPopup = false },
                    onConfirm: { showRestPopup = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showExitConfirmPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ConfirmPopup(
                    message: "您確定要結束遊戲嗎？",
                    onCancel: { showExitConfirmPopup = false },
                    onConfirm: { dismiss() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            if let angle = newValue, angle <= Self.holdThreshold {
                startHoldTimer()
            } else {
                stopHoldTimer()
            }
        }
        .onDisappear { holdTimer?.invalidate() }
    }
}

// MARK: - CoinBurstView

// 從水桶中心沿 2 點鐘方向（順時針從 12 點量起 60 度）依序噴出一排金幣，
// 全部出現後再依相同順序一顆顆消失；appeared/disappeared 由 Working2 的計時序列驅動。
private struct CoinBurstView: View {
    let bucketFraction: CGPoint
    let count: Int
    let appeared: Int
    let disappeared: Int

    private static let spacing: CGFloat = 20
    private static let coinSize: CGFloat = 28
    private static let directionAngleDegrees: Double = 60

    var body: some View {
        GeometryReader { geo in
            let center = Working2.overlayPosition(for: bucketFraction, in: geo.size)
            let radians = Self.directionAngleDegrees * .pi / 180
            let dx = sin(radians)
            let dy = -cos(radians)

            ForEach(0..<count, id: \.self) { i in
                if i < appeared && i >= disappeared {
                    Image("CoinIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.coinSize, height: Self.coinSize)
                        .position(
                            x: center.x + CGFloat(dx) * Self.spacing * CGFloat(i + 1),
                            y: center.y + CGFloat(dy) * Self.spacing * CGFloat(i + 1)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .allowsHitTesting(false)
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.black, lineWidth: 1.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 320, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 1.5)
        )
    }
}

#Preview {
    Working2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
}

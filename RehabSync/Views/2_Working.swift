import SwiftUI
import CoreBluetooth

// MARK: - Working2

struct Working2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void
    @Environment(BluetoothViewModel.self) private var btVM

    /// 裝置目前實際綁定在哪一側（左/右），給引導圈圈決定播放哪一支示範影片用。
    private var side: Int {
        DeviceViewModel().fetchAnySide() ?? 0
    }

    // 校正/測試階段在 PreWorking 啟動的即時角度預估，離開這裡時必須主動停止，
    // 否則 btVM.isLiveEstimating 會卡在 true，導致下次（不管同動作或別的動作）
    // 進測試頁時 guard 擋住重啟，畫面顯示殘留的舊角度或舊姿勢公式。
    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    private func stopLiveTestIfNeeded() {
        guard btVM.isLiveEstimating, let pair = thighAndCalfPeripherals else { return }
        btVM.stopLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
    }

    // MARK: - treatment_result 建立與串接

    private let resultVM = TreatmentResultViewModel()
    @State private var treatmentResult: TreatmentResult?

    /// 遊戲一開始（畫面顯示的那一刻）先建立這局遊戲唯一一筆 treatment_result，
    /// 陣列長度依目標組數/目標次數計算、全部初始化為 0，再把 id 交給 btVM
    /// 讓之後 acc/gyro/exg/advanced_statistics 每一筆寫入都能帶上這個 treatment_result_id。
    /// 建立完成後緊接著視同第一組的起始點，開始記錄。
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
    /// 這一組 3 分鐘倒數的起訖區間，交給 `Text(timerInterval:)` 顯示畫面上的倒數數字，
    /// 不需要另外自己寫一個每秒更新的 Timer。
    @State private var setCountdownRange: ClosedRange<Date>?

    /// 某一組的起始點：把當下毫秒時間戳記寫進 set_start_time[index]、打開 acc/gyro/exg 的記錄，
    /// 並啟動這一組的 3 分鐘倒數上限（見「3.3 從起始點起算倒數 3 分鐘歸零」）。
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

    /// 一次動作（讀秒 > 1 秒才算數）＝一次伸展，把讀秒時長（毫秒整數）寫進 extension_length
    /// 對應索引（索引 = (組序號-1)*目標次數 + (該組內第幾次-1)）。
    private func recordExtensionLength(seconds: Double, repNumberInSet: Int) {
        guard var result = treatmentResult else { return }
        let index = (currentSet - 1) * content.reps + (repNumberInSet - 1)
        guard result.extension_length.indices.contains(index) else { return }
        result.extension_length[index] = Int((seconds * 1000).rounded())
        treatmentResult = result
        resultVM.update(result)
    }

    /// 「讀秒中被打斷」邊界情況：提前結束（結束鍵確定／3 分鐘倒數歸零）觸發當下，
    /// 如果正卡在讀秒中（尚未超過 1 秒判定），直接取消，不計入 reps、也不寫入 extension_length。
    private func cancelInProgressHoldWithoutCounting() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdElapsed = 0
    }

    /// 3.3：從起始點起算倒數 3 分鐘歸零，視同該組提前結束。
    private func handleSetTimeLimitReached() {
        cancelInProgressHoldWithoutCounting()
        finishSet(index: currentSet - 1, reps: currentRep)
        if currentSet < content.sets {
            startSetRestCountdown()
        } else {
            showCompletionPopup = true
        }
    }

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
    @State private var showExitConfirmPopup = false
    @State private var showSetRestPopup = false
    @State private var setRestCountdown: Int = 0
    @State private var setRestTimer: Timer?
    @State private var showCompletionPopup = false
    @State private var navigateToPostWorking2 = false
    @State private var bigCoinElapsed: Double = -1
    @State private var bigCoinTimer: Timer?
    @State private var middleCoinElapsed: Double = -1
    @State private var middleCoinTimer: Timer?
    @State private var smallCoinElapsed: Double = -1
    @State private var smallCoinTimer: Timer?
    @State private var totalCoins = 0
    @State private var currentSet = 1
    @State private var currentRep = 0
    @State private var sessionStartDate = Date()
    @State private var isSessionPaused = false
    @State private var finalElapsedSeconds = 0

    private static let holdThreshold: Double = 20
    private static let holdDuration: Double = 5
    private static let catchQualifyDuration: Double = 1
    private static let catchAnimationDuration: Double = 1.5
    /// 每組從起始點起算的時間上限：倒數 3 分鐘歸零視同該組提前結束。
    private static let setTimeLimit: TimeInterval = 180

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

        // 各水桶內容物頂部邊緣的相對位置（x 與 bucketFraction 相同，y 取 bbox 頂端）
        var bucketTopFraction: CGPoint {
            switch self {
            case .small:  return CGPoint(x: 0.7821, y: 0.8333)
            case .middle: return CGPoint(x: 0.5308, y: 0.7662)
            case .big:    return CGPoint(x: 0.6615, y: 0.7431)
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
        recordExtensionLength(seconds: holdElapsed, repNumberInSet: currentRep + 1)
        advanceWeightliftingProgress()
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

    private func advanceWeightliftingProgress() {
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

    private func startSetRestCountdown() {
        cancelInProgressHoldWithoutCounting()
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
        case .big:    playCoinBurst(count: size.coinCount, elapsed: $bigCoinElapsed, timer: $bigCoinTimer)
        case .middle: playCoinBurst(count: size.coinCount, elapsed: $middleCoinElapsed, timer: $middleCoinTimer)
        case .small:  playCoinBurst(count: size.coinCount, elapsed: $smallCoinElapsed, timer: $smallCoinTimer)
        }
    }

    // 硬幣不是瞬移到固定槽位，而是從 bucket 中心冒出來後持續往 2 點鐘方向等速飄移；
    // elapsed 是這個 burst 從觸發起算的時間（60fps 更新），每顆硬幣的位置都即時由
    // (elapsed - 自己的出生時間) * 速度 算出，所以尚未消失的硬幣會一直繼續往前飛，
    // 不受其他硬幣依序消失影響。消失時機與淡出效果則交給 CoinBurstView 依 elapsed 計算。
    private func playCoinBurst(count: Int, elapsed: Binding<Double>, timer: Binding<Timer?>) {
        timer.wrappedValue?.invalidate()
        let start = Date()
        elapsed.wrappedValue = 0
        let appearEnd = Double(count) * CoinBurstView.stagger
        let totalDuration = appearEnd + CoinBurstView.holdAfterAppear + Double(count) * CoinBurstView.stagger + CoinBurstView.fadeOutDuration + 0.1
        var lastAppeared = 0

        timer.wrappedValue = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            let e = Date().timeIntervalSince(start)
            elapsed.wrappedValue = e

            // 不預先把整批金額算好，而是跟每顆硬幣實際冒出來的當下同步 +100。
            let currentAppeared = e >= 0 ? min(count, Int(e / CoinBurstView.stagger) + 1) : 0
            if currentAppeared > lastAppeared {
                totalCoins += (currentAppeared - lastAppeared) * 100
                lastAppeared = currentAppeared
            }

            if e >= totalDuration {
                t.invalidate()
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

            CoinBurstView(bucketFraction: CaughtFishSize.big.bucketTopFraction, centerFraction: CaughtFishSize.big.bucketFraction, count: CaughtFishSize.big.coinCount, elapsed: bigCoinElapsed)
            CoinBurstView(bucketFraction: CaughtFishSize.middle.bucketTopFraction, centerFraction: CaughtFishSize.middle.bucketFraction, count: CaughtFishSize.middle.coinCount, elapsed: middleCoinElapsed)
            CoinBurstView(bucketFraction: CaughtFishSize.small.bucketTopFraction, centerFraction: CaughtFishSize.small.bucketFraction, count: CaughtFishSize.small.coinCount, elapsed: smallCoinElapsed)

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

            GuideCircleOverlay(resourceName: "2_\(side == 1 ? "right" : "left")_video")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 24)

            if showExitConfirmPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ConfirmPopup(
                    message: "您確定要結束遊戲嗎？",
                    onCancel: {
                        showExitConfirmPopup = false
                        resumeSession()
                    },
                    onConfirm: {
                        showExitConfirmPopup = false
                        cancelInProgressHoldWithoutCounting()
                        finishSet(index: currentSet - 1, reps: currentRep)
                        showCompletionPopup = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showSetRestPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                SetRestPopup(secondsRemaining: setRestCountdown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showCompletionPopup {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                CompletionPopup(treatmentResult: treatmentResult, onComplete: {
                    showCompletionPopup = false
                    finalElapsedSeconds = Int(Date().timeIntervalSince(sessionStartDate))
                    navigateToPostWorking2 = true
                })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .fullScreenCover(isPresented: $navigateToPostWorking2) {
            if let treatmentResult {
                PostWorking_2(
                    content: content,
                    exercise: exercise,
                    totalCoins: totalCoins,
                    totalReps: bigFishCaught + middleFishCaught + smallFishCaught,
                    totalElapsedSeconds: finalElapsedSeconds,
                    bigFishCaught: bigFishCaught,
                    middleFishCaught: middleFishCaught,
                    smallFishCaught: smallFishCaught,
                    treatmentResult: treatmentResult,
                    onReturnToDashboard: onReturnToDashboard
                )
            }
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            guard !isSessionPaused, btVM.isRecording else { return }
            if let angle = newValue, angle <= Self.holdThreshold {
                startHoldTimer()
            } else {
                stopHoldTimer()
            }
        }
        .onChange(of: navigateToPostWorking2) { _, newValue in
            if newValue {
                pauseSession()
            }
        }
        .onAppear {
            createTreatmentResultIfNeeded()
        }
        .onDisappear {
            pauseSession()
            stopLiveTestIfNeeded()
            setTimeLimitTimer?.invalidate()
            setTimeLimitTimer = nil
            setCountdownRange = nil
            btVM.stopRecordingAll()
            btVM.currentTreatmentResultId = nil
        }
    }

    private func pauseSession() {
        isSessionPaused = true
        holdTimer?.invalidate()
        holdTimer = nil
        bigCoinTimer?.invalidate()
        middleCoinTimer?.invalidate()
        smallCoinTimer?.invalidate()
        setRestTimer?.invalidate()
    }

    private func resumeSession() {
        isSessionPaused = false
    }
}

// MARK: - CoinBurstView

// 從水桶中心沿 2 點鐘方向（順時針從 12 點量起 60 度）持續等速冒出一連串硬幣：
// 每顆硬幣的位置都是「(elapsed - 自己的出生時間) * 速度」即時算出，因此還沒被
// 消除的硬幣會一直往前飄移，不會因為前面的硬幣依序消失而停下來。elapsed 由
// Working2 的 60fps 計時器驅動；stagger/holdAfterAppear/fadeOutDuration 也給
// Working2 用來計算整段 burst 要跑多久（timer 何時可以停下來）。
private struct CoinBurstView: View {
    let bucketFraction: CGPoint
    let centerFraction: CGPoint
    let count: Int
    let elapsed: Double

    fileprivate static let stagger = 0.1
    fileprivate static let holdAfterAppear = 0.5
    fileprivate static let fadeOutDuration = 0.15
    private static let spacing: CGFloat = 20
    private static let secondsPerSpacing: Double = 0.175
    private static let speed = spacing / CGFloat(secondsPerSpacing)
    private static let coinSize: CGFloat = 50
    private static let directionAngleDegrees: Double = 60

    var body: some View {
        GeometryReader { geo in
            let center = Working2.overlayPosition(for: bucketFraction, in: geo.size)
            let radians = Self.directionAngleDegrees * .pi / 180
            let dx = CGFloat(sin(radians))
            let dy = CGFloat(-cos(radians))
            let appearEnd = Double(count) * Self.stagger
            let totalDuration = appearEnd + Self.holdAfterAppear + Double(count) * Self.stagger + Self.fadeOutDuration
            let appearedCount = elapsed >= 0 ? min(count, Int(elapsed / Self.stagger) + 1) : 0

            ForEach(0..<count, id: \.self) { i in
                let spawnTime = Double(i) * Self.stagger
                let disappearTime = appearEnd + Self.holdAfterAppear + Double(i) * Self.stagger
                let timeSinceDisappear = elapsed - disappearTime

                if elapsed >= spawnTime && timeSinceDisappear < Self.fadeOutDuration {
                    let traveled = CGFloat(elapsed - spawnTime) * Self.speed
                    let opacity = timeSinceDisappear > 0
                        ? max(0, 1 - timeSinceDisappear / Self.fadeOutDuration)
                        : 1
                    Image("CoinIcon")
                        .resizable()
                        .scaledToFit()
                        .brightness(0.2)
                        .saturation(1.3)
                        .frame(width: Self.coinSize, height: Self.coinSize)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.93, green: 0.75, blue: 0.22), lineWidth: 2)
                        )
                        .opacity(opacity)
                        .position(x: center.x + dx * traveled, y: center.y + dy * traveled)
                }
            }

            if appearedCount > 0 && elapsed <= totalDuration {
                let centerPos = Working2.overlayPosition(for: centerFraction, in: geo.size)
                let label = "+\(appearedCount * 100)"
                let outlineOffsets: [CGSize] = [
                    CGSize(width: -2, height: -2), CGSize(width: 2, height: -2),
                    CGSize(width: -2, height: 2), CGSize(width: 2, height: 2)
                ]
                // 每來一顆新硬幣就從 100pt 彈到 120pt 再彈回 100pt；用「距離最近一次硬幣
                // 出生的時間」算出一個 0→1→0 的脈衝，不需要額外的 onChange 事件觸發。
                let lastSpawnTime = Double(appearedCount - 1) * Self.stagger
                let timeSincePulse = elapsed - lastSpawnTime
                let pulseDuration = 0.15
                let pulseProgress = min(max(timeSincePulse / pulseDuration, 0), 1)
                let pulseFactor = sin(pulseProgress * .pi)
                let fontSize: CGFloat = 100 + 20 * CGFloat(pulseFactor)
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
                .position(x: centerPos.x, y: centerPos.y - 200)
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
                    Circle()
                        .fill(Color.white)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 1.5)
        )
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
                    Image("FishingEndIcon")
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
    Working2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        onReturnToDashboard: {}
    )
}

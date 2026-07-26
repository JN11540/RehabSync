import SwiftUI
import CoreBluetooth

/// 弓步遊戲畫面（exercise_id 22）目前只做出「即時視覺回饋」的部分：
/// 背景底層圖依 totalCoins 里程碑切換：< 2400 是 earth，>= 2400 換成 moon，>= 7500 換成
/// new_world；astronaut_landing.png 固定疊在底層圖上方，不隨里程碑改變；space_shuttle 是
/// 獨立的一層，不受背景切換影響；
/// 前景太空人角度 < 70° 顯示 get.png，>= 70° 換成 holding.png（微微抖動，同時直式膠囊水位隨秒數上漲），
/// 曾經達到 70° 後又回落到 < 25° 且讀秒超過 1 秒時，短暫換成 release.png（1.5 秒後切回預設），
/// 同時 astronaut_fuel.png 從雙手位置飛進火箭燃料艙口（同樣 1.5 秒），燃料箱抵達的瞬間
/// astronaut_space_shuttle.png 會連續放大＋變亮再變回原狀 3 次；不論是否達到 1 秒，
/// 只要回落到 < 25° 直式膠囊水位都會歸零；讀秒不足 1 秒時不計入 currentRep／評語次數／金錢，
/// 也不觸發 release/燃料箱/pulse/金錢動畫，讀秒門檻跟 9_Working.swift／2_Working.swift 一樣是
/// 1/3/5 秒對應 好/棒/優、3/9/15 個 coin.png；燃料箱抵達的同時，3/9/15 個 coin.png 也各自
/// 從固定起點拋物線飛到燃料艙口，並在右側依序顯示 +100/+200/... 累計金額（totalCoins 逐一累加）。
/// 頂部矩形匡顯示目標組次數、實際組次數、好/棒/優各自次數、累積金錢；左側圓圈顯示即時角度數字；
/// 太空梭右側另有一個總金幣直式膠囊（中心點固定在畫布座標 (631, 394)），只有 0／2400／7500
/// 三個刻度，水位跟著 totalCoins 即時更新，也是背景里程碑判斷的同一個數字來源。
/// 組間休息、完成彈窗等其餘遊戲機制尚未實作，等後續確認規則後再依 9_Working.swift 的骨架補上。
struct Working22: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let onReturnToDashboard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM

    // 角度門檻判斷邏輯先註解掉，等後續確認實際規則後再打開。
    // /// 太空人四個層級對應的角度區間（0°～90° 平均分成四段），
    // /// 之後如果確認了實際的判斷規則（例如跟直式膠囊的握持門檻綁定），這裡要跟著調整。
    // private static let angleTierBoundaries: [Double] = [22.5, 45, 67.5]
    //
    // private enum AstronautTier {
    //     case earth, landing, spaceShuttle, get
    // }
    //
    // private func astronautTier(for angle: Double?) -> AstronautTier {
    //     guard let angle else { return .earth }
    //     if angle < Self.angleTierBoundaries[0] { return .earth }
    //     if angle < Self.angleTierBoundaries[1] { return .landing }
    //     if angle < Self.angleTierBoundaries[2] { return .spaceShuttle }
    //     return .get
    // }

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

    // 直式膠囊水位：進入 holding 狀態時開始累加，離開 holding（不論回到 idle 或觸發 release）就停止累加；
    // 觸發 release 時額外歸零，對應「直式膠囊水位要歸零」。
    @State private var holdElapsed: Double = 0
    @State private var holdTimer: Timer?
    private static let holdDuration: Double = 5

    // 用 60Hz 直接改數值（不包 withAnimation），避免每 0.1 秒重啟一次動畫曲線
    // 造成的頓挫感，改成每禎微小增量、視覺上才會是真正連續的水位上升。
    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard holdElapsed < Self.holdDuration else { return }
            holdElapsed = min(holdElapsed + 1.0 / 60.0, Self.holdDuration)
        }
    }

    private func stopHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    // MARK: - 太空人狀態機（get 預設 → holding 深蹲維持 → release 放開瞬間）

    private enum AstronautState: Equatable {
        case idle
        case holding
        case releasing
    }

    @State private var astronautState: AstronautState = .idle
    @State private var hasReachedHoldThreshold = false
    @State private var releaseWorkItem: DispatchWorkItem?
    @State private var trembleTimer: Timer?
    @State private var trembleOffset: CGSize = .zero

    private static let holdAngleThreshold: Double = 70
    private static let releaseAngleThreshold: Double = 25
    private static let releaseAnimationDuration: Double = 1.5
    // 讀秒（holdElapsed）要超過這個秒數，回落到 releaseAngleThreshold 以下才算一次有效的 release。
    private static let holdQualifyDuration: Double = 1

    // MARK: - 燃料箱飛行動畫（release 當下，astronaut_fuel.png 從雙手位置飛進火箭艙口）

    // 這些滿版疊圖都用同樣的 canvas 尺寸與 padding(48) + scaledToFill 處理，
    // 座標換算公式跟 9_Working.swift／2_Working.swift 的 overlayPosition 完全相同。
    private static let overlayCanvasSize = CGSize(width: 1232, height: 864)
    private static let fuelStartPixel = CGPoint(x: 360, y: 620)
    private static let fuelEndPixel = CGPoint(x: 612, y: 514)

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

    @State private var showFuelAnimation = false
    @State private var fuelProgress: Double = 0
    @State private var fuelHideWorkItem: DispatchWorkItem?

    /// release 觸發的同時，讓 astronaut_fuel.png 在 releaseAnimationDuration 秒內
    /// 從 fuelStartPixel（雙手位置）飛到 fuelEndPixel（火箭燃料艙口）。
    private func triggerFuelFlight() {
        fuelHideWorkItem?.cancel()
        fuelProgress = 0
        showFuelAnimation = true
        withAnimation(.linear(duration: Self.releaseAnimationDuration)) {
            fuelProgress = 1
        }
        let workItem = DispatchWorkItem { showFuelAnimation = false }
        fuelHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseAnimationDuration, execute: workItem)
    }

    // MARK: - 火箭 pulse（燃料箱抵達後，astronaut_space_shuttle.png 放大＋變亮 3 次）

    @State private var spaceShuttleScale: CGFloat = 1
    @State private var spaceShuttleBrightness: Double = 0

    private static let pulseStepDuration: Double = 0.3
    private static let pulseScale: CGFloat = 1.15
    private static let pulseBrightness: Double = 0.3

    // 讓 space_shuttle 在 delay 之後（燃料箱剛好飛抵艙口那一刻）連續 pulse 幾次：
    // 每次 pulse 都是「放大＋變亮」再「回到原狀」，用 asyncAfter 依序排時間，
    // 寫法跟 9_Working.swift 的 startPulse 完全相同。
    private func startSpaceShuttlePulse(times: Int, delay: Double) {
        for i in 0..<times {
            let upTime = delay + Double(i) * Self.pulseStepDuration * 2
            let downTime = upTime + Self.pulseStepDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + upTime) {
                withAnimation(.easeInOut(duration: Self.pulseStepDuration)) {
                    spaceShuttleScale = Self.pulseScale
                    spaceShuttleBrightness = Self.pulseBrightness
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + downTime) {
                withAnimation(.easeInOut(duration: Self.pulseStepDuration)) {
                    spaceShuttleScale = 1
                    spaceShuttleBrightness = 0
                }
            }
        }
    }

    // MARK: - 金錢拋物線動畫（跟 space_shuttle pulse 同時觸發，coin.png 一個一個從固定起點飛到燃料艙口）

    private static let coinStartPixel = CGPoint(x: 864, y: 620)
    private static let coinEndPixel = CGPoint(x: 612, y: 514)
    private static let coinBurstDuration: Double = 1.0

    // 總金幣直式膠囊（太空梭右側）的刻度：0／2400／7500，水位 = totalCoins / coinCapsuleMaxValue。
    private static let coinCapsuleMaxValue: Double = 7500
    private static let coinCapsuleMidValue: Double = 2400

    // 背景依 totalCoins 里程碑切換底層圖（層級最低）：< 2400 是 earth，>= 2400 換成 moon，
    // >= 7500 換成 new_world；astronaut_landing.png（層級第二低）維持疊在底層圖上方，不隨里程碑改變。
    private var backgroundBaseImageName: String {
        if Double(totalCoins) >= Self.coinCapsuleMaxValue { return "AstronautNewWorldIcon" }
        if Double(totalCoins) >= Self.coinCapsuleMidValue { return "AstronautMoonIcon" }
        return "AstronautEarthIcon"
    }

    @State private var showCoinBurst = false
    @State private var coinBurstProgress: Double = 0
    @State private var coinBurstCount = 0

    /// delay 秒後（跟 startSpaceShuttlePulse 同一個時間點），讓 count 個 coin.png
    /// 依序（一個接一個）從 coinStartPixel 拋物線飛到 coinEndPixel。
    private func triggerCoinBurst(count: Int, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            coinBurstCount = count
            coinBurstProgress = 0
            showCoinBurst = true
            withAnimation(.linear(duration: Self.coinBurstDuration)) {
                coinBurstProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.coinBurstDuration) {
                showCoinBurst = false
            }
        }
    }

    // MARK: - 右側金錢累計數字（跟 coin.png 抵達同步，+100 → +200 → +300...）

    @State private var scoreElapsed: Double = -1
    @State private var scoreTimer: Timer?
    private static let scoreHoldAfterLast: Double = 0.6

    /// delay 秒後（跟 triggerCoinBurst 同一個時間點）開始跑右側的「+100/+200/+300...」累計數字：
    /// 數字累加跟硬幣飛行動畫脫鉤，用自己的 Timer 依固定節奏（CoinBurstScoreLabel.stagger）逐一往上跳，
    /// 確保無論硬幣數量多少，一定會完整跑完第一個數字到最後一個數字，寫法跟 9_Working.swift 的
    /// startScoreSequence 完全相同；totalCoins 也是在這裡（而不是 recordHoldResult）逐一 +100 累加。
    private func startScoreSequence(count: Int, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
    }

    /// 進入 holding 狀態時開始讓 astronaut_holding.png 的內容物持續微微抖動，
    /// 用 Timer 每 0.08 秒隨機挑一個小幅偏移，模擬用力撐住時的顫抖感。
    private func startTremble() {
        guard trembleTimer == nil else { return }
        trembleTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.08)) {
                trembleOffset = CGSize(width: CGFloat.random(in: -2...2), height: CGFloat.random(in: 1...4))
            }
        }
    }

    private func stopTremble() {
        trembleTimer?.invalidate()
        trembleTimer = nil
        withAnimation(.easeOut(duration: 0.1)) {
            trembleOffset = .zero
        }
    }

    /// 顯示 astronaut_release.png 1.5 秒後，自動切回預設的 astronaut_get.png。
    private func triggerReleaseAnimation() {
        astronautState = .releasing
        releaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { astronautState = .idle }
        releaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseAnimationDuration, execute: workItem)
    }

    // 目標組次數（content.sets/content.reps）之外，實際完成的組次數與各評語次數、累積金錢。
    @State private var currentSet = 1
    @State private var currentRep = 0
    @State private var excellentCount = 0
    @State private var goodCount = 0
    @State private var okCount = 0
    @State private var totalCoins = 0

    // 評語對應的讀秒門檻跟 9_Working.swift／2_Working.swift 的 1/3/5 秒完全相同；回傳值
    // 同時是 coin.png 拋物線動畫要飛幾個、右側「+100/+200/...」數字要跑幾個 stagger。
    // totalCoins 不在這裡加，改成跟 9_Working.swift 一樣交給 startScoreSequence 逐一 +100 累加。
    @discardableResult
    private func recordHoldResult(heldSeconds: Double) -> Int {
        let coinCount: Int
        if heldSeconds >= 5 {
            excellentCount += 1
            coinCount = 15
        } else if heldSeconds >= 3 {
            goodCount += 1
            coinCount = 9
        } else {
            okCount += 1
            coinCount = 3
        }
        currentRep += 1
        return coinCount
    }

    private func handleAngleChange(_ angle: Double?) {
        guard let angle else { return }
        if angle >= Self.holdAngleThreshold {
            hasReachedHoldThreshold = true
            releaseWorkItem?.cancel()
            astronautState = .holding
            startTremble()
            startHoldTimer()
        } else if angle < Self.releaseAngleThreshold && hasReachedHoldThreshold {
            hasReachedHoldThreshold = false
            let heldSeconds = holdElapsed
            let qualified = heldSeconds > Self.holdQualifyDuration
            stopTremble()
            stopHoldTimer()
            withAnimation(.easeOut(duration: 0.2)) {
                holdElapsed = 0
            }
            if qualified {
                let coinCount = recordHoldResult(heldSeconds: heldSeconds)
                triggerReleaseAnimation()
                triggerFuelFlight()
                startSpaceShuttlePulse(times: 3, delay: Self.releaseAnimationDuration)
                triggerCoinBurst(count: coinCount, delay: Self.releaseAnimationDuration)
                startScoreSequence(count: coinCount, delay: Self.releaseAnimationDuration)
            } else {
                astronautState = .idle
            }
        } else if astronautState == .holding {
            stopTremble()
            stopHoldTimer()
            astronautState = .idle
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
                .ignoresSafeArea()

            // 背景：底層圖依 totalCoins 里程碑切換（< 2400 是 earth，>= 2400 換成 moon，
            // >= 7500 換成 new_world），astronaut_landing.png 固定疊在底層圖上方，不隨里程碑改變。
            ZStack {
                Image(backgroundBaseImageName)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.4)
                Image("AstronautLandingIcon")
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(48)
            .allowsHitTesting(false)

            // space_shuttle 獨立成一層（跟 9_Working.swift 的靶心疊圖同樣做法），
            // 燃料箱抵達艙口後才能單獨對它 scaleEffect／brightness 做 pulse，不影響其他背景圖。
            Image("AstronautSpaceShuttleIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(spaceShuttleScale)
                .brightness(spaceShuttleBrightness)
                .padding(48)
                .allowsHitTesting(false)

            // 前景太空人：角度 < 70° 顯示 astronaut_get.png；角度 >= 70° 換成 astronaut_holding.png 並持續微微抖動；
            // 曾經達到 70° 之後又回落到 < 25° 時，短暫換成 astronaut_release.png（1.5 秒後自動切回預設）。
            Group {
                switch astronautState {
                case .idle:
                    Image("AstronautGetIcon")
                        .resizable()
                        .scaledToFill()
                case .holding:
                    Image("AstronautHoldingIcon")
                        .resizable()
                        .scaledToFill()
                        .offset(trembleOffset)
                case .releasing:
                    Image("AstronautReleaseIcon")
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(48)
            .allowsHitTesting(false)

            if showFuelAnimation {
                GeometryReader { geo in
                    MovingFuelIcon(
                        progress: fuelProgress,
                        start: Self.overlayPosition(for: Self.canvasFraction(x: Self.fuelStartPixel.x, y: Self.fuelStartPixel.y), in: geo.size),
                        end: Self.overlayPosition(for: Self.canvasFraction(x: Self.fuelEndPixel.x, y: Self.fuelEndPixel.y), in: geo.size),
                        startSize: 450,
                        endSize: 200
                    )
                }
                .allowsHitTesting(false)
            }

            if showCoinBurst {
                GeometryReader { geo in
                    CoinFlightBurst(
                        progress: coinBurstProgress,
                        count: coinBurstCount,
                        start: Self.overlayPosition(for: Self.canvasFraction(x: Self.coinStartPixel.x, y: Self.coinStartPixel.y), in: geo.size),
                        end: Self.overlayPosition(for: Self.canvasFraction(x: Self.coinEndPixel.x, y: Self.coinEndPixel.y), in: geo.size)
                    )
                }
                .allowsHitTesting(false)
            }

            if scoreElapsed >= 0 {
                GeometryReader { geo in
                    CoinBurstScoreLabel(
                        elapsed: scoreElapsed,
                        count: coinBurstCount,
                        position: Self.overlayPosition(for: Self.canvasFraction(x: 950, y: 600), in: geo.size)
                    )
                }
                .allowsHitTesting(false)
            }

            // 頂部矩形匡：跟 9_Working.swift 同樣的淺色矩形條 + 底下深色分隔線，
            // 寬度對齊下方遊戲畫面（同樣 padding(.horizontal, 48) + padding(.top, 48)）。
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.72, green: 0.82, blue: 0.82))

                    HStack(spacing: 12) {
                        Button {
                            onReturnToDashboard()
                            dismiss()
                        } label: {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)

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
                            Circle()
                                .fill(Color(red: 0.369, green: 0.690, blue: 0.824))
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                .frame(width: 40, height: 40)
                                .overlay(Text("好").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                            Text("\(okCount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.910, green: 0.306, blue: 0.290))
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                .frame(width: 40, height: 40)
                                .overlay(Text("棒").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                            Text("\(goodCount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.957, green: 0.871, blue: 0.235))
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                .frame(width: 40, height: 40)
                                .overlay(Text("優").font(.system(size: 16, weight: .bold)).foregroundStyle(.black))
                            Text("\(excellentCount)")
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

                        // 右側評語：讀秒 1/3/5 秒對應「好」／「棒」／「優」，跟頂部矩形匡同樣的圈圈樣式。
                        Circle()
                            .fill(Color(red: 0.369, green: 0.690, blue: 0.824))
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .frame(width: 32, height: 32)
                            .overlay(Text("好").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                            .position(x: 60, y: h * 4 / 5)
                        Circle()
                            .fill(Color(red: 0.910, green: 0.306, blue: 0.290))
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .frame(width: 32, height: 32)
                            .overlay(Text("棒").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                            .position(x: 60, y: h * 2 / 5)
                        Circle()
                            .fill(Color(red: 0.957, green: 0.871, blue: 0.235))
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .frame(width: 32, height: 32)
                            .overlay(Text("優").font(.system(size: 14, weight: .bold)).foregroundStyle(.black))
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
                            .foregroundStyle(.black)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding(12)
                    }
                }
                .frame(width: 130, height: 130)
            }
            .padding(24)
            .offset(x: 25, y: -100)

            // 總金幣直式膠囊（中心點對齊 space_shuttle 畫布座標 (631, 394)）：
            // 只有 0／2400／7500 三個刻度，水位跟著 totalCoins 即時更新。
            GeometryReader { geo in
                let capsuleCenter = Self.overlayPosition(for: Self.canvasFraction(x: 631, y: 394), in: geo.size)

                GeometryReader { innerGeo in
                    let h = innerGeo.size.height
                    let fillFraction = min(CGFloat(totalCoins) / CGFloat(Self.coinCapsuleMaxValue), 1)
                    let midY = h * (1 - CGFloat(Self.coinCapsuleMidValue / Self.coinCapsuleMaxValue))

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
                                    .frame(height: fillGeo.size.height * fillFraction)
                            }
                            .clipShape(Capsule())
                        }
                        .padding(6)
                        .clipShape(Capsule())
                        Capsule()
                            .strokeBorder(Color.black, lineWidth: 1.5)
                            .padding(6)

                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 28, height: 1.5)
                            .position(x: 20, y: midY)

                        Image("CoinIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(x: 20, y: -14)
                    }
                }
                .frame(width: 40, height: 200)
                .position(capsuleCenter)
            }
            .allowsHitTesting(false)
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            handleAngleChange(newValue)
        }
        .onDisappear {
            stopLiveTestIfNeeded()
            trembleTimer?.invalidate()
            holdTimer?.invalidate()
            releaseWorkItem?.cancel()
            fuelHideWorkItem?.cancel()
            scoreTimer?.invalidate()
        }
    }
}

// MARK: - MovingFuelIcon

// 讓燃料箱從起點直線飛向終點：progress 是唯一會被 SwiftUI 動畫插值的值，
// x/y 在每個插值後的 progress 當下重新計算，才能跟著 withAnimation 平滑移動
// （寫法跟 9_Working.swift 的 MovingArrow 完全相同）。
private struct MovingFuelIcon: View, Animatable {
    var progress: Double
    let start: CGPoint
    let end: CGPoint
    let startSize: CGFloat
    let endSize: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress
        let size = startSize + (endSize - startSize) * progress
        Image("AstronautFuelIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

// MARK: - CoinFlightBurst

// count 個 coin.png 從同一個固定起點依序（stagger）出發，各自沿拋物線飛向同一個終點後消失；
// 全部硬幣共用同一個 0→1 的 progress（由外部 withAnimation 在 coinBurstDuration 秒內跑完），
// 每顆硬幣依自己的出發時間換算出區間內的 localT，寫法跟 9_Working.swift 的 CoinConvergeBurst 相同，
// 差別只在起點是同一個固定座標，不是繞著終點隨機散開。
private struct CoinFlightBurst: View, Animatable {
    var progress: Double
    let count: Int
    let start: CGPoint
    let end: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let flightFraction = 0.5
    private static let arcHeight: CGFloat = 40
    private static let coinSize: CGFloat = 40

    var body: some View {
        let staggerFraction = count > 1 ? (1 - Self.flightFraction) / Double(count - 1) : 0

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let startFraction = Double(i) * staggerFraction
                let localT = min(max((progress - startFraction) / Self.flightFraction, 0), 1)

                if progress >= startFraction && localT < 1 {
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
// 用自己的 elapsed（由 Timer 驅動，見 Working22.startScoreSequence）逐一往上跳
// （+100 → +200 → +300...），跟硬幣飛行動畫的 1 秒視覺效果脫鉤，確保無論硬幣數量多少
// 都能完整跑完全部數字。
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
    Working22(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 22,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        onReturnToDashboard: {}
    )
    .environment(BluetoothViewModel())
}

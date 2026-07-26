import SwiftUI
import CoreBluetooth

/// 弓步遊戲畫面（exercise_id 22）目前只做出「即時視覺回饋」的部分：
/// 背景固定疊 earth／landing／space_shuttle 三張圖（不隨角度變化）；
/// 前景太空人角度 < 70° 顯示 get.png，>= 70° 換成 holding.png（微微抖動，同時直式膠囊水位隨秒數上漲），
/// 曾經達到 70° 後又回落到 < 25° 且讀秒超過 1 秒時，短暫換成 release.png（1.5 秒後切回預設），
/// 同時 astronaut_fuel.png 從雙手位置飛進火箭燃料艙口（同樣 1.5 秒）；不論是否達到 1 秒，
/// 只要回落到 < 25° 直式膠囊水位都會歸零（讀秒不足 1 秒時只是不觸發 release/燃料箱動畫）。
/// 左側圓圈顯示即時角度數字。組數/次數計分等遊戲機制尚未實作，等後續確認規則後再依 9_Working.swift 的骨架補上。
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
            let qualified = holdElapsed > Self.holdQualifyDuration
            stopTremble()
            stopHoldTimer()
            withAnimation(.easeOut(duration: 0.2)) {
                holdElapsed = 0
            }
            if qualified {
                triggerReleaseAnimation()
                triggerFuelFlight()
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

            // 背景：astronaut_earth／landing／space_shuttle 三張固定疊在一起，不隨角度變化。
            ZStack {
                Image("AstronautEarthIcon")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.4)
                Image("AstronautLandingIcon")
                    .resizable()
                    .scaledToFill()
                Image("AstronautSpaceShuttleIcon")
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
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

            HStack {
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

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

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

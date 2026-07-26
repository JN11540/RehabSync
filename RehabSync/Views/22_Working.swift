import SwiftUI
import CoreBluetooth

/// 弓步遊戲畫面（exercise_id 22）目前只做出「即時視覺回饋」的部分：
/// 背景太空人依「站姿即時預估角度」分成四個層級（earth 最低 → get 最高），
/// 左側圓圈顯示即時角度數字。組數/次數計分、直式膠囊（進度條）等遊戲機制
/// 尚未實作，等後續確認規則後再依 9_Working.swift 的骨架補上。
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

    // 直式膠囊的讀秒進度，先給預設值讓膠囊能顯示出來；實際驅動 holdElapsed 累加的
    // hold timer 邏輯等角度門檻規則確認後再補上。
    @State private var holdElapsed: Double = 0
    private static let holdDuration: Double = 5

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
                .ignoresSafeArea()

            // 預設狀態：四張太空人圖層直接疊在一起（earth 最底層 → get 最上層），
            // 等角度門檻規則確認後再改回依 btVM.currentEstimatedRealAngle 切換。
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
                Image("AstronautGetIcon")
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(48)
            .allowsHitTesting(false)

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
        .onDisappear {
            stopLiveTestIfNeeded()
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

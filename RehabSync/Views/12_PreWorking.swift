import SwiftUI
import CoreBluetooth

// MARK: - PreWorking12

struct PreWorking12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var step = 0
    @State private var didAttemptCalibration = false
    @State private var calibrationCountdown = 5
    @State private var countdownTimer: Timer?
    @State private var showSuccessArrow = false
    @State private var legRotation: Double = 0

    private var stepTitle: String {
        switch step {
        case 0: return "確認裝備齊全"
        case 1: return "準備踏板或凳子"
        case 2: return "校正"
        default: return "登階運動測試"
        }
    }

    private func resetCalibration() {
        didAttemptCalibration = false
        calibrationCountdown = 5
        countdownTimer?.invalidate()
        countdownTimer = nil
        showSuccessArrow = false
        btVM.baselineResult = nil
        btVM.isCollectingBaseline = false
    }

    private var thighAndCalfPeripherals: (thigh: CBPeripheral, calf: CBPeripheral)? {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid),
              let thighPeripheral = btVM.connectedPeripherals[thighUUID],
              let calfPeripheral  = btVM.connectedPeripherals[calfUUID]
        else { return nil }
        return (thighPeripheral, calfPeripheral)
    }

    // 校正結果對應到「量測角度 → 預估真實角度」的公式是坐姿/站姿各一套，
    // 進入測試頁前先依 content.exercise_id 確認目前是哪個動作，避免套錯公式導致角度算錯。
    private var posture: BluetoothViewModel.KneePosture {
        switch content.exercise_id {
        case 12: return .standing
        default: return .sitting
        }
    }

    private func startLiveTestIfNeeded() {
        guard !btVM.isLiveEstimating,
              let pair = thighAndCalfPeripherals,
              let baseline = btVM.baselineResult
        else { return }
        btVM.startLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline, posture: posture)
    }

    private func stopLiveTestIfNeeded() {
        guard btVM.isLiveEstimating, let pair = thighAndCalfPeripherals else { return }
        btVM.stopLiveEstimateRealAngle(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
    }

    // divide_4（上半身）本身不會旋轉，但它底部藍綠色端（肩頸下緣）要跟著 divide_2
    // （大腿＋小腿）頂部的藍綠色端一起移動，才不會讓上半身跟腿部脫節。
    // divide_2 頂部藍綠色端在 divide_2 自己的旋轉軸心（腳踝，skin 中心）為圓心，
    // 隨 legRotation 做圓弧運動，這裡直接算出該點相對於角度 0 時位移了多少，
    // 再把同樣的位移套用到 divide_4 上，兩端點就會隨時保持疊合（而不只是首尾對齊）。
    private var divide4Offset: CGSize {
        let theta = legRotation * Double.pi / 180
        let dx0 = 124.0
        let dy0 = -522.0
        let rotatedX = dx0 * cos(theta) - dy0 * sin(theta)
        let rotatedY = dx0 * sin(theta) + dy0 * cos(theta)
        let scale = 500.0 / 2048.0
        return CGSize(width: (rotatedX - dx0) * scale, height: (rotatedY - dy0) * scale)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.85, green: 0.93, blue: 0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(white: 0.6), lineWidth: 5)
                    )
                    .overlay(alignment: .top) {
                        Text(stepTitle)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.top, 24)
                    }

                if step == 0 {
                    HStack(spacing: 24) {
                        VStack(spacing: 0) {
                            Image("KneeThighConnectedIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 380)
                                .padding(4)
                            AssureLabel(text: "裝置連線了嗎？")
                                .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 0) {
                            Image("WearPadAndGearsIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 380)
                                .padding(4)
                            AssureLabel(text: "護膝穿戴了嗎？")
                                .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 174)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 1 {
                    VStack(spacing: 12) {
                        Image("StoolIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Text("請先準備一階穩固、小腿一半高度的踏板或凳子\n並確保踩踏處平整、不濕滑")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 2 {
                    VStack(spacing: 16) {
                        Image("Exercise12Stage1")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Text("請站直，膝關節伸直\n點擊『校正』按鈕後，請維持身體靜止不動 5 秒鐘喔！")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .padding(.leading, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showSuccessArrow {
                        Button(action: { step += 1 }) {
                            Image("ArrowIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 0)
                    } else {
                        VStack(spacing: 12) {
                            Button(action: {
                                guard let pair = thighAndCalfPeripherals else { return }
                                didAttemptCalibration = true
                                calibrationCountdown = 5
                                countdownTimer?.invalidate()
                                countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                                    if calibrationCountdown > 1 {
                                        calibrationCountdown -= 1
                                    } else {
                                        timer.invalidate()
                                    }
                                }
                                btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                                    Circle()
                                        .strokeBorder(Color.black, lineWidth: 6)
                                    if btVM.isCollectingBaseline {
                                        Text("\(calibrationCountdown)")
                                            .font(.system(size: 100, weight: .bold))
                                            .foregroundStyle(.black)
                                    } else {
                                        Text("校正")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundStyle(.black)
                                    }
                                }
                                .frame(width: 200, height: 200)
                            }
                            .buttonStyle(.plain)
                            .disabled(btVM.isCollectingBaseline)

                            if thighAndCalfPeripherals == nil {
                                Text("裝置未連線")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                            } else if btVM.baselineResult != nil {
                                Text("校正成功！")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.green)
                            } else if didAttemptCalibration && !btVM.isCollectingBaseline {
                                Text("校正失敗，請重試！")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 40)
                    }
                } else if step == 3 {
                    ZStack {
                        Image("PartialSquatDivide1Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Image("PartialSquatDivide2Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .rotationEffect(.degrees(legRotation), anchor: UnitPoint(x: 0.542, y: 0.685))

                        Image("PartialSquatDivide4Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .offset(divide4Offset)

                        Image("PartialSquatDivide3Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .rotationEffect(.degrees(legRotation / 1.5), anchor: UnitPoint(x: 0.410, y: 0.481))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Group {
                        if let angle = btVM.currentEstimatedRealAngle {
                            Text(String(format: "%.1f°", angle))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        } else {
                            Text("等待資料…")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                }

                Button(action: {
                    if step == 2 { resetCalibration() }
                    if step == 3 { stopLiveTestIfNeeded() }
                    dismiss()
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
                    .padding(16)
                }
                .buttonStyle(.plain)

                if step < 2 {
                    Button(action: { step += 1 }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 0)
                }

                if step > 0 {
                    Button(action: {
                        if step == 2 || step == 3 { resetCalibration() }
                        if step == 3 { stopLiveTestIfNeeded() }
                        step -= 1
                    }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(x: -1, y: 1)
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 0)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)
        }
        .onChange(of: btVM.baselineResult) { _, newValue in
            if newValue != nil {
                showSuccessArrow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSuccessArrow = true
                }
            } else {
                showSuccessArrow = false
            }
        }
        .onChange(of: step) { oldValue, newValue in
            if oldValue == 2 && newValue < oldValue {
                resetCalibration()
            }
            if oldValue == 3 && newValue != 3 {
                stopLiveTestIfNeeded()
            }
            if newValue == 3 {
                legRotation = 0
                startLiveTestIfNeeded()
            }
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                legRotation = newValue ?? 0
            }
        }
    }
}

// MARK: - Assure Label

private struct AssureLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    PreWorking12(
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

import SwiftUI
import CoreBluetooth

// MARK: - PreWorking2

struct PreWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var step = 0
    @State private var calibrationPhase: CalibrationPhase = .idle
    @State private var calibrationFailed = false
    @State private var aboutToCalibrateCountdown = 2
    @State private var aboutToCalibrateTimer: Timer?
    @State private var calibrationCountdown = 5
    @State private var countdownTimer: Timer?
    @State private var legRotation: Double = 0
    @State private var navigateToWorking2 = false

    private enum CalibrationPhase {
        case idle
        case aboutToCalibrate
        case calibrating
    }

    private var stepTitle: String {
        switch step {
        case 0: return "確認裝備齊全"
        case 1: return "準備椅子"
        case 2: return "放置平板"
        case 3: return "校正"
        default: return "膝關節終端伸展測試"
        }
    }

    private func resetCalibration() {
        aboutToCalibrateTimer?.invalidate()
        aboutToCalibrateTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        calibrationPhase = .idle
        calibrationFailed = false
        aboutToCalibrateCountdown = 2
        calibrationCountdown = 5
        btVM.baselineResult = nil
        btVM.isCollectingBaseline = false
    }

    // 使用者按下「校正」圓圈才開始：先提示「不要動」2 秒，
    // 接著才是真正的 5 秒收集（校正倒數 5→1）。成功就直接翻頁，
    // 失敗則回到 idle，需要使用者再按一次「校正」才會重新開始，不自動重試。
    private func scheduleCalibrationAttempt() {
        calibrationPhase = .aboutToCalibrate
        calibrationFailed = false
        aboutToCalibrateCountdown = 2
        aboutToCalibrateTimer?.invalidate()
        aboutToCalibrateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if aboutToCalibrateCountdown > 1 {
                aboutToCalibrateCountdown -= 1
            } else {
                timer.invalidate()
                startCalibrationAttempt()
            }
        }
    }

    private func startCalibrationAttempt() {
        calibrationPhase = .calibrating
        calibrationCountdown = 5
        countdownTimer?.invalidate()
        if let pair = thighAndCalfPeripherals {
            btVM.startBaselineCalibration(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if calibrationCountdown > 1 {
                calibrationCountdown -= 1
            } else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    evaluateCalibrationResult()
                }
            }
        }
    }

    private func evaluateCalibrationResult() {
        if btVM.baselineResult != nil {
            step += 1
        } else {
            resetCalibration()
            calibrationFailed = true
        }
    }

    private var calibrationPhaseLabel: String? {
        switch calibrationPhase {
        case .idle:             return nil
        case .aboutToCalibrate: return "準備校正\n不要動喔"
        case .calibrating:      return "校正"
        }
    }

    private var calibrationPhaseNumber: String? {
        switch calibrationPhase {
        case .idle:             return nil
        case .aboutToCalibrate: return "\(aboutToCalibrateCountdown)"
        case .calibrating:      return "\(calibrationCountdown)"
        }
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
        case 9: return .standing
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
                        Image("ChairIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Text("請先找一張高度剛好到您膝蓋的椅子")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 2 {
                    VStack(spacing: 12) {
                        Image("TabletDeskIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        Text("請將平板放置於桌面上\n準備就緒後點擊「開始」")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 3 {
                    HStack(spacing: 60) {
                        Image("StopNoMoveIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)

                        VStack(spacing: 16) {
                            Text(calibrationPhaseLabel ?? "")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 76)

                            if calibrationPhase == .idle {
                                Button(action: {
                                    guard thighAndCalfPeripherals != nil else { return }
                                    scheduleCalibrationAttempt()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                                        Circle()
                                            .strokeBorder(Color.black, lineWidth: 6)
                                        Text("校正")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundStyle(.black)
                                    }
                                    .frame(width: 200, height: 200)
                                }
                                .buttonStyle(.plain)
                                .disabled(thighAndCalfPeripherals == nil)
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                                    Circle()
                                        .strokeBorder(Color.black, lineWidth: 6)

                                    if let number = calibrationPhaseNumber {
                                        Text(number)
                                            .font(.system(size: 100, weight: .bold))
                                            .foregroundStyle(.black)
                                    }
                                }
                                .frame(width: 200, height: 200)
                            }

                            if calibrationFailed {
                                Text("校正失敗，請重新嘗試")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                            }

                            if thighAndCalfPeripherals == nil {
                                Text("裝置未連線")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if step == 4 {
                    HStack(spacing: -80) {
                        Image("OnlyLegIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .rotationEffect(.degrees(legRotation))
                            .offset(x: 170, y: 50)

                        Image("StopNoMoveIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 500, height: 500)
                            .offset(x: -185)
                    }
                    .padding(.horizontal, 24)
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
                    if step == 3 { resetCalibration() }
                    if step == 4 {
                        stopLiveTestIfNeeded()
                    }
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

                if step < 3 {
                    Button(action: { step += 1 }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 0)
                } else if step == 4 {
                    Button(action: {
                        navigateToWorking2 = true
                    }) {
                        Image("ArrowIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 0)
                }

                if step > 0 && step != 3 {
                    Button(action: {
                        if step == 4 {
                            resetCalibration()
                            stopLiveTestIfNeeded()
                        }
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
        .onChange(of: step) { oldValue, newValue in
            if oldValue == 4 && newValue != 4 {
                stopLiveTestIfNeeded()
            }
            if newValue == 3 {
                resetCalibration()
            }
            if newValue == 4 {
                legRotation = -90
                startLiveTestIfNeeded()
            }
        }
        .onChange(of: btVM.currentEstimatedRealAngle) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                legRotation = -(newValue ?? 90)
            }
        }
        .fullScreenCover(isPresented: $navigateToWorking2) {
            Working2(content: content, exercise: exercise)
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
    PreWorking2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
    .environment(BluetoothViewModel())
}

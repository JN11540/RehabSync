import SwiftUI
import CoreBluetooth

// MARK: - PreWorking12

struct PreWorking12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var step = 0
    @State private var calibrationPhase: CalibrationPhase = .preparingPosture
    @State private var postureCountdown = 10
    @State private var postureTimer: Timer?
    @State private var calibrationCountdown = 5
    @State private var countdownTimer: Timer?
    @State private var stepDisplayStage: StepDisplayStage = .standing
    @State private var stepUpGeneration = 0
    @State private var navigateToWorking12 = false

    private enum StepDisplayStage {
        case standing
        case steppingUp
        case standingOnStep
        case steppingDown
    }

    private enum CalibrationPhase {
        case preparingPosture
        case aboutToCalibrate
        case calibrating
    }

    private var stepTitle: String {
        switch step {
        case 0: return "確認裝備齊全"
        case 1: return "準備踏板或凳子"
        case 2: return "放置平板"
        case 3: return "校正"
        default: return "登階運動測試"
        }
    }

    private func resetCalibration() {
        postureTimer?.invalidate()
        postureTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        calibrationPhase = .preparingPosture
        postureCountdown = 10
        calibrationCountdown = 5
        btVM.baselineResult = nil
        btVM.isCollectingBaseline = false
    }

    // 校正頁進來後全自動跑：先給 10 秒擺姿勢時間，接著提示「不要動」2 秒，
    // 最後才是真正的 5 秒收集（校正倒數 5→1）。成功就直接翻頁，失敗則回到
    // 「不要動」提示重新收集一次，不用使用者手動按重試。
    private func startCalibrationFlow() {
        resetCalibration()
        startPostureCountdown()
    }

    private func startPostureCountdown() {
        calibrationPhase = .preparingPosture
        postureCountdown = 10
        postureTimer?.invalidate()
        postureTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if postureCountdown > 1 {
                postureCountdown -= 1
            } else {
                timer.invalidate()
                scheduleCalibrationAttempt()
            }
        }
    }

    private func scheduleCalibrationAttempt() {
        calibrationPhase = .aboutToCalibrate
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            startCalibrationAttempt()
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
            scheduleCalibrationAttempt()
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

    private var stepDisplayImageName: String {
        switch stepDisplayStage {
        case .standing:       return "Exercise12Stage1"
        case .steppingUp:     return "Exercise12Stage2"
        case .standingOnStep: return "Exercise12Stage3"
        case .steppingDown:   return "Exercise12Stage2"
        }
    }

    private var stepDisplayLabel: String {
        switch stepDisplayStage {
        case .standing:                     return "站立"
        case .steppingUp, .standingOnStep:  return "上階"
        case .steppingDown:                 return "下階"
        }
    }

    // 上階（status 1）本身沒有時間上限，先顯示「移動中」的 stool_step_up.png，
    // 滿 1.5 秒後才換成「已站上階梯」的 stool_standing_person.png；用 generation 計數器
    // 避免使用者提早下階（status 2）之後，這個延遲排程還套用到舊的上階狀態上。
    private func handleStepStatusChange(_ newValue: Int?) {
        switch newValue {
        case 1:
            stepDisplayStage = .steppingUp
            stepUpGeneration += 1
            let generation = stepUpGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if generation == stepUpGeneration, btVM.currentStepStatus == 1 {
                    stepDisplayStage = .standingOnStep
                }
            }
        case 2:
            stepDisplayStage = .steppingDown
        default:
            stepDisplayStage = .standing
        }
    }

    private func startLiveTestIfNeeded() {
        guard !btVM.isEstimatingStepStatus,
              let pair = thighAndCalfPeripherals,
              let baseline = btVM.baselineResult
        else { return }
        btVM.startStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf, baseline: baseline)
    }

    private func stopLiveTestIfNeeded() {
        guard btVM.isEstimatingStepStatus, let pair = thighAndCalfPeripherals else { return }
        btVM.stopStepStatusEstimation(thighPeripheral: pair.thigh, calfPeripheral: pair.calf)
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
                    Image("Exercise12Stage1")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 500, height: 500)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                            Circle()
                                .strokeBorder(Color.black, lineWidth: 6)

                            switch calibrationPhase {
                            case .preparingPosture:
                                VStack(spacing: 4) {
                                    Text("準備姿勢")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.black)
                                    Text("\(postureCountdown)")
                                        .font(.system(size: 56, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            case .aboutToCalibrate:
                                Text("準備校正\n不要動喔")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.black)
                                    .multilineTextAlignment(.center)
                            case .calibrating:
                                Text("\(calibrationCountdown)")
                                    .font(.system(size: 100, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 200, height: 200)

                        if thighAndCalfPeripherals == nil {
                            Text("裝置未連線")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 40)
                } else if step == 4 {
                    Image(stepDisplayImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 500, height: 500)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Group {
                        if btVM.currentStepStatus != nil {
                            Text(stepDisplayLabel)
                                .font(.system(size: 32, weight: .bold))
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
                    if step == 4 { stopLiveTestIfNeeded() }
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
                } else if step == 2 {
                    Button(action: { step += 1 }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.99, green: 0.88, blue: 0.49))
                            Circle()
                                .strokeBorder(Color.black, lineWidth: 6)
                            Text("開始")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 200, height: 200)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 40)
                } else if step == 4 {
                    Button(action: {
                        navigateToWorking12 = true
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
                startCalibrationFlow()
            }
            if newValue == 4 {
                stepDisplayStage = .standing
                startLiveTestIfNeeded()
            }
        }
        .onChange(of: btVM.currentStepStatus) { _, newValue in
            handleStepStatusChange(newValue)
        }
        .fullScreenCover(isPresented: $navigateToWorking12) {
            Working12(content: content, exercise: exercise)
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

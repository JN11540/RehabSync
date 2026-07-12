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

    private static let holdDuration: Double = 9
    private static let giveFoodDuration: Double = 1.5

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

                        Text("9")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black)
                            .position(x: -20, y: 0)

                        ForEach(1..<5) { i in
                            Text("\(9 - 2 * i)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.black)
                                .position(x: -20, y: h * CGFloat(i) / 5)
                        }

                        Image("TakoyakiCustomerComingMoodIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .position(x: 60, y: h * 2 / 5)
                        Image("TakoyakiCustomerBadMoodIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .position(x: 60, y: h * 1 / 5)
                        Image("TakoyakiCustomerAngryMoodIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
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

                    Text(stepStatusLabel)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.black)
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
                stopHoldTimer()
                showGiveFood = true
                showReceive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.giveFoodDuration) {
                    showGiveFood = false
                    showReceive = false
                }
            }
        }
        .onDisappear {
            holdTimer?.invalidate()
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

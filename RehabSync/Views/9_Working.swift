import SwiftUI

// MARK: - Working9

struct Working9: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var holdElapsed: Double = 0
    @State private var holdTimer: Timer?
    @State private var showOutIcon = false
    @State private var hitBowIconName: String? = nil

    private static let holdThreshold: Double = 45
    private static let holdDuration: Double = 5
    private static let outIconDuration: Double = 1.5

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

            if heldSeconds >= 5 {
                hitBowIconName = "BowYellowIcon"
            } else if heldSeconds >= 3 {
                hitBowIconName = "BowRedIcon"
            } else if heldSeconds >= 1 {
                hitBowIconName = "BowBlueIcon"
            }
            if hitBowIconName != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.outIconDuration) {
                    hitBowIconName = nil
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

            Image("ArrowTargetIcon")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(48)

            if let hitBowIconName {
                Image(hitBowIconName)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(48)
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

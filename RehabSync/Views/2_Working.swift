import SwiftUI

// MARK: - Working2

struct Working2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(BluetoothViewModel.self) private var btVM

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()

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
                        Capsule()
                            .fill(Color.blue)
                            .padding(6)
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
                            .foregroundStyle(.white)
                            .position(x: 40 + 20, y: 0)

                        ForEach(1..<5) { i in
                            Text("\(5 - i)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .position(x: 40 + 20, y: h * CGFloat(i) / 5)
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
                        Text(String(format: "%.0f", angle))
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
        exercise: nil
    )
}

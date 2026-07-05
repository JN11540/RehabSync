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
                }
                .frame(width: 40, height: 300)

                ZStack {
                    Circle()
                        .fill(Color(white: 0.35))
                    Circle()
                        .fill(Color.white)
                        .padding(6)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                        .padding(6)

                    if let angle = btVM.currentEstimatedRealAngle {
                        Text(String(format: "%.0f", angle))
                            .font(.system(size: 75, weight: .bold))
                            .foregroundStyle(.black)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding(18)
                    }
                }
                .frame(width: 195, height: 195)
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

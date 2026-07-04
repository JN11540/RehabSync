import SwiftUI

// MARK: - PreWorking2

struct PreWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()

            Text(exercise?.name ?? "未知動作")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
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
}

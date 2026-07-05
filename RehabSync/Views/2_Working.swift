import SwiftUI

// MARK: - Working2

struct Working2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    var body: some View {
        Color.black.ignoresSafeArea()
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

import SwiftUI

// MARK: - PostWorking9

struct PostWorking9: View {
    let content: TreatmentContent
    let exercise: Exercise?

    var body: some View {
        Color.white
            .ignoresSafeArea()
    }
}

#Preview {
    PostWorking9(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 9,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
}

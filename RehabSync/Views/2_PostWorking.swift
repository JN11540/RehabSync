import SwiftUI

// MARK: - PostWorking2

struct PostWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            Image("FishingEndIcon")
                .resizable()
                .scaledToFill()
                .opacity(0.5)
                .clipped()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    PostWorking2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil
    )
}

import SwiftUI

// MARK: - PostWorking2

struct PostWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.85, green: 0.93, blue: 0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(white: 0.6), lineWidth: 5)
                    )

                VStack {
                    HStack(alignment: .bottom, spacing: 12) {
                        Image("FinishGameLeftIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)

                        Image("FinishGameRightIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                            }
                        }
                        .frame(height: 100)

                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                        }
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.6), lineWidth: 1.5))
                        }
                        .frame(height: 200)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 0)
                    .offset(y: -50)

                    Spacer()
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)
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

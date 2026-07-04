import SwiftUI

// MARK: - PreWorking2

struct PreWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss

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
                        Text("穿戴方式")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.top, 24)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.70, green: 0.80, blue: 0.86))
                    .padding(.top, 80)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                Button(action: { dismiss() }) {
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
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 400)
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

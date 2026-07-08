import SwiftUI

// MARK: - PostWorking2

struct PostWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    // 取自 finish_game_left.png 圖片中五個主要色塊（黃／橘／藍／膚粉／桃紅）
    private static let congratsColors: [Color] = [
        Color(red: 0.996, green: 0.914, blue: 0.486),
        Color(red: 0.992, green: 0.706, blue: 0.255),
        Color(red: 0.541, green: 0.788, blue: 0.996),
        Color(red: 0.949, green: 0.690, blue: 0.635),
        Color(red: 0.941, green: 0.447, blue: 0.502)
    ]
    private static let congratsText = ["恭", "喜", "完", "成", "！"]

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

                        HStack(spacing: 6) {
                            ForEach(0..<Self.congratsText.count, id: \.self) { i in
                                OutlinedCongratsChar(text: Self.congratsText[i], color: Self.congratsColors[i])
                            }
                        }

                        Image("FinishGameRightIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ForEach(0..<7, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                            }
                        }
                        .frame(height: 100)

                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                        }
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
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

// MARK: - OutlinedCongratsChar

private struct OutlinedCongratsChar: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 100, weight: .bold))
            .foregroundStyle(color)
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

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
            Color.white
                .ignoresSafeArea()

            Image("FishingEndIcon")
                .resizable()
                .scaledToFill()
                .opacity(0.3)
                .clipped()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Image("FinishGameLeftIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(0..<Self.congratsText.count, id: \.self) { i in
                            Text(Self.congratsText[i])
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Self.congratsColors[i])
                        }
                    }

                    Spacer()

                    Image("FinishGameRightIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)

                Spacer()
            }
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

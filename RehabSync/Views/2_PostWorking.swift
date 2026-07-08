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
                HStack(spacing: 12) {
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                        .frame(height: 70)

                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1.5))
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
                    .frame(height: 100)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                Spacer()
            }
        }
    }
}

// MARK: - OutlinedCongratsChar

private struct OutlinedCongratsChar: View {
    let text: String
    let color: Color

    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -2, height: -2), CGSize(width: 2, height: -2),
        CGSize(width: -2, height: 2), CGSize(width: 2, height: 2)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<Self.outlineOffsets.count, id: \.self) { i in
                Text(text)
                    .font(.system(size: 100, weight: .bold))
                    .foregroundStyle(Color.black)
                    .offset(Self.outlineOffsets[i])
            }
            Text(text)
                .font(.system(size: 100, weight: .bold))
                .foregroundStyle(color)
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

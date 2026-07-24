import SwiftUI

struct PostWorking_12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalSets: Int
    let totalElapsedSeconds: Int
    let comingMoodCount: Int
    let badMoodCount: Int
    let angryMoodCount: Int
    let treatmentResult: TreatmentResult
    let onReturnToDashboard: () -> Void

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)
    fileprivate static let lightPurple = Color(red: 0.94, green: 0.92, blue: 0.99)
    fileprivate static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.99)
    fileprivate static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    fileprivate static let green = Color(red: 0.20, green: 0.70, blue: 0.45)
    fileprivate static let blue = Color(red: 0.25, green: 0.55, blue: 0.95)

    /// 毫秒轉成「X 分 YY 秒」，`ms <= 0` 一律視為沒有資料。
    fileprivate static func formatMinutesSeconds(ms: Int) -> String {
        guard ms > 0 else { return "－" }
        let totalSeconds = ms / 1000
        return String(format: "%d 分 %02d 秒", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("你好棒！")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 20))
                    .foregroundStyle(Self.mutedText)

                Spacer()

                Button(action: onReturnToDashboard) {
                    Text("回到總覽")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(Self.darkPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
    }
}

#Preview {
    PostWorking_12(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 12,
            sets: 2, set_rest_time: 10,
            reps: 5,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 0,
        totalSets: 2,
        totalElapsedSeconds: 120,
        comingMoodCount: 0,
        badMoodCount: 0,
        angryMoodCount: 0,
        treatmentResult: TreatmentResult(
            treatment_id: 1, treatment_content_id: 1,
            reps: [5, 3], extension_length: [0, 0, 0, 0, 0, 0, 0, 0],
            set_start_time: [0, 30000], set_end_time: [20000, 60000],
            date: Int(Date().timeIntervalSince1970)
        ),
        onReturnToDashboard: {}
    )
}

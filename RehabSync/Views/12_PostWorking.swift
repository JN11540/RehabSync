import SwiftUI

// MARK: - PostWorking12

struct PostWorking12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalSets: Int
    let totalElapsedSeconds: Int
    let comingMoodCount: Int
    let badMoodCount: Int
    let angryMoodCount: Int
    let onReturnToDashboard: () -> Void
    @State private var barGrowProgress: Double = 0

    private func comparisonMessage(_ value: Int) -> String {
        if 0 > value {
            return "😆 今天是不是還沒睡醒？"
        } else if 0 == value {
            return "😎 穩啦，一樣厲害！"
        } else {
            return "🔥 有喔！這次比較猛！"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack {
                    HStack(alignment: .bottom, spacing: 60) {
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
                    .padding(.top, 16)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 1.0, green: 0.96, blue: 0.85))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.70, green: 0.52, blue: 0.10), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(totalCoins))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 金幣", color: Color(red: 0.70, green: 0.52, blue: 0.10))
                                                    Rectangle()
                                                        .fill(Color(red: 1.0, green: 0.85, blue: 0.60))
                                                        .frame(width: barWidth, height: (0 > totalCoins ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalCoins) * barGrowProgress, suffix: " 金幣", color: Color(red: 0.70, green: 0.52, blue: 0.10))
                                                    Rectangle()
                                                        .fill(Color(red: 1.0, green: 0.70, blue: 0.25))
                                                        .frame(width: barWidth, height: (0 >= totalCoins ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.70, green: 0.52, blue: 0.10))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.70, green: 0.52, blue: 0.10))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("CoinIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.75, green: 0.90, blue: 0.98))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.314, green: 0.647, blue: 0.863), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(totalSets))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.098, green: 0.353, blue: 0.549))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 組", color: Color(red: 0.098, green: 0.353, blue: 0.549))
                                                    Rectangle()
                                                        .fill(Color(red: 0.65, green: 0.85, blue: 0.98))
                                                        .frame(width: barWidth, height: (0 > totalSets ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalSets) * barGrowProgress, suffix: " 組", color: Color(red: 0.098, green: 0.353, blue: 0.549))
                                                    Rectangle()
                                                        .fill(Color(red: 0.20, green: 0.55, blue: 0.80))
                                                        .frame(width: barWidth, height: (0 >= totalSets ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.098, green: 0.353, blue: 0.549))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.098, green: 0.353, blue: 0.549))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.098, green: 0.353, blue: 0.549))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("TargetIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                        }
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.85, green: 0.96, blue: 0.99))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.490, green: 0.824, blue: 0.937), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(totalElapsedSeconds))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.106, green: 0.373, blue: 0.451))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 秒", color: Color(red: 0.106, green: 0.373, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.70, green: 0.92, blue: 0.98))
                                                        .frame(width: barWidth, height: (0 > totalElapsedSeconds ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalElapsedSeconds) * barGrowProgress, suffix: " 秒", color: Color(red: 0.106, green: 0.373, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.275, green: 0.706, blue: 0.831))
                                                        .frame(width: barWidth, height: (0 >= totalElapsedSeconds ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.106, green: 0.373, blue: 0.451))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.106, green: 0.373, blue: 0.451))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.106, green: 0.373, blue: 0.451))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("TotalTimeIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.99, green: 0.96, blue: 0.83))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.957, green: 0.871, blue: 0.235), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(comingMoodCount))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.05))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.45, blue: 0.05))
                                                    Rectangle()
                                                        .fill(Color(red: 0.99, green: 0.93, blue: 0.65))
                                                        .frame(width: barWidth, height: (0 > comingMoodCount ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(comingMoodCount) * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.45, blue: 0.05))
                                                    Rectangle()
                                                        .fill(Color(red: 0.957, green: 0.871, blue: 0.235))
                                                        .frame(width: barWidth, height: (0 >= comingMoodCount ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.55, green: 0.45, blue: 0.05))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.05))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.05))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("TakoyakiCustomerComingMoodIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                        }
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.99, green: 0.90, blue: 0.80))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.9, green: 0.6, blue: 0.3), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(badMoodCount))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.05))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.32, blue: 0.05))
                                                    Rectangle()
                                                        .fill(Color(red: 0.99, green: 0.80, blue: 0.60))
                                                        .frame(width: barWidth, height: (0 > badMoodCount ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(badMoodCount) * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.32, blue: 0.05))
                                                    Rectangle()
                                                        .fill(Color(red: 0.9, green: 0.6, blue: 0.3))
                                                        .frame(width: barWidth, height: (0 >= badMoodCount ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.55, green: 0.32, blue: 0.05))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.05))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.05))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("TakoyakiCustomerBadMoodIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.98, green: 0.88, blue: 0.87))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.910, green: 0.306, blue: 0.290), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Text(comparisonMessage(angryMoodCount))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.13))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .frame(height: 24)
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.15, blue: 0.13))
                                                    Rectangle()
                                                        .fill(Color(red: 0.97, green: 0.75, blue: 0.73))
                                                        .frame(width: barWidth, height: (0 > angryMoodCount ? 60 : 30) * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(angryMoodCount) * barGrowProgress, suffix: " 次", color: Color(red: 0.55, green: 0.15, blue: 0.13))
                                                    Rectangle()
                                                        .fill(Color(red: 0.910, green: 0.306, blue: 0.290))
                                                        .frame(width: barWidth, height: (0 >= angryMoodCount ? 30 : 60) * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.55, green: 0.15, blue: 0.13))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.13))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.13))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("TakoyakiCustomerAngryMoodIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 0)
                    .offset(y: -20)

                    Spacer()
                }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)

            Button(action: { onReturnToDashboard() }) {
                Image("ArrowIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(24)
            .offset(y: 50)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                barGrowProgress = 1
            }
        }
    }
}

// MARK: - BarValueText

private struct BarValueText: View, Animatable {
    var value: Double
    let suffix: String
    let color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))\(suffix)")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color)
    }
}

#Preview {
    PostWorking12(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 12,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 1500,
        totalSets: 2,
        totalElapsedSeconds: 245,
        comingMoodCount: 3,
        badMoodCount: 2,
        angryMoodCount: 1,
        onReturnToDashboard: {}
    )
}

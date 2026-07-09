import SwiftUI

// MARK: - PostWorking2

struct PostWorking2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalReps: Int
    let totalElapsedSeconds: Int
    let bigFishCaught: Int
    let middleFishCaught: Int
    let smallFishCaught: Int
    @State private var barGrowProgress: Double = 0

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
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 金幣", color: Color(red: 0.70, green: 0.52, blue: 0.10))
                                                    Rectangle()
                                                        .fill(Color(red: 1.0, green: 0.85, blue: 0.60))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalCoins) * barGrowProgress, suffix: " 金幣", color: Color(red: 0.70, green: 0.52, blue: 0.10))
                                                    Rectangle()
                                                        .fill(Color(red: 1.0, green: 0.70, blue: 0.25))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
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
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 次", color: Color(red: 0.098, green: 0.353, blue: 0.549))
                                                    Rectangle()
                                                        .fill(Color(red: 0.65, green: 0.85, blue: 0.98))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalReps) * barGrowProgress, suffix: " 次", color: Color(red: 0.098, green: 0.353, blue: 0.549))
                                                    Rectangle()
                                                        .fill(Color(red: 0.20, green: 0.55, blue: 0.80))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
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

                                Image("RepsIcon")
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
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 秒", color: Color(red: 0.106, green: 0.373, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.70, green: 0.92, blue: 0.98))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(totalElapsedSeconds) * barGrowProgress, suffix: " 秒", color: Color(red: 0.106, green: 0.373, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.275, green: 0.706, blue: 0.831))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
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
                                    .fill(Color(red: 0.88, green: 0.93, blue: 0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.678, green: 0.776, blue: 0.804), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 個", color: Color(red: 0.322, green: 0.416, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.80, green: 0.87, blue: 0.90))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(bigFishCaught) * barGrowProgress, suffix: " 個", color: Color(red: 0.322, green: 0.416, blue: 0.451))
                                                    Rectangle()
                                                        .fill(Color(red: 0.678, green: 0.776, blue: 0.804))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.322, green: 0.416, blue: 0.451))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.322, green: 0.416, blue: 0.451))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.322, green: 0.416, blue: 0.451))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("BigFishIcon")
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
                                    .fill(Color(red: 0.99, green: 0.93, blue: 0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.992, green: 0.827, blue: 0.427), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 個", color: Color(red: 0.612, green: 0.451, blue: 0.031))
                                                    Rectangle()
                                                        .fill(Color(red: 0.99, green: 0.88, blue: 0.55))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(middleFishCaught) * barGrowProgress, suffix: " 個", color: Color(red: 0.612, green: 0.451, blue: 0.031))
                                                    Rectangle()
                                                        .fill(Color(red: 0.992, green: 0.827, blue: 0.427))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.612, green: 0.451, blue: 0.031))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.612, green: 0.451, blue: 0.031))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.612, green: 0.451, blue: 0.031))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("MiddleFishIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(8)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.98, green: 0.90, blue: 0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.949, green: 0.773, blue: 0.800), lineWidth: 3)
                                    )

                                GeometryReader { geo in
                                    let barWidth = max((geo.size.width - 32 - 16) / 2, 0)

                                    VStack(spacing: 0) {
                                        Spacer()
                                        HStack(alignment: .bottom, spacing: 16) {
                                            VStack(spacing: 4) {
                                                BarValueText(value: 0 * barGrowProgress, suffix: " 個", color: Color(red: 0.647, green: 0.298, blue: 0.376))
                                                    Rectangle()
                                                        .fill(Color(red: 0.99, green: 0.85, blue: 0.88))
                                                        .frame(width: barWidth, height: 60 * barGrowProgress)
                                            }
                                            VStack(spacing: 4) {
                                                BarValueText(value: Double(smallFishCaught) * barGrowProgress, suffix: " 個", color: Color(red: 0.647, green: 0.298, blue: 0.376))
                                                    Rectangle()
                                                        .fill(Color(red: 0.949, green: 0.773, blue: 0.800))
                                                        .frame(width: barWidth, height: 110 * barGrowProgress)
                                            }
                                        }
                                        Rectangle()
                                            .fill(Color(red: 0.647, green: 0.298, blue: 0.376))
                                            .frame(height: 2)
                                        HStack(spacing: 16) {
                                            Text("--")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.647, green: 0.298, blue: 0.376))
                                                .frame(width: barWidth)
                                            Text("本次")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(Color(red: 0.647, green: 0.298, blue: 0.376))
                                                .frame(width: barWidth)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }

                                Image("SmallFishIcon")
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
        }
        .onAppear {
            withAnimation(.easeOut(duration: 3)) {
                barGrowProgress = 1
            }
        }
    }
}

// MARK: - BarValueText

// 讓長條圖上方的數字隨著直方長高的動畫同步從 0 數到目標值：Animatable 讓 SwiftUI
// 在 withAnimation 期間對 value 做插值，body 每一幀都會用當下插值後的 value 重新渲染。
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
    PostWorking2(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 2,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 1500,
        totalReps: 12,
        totalElapsedSeconds: 245,
        bigFishCaught: 3,
        middleFishCaught: 5,
        smallFishCaught: 4
    )
}

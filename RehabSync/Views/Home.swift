import SwiftUI

struct Home: View {
    var body: some View {
        TabView {
            HomeContent()
                .tabItem { Label("主頁", systemImage: "house") }
            Statistic()
                .tabItem { Label("數據", systemImage: "chart.bar") }
            Setting()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

// MARK: - Home Content

struct HomeContent: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HomeHeader()
                    .padding(.horizontal, 24)
                GeometryReader { geo in
                    let spacing: CGFloat = 20
                    let hPad: CGFloat = 24
                    let usable = geo.size.width - hPad * 2 - spacing
                    HStack(alignment: .top, spacing: spacing) {
                        // 左欄 60%
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("治療計畫")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                                Spacer()
                                Button("查看全部 ›") {}
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                            }
                            TreatmentPlanCard()
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: usable * 0.6)
                        .frame(maxHeight: .infinity, alignment: .top)

                        // 右欄 40%
                        GeometryReader { rightGeo in
                            VStack(spacing: 16) {
                                HealthTipCard()
                                    .frame(height: (rightGeo.size.height - 16) * 0.6)
                                AssessmentEntryCard()
                                    .frame(height: (rightGeo.size.height - 16) * 0.4)
                            }
                        }
                        .frame(width: usable * 0.4)
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, hPad)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Header

struct HomeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("Rehab")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("Sync")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }
            Text("MOTION-SYNCHRONIZED NEUROMUSCULAR TRAINING SYSTEM")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .kerning(0.5)
        }
    }
}

// MARK: - Treatment Plan Card

struct TreatmentPlanCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.78, green: 0.88, blue: 0.95))
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("基本頸部訓練")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))

                HStack(spacing: 12) {
                    OutlineButton(title: "Start") {}
                    OutlineButton(title: "動作列表") {}
                    Spacer()
                    ProgressView(value: 0.28)
                        .tint(Color(red: 0.15, green: 0.6, blue: 0.55))
                        .frame(width: 100)
                    Text("28%")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Health Tip Card

struct HealthTipCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 漸層背景
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.38, blue: 0.88),
                    Color(red: 0.22, green: 0.30, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 粉色光暈
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.88, green: 0.45, blue: 0.55).opacity(0.65),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: 80, y: 40)

            // 內容
            VStack(alignment: .leading, spacing: 0) {
                // 標題列
                HStack(spacing: 8) {
                    Text("\u{201C}")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("今日健康提示")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                // 提示文字
                Text("定期伸展胸肌有助於預防圓肩姿勢，減輕頸部長期負擔。")
                    .font(.system(size: 18, weight: .bold))
                    .italic()
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // 右下引號
                HStack {
                    Spacer()
                    Text("\u{201D}")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                }

                // 底部分隔線 + footer
                Divider().background(.white.opacity(0.25))
                HStack(spacing: 6) {
                    Image(systemName: "diamond")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("查看全部提示")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Assessment Entry Card

struct AssessmentEntryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                Text("主觀量表")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            }
            Text("記錄今日訓練前的主觀感受")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
            Button("記錄今日評量") {}
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Shared Components

struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.white)
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }
}

#Preview {
    Home()
}

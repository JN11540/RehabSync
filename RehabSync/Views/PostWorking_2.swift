import SwiftUI
import Charts

struct PostWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalReps: Int
    let totalElapsedSeconds: Int
    let bigFishCaught: Int
    let middleFishCaught: Int
    let smallFishCaught: Int

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)
    fileprivate static let lightPurple = Color(red: 0.94, green: 0.92, blue: 0.99)
    fileprivate static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.99)
    fileprivate static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    fileprivate static let green = Color(red: 0.20, green: 0.70, blue: 0.45)
    fileprivate static let blue = Color(red: 0.25, green: 0.55, blue: 0.95)
    fileprivate static let orange = Color(red: 0.95, green: 0.65, blue: 0.20)
    fileprivate static let pink = Color(red: 0.90, green: 0.30, blue: 0.45)
    fileprivate static let teal = Color(red: 0.35, green: 0.80, blue: 0.75)
    fileprivate static let yellow = Color(red: 0.95, green: 0.75, blue: 0.30)

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        PostWorking2Header()
                        PostWorking2StatRow()

                        PostWorking2DonationOverviewCard()
                            .frame(maxHeight: .infinity)
                    }
                    .padding(28)
                    .frame(minHeight: geo.size.height)
                }
            }
            .background(Self.panelBackground)
        }
        .background(Color.white)
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct PostWorking2Header: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你好棒！")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 20))
                    .foregroundStyle(PostWorking_2.mutedText)
            }

            Spacer()
        }
    }
}

// MARK: - Stat Row

private struct PostWorking2Stat {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let change: String
    let isPositive: Bool
    let note: String
}

private struct PostWorking2StatRow: View {
    private let stats: [PostWorking2Stat] = [
        PostWorking2Stat(icon: "clock.fill", color: PostWorking_2.midPurple, label: "總時間", value: "10 分 00 秒", change: "", isPositive: true, note: ""),
        PostWorking2Stat(icon: "repeat.circle.fill", color: PostWorking_2.blue, label: "總次數", value: "30 次", change: "", isPositive: true, note: ""),
        PostWorking2Stat(icon: "figure.flexibility", color: PostWorking_2.green, label: "平均伸展時長", value: "4.5 秒", change: "", isPositive: true, note: "")
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(stats, id: \.label) { stat in
                PostWorking2StatCard(stat: stat)
            }
        }
    }
}

private struct PostWorking2StatCard: View {
    let stat: PostWorking2Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(stat.color.opacity(0.15))
                    Image(systemName: stat.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(stat.color)
                }
                .frame(width: 32, height: 32)
                Spacer()
            }
            Text(stat.label)
                .font(.system(size: 20))
                .foregroundStyle(PostWorking_2.mutedText)
            Text(stat.value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.black)

            if !stat.change.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: stat.isPositive ? "arrow.up" : "arrow.down")
                    Text(stat.change)
                    Text(stat.note)
                        .foregroundStyle(PostWorking_2.mutedText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stat.isPositive ? PostWorking_2.green : PostWorking_2.pink)
            } else if !stat.note.isEmpty {
                Text(stat.note)
                    .font(.system(size: 11))
                    .foregroundStyle(PostWorking_2.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Donation Overview (Bar Chart)

private struct PostWorking2AttemptDuration: Identifiable {
    let attempt: Int
    let seconds: Double
    var id: Int { attempt }
}

private enum PostWorking2Group: CaseIterable, Equatable {
    case first
    case second
    case third

    var label: String {
        switch self {
        case .first: "第一組"
        case .second: "第二組"
        case .third: "第三組"
        }
    }

    var totalTime: String {
        switch self {
        case .first: "3 分 00 秒"
        case .second: "2 分 45 秒"
        case .third: "3 分 20 秒"
        }
    }

    var totalCount: String {
        "10 次"
    }

    var averageDuration: String {
        switch self {
        case .first: "5.5 秒"
        case .second: "5.0 秒"
        case .third: "6.0 秒"
        }
    }

    var durations: [Double] {
        switch self {
        case .first: [5, 5, 5, 5, 5, 5, 5, 5, 5, 4]
        case .second: [5, 5, 4, 5, 6, 5, 4, 5, 5, 6]
        case .third: [6, 6, 7, 6, 5, 6, 7, 6, 6, 5]
        }
    }

    var data: [PostWorking2AttemptDuration] {
        durations.enumerated().map { index, seconds in
            PostWorking2AttemptDuration(attempt: index + 1, seconds: seconds)
        }
    }
}

private struct PostWorking2DonationOverviewCard: View {
    @State private var selectedGroup: PostWorking2Group = .first
    @State private var showRetentionDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                HStack(spacing: 16) {
                    ForEach(PostWorking2Group.allCases, id: \.label) { group in
                        Button {
                            selectedGroup = group
                        } label: {
                            Text(group.label)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(group == selectedGroup ? Color.white : PostWorking_2.mutedText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(group == selectedGroup ? PostWorking_2.darkPurple : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Button {
                    showRetentionDetail = true
                } label: {
                    Text("檢視")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PostWorking_2.mutedText)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text(selectedGroup.totalTime)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text(selectedGroup.totalCount)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("平均伸直時間")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text(selectedGroup.averageDuration)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                Chart(selectedGroup.data) { point in
                    BarMark(
                        x: .value("次數", point.attempt),
                        y: .value("單次伸直時間（秒）", point.seconds),
                        width: .fixed(22)
                    )
                    .foregroundStyle(PostWorking_2.darkPurple)
                    .cornerRadius(2)
                }
                .chartXScale(domain: 0.5...10.5)
                .chartYScale(domain: 0...7)
                .chartXAxis {
                    AxisMarks(values: Array(1...10)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                                    .font(.system(size: 16))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(0...7)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.system(size: 16))
                    }
                }
                .chartXAxisLabel(alignment: .center) {
                    Text("次數")
                        .font(.system(size: 18))
                }
                .chartYAxisLabel(position: .leading, alignment: .center) {
                    Text("單次伸直時間（秒）")
                        .font(.system(size: 18))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220, alignment: .leading)
                .offset(y: 25)
            }
            .padding(.trailing, 20)
            .frame(height: 300)
        }
        .padding(20)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        .fullScreenCover(isPresented: $showRetentionDetail) {
            PostWorking2RetentionDetailSheet()
        }
    }
}

// MARK: - Donor Retention Rate

private struct PostWorking2RetentionCard: View {
    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul"]
    private let values: [CGFloat] = [0.45, 0.55, 0.50, 0.65, 0.60, 0.75, 0.684]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Donor Retention Rate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                HStack(spacing: 4) {
                    Text("This Year")
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PostWorking_2.mutedText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("68.4%")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.black)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text("8.3% vs Last Year")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PostWorking_2.green)
            }

            PostWorking2LineChart(values: values)
                .frame(height: 100)

            HStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    Text(month)
                        .font(.system(size: 10))
                        .foregroundStyle(PostWorking_2.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 20) {
                PostWorking2RetentionStat(label: "New Donors", value: "532", change: "15.3%", isPositive: true)
                PostWorking2RetentionStat(label: "Returning Donors", value: "716", change: "11.2%", isPositive: true)
                PostWorking2RetentionStat(label: "Churned Donors", value: "232", change: "6.8%", isPositive: false)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

private struct PostWorking2RetentionStat: View {
    let label: String
    let value: String
    let change: String
    let isPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PostWorking_2.mutedText)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black)
            HStack(spacing: 3) {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                Text(change)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isPositive ? PostWorking_2.green : PostWorking_2.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PostWorking2LineChart: View {
    let values: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: stepX * CGFloat(index), y: geo.size.height * (1 - value))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(PostWorking_2.darkPurple, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PostWorking2RetentionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            PostWorking_2.panelBackground.ignoresSafeArea()

            PostWorking2RetentionCard()
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PostWorking_2.darkPurple)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }
}

#Preview {
    PostWorking_2(
        content: TreatmentContent(treatment_id: 1, exercise_id: 2, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil,
        totalCoins: 120,
        totalReps: 30,
        totalElapsedSeconds: 600,
        bigFishCaught: 5,
        middleFishCaught: 10,
        smallFishCaught: 15
    )
}

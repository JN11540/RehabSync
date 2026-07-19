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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    PostWorking2Header()
                    PostWorking2StatRow()

                    HStack(alignment: .top, spacing: 20) {
                        PostWorking2DonationOverviewCard()
                            .frame(maxWidth: .infinity)
                        PostWorking2DonationSourceCard()
                            .frame(width: 260)
                        PostWorking2RecentDonationsCard()
                            .frame(width: 260)
                    }

                    HStack(alignment: .top, spacing: 20) {
                        PostWorking2TopCampaignsCard()
                            .frame(maxWidth: .infinity)
                        PostWorking2RetentionCard()
                            .frame(maxWidth: .infinity)
                        PostWorking2QuickInsightsCard()
                            .frame(width: 260)
                    }
                }
                .padding(28)
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 14))
                    .foregroundStyle(PostWorking_2.mutedText)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text("May 1 - May 31, 2025")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.black.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08)))

                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.08)))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "bell.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.black.opacity(0.7))
                        )
                    Text("3")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(PostWorking_2.pink)
                        .clipShape(Circle())
                        .offset(x: 2, y: -2)
                }
            }
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
                .font(.system(size: 12))
                .foregroundStyle(PostWorking_2.mutedText)
            Text(stat.value)
                .font(.system(size: 20, weight: .bold))
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

private struct PostWorking2DonationOverviewCard: View {
    private let data: [PostWorking2AttemptDuration] = (1...10).map { attempt in
        PostWorking2AttemptDuration(attempt: attempt, seconds: attempt == 10 ? 4 : 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("第一組資訊")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                HStack(spacing: 4) {
                    Text("Monthly")
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PostWorking_2.mutedText)
            }

            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 12))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("3 分 00 秒")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 12))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("10 次")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("平均伸直時間")
                        .font(.system(size: 12))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("5.5 秒")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }

            Chart(data) { point in
                BarMark(
                    x: .value("次數", point.attempt),
                    y: .value("時間（秒）", point.seconds),
                    width: .fixed(22)
                )
                .foregroundStyle(PostWorking_2.darkPurple)
                .cornerRadius(2)
            }
            .chartXScale(domain: 1...10)
            .chartYScale(domain: 0...7)
            .chartXAxis {
                AxisMarks(values: Array(1...10)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0...7)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("次數", alignment: .center)
            .chartYAxisLabel("時間（秒）", position: .leading, alignment: .center)
            .frame(width: 463, height: 160, alignment: .leading)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Donations by Source (Donut Chart)

private struct PostWorking2DonationSourceCard: View {
    private struct Slice {
        let label: String
        let percent: Double
        let amount: String
        let color: Color
    }

    private let slices: [Slice] = [
        Slice(label: "Website", percent: 0.45, amount: "$5,775.39", color: PostWorking_2.darkPurple),
        Slice(label: "Mobile App", percent: 0.25, amount: "$3,025.32", color: PostWorking_2.teal),
        Slice(label: "Social Media", percent: 0.15, amount: "$1,925.13", color: PostWorking_2.orange),
        Slice(label: "Email Campaigns", percent: 0.10, amount: "$1,283.42", color: PostWorking_2.blue),
        Slice(label: "Other", percent: 0.05, amount: "$641.03", color: Color.black.opacity(0.2))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Donations by Source")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black)

            ZStack {
                PostWorking2Donut(slices: slices.map { ($0.percent, $0.color) })
                    .frame(width: 140, height: 140)
                VStack(spacing: 2) {
                    Text("Total")
                        .font(.system(size: 11))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("$12,834.19")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                    Text("100%")
                        .font(.system(size: 11))
                        .foregroundStyle(PostWorking_2.mutedText)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices, id: \.label) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.75))
                        Spacer()
                        Text("\(Int(slice.percent * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

private struct PostWorking2Donut: View {
    let slices: [(Double, Color)]

    private var segments: [(start: Double, end: Double, color: Color)] {
        var result: [(Double, Double, Color)] = []
        var cursor = 0.0
        for (percent, color) in slices {
            let end = cursor + percent
            result.append((cursor, end, color))
            cursor = end
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Recent Donations

private struct PostWorking2Donor {
    let name: String
    let time: String
    let amount: String
}

private struct PostWorking2RecentDonationsCard: View {
    private let donors: [PostWorking2Donor] = [
        PostWorking2Donor(name: "Sarah Williams", time: "2 mins ago", amount: "$100.00"),
        PostWorking2Donor(name: "Michael Brown", time: "10 mins ago", amount: "$250.00"),
        PostWorking2Donor(name: "Emily Davis", time: "25 mins ago", amount: "$75.00"),
        PostWorking2Donor(name: "James Wilson", time: "1 hour ago", amount: "$500.00"),
        PostWorking2Donor(name: "Olivia Martinez", time: "2 hours ago", amount: "$120.00")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Donations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                Text("View all")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PostWorking_2.darkPurple)
            }

            VStack(spacing: 14) {
                ForEach(donors, id: \.name) { donor in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(PostWorking_2.midPurple.opacity(0.2))
                            Text(donor.name.split(separator: " ").compactMap { $0.first }.map(String.init).joined())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(PostWorking_2.darkPurple)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(donor.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black)
                            Text(donor.time)
                                .font(.system(size: 11))
                                .foregroundStyle(PostWorking_2.mutedText)
                        }
                        Spacer()
                        Text(donor.amount)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PostWorking_2.green)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Top Campaigns

private struct PostWorking2Campaign {
    let name: String
    let raised: String
    let percent: Double
}

private struct PostWorking2TopCampaignsCard: View {
    private let campaigns: [PostWorking2Campaign] = [
        PostWorking2Campaign(name: "Clean Water Initiative", raised: "$4,250.00 raised", percent: 0.85),
        PostWorking2Campaign(name: "Education for All", raised: "$3,120.00 raised", percent: 0.62),
        PostWorking2Campaign(name: "Food for Families", raised: "$2,850.00 raised", percent: 0.71),
        PostWorking2Campaign(name: "Health & Wellness", raised: "$1,950.00 raised", percent: 0.49)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Top Campaigns")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                Text("View all")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PostWorking_2.darkPurple)
            }

            VStack(spacing: 16) {
                ForEach(campaigns, id: \.name) { campaign in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(PostWorking_2.lightPurple)
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "leaf.fill").foregroundStyle(PostWorking_2.darkPurple))

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(campaign.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black)
                                Spacer()
                                Text("\(Int(campaign.percent * 100))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PostWorking_2.darkPurple)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.black.opacity(0.06))
                                    Capsule().fill(PostWorking_2.darkPurple)
                                        .frame(width: geo.size.width * campaign.percent)
                                }
                            }
                            .frame(height: 6)
                            Text(campaign.raised)
                                .font(.system(size: 11))
                                .foregroundStyle(PostWorking_2.mutedText)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
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

// MARK: - Quick Insights

private struct PostWorking2Insight {
    let label: String
    let value: String
    let note: String
}

private struct PostWorking2QuickInsightsCard: View {
    private let insights: [PostWorking2Insight] = [
        PostWorking2Insight(label: "Lifetime Value (LTV)", value: "$325.50", note: "+12.7%"),
        PostWorking2Insight(label: "Highest Donation", value: "$2,500.00", note: "By John Doe"),
        PostWorking2Insight(label: "Most Active Donor", value: "Sarah Williams", note: "12 donations"),
        PostWorking2Insight(label: "Donor Countries", value: "24", note: "Across the world")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Insights")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black)

            VStack(spacing: 16) {
                ForEach(insights, id: \.label) { insight in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.label)
                                .font(.system(size: 11))
                                .foregroundStyle(PostWorking_2.mutedText)
                            Text(insight.value)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black)
                        }
                        Spacer()
                        Text(insight.note)
                            .font(.system(size: 11))
                            .foregroundStyle(PostWorking_2.mutedText)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
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

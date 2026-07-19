import SwiftUI

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
            PostWorking2Sidebar()
                .frame(width: 220)

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

// MARK: - Sidebar

private struct PostWorking2NavItem {
    let icon: String
    let title: String
    var badge: Int? = nil
}

private struct PostWorking2Sidebar: View {
    private let generalItems: [PostWorking2NavItem] = [
        PostWorking2NavItem(icon: "square.grid.2x2.fill", title: "Dashboard"),
        PostWorking2NavItem(icon: "megaphone.fill", title: "Campaigns"),
        PostWorking2NavItem(icon: "person.2.fill", title: "Donors"),
        PostWorking2NavItem(icon: "dollarsign.circle.fill", title: "Donations"),
        PostWorking2NavItem(icon: "handshake.fill", title: "Pledges"),
        PostWorking2NavItem(icon: "chart.bar.fill", title: "Reports"),
        PostWorking2NavItem(icon: "envelope.fill", title: "Messages", badge: 3)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(PostWorking_2.darkPurple)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("HOPEWAY")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                    Text("Making a difference,\ntogether.")
                        .font(.system(size: 10))
                        .foregroundStyle(PostWorking_2.mutedText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)

            VStack(spacing: 4) {
                ForEach(generalItems, id: \.title) { item in
                    PostWorking2SidebarRow(item: item, isSelected: item.title == "Dashboard")
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Upgrade to Pro")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PostWorking_2.darkPurple)
                Text("Unlock advanced reports, custom insights & more.")
                    .font(.system(size: 11))
                    .foregroundStyle(PostWorking_2.mutedText)
                Button {} label: {
                    Text("Upgrade Now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(PostWorking_2.darkPurple)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(PostWorking_2.lightPurple)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(PostWorking_2.midPurple)
                    Text("AJ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Andrew Johnson")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                    Text("Admin")
                        .font(.system(size: 11))
                        .foregroundStyle(PostWorking_2.mutedText)
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

private struct PostWorking2SidebarRow: View {
    let item: PostWorking2NavItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .frame(width: 18)
            Text(item.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            Spacer()
            if let badge = item.badge {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(PostWorking_2.pink)
                    .clipShape(Circle())
            }
        }
        .foregroundStyle(isSelected ? .white : Color.black.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? PostWorking_2.darkPurple : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Header

private struct PostWorking2Header: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back, Andrew!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("Here's what's happening with HopeWay today.")
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
        PostWorking2Stat(icon: "dollarsign.circle.fill", color: PostWorking_2.midPurple, label: "Total Donations", value: "$12,834.19", change: "18.2%", isPositive: true, note: "vs Apr 1 - Apr 30"),
        PostWorking2Stat(icon: "person.2.fill", color: PostWorking_2.blue, label: "Total Donors", value: "1,248", change: "14.7%", isPositive: true, note: "vs Apr 1 - Apr 30"),
        PostWorking2Stat(icon: "checkmark.seal.fill", color: PostWorking_2.green, label: "Donation Goal", value: "80%", change: "", isPositive: true, note: "$8,000 of $10,000"),
        PostWorking2Stat(icon: "person.badge.plus.fill", color: PostWorking_2.orange, label: "New Donors", value: "164", change: "22.1%", isPositive: true, note: "vs Apr 1 - Apr 30"),
        PostWorking2Stat(icon: "chart.line.uptrend.xyaxis", color: PostWorking_2.pink, label: "Avg. Donation", value: "$75.23", change: "2.4%", isPositive: false, note: "vs Apr 1 - Apr 30")
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
            } else {
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

private struct PostWorking2DonationOverviewCard: View {
    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private let income: [CGFloat] = [0.45, 0.55, 0.60, 0.50, 0.90, 0.65, 0.70, 0.60, 0.75, 0.68, 0.72, 0.80]
    private let expenses: [CGFloat] = [0.20, 0.25, 0.22, 0.18, 0.15, 0.20, 0.24, 0.19, 0.21, 0.23, 0.20, 0.22]
    private let chartHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Donation Overview")
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
                    Text("Income")
                        .font(.system(size: 12))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("$8,234.19")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("20.6% vs Apr 1 - Apr 30")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PostWorking_2.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expenses")
                        .font(.system(size: 12))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("$1,245.34")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("4.3% vs Apr 1 - Apr 30")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PostWorking_2.pink)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PostWorking_2.darkPurple)
                                .frame(width: 6, height: chartHeight * income[index])
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PostWorking_2.lightPurple)
                                .frame(width: 6, height: chartHeight * expenses[index])
                        }
                        Text(month)
                            .font(.system(size: 10))
                            .foregroundStyle(PostWorking_2.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight + 20)
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

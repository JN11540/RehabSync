import SwiftUI

// MARK: - Dashboard Palette

private enum DashboardPalette {
    static let indigo = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let indigoDark = Color(red: 0.22, green: 0.18, blue: 0.68)
    static let indigoFaint = Color(red: 0.93, green: 0.93, blue: 0.98)
    static let teal = Color(red: 0.38, green: 0.85, blue: 0.78)
    static let panelBackground = Color(red: 0.965, green: 0.965, blue: 0.99)
    static let cardBackground = Color(red: 0.98, green: 0.98, blue: 0.995)
    static let onlineDot = Color(red: 0.30, green: 0.78, blue: 0.62)
    static let offlineDot = Color(red: 0.75, green: 0.75, blue: 0.79)
    static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
}

// MARK: - Dashboard

struct Dashboard: View {
    @State private var selectedNav: DashboardNavItem = .overview
    @State private var selectedDay = 10
    var onNavigateToTest: () -> Void = {}
    var onNavigateToTest1: () -> Void = {}
    var onNavigateToSettings: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar(
                selectedNav: $selectedNav,
                onNavigateToTest: onNavigateToTest,
                onNavigateToTest1: onNavigateToTest1,
                onNavigateToSettings: onNavigateToSettings
            )
                .frame(width: 220)

            if selectedNav == .overview {
                DashboardOverviewContent()
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(Color.white)

                DashboardSchedulePanel(selectedDay: $selectedDay)
                    .frame(width: 380)
                    .background(DashboardPalette.panelBackground)
            } else {
                DashboardPlaceholderCard(title: selectedNav.title)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Sidebar Nav

private enum DashboardNavItem: CaseIterable {
    case overview, training, test, test1, importData, exportData, settings

    var title: String {
        switch self {
        case .overview: "總覽"
        case .training: "訓練"
        case .test: "測試"
        case .test1: "測試1"
        case .importData: "匯入"
        case .exportData: "匯出"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .training: "arrow.left.arrow.right"
        case .test: "wrench.and.screwdriver"
        case .test1: "wrench.and.screwdriver.fill"
        case .importData: "square.and.arrow.down"
        case .exportData: "square.and.arrow.up"
        case .settings: "gearshape.fill"
        }
    }
}

private struct DashboardSidebar: View {
    @Binding var selectedNav: DashboardNavItem
    var onNavigateToTest: () -> Void = {}
    var onNavigateToTest1: () -> Void = {}
    var onNavigateToSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text("Rehab")
                    .foregroundStyle(DashboardPalette.teal)
                Text("Sync")
                    .foregroundStyle(Color.black)
            }
            .font(.system(size: 30, weight: .bold))
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)

            DashboardSidebarSectionLabel(text: "一般")
            DashboardSidebarItem(item: .overview, selectedNav: $selectedNav)
            DashboardSidebarItem(item: .training, selectedNav: $selectedNav)
            DashboardSidebarItem(item: .test, selectedNav: $selectedNav, action: onNavigateToTest)
            DashboardSidebarItem(item: .test1, selectedNav: $selectedNav, action: onNavigateToTest1)

            DashboardSidebarSectionLabel(text: "工具")
                .padding(.top, 24)
            DashboardSidebarItem(item: .importData, selectedNav: $selectedNav)
            DashboardSidebarItem(item: .exportData, selectedNav: $selectedNav)

            Spacer()

            DashboardSidebarItem(item: .settings, selectedNav: $selectedNav, action: onNavigateToSettings)
                .padding(.bottom, 20)
        }
    }
}

private struct DashboardSidebarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(DashboardPalette.mutedText)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
    }
}

private struct DashboardSidebarItem: View {
    let item: DashboardNavItem
    @Binding var selectedNav: DashboardNavItem
    var action: (() -> Void)? = nil

    private var isSelected: Bool { selectedNav == item }

    var body: some View {
        Button {
            selectedNav = item
            action?()
        } label: {
            HStack(spacing: 20) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? DashboardPalette.indigo : Color.black.opacity(0.75))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? DashboardPalette.indigoFaint : Color.clear)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder Card

private struct DashboardPlaceholderCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Overview Content (center column)

private struct DashboardOverviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("總覽")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.black)
                Spacer()
                Image(systemName: "bell.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DashboardPalette.indigo)
            }

            HStack(alignment: .top, spacing: 20) {
                DeviceIllustrationCard()
                    .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    LegDeviceCard(legTitle: "左腿")
                    LegDeviceCard(legTitle: "右腿")
                }
                .frame(maxWidth: .infinity)
            }

            ActivityChartCard()
        }
    }
}

// MARK: - Device Illustration Card

private struct DeviceIllustrationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("裝置")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DashboardPalette.mutedText)
            }

            ZStack(alignment: .bottomTrailing) {
                Image("MuscleFigure")
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: 340)

                DashboardConnectionLegend()
                    .padding(16)
            }
        }
        .padding(20)
        .background(DashboardPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DashboardConnectionLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(DashboardPalette.onlineDot).frame(width: 8, height: 8)
                Text("已連線")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            HStack(spacing: 8) {
                Circle().fill(DashboardPalette.offlineDot).frame(width: 8, height: 8)
                Text("未連線")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: - Leg Device Card

private struct LegDeviceCard: View {
    let legTitle: String
    @State private var deviceVM = DeviceViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(legTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)

            DeviceStatusRow(title: "大腿：", isConnected: deviceVM.fetch(limb: 0) != nil)
            DeviceStatusRow(title: "小腿：", isConnected: deviceVM.fetch(limb: 1) != nil)
        }
        .padding(20)
        .background(DashboardPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DeviceStatusRow: View {
    let title: String
    var isConnected: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            DashboardSensorIcon()

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black)
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? DashboardPalette.onlineDot : DashboardPalette.offlineDot)
                        .frame(width: 7, height: 7)
                    Text(isConnected ? "已連線" : "未連線")
                        .font(.system(size: 13))
                        .foregroundStyle(DashboardPalette.mutedText)
                }
            }

            Spacer()

            Image(systemName: "wifi")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DashboardPalette.mutedText)
                .rotationEffect(.degrees(90))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DashboardSensorIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.black)
            .frame(width: 20, height: 34)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 10, height: 3)
                    .offset(y: -9)
            )
    }
}

// MARK: - Activity Chart Card

private struct ActivityChartCard: View {
    private let weekdays = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]
    /// 每天兩根長條的相對高度（0~1），僅作示意用途
    private let barHeights: [(teal: CGFloat, indigo: CGFloat)] = [
        (0.55, 0.85), (0.65, 0.45), (0.80, 0.60), (0.50, 0.90),
        (0.70, 0.55), (0.60, 0.75), (0.45, 0.65)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("活動數據")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(barHeights.enumerated()), id: \.offset) { _, heights in
                    HStack(alignment: .bottom, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DashboardPalette.teal)
                            .frame(width: 10, height: 90 * heights.teal)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DashboardPalette.indigo)
                            .frame(width: 10, height: 90 * heights.indigo)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)

            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 13))
                        .foregroundStyle(DashboardPalette.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(DashboardPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Schedule Panel (right column)

private struct DashboardAppointment {
    let icon: String
    let title: String
    let time: String
    let subtitle: String?

    init(icon: String, title: String, time: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.time = time
        self.subtitle = subtitle
    }
}

private struct DashboardSchedulePanel: View {
    @Binding var selectedDay: Int

    private let topAppointments: [DashboardAppointment] = [
        DashboardAppointment(icon: "🦷", title: "牙科門診", time: "09:00-11:00", subtitle: "Dr. Cameron Wülamcon"),
        DashboardAppointment(icon: "💪", title: "物理治療預約", time: "11:00-12:00", subtitle: "Dr. Kevin Djeens")
    ]

    private let todayAppointments: [DashboardAppointment] = [
        DashboardAppointment(icon: "🏃", title: "徒步康復訓練", time: "11:00 AM"),
        DashboardAppointment(icon: "👁️", title: "眼科檢查", time: "14:00 PM")
    ]

    private let upcomingAppointments: [DashboardAppointment] = [
        DashboardAppointment(icon: "❤️", title: "心率諮詢師", time: "12:00 AM"),
        DashboardAppointment(icon: "👨‍⚕️", title: "神經科回診", time: "16:00 PM")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color(red: 0.35, green: 0.85, blue: 0.90))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        )
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(DashboardPalette.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                DashboardCalendarCard(selectedDay: $selectedDay)

                HStack(spacing: 12) {
                    ForEach(topAppointments.indices, id: \.self) { index in
                        DashboardAppointmentChip(appointment: topAppointments[index], highlighted: index == 0)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("即將到來的預約")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black)

                    DashboardAppointmentSection(label: "當日", appointments: todayAppointments)
                    DashboardAppointmentSection(label: "近六", appointments: upcomingAppointments)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Calendar Card

private struct DashboardCalendarCard: View {
    @Binding var selectedDay: Int

    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
    /// 2021 年 10 月：(顯示的日期, 是否為當月)
    private let calendarRows: [[(day: Int, inMonth: Bool)]] = [
        [(26, false), (27, false), (28, false), (29, false), (30, false), (1, true), (2, true)],
        [(3, true), (4, true), (5, true), (6, true), (7, true), (8, true), (9, true)],
        [(10, true), (11, true), (12, true), (13, true), (14, true), (15, true), (16, true)],
        [(17, true), (18, true), (19, true), (20, true), (21, true), (22, true), (23, true)],
        [(24, true), (25, true), (26, true), (27, true), (28, true), (29, true), (30, true)],
        [(31, true), (1, false), (2, false), (3, false), (4, false), (5, false), (6, false)]
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("2021 年 10 月")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                Button {} label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DashboardPalette.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 10) {
                ForEach(calendarRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(calendarRows[rowIndex], id: \.day) { cell in
                            DashboardCalendarDayCell(
                                day: cell.day,
                                inMonth: cell.inMonth,
                                isSelected: cell.inMonth && cell.day == selectedDay
                            )
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                guard cell.inMonth else { return }
                                selectedDay = cell.day
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardCalendarDayCell: View {
    let day: Int
    let inMonth: Bool
    let isSelected: Bool

    var body: some View {
        Text("\(day)")
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(
                isSelected ? .white : (inMonth ? Color.black.opacity(0.85) : Color.black.opacity(0.25))
            )
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(isSelected ? DashboardPalette.indigo : Color.clear)
            )
    }
}

// MARK: - Appointment Chips

private struct DashboardAppointmentChip: View {
    let appointment: DashboardAppointment
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appointment.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(highlighted ? .white : Color.black)
                Spacer()
                Text(appointment.icon)
                    .font(.system(size: 18))
            }
            Text(appointment.time)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(highlighted ? .white.opacity(0.85) : DashboardPalette.mutedText)
            if let subtitle = appointment.subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(highlighted ? .white.opacity(0.7) : DashboardPalette.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? DashboardPalette.indigoDark : DashboardPalette.indigoFaint)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DashboardAppointmentSection: View {
    let label: String
    let appointments: [DashboardAppointment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DashboardPalette.mutedText)

            HStack(spacing: 12) {
                ForEach(appointments.indices, id: \.self) { index in
                    DashboardAppointmentTile(appointment: appointments[index])
                }
            }
        }
    }
}

private struct DashboardAppointmentTile: View {
    let appointment: DashboardAppointment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appointment.icon)
                .font(.system(size: 20))
            Text(appointment.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
            Text(appointment.time)
                .font(.system(size: 12))
                .foregroundStyle(DashboardPalette.mutedText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.indigoFaint)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    Dashboard()
}

import SwiftUI

// MARK: - Dashboard Palette

private enum DashboardPalette {
    static let indigo = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let indigoDark = Color(red: 0.22, green: 0.18, blue: 0.68)
    static let indigoFaint = Color(red: 0.93, green: 0.93, blue: 0.98)
    static let teal = Color(red: 0.38, green: 0.85, blue: 0.78)
    static let panelBackground = Color(red: 0.965, green: 0.965, blue: 0.99)
    static let cardBackground = Color(red: 0.98, green: 0.98, blue: 0.995)
    static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    static let chartGray = Color(red: 0.80, green: 0.81, blue: 0.86)
}

// MARK: - Dashboard

struct Dashboard: View {
    @State private var selectedNav: DashboardNavItem = .overview
    @State private var selectedDay = 10
    @State private var showDeviceListModal = false
    @State private var deviceListSide = 0
    @State private var deviceListLimb = 0
    @State private var deviceStatusTick = 0
    @Environment(BluetoothViewModel.self) private var btVM
    private let deviceVM = DeviceViewModel()
    var onNavigateToTest: () -> Void = {}
    var onNavigateToTest1: () -> Void = {}
    var onNavigateToSettings: () -> Void = {}

    private func openDeviceList(side: Int, limb: Int) {
        deviceListSide = side
        deviceListLimb = limb
        showDeviceListModal = true
    }

    /// 每 5 秒檢查已綁定的裝置是否仍偵測得到（存在於 btVM.connectedPeripherals），
    /// 偵測不到（裝置關機/斷線）就自動解除綁定，並用 deviceStatusTick 強制畫面重新讀取最新狀態。
    private func checkBoundDevicesReachable() {
        for side in 0...1 {
            for limb in 0...1 {
                guard let device = deviceVM.fetch(side: side, limb: limb),
                      let uuid = UUID(uuidString: device.device_uuid),
                      btVM.connectedPeripherals[uuid] == nil
                else { continue }
                deviceVM.delete(uuid: device.device_uuid)
            }
        }

        // 一腿裝一個裝置（左右各一，非同腿湊滿兩個）不是合法配對狀態，偵測到就兩個都解除綁定。
        let leftCount = (0...1).filter { deviceVM.fetch(side: 0, limb: $0) != nil }.count
        let rightCount = (0...1).filter { deviceVM.fetch(side: 1, limb: $0) != nil }.count
        if leftCount == 1 && rightCount == 1 {
            for limb in 0...1 {
                if let device = deviceVM.fetch(side: 0, limb: limb) { deviceVM.delete(uuid: device.device_uuid) }
                if let device = deviceVM.fetch(side: 1, limb: limb) { deviceVM.delete(uuid: device.device_uuid) }
            }
        }

        deviceStatusTick += 1
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                DashboardSidebar(
                    selectedNav: $selectedNav,
                    onNavigateToTest: onNavigateToTest,
                    onNavigateToTest1: onNavigateToTest1,
                    onNavigateToSettings: onNavigateToSettings
                )
                    .frame(width: 220)

                if selectedNav == .overview {
                    DashboardOverviewContent(onDeviceRowTap: openDeviceList)
                        .id(deviceStatusTick)
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

            if showDeviceListModal {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { showDeviceListModal = false }

                DashboardDeviceListModal(side: deviceListSide, limb: deviceListLimb, onClose: { showDeviceListModal = false })
                    .frame(width: 420, height: 520)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                checkBoundDevicesReachable()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
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
    var onDeviceRowTap: (Int, Int) -> Void = { _, _ in }

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

            DeviceOverviewCard(onDeviceRowTap: onDeviceRowTap)

            ActivityChartCard()
        }
    }
}

// MARK: - Device Overview Card

private struct DeviceOverviewCard: View {
    var onDeviceRowTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("裝置")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            DeviceIllustration(onRowTap: onDeviceRowTap)
                .frame(maxWidth: .infinity)
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

private struct DeviceIllustration: View {
    var onRowTap: (Int, Int) -> Void = { _, _ in }
    @State private var deviceVM = DeviceViewModel()

    private var leftThighConnected: Bool { deviceVM.fetch(side: 0, limb: 0) != nil }
    private var leftCalfConnected: Bool { deviceVM.fetch(side: 0, limb: 1) != nil }
    private var rightThighConnected: Bool { deviceVM.fetch(side: 1, limb: 0) != nil }
    private var rightCalfConnected: Bool { deviceVM.fetch(side: 1, limb: 1) != nil }

    /// 已連線的左腿裝置數（0~2），用來判斷目前是不是「正要裝第二個裝置」的狀態。
    private var leftConnectedCount: Int {
        (leftThighConnected ? 1 : 0) + (leftCalfConnected ? 1 : 0)
    }
    private var rightConnectedCount: Int {
        (rightThighConnected ? 1 : 0) + (rightCalfConnected ? 1 : 0)
    }

    /// 第一個裝置裝在左腿、右腿還沒開始裝時，鎖住右腿，強迫先把左腿裝滿；反之亦然。
    private var isLeftDisabled: Bool { rightConnectedCount == 1 && leftConnectedCount == 0 }
    private var isRightDisabled: Bool { leftConnectedCount == 1 && rightConnectedCount == 0 }

    /// 裝置最多接兩個，湊滿兩個之後，尚未連線的圓形都不可再點擊。
    private var isMaxDevicesReached: Bool { leftConnectedCount + rightConnectedCount >= 2 }

    private var isLeftThighDisabled: Bool { isLeftDisabled || (isMaxDevicesReached && !leftThighConnected) }
    private var isLeftCalfDisabled: Bool { isLeftDisabled || (isMaxDevicesReached && !leftCalfConnected) }
    private var isRightThighDisabled: Bool { isRightDisabled || (isMaxDevicesReached && !rightThighConnected) }
    private var isRightCalfDisabled: Bool { isRightDisabled || (isMaxDevicesReached && !rightCalfConnected) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("MuscleFigure")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                DashboardConnectionBadge(label: "左大腿", isConnected: leftThighConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowTap(0, 0) }
                    .allowsHitTesting(!isLeftThighDisabled)
                    .opacity(isLeftThighDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "左小腿", isConnected: leftCalfConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowTap(0, 1) }
                    .allowsHitTesting(!isLeftCalfDisabled)
                    .opacity(isLeftCalfDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.84)
                DashboardConnectionBadge(label: "右大腿", isConnected: rightThighConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowTap(1, 0) }
                    .allowsHitTesting(!isRightThighDisabled)
                    .opacity(isRightThighDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "右小腿", isConnected: rightCalfConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowTap(1, 1) }
                    .allowsHitTesting(!isRightCalfDisabled)
                    .opacity(isRightCalfDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.84)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }
}

private struct DashboardConnectionBadge: View {
    let label: String
    var isConnected: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black)

            Text(isConnected ? "已連線" : "未連線")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isConnected ? Color.white : Color.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 72)
                .background(isConnected ? DashboardPalette.teal : Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        }
    }
}

// MARK: - Activity Chart Card

private struct ActivityChartCard: View {
    private let weekdays = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]
    private let chartHeight: CGFloat = 90
    private let barHeight: CGFloat = 80
    private let shortBarHeight: CGFloat = 40
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 12
    private let barColor = DashboardPalette.chartGray

    /// 同一天 4 根柱子的總寬度，讓不同天之間的間距（barSpacing）跟同一天內柱子的間距一致。
    private var dayGroupWidth: CGFloat { 4 * barWidth + 3 * barSpacing }

    private var taipeiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        calendar.firstWeekday = 2 // 週一為一週的開始
        return calendar
    }

    /// 以台灣時區偵測今天所在的這週（週一~週日）日期。
    private var weekDates: [Date] {
        let calendar = taipeiCalendar
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=週日, 2=週一, ..., 7=週六
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func dateLabel(for date: Date) -> String {
        let calendar = taipeiCalendar
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活動數據")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(weekdays, id: \.self) { _ in
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(0..<4, id: \.self) { index in
                            Group {
                                if index == 2 {
                                    VStack(spacing: 3) {
                                        Capsule()
                                            .fill(barColor)
                                            .frame(width: barWidth, height: 15)
                                        Capsule()
                                            .fill(barColor)
                                            .frame(width: barWidth, height: 15)
                                    }
                                } else {
                                    Capsule()
                                        .fill(barColor)
                                        .frame(width: barWidth, height: (index == 1 || index == 3) ? shortBarHeight : barHeight)
                                }
                            }
                            .offset(y: index == 1 ? -30 : (index == 2 ? -20 : 0))
                        }
                    }
                    .frame(width: dayGroupWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: chartHeight)

            HStack(spacing: barSpacing) {
                ForEach(Array(zip(weekdays, weekDates).enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 2) {
                        Text(pair.0)
                            .font(.system(size: 16))
                            .foregroundStyle(DashboardPalette.mutedText)
                        Text(dateLabel(for: pair.1))
                            .font(.system(size: 12))
                            .foregroundStyle(DashboardPalette.mutedText)
                    }
                    .frame(width: dayGroupWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
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

// MARK: - Device List Modal

private struct DashboardDeviceListModal: View {
    let side: Int
    let limb: Int
    let onClose: () -> Void

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var selectedDevice: DiscoveredDevice? = nil
    private let deviceVM = DeviceViewModel()

    private func handleCancel() {
        if let selectedDevice {
            if btVM.connectedPeripherals[selectedDevice.id] != nil {
                btVM.disconnect(id: selectedDevice.id)
            } else {
                btVM.cancelPendingConnection()
            }
        }
        onClose()
    }

    private func handleConfirm() {
        if let selectedDevice {
            deviceVM.insert(uuid: selectedDevice.id.uuidString, name: selectedDevice.name, side: side, limb: limb)
        }
        onClose()
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("藍牙裝置")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.leading, 24)

                    Spacer()

                    Button(action: handleCancel) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                            Circle()
                                .stroke(DashboardPalette.indigo, lineWidth: 1.5)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(DashboardPalette.indigo)
                        }
                        .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if btVM.discoveredDevices.isEmpty {
                            Text("掃描中…")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(DashboardPalette.mutedText)
                                .padding(.top, 20)
                        } else {
                            ForEach(btVM.discoveredDevices) { device in
                                let isConnected = btVM.connectedPeripherals[device.id] != nil
                                let isConnecting = device.id == selectedDevice?.id && {
                                    if case .connecting = btVM.connectionState { return true }
                                    return false
                                }()

                                Button {
                                    selectedDevice = device
                                    btVM.connectDiscovered(device)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(isConnected ? .white : Color.black)
                                                .lineLimit(1)
                                            Text(device.id.uuidString)
                                                .font(.system(size: 11))
                                                .foregroundStyle(isConnected ? .white.opacity(0.8) : DashboardPalette.mutedText)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                        }
                                        Spacer()
                                        if isConnecting {
                                            ProgressView()
                                                .tint(isConnected ? .white : DashboardPalette.indigo)
                                        } else if isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        isConnected
                                            ? DashboardPalette.indigo
                                            : (device.id == selectedDevice?.id ? DashboardPalette.indigo.opacity(0.15) : DashboardPalette.indigoFaint)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 80)
                }
            }

            Button(action: handleConfirm) {
                ZStack {
                    Circle()
                        .fill(DashboardPalette.indigo)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(selectedDevice == nil)
            .opacity(selectedDevice == nil ? 0.4 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .onAppear { btVM.startScan() }
        .onDisappear { btVM.stopScan() }
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
        .environment(BluetoothViewModel())
}

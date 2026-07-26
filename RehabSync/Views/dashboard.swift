import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dashboard Palette

private enum DashboardPalette {
    static let indigo = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let indigoDark = Color(red: 0.22, green: 0.18, blue: 0.68)
    static let indigoFaint = Color(red: 0.93, green: 0.93, blue: 0.98)
    static let teal = Color(red: 0.38, green: 0.85, blue: 0.78)
    static let panelBackground = Color(red: 0.97, green: 0.96, blue: 0.995)
    static let cardBackground = Color(red: 0.97, green: 0.96, blue: 0.995)
    static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    static let chartGray = Color(red: 0.80, green: 0.81, blue: 0.86)
}

// MARK: - Taipei Week Helper

private func taipeiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    calendar.firstWeekday = 2 // 週一為一週的開始
    return calendar
}

/// 以台灣時區偵測今天所在的這週（週一~週日）日期，weekOffset 可往前/往後移動整週（-1 = 上週，1 = 下週）。
private func currentWeekDates(weekOffset: Int = 0) -> [Date] {
    let calendar = taipeiCalendar()
    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today) // 1=週日, 2=週一, ..., 7=週六
    let daysSinceMonday = (weekday + 5) % 7
    guard let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today),
          let targetMonday = calendar.date(byAdding: .day, value: weekOffset * 7, to: thisMonday)
    else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: targetMonday) }
}

// MARK: - Dashboard

struct Dashboard: View {
    @State private var selectedNav: DashboardNavItem = .overview
    @State private var weekOffset = 0
    @State private var selectedWeekdayIndex: Int = {
        let calendar = taipeiCalendar()
        let weekday = calendar.component(.weekday, from: Date()) // 1=週日, 2=週一, ..., 7=週六
        return (weekday + 5) % 7 // 轉成週一為 0 的索引
    }()
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

                    DashboardSchedulePanel(weekOffset: $weekOffset, selectedWeekdayIndex: $selectedWeekdayIndex)
                        .frame(width: 420)
                        .background(DashboardPalette.panelBackground)
                } else if selectedNav == .exportData {
                    DashboardExportFolderPanel()
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
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

// MARK: - Export Folder Panel（database-export-implementation-steps.md 階段 7）

/// 接住 UIDocumentPickerViewController 的選取結果，橋接回 SwiftUI；
/// 呼叫端要在選取完成前一直持有這個物件，picker 才不會在使用者選定資料夾前就被釋放掉。
private final class ExportFolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            onPick(url)
        }
    }
}

private struct DashboardExportFolderPanel: View {
    @State private var folderName: String? = nil
    @State private var pickerDelegate: ExportFolderPickerDelegate?

    private func topMostViewController(from base: UIViewController?) -> UIViewController? {
        if let presented = base?.presentedViewController {
            return topMostViewController(from: presented)
        }
        return base
    }

    private func presentFolderPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        let delegate = ExportFolderPickerDelegate { url in
            ExportDestinationStore.save(folderURL: url)
            folderName = url.lastPathComponent
            pickerDelegate = nil
        }
        pickerDelegate = delegate
        picker.delegate = delegate

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController,
           let topMost = topMostViewController(from: root) {
            topMost.present(picker, animated: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("匯出")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            if let folderName {
                Text("目前指定資料夾：\(folderName)")
                    .font(.system(size: 16))
                    .foregroundStyle(DashboardPalette.mutedText)
            } else {
                Text("請選擇一個資料夾，之後遊戲匯出的 JSON／CSV 會自動存到這裡。")
                    .font(.system(size: 16))
                    .foregroundStyle(DashboardPalette.mutedText)
            }

            Button(action: presentFolderPicker) {
                Text(folderName == nil ? "選擇資料夾" : "重新選擇")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DashboardPalette.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            folderName = ExportDestinationStore.resolveDesignatedFolder()?.lastPathComponent
        }
    }
}

// MARK: - Overview Content (center column)

private struct DashboardOverviewContent: View {
    var onDeviceRowTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("總覽")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.black)

            DeviceOverviewCard(onDeviceRowTap: onDeviceRowTap)

            ActivityChartCard()
        }
    }
}

// MARK: - Device Overview Card

private struct DeviceOverviewCard: View {
    var onDeviceRowTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
    @Environment(BluetoothViewModel.self) private var btVM

    /// 已連線裝置按壓超過兩秒才解除綁定，避免誤觸；解除時若還連著線也一併中斷藍牙連線。
    private func unbind(side: Int, limb: Int) {
        guard let device = deviceVM.fetch(side: side, limb: limb) else { return }
        if let uuid = UUID(uuidString: device.device_uuid) {
            btVM.disconnect(id: uuid)
        }
        deviceVM.delete(uuid: device.device_uuid)
    }

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
                    .onTapGesture { if !leftThighConnected { onRowTap(0, 0) } }
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 0, limb: 0) }
                    .allowsHitTesting(!isLeftThighDisabled)
                    .opacity(isLeftThighDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "左小腿", isConnected: leftCalfConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { if !leftCalfConnected { onRowTap(0, 1) } }
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 0, limb: 1) }
                    .allowsHitTesting(!isLeftCalfDisabled)
                    .opacity(isLeftCalfDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.84)
                DashboardConnectionBadge(label: "右大腿", isConnected: rightThighConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { if !rightThighConnected { onRowTap(1, 0) } }
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 1, limb: 0) }
                    .allowsHitTesting(!isRightThighDisabled)
                    .opacity(isRightThighDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "右小腿", isConnected: rightCalfConnected)
                    .contentShape(Rectangle())
                    .onTapGesture { if !rightCalfConnected { onRowTap(1, 1) } }
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 1, limb: 1) }
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

    private var weekDates: [Date] { currentWeekDates() }

    private func dateLabel(for date: Date) -> String {
        let calendar = taipeiCalendar()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            .offset(y: index == 1 ? -28 : (index == 2 ? -18 : 2))
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
                        Text(dateLabel(for: pair.1))
                            .font(.system(size: 16))
                            .foregroundStyle(DashboardPalette.mutedText)
                        Text(pair.0)
                            .font(.system(size: 16))
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
        releaseSelectedDevice()
        onClose()
    }

    /// 解除目前選取裝置的連線（已連上就斷線，還在連線中就取消），
    /// 供「關閉視窗」與「改點其他裝置」共用。
    private func releaseSelectedDevice() {
        guard let selectedDevice else { return }
        if btVM.connectedPeripherals[selectedDevice.id] != nil {
            btVM.disconnect(id: selectedDevice.id)
        } else {
            btVM.cancelPendingConnection()
        }
    }

    private func handleConfirm() {
        if let selectedDevice {
            deviceVM.insert(uuid: selectedDevice.id.uuidString, name: selectedDevice.name, side: side, limb: limb)
        }
        onClose()
    }

    private var isConnecting: Bool {
        if case .connecting = btVM.connectionState { return true }
        return false
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
                        .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                    .opacity(isConnecting ? 0.4 : 1)
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
                                    guard device.id != selectedDevice?.id else { return }
                                    releaseSelectedDevice()
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
                .frame(width: 50, height: 50)
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(selectedDevice == nil || isConnecting)
            .opacity(selectedDevice == nil || isConnecting ? 0.4 : 1)
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

private struct DashboardSchedulePanel: View {
    @Binding var weekOffset: Int
    @Binding var selectedWeekdayIndex: Int

    @State private var treatmentVM = TreatmentViewModel()
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var showTrainingDestination = false
    @State private var destinationContent: TreatmentContent? = nil
    @State private var destinationExercise: Exercise? = nil
    @State private var showExportFolderNotSetAlert = false

    /// 以 exercise_id 對應要跳轉的訓練前置頁面，之後新增其他動作的頁面時直接在這裡加一筆對應即可。
    private static let trainingMenuDestinations: [Int: (TreatmentContent, Exercise?, @escaping () -> Void) -> AnyView] = [
        2: { content, exercise, onReturnToDashboard in AnyView(PreWorking_2(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
        9: { content, exercise, onReturnToDashboard in AnyView(PreWorking_9(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
        12: { content, exercise, onReturnToDashboard in AnyView(PreWorking_12(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
        22: { content, exercise, onReturnToDashboard in AnyView(PreWorking_22(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) }
    ]

    /// 資料庫沒有治療計畫選擇 UI，比照 Test1 的作法，以第一個治療計畫代表「目前的訓練菜單」。
    private func loadTrainingMenu() {
        treatmentVM.fetchAll()
        if let treatmentId = treatmentVM.treatments.first?.id {
            contentVM.fetchAll(for: Int(treatmentId))
        }
        exerciseVM.fetchAll()
    }

    /// 週曆目前選取的日期（依 weekOffset 決定是哪一週，再依 selectedWeekdayIndex 取出那週的第幾天）。
    private var selectedDate: Date? {
        let dates = currentWeekDates(weekOffset: weekOffset)
        guard dates.indices.contains(selectedWeekdayIndex) else { return nil }
        return dates[selectedWeekdayIndex]
    }

    /// 只顯示週曆目前選取那天（台灣時區）的訓練菜單，點擊其他天／切換上下週就換成當天的菜單。
    private var selectedDayContents: [TreatmentContent] {
        guard let selectedDate else { return [] }
        let calendar = taipeiCalendar()
        let target = calendar.startOfDay(for: selectedDate)
        return contentVM.contents.filter {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.date))) == target
        }
    }

    /// 動作卡片只有在檢視「今天」時才能點擊，檢視其他天（過去/未來）點擊要沒有反應。
    private var isSelectedDayToday: Bool {
        guard let selectedDate else { return false }
        return taipeiCalendar().isDate(selectedDate, inSameDayAs: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DashboardCalendarCard(weekOffset: $weekOffset, selectedWeekdayIndex: $selectedWeekdayIndex)

            Text("訓練菜單")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if selectedDayContents.isEmpty {
                        Text("當天沒有安排任何訓練動作")
                            .font(.system(size: 16))
                            .foregroundStyle(DashboardPalette.mutedText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(selectedDayContents, id: \.self) { content in
                            let exercise = exerciseVM.fetch(by: content.exercise_id)
                            DashboardTrainingMenuRow(
                                content: content,
                                exercise: exercise,
                                isInteractive: isSelectedDayToday,
                                onTap: {
                                    guard Self.trainingMenuDestinations[content.exercise_id] != nil else { return }
                                    guard ExportDestinationStore.hasDesignatedFolder() else {
                                        showExportFolderNotSetAlert = true
                                        return
                                    }
                                    destinationContent = content
                                    destinationExercise = exercise
                                    showTrainingDestination = true
                                }
                            )
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(24)
        .onAppear { loadTrainingMenu() }
        .fullScreenCover(isPresented: $showTrainingDestination) {
            if let destinationContent,
               let build = Self.trainingMenuDestinations[destinationContent.exercise_id] {
                build(destinationContent, destinationExercise, { showTrainingDestination = false })
            }
        }
        .alert("尚未設定匯出資料夾", isPresented: $showExportFolderNotSetAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先到側邊欄「匯出」分頁設定指定資料夾，才能開始這個動作。")
        }
    }
}

private struct DashboardTrainingMenuRow: View {
    let content: TreatmentContent
    let exercise: Exercise?
    var isInteractive: Bool = true
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let id = exercise?.id {
                    Image("Exercise\(id)")
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(DashboardPalette.mutedText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipped()
            .background(DashboardPalette.indigoFaint)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise?.name ?? "未知動作")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Text("組數 \(content.sets) · 次數 \(content.reps) · 組間休息 \(content.set_rest_time) 秒")
                    .font(.system(size: 16))
                    .foregroundStyle(DashboardPalette.mutedText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .opacity(isInteractive ? 1 : 0.5)
        .allowsHitTesting(isInteractive)
    }
}

// MARK: - Calendar Card

private struct DashboardWeekColumn {
    let weekday: String
    let date: Int
}

private struct DashboardCalendarCard: View {
    @Binding var weekOffset: Int
    @Binding var selectedWeekdayIndex: Int

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    /// 以台灣時區偵測 weekOffset 所指定的那一週（週一~週日），跟活動數據卡片使用同一套週別邏輯。
    private var weekDates: [Date] { currentWeekDates(weekOffset: weekOffset) }

    private var columns: [DashboardWeekColumn] {
        let calendar = taipeiCalendar()
        return zip(Self.weekdayLabels, weekDates).map { weekday, date in
            DashboardWeekColumn(weekday: weekday, date: calendar.component(.day, from: date))
        }
    }

    private var monthTitle: String {
        let calendar = taipeiCalendar()
        guard let anchor = weekDates.first else { return "" }
        let year = calendar.component(.year, from: anchor)
        let month = calendar.component(.month, from: anchor)
        return "\(year) 年 \(month) 月"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(monthTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 75)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    DashboardWeekDayColumnView(column: column, isSelected: index == selectedWeekdayIndex)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedWeekdayIndex = index }
                }
            }
        }
    }
}

private struct DashboardWeekDayColumnView: View {
    let column: DashboardWeekColumn
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(column.weekday)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? .white : DashboardPalette.mutedText)
            Text("\(column.date)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.black.opacity(0.85))
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .background(
            Capsule().fill(isSelected ? DashboardPalette.indigo : Color.clear)
        )
    }
}

#Preview {
    Dashboard()
        .environment(BluetoothViewModel())
}

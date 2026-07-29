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
    static let activityLightPurple = Color(red: 0.80, green: 0.75, blue: 0.94)
    static let activityPurple = Color(red: 0.58, green: 0.46, blue: 0.86)
    static let activityDarkPurple = Color(red: 0.36, green: 0.24, blue: 0.62)
}

/// 以 exercise_id 對應要跳轉的訓練前置頁面，訓練菜單預覽卡（右側面板）跟「未完成動作」視窗共用同一份對照表，
/// 之後新增其他動作的頁面時直接在這裡加一筆對應即可。
private let dashboardTrainingMenuDestinations: [Int: (TreatmentContent, Exercise?, @escaping () -> Void) -> AnyView] = [
    2: { content, exercise, onReturnToDashboard in AnyView(PreWorking_2(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
    9: { content, exercise, onReturnToDashboard in AnyView(PreWorking_9(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
    12: { content, exercise, onReturnToDashboard in AnyView(PreWorking_12(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) },
    22: { content, exercise, onReturnToDashboard in AnyView(PreWorking_22(content: content, exercise: exercise, onReturnToDashboard: onReturnToDashboard)) }
]

// MARK: - Taipei Week Helper

private func taipeiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    calendar.firstWeekday = 2 // 週一為一週的開始
    return calendar
}

/// 今天在「週一為 0」索引下對應的星期幾（0=週一…6=週日），跟 `currentWeekDates` 共用同一套換算。
private func todayWeekdayIndex() -> Int {
    let calendar = taipeiCalendar()
    let weekday = calendar.component(.weekday, from: Date()) // 1=週日, 2=週一, ..., 7=週六
    return (weekday + 5) % 7
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
    @State private var selectedWeekdayIndex: Int = todayWeekdayIndex()
    @State private var showIncompleteActionsModal = false
    @State private var showBluetoothBindingModal = false
    @State private var deviceStatusTick = 0
    @Environment(BluetoothViewModel.self) private var btVM
    private let deviceVM = DeviceViewModel()
    var onNavigateToTest: () -> Void = {}
    var onNavigateToTest1: () -> Void = {}

    /// 每 5 秒檢查已綁定的裝置是否仍有連線（存在於 btVM.connectedPeripherals），
    /// 沒有連線（裝置關機/離開範圍/App 剛重開還沒重新連上）就嘗試背景重連，
    /// 不再自動解除綁定——裝置暫時連不到，下一個 5 秒週期會再重試，直到連上為止。
    /// 用 deviceStatusTick 強制畫面重新讀取最新狀態。
    private func checkBoundDevicesReachable() {
        #if DEBUG
        print("[RECONNECT-DIAG] checkBoundDevicesReachable 開始檢查")
        #endif
        for side in 0...1 {
            for limb in 0...1 {
                guard let device = deviceVM.fetch(side: side, limb: limb) else { continue }
                guard let uuid = UUID(uuidString: device.device_uuid) else {
                    #if DEBUG
                    print("[RECONNECT-DIAG] side=\(side) limb=\(limb) device_uuid 字串解析失敗：\(device.device_uuid)")
                    #endif
                    continue
                }
                guard btVM.connectedPeripherals[uuid] == nil else {
                    #if DEBUG
                    print("[RECONNECT-DIAG] side=\(side) limb=\(limb) 已經有連線，跳過")
                    #endif
                    continue
                }
                #if DEBUG
                print("[RECONNECT-DIAG] side=\(side) limb=\(limb) 有紀錄但沒連線，呼叫 attemptBackgroundReconnect uuid=\(uuid)")
                #endif
                btVM.attemptBackgroundReconnect(uuid: uuid)
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
                    onNavigateToTest1: onNavigateToTest1
                )
                    .frame(width: 220)

                if selectedNav == .overview {
                    DashboardOverviewContent()
                        .id(deviceStatusTick)
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background(Color.white)

                    DashboardSchedulePanel(
                        weekOffset: $weekOffset, selectedWeekdayIndex: $selectedWeekdayIndex,
                        onBellTap: { showIncompleteActionsModal = true }
                    )
                        .frame(width: 420)
                        .background(DashboardPalette.panelBackground)
                } else if selectedNav == .importData {
                    DashboardImportJSONPanel()
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                } else if selectedNav == .exportData {
                    DashboardExportFolderPanel()
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                } else if selectedNav == .settings {
                    DashboardSettingsPanel(onBluetoothBindingTap: { showBluetoothBindingModal = true })
                        .id(deviceStatusTick)
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

            if showIncompleteActionsModal {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                DashboardIncompleteActionsModal(onClose: { showIncompleteActionsModal = false })
                    .frame(width: 420, height: 520)
            }

            if showBluetoothBindingModal {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                DashboardBluetoothBindingModal(onClose: { showBluetoothBindingModal = false })
                    .frame(width: 640, height: 520)
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

            DashboardSidebarItem(item: .settings, selectedNav: $selectedNav)
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

// MARK: - Settings Panel

private struct DashboardSettingsPanel: View {
    let onBluetoothBindingTap: () -> Void

    @State private var deviceVM = DeviceViewModel()
    @Environment(BluetoothViewModel.self) private var btVM

    /// `device` 表已經有 2 筆紀錄（不論目前是否有實際連線）就不能再綁新裝置，
    /// 跟人形圖／藍芽裝置綁定視窗左欄「最多同時綁 2 顆」是同一條規則，共用 `DeviceBindingRules`。
    private var isMaxDevicesReached: Bool {
        DeviceBindingRules.snapshot(deviceVM: deviceVM, btVM: btVM).isMaxDevicesReached
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.black)

            Button(action: onBluetoothBindingTap) {
                Text("藍芽裝置綁定")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DashboardPalette.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isMaxDevicesReached)
            .opacity(isMaxDevicesReached ? 0.4 : 1)

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
        guard folderName == nil else { return }
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
                .font(.system(size: 26, weight: .semibold))
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
                Text("選擇資料夾")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(folderName == nil ? DashboardPalette.indigo : DashboardPalette.mutedText)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(folderName != nil)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            folderName = ExportDestinationStore.resolveDesignatedFolder()?.lastPathComponent
        }
    }
}

// MARK: - Import JSON Panel

/// 接住 UIDocumentPickerViewController 選取 JSON 檔案的結果，橋接回 SwiftUI；
/// 呼叫端要在選取完成前一直持有這個物件，picker 才不會在使用者選定檔案前就被釋放掉。
private final class ImportJSONPickerDelegate: NSObject, UIDocumentPickerDelegate {
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

private struct DashboardImportJSONPanel: View {
    @State private var vm = TreatmentViewModel()
    @State private var pickerDelegate: ImportJSONPickerDelegate?
    @State private var importSuccess = false
    @State private var importError: String?

    /// 用資料庫裡現有的 `Treatment` 判斷「之前是否已經上傳過 JSON」——`Treatment` 只有透過這裡的匯入，
    /// 或 Setting 頁「移除所有資料」才會清空，所以能直接拿來當作是否允許再次匯入的依據。
    private var hasExistingTreatment: Bool { !vm.treatments.isEmpty }

    private func topMostViewController(from base: UIViewController?) -> UIViewController? {
        if let presented = base?.presentedViewController {
            return topMostViewController(from: presented)
        }
        return base
    }

    private func presentFilePicker() {
        guard !hasExistingTreatment else { return }
        importSuccess = false
        importError = nil

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        let delegate = ImportJSONPickerDelegate { url in
            do {
                try vm.importTreatment(from: url)
                importSuccess = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    importSuccess = false
                }
            } catch {
                importError = error.localizedDescription
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    importError = nil
                }
            }
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
            Text("匯入")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.black)

            if hasExistingTreatment {
                Label("已經匯入過治療計畫，無法再次上傳 JSON。", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
            } else {
                Text("選擇一個 JSON 檔案匯入治療計畫。")
                    .font(.system(size: 16))
                    .foregroundStyle(DashboardPalette.mutedText)
            }

            Button(action: presentFilePicker) {
                Text("選擇檔案")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(hasExistingTreatment ? DashboardPalette.mutedText : DashboardPalette.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(hasExistingTreatment)

            if importSuccess {
                Label("匯入成功", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let importError {
                Label("匯入失敗：\(importError)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { vm.fetchAll() }
    }
}

// MARK: - Overview Content (center column)

private struct DashboardOverviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("總覽")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.black)

            DeviceOverviewCard()

            ActivityChartCard()
        }
    }
}

// MARK: - Device Overview Card

private struct DeviceOverviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("裝置")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            DeviceIllustration()
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

    var body: some View {
        let snapshot = DeviceBindingRules.snapshot(deviceVM: deviceVM, btVM: btVM)

        GeometryReader { geo in
            ZStack {
                Image("MuscleFigure")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                DashboardConnectionBadge(label: "左大腿", status: snapshot.leftThigh.status)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 0, limb: 0) }
                    .allowsHitTesting(!snapshot.leftThigh.isDisabled)
                    .opacity(snapshot.leftThigh.isDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "左小腿", status: snapshot.leftCalf.status)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 0, limb: 1) }
                    .allowsHitTesting(!snapshot.leftCalf.isDisabled)
                    .opacity(snapshot.leftCalf.isDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.84)
                DashboardConnectionBadge(label: "右大腿", status: snapshot.rightThigh.status)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 1, limb: 0) }
                    .allowsHitTesting(!snapshot.rightThigh.isDisabled)
                    .opacity(snapshot.rightThigh.isDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.54)
                DashboardConnectionBadge(label: "右小腿", status: snapshot.rightCalf.status)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) { unbind(side: 1, limb: 1) }
                    .allowsHitTesting(!snapshot.rightCalf.isDisabled)
                    .opacity(snapshot.rightCalf.isDisabled ? 0.4 : 1)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.84)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }
}

private struct DashboardConnectionBadge: View {
    let label: String
    var status: DeviceConnectionStatus = .unbound

    private var text: String {
        switch status {
        case .unbound: "未連線"
        case .reconnecting: "掃描中"
        case .connected: "已連線"
        }
    }

    private var textColor: Color {
        switch status {
        case .unbound: Color.black.opacity(0.7)
        case .reconnecting, .connected: Color.white
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .unbound: Color.white
        case .reconnecting: DashboardPalette.indigo
        case .connected: DashboardPalette.teal
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 72)
                .background(backgroundColor)
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

    private let resultVM = TreatmentResultViewModel()

    /// 同一天 4 根柱子的總寬度，讓不同天之間的間距（barSpacing）跟同一天內柱子的間距一致。
    private var dayGroupWidth: CGFloat { 4 * barWidth + 3 * barSpacing }

    private var weekDates: [Date] { currentWeekDates() }

    private func dateLabel(for date: Date) -> String {
        let calendar = taipeiCalendar()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    /// 查這一天（`date` 是當天零點）的 `treatment_result` 筆數，換算成對應的柱子顏色：
    /// 0 筆＝灰色、1 筆＝淺紫、2 筆＝紫、>=3 筆＝深紫。
    private func barColor(for date: Date) -> Color {
        let calendar = taipeiCalendar()
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DashboardPalette.chartGray
        }
        let from = Int(dayStart.timeIntervalSince1970 * 1000)
        let to = Int(dayEnd.timeIntervalSince1970 * 1000)
        let count = resultVM.count(from: from, to: to)

        switch count {
        case 0: return DashboardPalette.chartGray
        case 1: return DashboardPalette.activityLightPurple
        case 2: return DashboardPalette.activityPurple
        default: return DashboardPalette.activityDarkPurple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活動數據")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(weekDates.enumerated()), id: \.offset) { _, date in
                    let color = barColor(for: date)
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(0..<4, id: \.self) { index in
                            Group {
                                if index == 2 {
                                    VStack(spacing: 3) {
                                        Capsule()
                                            .fill(color)
                                            .frame(width: barWidth, height: 15)
                                        Capsule()
                                            .fill(color)
                                            .frame(width: barWidth, height: 15)
                                    }
                                } else {
                                    Capsule()
                                        .fill(color)
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


// MARK: - Bluetooth Binding Modal（settings-bluetooth-binding-plan.md）

/// 「設定」頁「藍芽裝置綁定」按鈕跳出的視窗：左欄「綁定部位」（4 個固定選項）＋右欄「藍牙裝置」
/// （目前掃描到的所有裝置）。現在是全 App 唯一的手動連線入口——人形圖（`DeviceIllustration`）
/// 原本點部位會跳出的單欄視窗（`DashboardDeviceListModal`）已經拿掉，改成完全依賴背景重連
/// （`BluetoothViewModel.attemptBackgroundReconnect`），見 settings-bluetooth-binding-plan.md 第 6 節。
/// 左欄的「最多 2 顆、同側優先」規則共用 `DeviceBindingRules`，跟人形圖是同一套。
private struct DashboardBluetoothBindingModal: View {
    let onClose: () -> Void

    @Environment(BluetoothViewModel.self) private var btVM
    @State private var deviceVM = DeviceViewModel()
    @State private var selectedLimb: (side: Int, limb: Int)?
    @State private var selectedDevice: DiscoveredDevice? = nil

    private static let limbs: [(side: Int, limb: Int, label: String)] = [
        (0, 0, "左大腿"), (0, 1, "左小腿"), (1, 0, "右大腿"), (1, 1, "右小腿"),
    ]

    private func handleCancel() {
        releaseSelectedDevice()
        onClose()
    }

    /// 解除目前選取裝置的連線（已連上就斷線，還在連線中就取消），供「關閉視窗」與「改點其他裝置」共用。
    private func releaseSelectedDevice() {
        guard let selectedDevice else { return }
        if btVM.connectedPeripherals[selectedDevice.id] != nil {
            btVM.disconnect(id: selectedDevice.id)
        } else {
            btVM.cancelPendingConnection()
        }
    }

    /// 確認＝寫進 `device` 表後直接關閉視窗，一次只能綁一個部位，要綁下一個部位得重新開視窗。
    private func handleConfirm() {
        if let selectedLimb, let selectedDevice {
            deviceVM.insert(uuid: selectedDevice.id.uuidString, name: selectedDevice.name, side: selectedLimb.side, limb: selectedLimb.limb)
        }
        onClose()
    }

    /// 已連線裝置按壓超過兩秒才解除綁定，避免誤觸；解除時若還連著線也一併中斷藍牙連線。
    private func unbind(side: Int, limb: Int) {
        guard let device = deviceVM.fetch(side: side, limb: limb) else { return }
        if let uuid = UUID(uuidString: device.device_uuid) {
            btVM.disconnect(id: uuid)
        }
        deviceVM.delete(uuid: device.device_uuid)
    }

    private func slotState(side: Int, limb: Int, snapshot: DeviceBindingRules.Snapshot) -> DeviceBindingRules.SlotState {
        switch (side, limb) {
        case (0, 0): return snapshot.leftThigh
        case (0, 1): return snapshot.leftCalf
        case (1, 0): return snapshot.rightThigh
        default: return snapshot.rightCalf
        }
    }

    private var isConnecting: Bool {
        if case .connecting = btVM.connectionState { return true }
        return false
    }

    var body: some View {
        let snapshot = DeviceBindingRules.snapshot(deviceVM: deviceVM, btVM: btVM)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)

            VStack(spacing: 0) {
                HStack {
                    Text("藍芽裝置綁定")
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
                .padding(.bottom, 16)

                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        ForEach(Self.limbs, id: \.label) { item in
                            let slot = slotState(side: item.side, limb: item.limb, snapshot: snapshot)
                            let boundDevice = slot.status.isBound ? deviceVM.fetch(side: item.side, limb: item.limb) : nil
                            let isSelected = selectedLimb?.side == item.side && selectedLimb?.limb == item.limb

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(slot.status.isBound || isSelected ? .white : Color.black)

                                if slot.status.isBound {
                                    Text(slot.status == .connected ? "已連線" : "掃描中")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.85))
                                    if let boundDevice {
                                        Text(boundDevice.device_name)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.85))
                                            .lineLimit(1)
                                        Text(boundDevice.device_uuid)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }
                                } else {
                                    Text("未連線")
                                        .font(.system(size: 12))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : DashboardPalette.mutedText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                slot.status.isBound
                                    ? DashboardPalette.indigo
                                    : (isSelected ? DashboardPalette.indigoDark : DashboardPalette.indigoFaint)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !slot.status.isBound { selectedLimb = (item.side, item.limb) }
                            }
                            .onLongPressGesture(minimumDuration: 2) {
                                unbind(side: item.side, limb: item.limb)
                            }
                            .allowsHitTesting(!slot.isDisabled)
                            .opacity(slot.isDisabled ? 0.4 : 1)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .frame(width: 200)

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 1)

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
                                    let isSelected = device.id == selectedDevice?.id
                                    let isThisConnecting = isSelected && isConnecting
                                    let isHighlighted = isConnected || isSelected

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
                                                    .foregroundStyle(isHighlighted ? .white : Color.black)
                                                    .lineLimit(1)
                                                Text(device.id.uuidString)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : DashboardPalette.mutedText)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.6)
                                            }
                                            Spacer()
                                            if isThisConnecting {
                                                ProgressView()
                                                    .tint(.white)
                                            } else if isConnected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            isConnected
                                                ? DashboardPalette.indigo
                                                : (isSelected ? DashboardPalette.indigoDark : DashboardPalette.indigoFaint)
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
                    .frame(maxWidth: .infinity)
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
            .disabled(selectedLimb == nil || selectedDevice == nil || isConnecting)
            .opacity(selectedLimb == nil || selectedDevice == nil || isConnecting ? 0.4 : 1)
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

// MARK: - Incomplete Actions Modal

/// 點鈴鐺跳出的視窗，420×520，跟其他 Dashboard 彈出視窗同樣的卡片樣式；
/// 列出「今天安排、但還沒做過任何一次」的動作，判斷邏輯跟鈴鐺是否震動（`allTodayContentsDone`）共用同一套規則。
private struct DashboardIncompleteActionsModal: View {
    let onClose: () -> Void

    @State private var treatmentVM = TreatmentViewModel()
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var showTrainingDestination = false
    @State private var destinationContent: TreatmentContent? = nil
    @State private var destinationExercise: Exercise? = nil
    @State private var showExportFolderNotSetAlert = false
    @State private var showBluetoothNotBoundAlert = false
    private let deviceVM = DeviceViewModel()

    private func loadData() {
        treatmentVM.fetchAll()
        if let treatmentId = treatmentVM.treatments.first?.id {
            contentVM.fetchAll(for: Int(treatmentId))
        }
        exerciseVM.fetchAll()
    }

    private var incompleteTodayContents: [TreatmentContent] {
        guard let treatmentId = treatmentVM.treatments.first?.id else { return [] }
        let calendar = taipeiCalendar()
        let today = calendar.startOfDay(for: Date())
        let todayContents = contentVM.contents.filter {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.date))) == today
        }
        let completedIds = resultVM.fetchCompletedContentIds(for: Int(treatmentId))
        return todayContents.filter { !completedIds.contains(Int($0.id ?? -1)) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("未完成動作")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.leading, 24)

                    Spacer()

                    Button(action: onClose) {
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
                    .padding(.trailing, 16)
                }
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if incompleteTodayContents.isEmpty {
                            Text("今天的動作都已完成")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(DashboardPalette.mutedText)
                                .padding(.top, 20)
                        } else {
                            ForEach(incompleteTodayContents, id: \.self) { content in
                                let exercise = exerciseVM.fetch(by: content.exercise_id)
                                DashboardTrainingMenuRow(
                                    content: content,
                                    exercise: exercise,
                                    isInteractive: true,
                                    onTap: {
                                        guard dashboardTrainingMenuDestinations[content.exercise_id] != nil else { return }
                                        guard deviceVM.boundDeviceCount() >= 2 else {
                                            showBluetoothNotBoundAlert = true
                                            return
                                        }
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
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .onAppear { loadData() }
        .fullScreenCover(isPresented: $showTrainingDestination) {
            if let destinationContent,
               let build = dashboardTrainingMenuDestinations[destinationContent.exercise_id] {
                build(destinationContent, destinationExercise, {
                    showTrainingDestination = false
                    onClose()
                })
            }
        }
        .alert("尚未設定匯出資料夾", isPresented: $showExportFolderNotSetAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先到側邊欄「匯出」分頁設定指定資料夾，才能開始這個動作。")
        }
        .alert("尚未綁定藍芽裝置", isPresented: $showBluetoothNotBoundAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先到「設定」頁綁定大腿／小腿藍芽裝置，才能開始這個動作。")
        }
    }
}

// MARK: - Schedule Panel (right column)

private struct DashboardSchedulePanel: View {
    @Binding var weekOffset: Int
    @Binding var selectedWeekdayIndex: Int
    var onBellTap: () -> Void = {}

    @State private var treatmentVM = TreatmentViewModel()
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var showTrainingDestination = false
    @State private var destinationContent: TreatmentContent? = nil
    @State private var destinationExercise: Exercise? = nil
    @State private var showExportFolderNotSetAlert = false
    @State private var showBluetoothNotBoundAlert = false
    @State private var bellShakeAngle: Double = 0
    private let deviceVM = DeviceViewModel()

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

    /// 鈴鐺永遠只看「真正的今天」，跟日曆目前選取檢視的那天（selectedDayContents／weekOffset／selectedWeekdayIndex）無關。
    private var todayContents: [TreatmentContent] {
        let calendar = taipeiCalendar()
        let today = calendar.startOfDay(for: Date())
        return contentVM.contents.filter {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.date))) == today
        }
    }

    /// 今天安排的動作是否全部至少做過一次（`treatment_result` 裡有對應的 `treatment_content_id`）；
    /// 今天沒有安排任何動作時視為「已完成」，鈴鐺不需要震動提醒。
    private var allTodayContentsDone: Bool {
        guard let treatmentId = treatmentVM.treatments.first?.id else { return true }
        let completedIds = resultVM.fetchCompletedContentIds(for: Int(treatmentId))
        return todayContents.allSatisfy { completedIds.contains(Int($0.id ?? -1)) }
    }

    private func updateBellShake() {
        if allTodayContentsDone {
            withAnimation(.easeInOut(duration: 0.2)) { bellShakeAngle = 0 }
        } else {
            withAnimation(.easeInOut(duration: 0.07).repeatForever(autoreverses: true)) {
                bellShakeAngle = 14
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "bell.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(DashboardPalette.indigo)
                .rotationEffect(.degrees(bellShakeAngle), anchor: .top)
                .contentShape(Rectangle())
                .onTapGesture { onBellTap() }
                .onAppear { updateBellShake() }
                .onChange(of: allTodayContentsDone) { _, _ in updateBellShake() }

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
                                    guard dashboardTrainingMenuDestinations[content.exercise_id] != nil else { return }
                                    guard deviceVM.boundDeviceCount() >= 2 else {
                                        showBluetoothNotBoundAlert = true
                                        return
                                    }
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
               let build = dashboardTrainingMenuDestinations[destinationContent.exercise_id] {
                build(destinationContent, destinationExercise, { showTrainingDestination = false })
            }
        }
        .alert("尚未設定匯出資料夾", isPresented: $showExportFolderNotSetAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先到側邊欄「匯出」分頁設定指定資料夾，才能開始這個動作。")
        }
        .alert("尚未綁定藍芽裝置", isPresented: $showBluetoothNotBoundAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("請先到「設定」頁綁定大腿／小腿藍芽裝置，才能開始這個動作。")
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
                Button {
                    weekOffset = 0
                    selectedWeekdayIndex = todayWeekdayIndex()
                } label: {
                    Text("今日")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DashboardPalette.indigo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().stroke(DashboardPalette.indigo, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
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

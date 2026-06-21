import SwiftUI
import CoreBluetooth

// MARK: - goHome Environment Key

private struct GoHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var goHome: () -> Void {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}

struct Home: View {
    @State private var btVM = BluetoothViewModel()

    var body: some View {
        TabView {
            HomeContent()
                .tabItem { Label("主頁", systemImage: "house") }
            Statistic()
                .tabItem { Label("數據", systemImage: "chart.bar") }
            TestPage(btVM: btVM)
                .tabItem { Label("測試", systemImage: "flask") }
            Setting()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .environment(btVM)
        .overlay {
            if btVM.isCleaningUp {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("正在刪除舊資料")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("請稍候，完成後自動關閉")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(32)
                .background(Color(red: 0.1, green: 0.25, blue: 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Home Content

struct HomeContent: View {
    @State private var vm = TreatmentViewModel()
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
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
                            TreatmentPlanSection(vm: vm)
                                .frame(width: usable * 0.6)
                                .frame(maxHeight: .infinity, alignment: .top)

                            // 右欄 40%
                            GeometryReader { rightGeo in
                                VStack(spacing: 16) {
                                    BluetoothDeviceCard()
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
            .onAppear { vm.fetchAll() }
            .navigationDestination(for: TreatmentContent.self) { content in
                PreWorking(content: content)
            }
            .navigationDestination(for: Treatment.self) { treatment in
                TreatmentView(treatment: treatment)
            }
        }
        .environment(\.goHome, { navPath = NavigationPath() })
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

// MARK: - Treatment Plan Section

struct TreatmentPlanSection: View {
    let vm: TreatmentViewModel

    var body: some View {
        let plans = vm.treatments

        if plans.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.gray.opacity(0.4))
                Text("目前沒有治療計畫")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        } else if plans.count == 1 {
            TreatmentPlanCard(treatment: plans[0])
                .frame(maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let cardHeight = geo.size.height
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(plans, id: \.id) { plan in
                            TreatmentPlanCard(treatment: plan)
                                .frame(height: cardHeight)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Treatment Plan Card

struct TreatmentPlanCard: View {
    let treatment: Treatment
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var contentVM = TreatmentContentViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var showCompletedAlert = false
    @State private var showBTAlert = false

    private var completedContentIds: Set<Int> {
        Set(resultVM.results.map { $0.treatment_content_id })
    }

    private var progress: Double {
        let total = contentVM.contents.count
        return total > 0 ? Double(completedContentIds.count) / Double(total) : 0
    }

    private var isAllCompleted: Bool {
        !contentVM.contents.isEmpty &&
        contentVM.contents.allSatisfy { completedContentIds.contains(Int($0.id ?? -1)) }
    }

    private var activeContent: TreatmentContent? {
        contentVM.contents
            .first { !completedContentIds.contains(Int($0.id ?? -1)) }
    }

    private var bothDevicesConnected: Bool {
        let dvm = DeviceViewModel()
        guard let thigh = dvm.fetch(limb: 0), let thighUUID = UUID(uuidString: thigh.device_uuid),
              let calf  = dvm.fetch(limb: 1), let calfUUID  = UUID(uuidString: calf.device_uuid)
        else { return false }
        return btVM.connectedPeripherals[thighUUID] != nil &&
               btVM.connectedPeripherals[calfUUID]  != nil
    }

    @ViewBuilder
    private var startLabel: some View {
        HStack(spacing: 6) {
            Text("開始")
            Image(systemName: "arrow.up.right")
        }
        .font(.system(size: 18, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.white)
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }

    private var startDate: String {
        let d = Date(timeIntervalSince1970: TimeInterval(treatment.start_time))
        let cal = Calendar.current
        return "\(cal.component(.year, from: d))年\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
    }

    private var endDate: String {
        let d = Date(timeIntervalSince1970: TimeInterval(treatment.end_time))
        let cal = Calendar.current
        return "\(cal.component(.year, from: d))年\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                Text("治療計畫")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.78, green: 0.88, blue: 0.95))
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("治療計畫名稱：\(treatment.name)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("治療計畫日期：\(startDate) ~ \(endDate)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            }

            HStack(spacing: 12) {
                if isAllCompleted {
                    Button { showCompletedAlert = true } label: { startLabel }
                        .alert("治療計畫已完成", isPresented: $showCompletedAlert) {
                            Button("確定", role: .cancel) {}
                        } message: {
                            Text("您已完成此治療計畫的所有訓練動作，恭喜您！")
                        }
                } else if let content = activeContent {
                    if bothDevicesConnected {
                        NavigationLink(value: content) { startLabel }
                    } else {
                        Button { showBTAlert = true } label: { startLabel }
                            .alert("請先連接藍芽裝置", isPresented: $showBTAlert) {
                                Button("確定", role: .cancel) {}
                            } message: {
                                Text("請確認大腿與小腿裝置皆已連線，再開始治療。")
                            }
                    }
                }
                NavigationLink(value: treatment) {
                    Text("動作列表")
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
                Spacer()
                ProgressView(value: progress)
                    .tint(Color(red: 0.15, green: 0.6, blue: 0.55))
                    .frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .onAppear {
            let tid = Int(treatment.id ?? 0)
            contentVM.fetchAll(for: tid)
            resultVM.fetchAll(for: tid)
        }
    }
}

// MARK: - Bluetooth Device Card

enum LimbSlot {
    case thigh, calf
}

struct BoundDevice: Identifiable {
    let id: UUID
    let name: String
}

struct BluetoothDeviceCard: View {
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var deviceVM = DeviceViewModel()
    @State private var showSheet = false
    @State private var connectingFor: LimbSlot = .thigh
    @State private var thighDevice: BoundDevice? = nil
    @State private var calfDevice: BoundDevice? = nil
    @State private var freshlyConnectedPeripheral: CBPeripheral? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.1, green: 0.25, blue: 0.4)
            VStack(alignment: .leading, spacing: 22) {
                // 標題列
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 25))
                        .foregroundStyle(.cyan)
                    Text("藍芽與裝置")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if thighDevice != nil || calfDevice != nil {
                        Button {
                            if let d = thighDevice {
                                deviceVM.delete(uuid: d.id.uuidString)
                                btVM.disconnect(id: d.id)
                                thighDevice = nil
                            }
                            if let d = calfDevice {
                                deviceVM.delete(uuid: d.id.uuidString)
                                btVM.disconnect(id: d.id)
                                calfDevice = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 大腿裝置
                LimbSlotRow(
                    label: "大腿裝置",
                    device: thighDevice,
                    isConnected: thighDevice.map { btVM.connectedPeripherals[$0.id] != nil } ?? false,
                    onAdd: {
                        connectingFor = .thigh
                        btVM.startScan()
                        showSheet = true
                    }
                )

                // 小腿裝置
                LimbSlotRow(
                    label: "小腿裝置",
                    device: calfDevice,
                    isConnected: calfDevice.map { btVM.connectedPeripherals[$0.id] != nil } ?? false,
                    addDisabled: thighDevice == nil,
                    onAdd: {
                        connectingFor = .calf
                        btVM.startScan()
                        showSheet = true
                    }
                )
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
        .onAppear {
            // 從 DB 還原綁定裝置
            if let d = deviceVM.fetch(limb: 0), let uuid = UUID(uuidString: d.device_uuid) {
                thighDevice = BoundDevice(id: uuid, name: d.device_name)
            }
            if let d = deviceVM.fetch(limb: 1), let uuid = UUID(uuidString: d.device_uuid) {
                calfDevice = BoundDevice(id: uuid, name: d.device_name)
            }

            btVM.onConnected = { peripheral in
                let limb = connectingFor == .thigh ? 0 : 1
                deviceVM.insert(
                    uuid: peripheral.identifier.uuidString,
                    name: peripheral.name ?? "未知裝置",
                    limb: limb
                )
                guard let d = deviceVM.fetch(limb: limb),
                      let uuid = UUID(uuidString: d.device_uuid) else { return }
                let device = BoundDevice(id: uuid, name: d.device_name)
                switch connectingFor {
                case .thigh: thighDevice = device
                case .calf:  calfDevice  = device
                }
                freshlyConnectedPeripheral = peripheral
            }
            btVM.onDisconnected = { _ in }
        }
        .sheet(isPresented: $showSheet, onDismiss: {
            btVM.stopScan()
            freshlyConnectedPeripheral = nil
        }) {
            AddDeviceSheet(
                vm: btVM,
                connectedPeripheral: $freshlyConnectedPeripheral,
                onCalibrationFailed: { peripheral in
                    deviceVM.delete(uuid: peripheral.identifier.uuidString)
                    btVM.disconnect(id: peripheral.identifier)
                    switch connectingFor {
                    case .thigh: thighDevice = nil
                    case .calf:  calfDevice  = nil
                    }
                }
            )
            .presentationDetents([.fraction(0.75)])
            .presentationCornerRadius(16)
            .interactiveDismissDisabled(freshlyConnectedPeripheral != nil)
        }
    }
}

struct LimbSlotRow: View {
    let label: String
    let device: BoundDevice?
    let isConnected: Bool
    var addDisabled: Bool = false
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            if let device {
                BoundDeviceRow(device: device, isConnected: isConnected)
            } else {
                AddDeviceTile(action: onAdd)
                    .disabled(addDisabled)
                    .opacity(addDisabled ? 0.35 : 1)
            }
        }
    }
}

struct BoundDeviceRow: View {
    let device: BoundDevice
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.right")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                Text(device.id.uuidString)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(isConnected ? "已連線" : "未連線")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AddDeviceTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white)
                Text("新增裝置")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Device Sheet

struct AddDeviceSheet: View {
    let vm: BluetoothViewModel
    @Binding var connectedPeripheral: CBPeripheral?
    let onCalibrationFailed: (CBPeripheral) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var calibrationPhase: CalibrationPhase = .idle
    @State private var countdown: Int = 5

    enum CalibrationPhase { case idle, ready, calibrating, success, failed }

    var body: some View {
        if let peripheral = connectedPeripheral {
            calibrationView(peripheral: peripheral)
        } else {
            scanningView()
        }
    }

    // MARK: Scanning

    @ViewBuilder
    private func scanningView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("新增裝置")
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Text("確定您的裝置已開啟且可供探索。在下面選取裝置以連線。")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Divider().padding(.vertical, 16)

            if vm.connectionState == .connecting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("連線中…")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            } else if vm.discoveredDevices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在掃描…")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.discoveredDevices) { device in
                            Button {
                                vm.connectDiscovered(device)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "dot.radiowaves.right")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name)
                                            .font(.system(size: 18))
                                            .foregroundStyle(.primary)
                                        Text(device.id.uuidString)
                                            .font(.system(size: 18))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.connectionState == .connecting)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            if case .failed(let reason) = vm.connectionState {
                Text("連線失敗：\(reason)")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            Spacer()

            Divider()
            HStack {
                Spacer()
                Button("取消") {
                    vm.cancelPendingConnection()
                    dismiss()
                }
                .font(.system(size: 18))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: Calibration

    @ViewBuilder
    private func calibrationView(peripheral: CBPeripheral) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("裝置校正")
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Divider().padding(.vertical, 16)

            Spacer()

            VStack(spacing: 24) {
                switch calibrationPhase {
                case .idle:
                    // 裝置平放桌上示意圖
                    VStack(spacing: 6) {
                        Image(systemName: "iphone.landscape")
                            .font(.system(size: 64))
                            .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 140, height: 4)
                    }
                    VStack(spacing: 10) {
                        Text("裝置配對成功")
                            .font(.system(size: 18, weight: .semibold))
                        Text("請將裝置放置於桌上平放，不要移動，再點擊「確定」。")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("確定") {
                        calibrationPhase = .ready
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 13)
                    .background(Color(red: 0.1, green: 0.25, blue: 0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                case .ready:
                    Image(systemName: "gyroscope")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    VStack(spacing: 10) {
                        Text("準備校正")
                            .font(.system(size: 18, weight: .semibold))
                        Text("裝置保持靜止，點擊「校正」開始 5 秒感測器校正。")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("校正") {
                        beginCalibration(peripheral: peripheral)
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 13)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                case .calibrating:
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                            .frame(width: 90, height: 90)
                        Text("\(countdown)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                    }
                    Text("校正中，請勿移動裝置…")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("校正成功！")
                        .font(.system(size: 20, weight: .semibold))

                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                    Text("校正失敗，已取消裝置綁定")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()
        }
        .onChange(of: vm.calibratingUUIDs) { _, newSet in
            guard calibrationPhase == .calibrating,
                  !newSet.contains(peripheral.identifier) else { return }
            finishCalibration(peripheral: peripheral)
        }
    }

    private func beginCalibration(peripheral: CBPeripheral) {
        calibrationPhase = .calibrating
        countdown = 5
        vm.startCalibration(peripheral: peripheral)
        Task {
            for i in stride(from: 5, through: 0, by: -1) {
                countdown = i
                if i > 0 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    private func finishCalibration(peripheral: CBPeripheral) {
        if vm.gyroBiases[peripheral.identifier] != nil {
            calibrationPhase = .success
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            }
        } else {
            calibrationPhase = .failed
            onCalibrationFailed(peripheral)
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        }
    }
}

// MARK: - Assessment Entry Card

struct AssessmentEntryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 25))
                    .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                Text("主觀量表")
                    .font(.system(size: 25, weight: .semibold))
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

import SwiftUI
import Combine

// MARK: - Preview Mode

private enum Test1PreviewMode {
    case none, training, device
}

// MARK: - Test1

struct Test1: View {
    private let mint = Color(red: 0.25, green: 0.85, blue: 0.75)
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var previewMode: Test1PreviewMode = .none
    @State private var showAddDeviceModal = false
    @State private var addDeviceLimb = 0
    @State private var selectedDate = Date()
    @State private var treatmentVM = TreatmentViewModel()
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var deviceVM = DeviceViewModel()
    @State private var thighDevice: Device? = nil
    @State private var calfDevice: Device? = nil

    private var todayContents: [TreatmentContent] {
        let day = Calendar.current.startOfDay(for: selectedDate)
        return contentVM.contents.filter {
            Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.date))) == day
        }
    }

    // 比照主頁（Home.swift）的完成判斷：treatment_content_id 是否已有 TreatmentResult 紀錄
    private var completedContentIds: Set<Int> {
        Set(resultVM.results.map { $0.treatment_content_id })
    }

    private func loadTrainingMenu() {
        treatmentVM.fetchAll()
        // Test1 沒有治療計畫選擇 UI，先以第一個治療計畫代表「目前的訓練菜單」
        if let treatmentId = treatmentVM.treatments.first?.id {
            contentVM.fetchAll(for: Int(treatmentId))
            resultVM.fetchAll(for: Int(treatmentId))
        }
        exerciseVM.fetchAll()
        previewMode = .training
    }

    private func showDeviceConnection() {
        previewMode = .device
        refreshDevices()
    }

    private func refreshDevices() {
        thighDevice = deviceVM.fetch(limb: 0)
        calfDevice = deviceVM.fetch(limb: 1)
    }

    private func openAddDevice(limb: Int) {
        addDeviceLimb = limb
        showAddDeviceModal = true
    }

    /// 每 5 秒檢查已綁定裝置是否仍偵測得到（存在於 btVM.connectedPeripherals），偵測不到就自動解除綁定。
    private func checkBoundDevicesReachable() {
        guard previewMode == .device, !showAddDeviceModal else { return }
        if let thighDevice, let uuid = UUID(uuidString: thighDevice.device_uuid),
           btVM.connectedPeripherals[uuid] == nil {
            deviceVM.delete(uuid: thighDevice.device_uuid)
        }
        if let calfDevice, let uuid = UUID(uuidString: calfDevice.device_uuid),
           btVM.connectedPeripherals[uuid] == nil {
            deviceVM.delete(uuid: calfDevice.device_uuid)
        }
        refreshDevices()
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            let hPad: CGFloat = 24
            let usable = geo.size.width - hPad * 2 - spacing

            ZStack {
                HStack(alignment: .top, spacing: spacing) {
                    Test1Sidebar(
                        mint: mint,
                        onDeviceConnectionTap: showDeviceConnection,
                        onTrainingMenuTap: loadTrainingMenu
                    )
                        .frame(width: usable * 0.35)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    Test1PreviewFrame(
                        mint: mint,
                        mode: previewMode,
                        contents: todayContents,
                        exercises: exerciseVM.exercises,
                        completedContentIds: completedContentIds,
                        selectedDate: $selectedDate,
                        thighDevice: thighDevice,
                        calfDevice: calfDevice,
                        onAddDeviceTap: openAddDevice
                    )
                    .frame(width: usable * 0.65)
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showAddDeviceModal {
                    Group {
                        if addDeviceLimb == 0 {
                            ThighAddDeviceModal(
                                mint: mint,
                                savedDevice: thighDevice,
                                onCancel: {
                                    showAddDeviceModal = false
                                    refreshDevices()
                                },
                                onConfirm: {
                                    showAddDeviceModal = false
                                    refreshDevices()
                                }
                            )
                        } else {
                            CalfAddDeviceModal(
                                mint: mint,
                                savedDevice: calfDevice,
                                onCancel: {
                                    showAddDeviceModal = false
                                    refreshDevices()
                                },
                                onConfirm: {
                                    showAddDeviceModal = false
                                    refreshDevices()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, hPad)
                    .padding(.vertical, 20)
                }
            }
        }
        .background {
            Image("Test1Preview")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .clipped()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            checkBoundDevicesReachable()
        }
    }
}

// MARK: - Sidebar

private struct Test1Sidebar: View {
    let mint: Color
    let onDeviceConnectionTap: () -> Void
    let onTrainingMenuTap: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Test1MenuTile(title: "掃描 QR code", mint: mint) {
                Image("PhoneQRIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .scaleEffect(2.8)
            }
            Button(action: onDeviceConnectionTap) {
                Test1MenuTile(title: "裝置連線", mint: mint) {
                    ZStack(alignment: .topTrailing) {
                        Image("KneePadIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                            .offset(x: 8, y: 0)
                    }
                    .scaleEffect(2.8)
                }
            }
            .buttonStyle(.plain)
            Button(action: onTrainingMenuTap) {
                Test1MenuTile(title: "訓練菜單", mint: mint) {
                    Image("MenuIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .scaleEffect(2.2)
                }
            }
            .buttonStyle(.plain)
            Test1MenuTile(title: "商店", mint: mint) {
                Image("StoreIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .scaleEffect(2.2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.75), radius: 16, y: 7)
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.black, lineWidth: 6)
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 18
                    )
                    .padding(3)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 6)
                    .padding(21)
            }
        )
    }
}

private struct Test1MenuTile<Icon: View>: View {
    let title: String
    let mint: Color
    @ViewBuilder var icon: () -> Icon

    init(title: String, mint: Color, @ViewBuilder icon: @escaping () -> Icon = { EmptyView() }) {
        self.title = title
        self.mint = mint
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .padding(.leading, 14)
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 30)
        .background {
            ZStack {
                mint
                HStack(spacing: 14) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 36, height: 200)
                        .rotationEffect(.degrees(20))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 20, height: 200)
                        .rotationEffect(.degrees(20))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview Frame

private struct Test1PreviewFrame: View {
    let mint: Color
    var mode: Test1PreviewMode = .none
    let contents: [TreatmentContent]
    let exercises: [Exercise]
    let completedContentIds: Set<Int>
    @Binding var selectedDate: Date
    var thighDevice: Device? = nil
    var calfDevice: Device? = nil
    var onAddDeviceTap: (Int) -> Void = { _ in }
    @State private var selectedContentId: Int64? = nil

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateString: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: selectedDate)
        let m = cal.component(.month, from: selectedDate)
        let d = cal.component(.day, from: selectedDate)
        return "\(y)年\(m)月\(d)日"
    }

    private func exerciseName(for content: TreatmentContent) -> String {
        exercises.first { $0.id == Int64(content.exercise_id) }?.name ?? "未知動作"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.95))

            VStack(spacing: 0) {
                if mode == .training {
                    HStack(spacing: 16) {
                        Button {
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                        } label: {
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Text(dateString)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)

                        Button {
                            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                        } label: {
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(180))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 48)
                }

                Group {
                    switch mode {
                    case .training:
                        if contents.isEmpty {
                            Text("當天沒有安排訓練動作")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            VStack(spacing: 12) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(contents, id: \.id) { content in
                                            TrainingCard(
                                                imageName: "Exercise\(content.exercise_id)",
                                                title: exerciseName(for: content),
                                                subtitle: "\(content.sets) 組 · \(content.reps) 次 · 休息 \(content.set_rest_time) 秒",
                                                mint: mint,
                                                isDone: completedContentIds.contains(Int(content.id ?? -1)),
                                                isSelectable: isToday,
                                                isSelected: isToday && selectedContentId == content.id
                                            )
                                            .frame(width: 220)
                                            .onTapGesture {
                                                guard isToday else { return }
                                                selectedContentId = content.id
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 40)
                                    .padding(.top, 40)
                                }

                                IconLegend()
                                    .padding(.top, 16)
                                    .padding(.bottom, 24)
                            }
                        }
                    case .device:
                        DeviceConnectionButtons(
                            mint: mint,
                            thighDevice: thighDevice,
                            calfDevice: calfDevice,
                            onAddDeviceTap: onAddDeviceTap
                        )
                    case .none:
                        VStack(spacing: 10) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("預覽區")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onChange(of: selectedDate) { _, _ in
            selectedContentId = nil
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.black, lineWidth: 6)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 25
                    )
                    .padding(3)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.black, lineWidth: 6)
                    .padding(28)
            }
        )
    }
}

// MARK: - Device Connection Buttons

private struct DeviceConnectionButtons: View {
    let mint: Color
    var thighDevice: Device? = nil
    var calfDevice: Device? = nil
    var onAddDeviceTap: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                DeviceImageCard(
                    imageName: thighDevice != nil ? "KneeThighConnectedIcon" : "KneeThighDisconnectedIcon",
                    title: "大腿裝置",
                    mint: mint,
                    isConnected: thighDevice != nil,
                    connectedInfo: thighDevice.map { "\($0.device_name) · \($0.device_uuid)" },
                    dimWhenDisconnected: false
                )
                .frame(width: 220)
                .contentShape(Rectangle())
                .onTapGesture { onAddDeviceTap(0) }
                DeviceImageCard(
                    imageName: calfDevice != nil ? "KneeCalfConnectedIcon" : "KneeCalfDisconnectedIcon",
                    title: "小腿裝置",
                    mint: mint,
                    isConnected: calfDevice != nil,
                    connectedInfo: calfDevice.map { "\($0.device_name) · \($0.device_uuid)" },
                    dimWhenDisconnected: false
                )
                .frame(width: 220)
                .contentShape(Rectangle())
                .onTapGesture { onAddDeviceTap(1) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }
}

// MARK: - Thigh / Calf Add Device Modals

/// 大腿裝置與小腿裝置各自獨立的新增裝置視窗，各自擁有獨立的 view identity，
/// 避免切換裝置部位時共用同一個 view instance 導致連線中的裝置被彼此的取消/確認操作誤動到。
private struct ThighAddDeviceModal: View {
    let mint: Color
    var savedDevice: Device? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        DeviceBindModal(
            mint: mint,
            limb: 0,
            limbTitle: "大腿裝置",
            connectedImageName: "KneeThighConnectedIcon",
            disconnectedImageName: "KneeThighDisconnectedIcon",
            savedDevice: savedDevice,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }
}

private struct CalfAddDeviceModal: View {
    let mint: Color
    var savedDevice: Device? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        DeviceBindModal(
            mint: mint,
            limb: 1,
            limbTitle: "小腿裝置",
            connectedImageName: "KneeCalfConnectedIcon",
            disconnectedImageName: "KneeCalfDisconnectedIcon",
            savedDevice: savedDevice,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }
}

// MARK: - Device Bind Modal (shared implementation)

private struct DeviceBindModal: View {
    let mint: Color
    let limb: Int
    let limbTitle: String
    let connectedImageName: String
    let disconnectedImageName: String
    var savedDevice: Device? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(BluetoothViewModel.self) private var btVM
    @State private var selectedDevice: DiscoveredDevice? = nil
    private let deviceVM = DeviceViewModel()

    private let darkGreen = Color(red: 0.15, green: 0.5, blue: 0.45)
    private let brightGreen = Color(red: 0.3, green: 0.8, blue: 0.78)

    private var isSelectedConnected: Bool {
        guard let selectedDevice else { return false }
        return btVM.connectedPeripherals[selectedDevice.id] != nil
    }

    private var hasSelectedInfo: Bool {
        (isSelectedConnected && selectedDevice != nil) || savedDevice != nil
    }

    private var previewImageName: String {
        hasSelectedInfo ? connectedImageName : disconnectedImageName
    }

    private var selectedConnectedInfo: String? {
        if isSelectedConnected, let selectedDevice {
            return "\(selectedDevice.name) · \(selectedDevice.id.uuidString)"
        }
        if let savedDevice {
            return "\(savedDevice.device_name) · \(savedDevice.device_uuid)"
        }
        return nil
    }

    private var connectingDeviceId: UUID? {
        guard let selectedDevice, case .connecting = btVM.connectionState else { return nil }
        return selectedDevice.id
    }

    private func handleCancel() {
        if let selectedDevice {
            if btVM.connectedPeripherals[selectedDevice.id] != nil {
                btVM.disconnect(id: selectedDevice.id)
            } else {
                btVM.cancelPendingConnection()
            }
            deviceVM.delete(uuid: selectedDevice.id.uuidString)
        }
        onCancel()
    }

    private func handleConfirm() {
        if let selectedDevice {
            deviceVM.insert(uuid: selectedDevice.id.uuidString, name: selectedDevice.name, limb: limb)
        }
        onConfirm()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color(white: 0.85))
                    Text("新增裝置")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
                .frame(height: 72)
                Rectangle()
                    .fill(Color(white: 0.3))
                    .frame(height: 8)
                    .offset(y: -10)

                HStack(alignment: .top, spacing: 16) {
                    DeviceScanColumn(
                        title: limbTitle,
                        devices: btVM.discoveredDevices,
                        darkGreen: darkGreen,
                        brightGreen: brightGreen,
                        connectingDeviceId: connectingDeviceId,
                        onSelect: { device in
                            selectedDevice = device
                            btVM.connectDiscovered(device)
                        }
                    )
                    .padding(.top, 24)

                    DeviceImageCard(
                        imageName: previewImageName,
                        title: limbTitle,
                        mint: mint,
                        isConnected: hasSelectedInfo,
                        connectedInfo: selectedConnectedInfo,
                        dimWhenDisconnected: false
                    )
                    .frame(width: 220)
                    .frame(maxWidth: .infinity)
                    .offset(y: -24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)

                Spacer()
            }

            Button(action: handleCancel) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                        .padding(4)
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 40, height: 40)
                .padding(16)
            }
            .buttonStyle(.plain)

            Button(action: handleConfirm) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 1.5)
                        .padding(4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 40, height: 40)
                .padding(16)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { btVM.startScan() }
        .onDisappear { btVM.stopScan() }
    }
}

// MARK: - Device Scan Column

/// 左側「大腿裝置」掃描結果清單：固定顯示高度為 5 個項目，超出時可用右側直式膠囊上下拖曳捲動。
private struct DeviceScanColumn: View {
    let title: String
    let devices: [DiscoveredDevice]
    let darkGreen: Color
    let brightGreen: Color
    var connectingDeviceId: UUID? = nil
    let onSelect: (DiscoveredDevice) -> Void

    @State private var scrollOffset: CGFloat = 0

    private let itemHeight: CGFloat = 60
    private let itemSpacing: CGFloat = 14
    private let visibleHeight: CGFloat = 356
    private let trackWidth: CGFloat = 20
    private let thumbMinHeight: CGFloat = 40

    private var contentHeight: CGFloat {
        guard !devices.isEmpty else { return visibleHeight }
        return CGFloat(devices.count) * itemHeight + CGFloat(devices.count - 1) * itemSpacing
    }
    private var maxScroll: CGFloat { max(contentHeight - visibleHeight, 0) }
    private var thumbHeight: CGFloat {
        guard contentHeight > visibleHeight else { return visibleHeight }
        return max(visibleHeight * visibleHeight / contentHeight, thumbMinHeight)
    }
    private var thumbTravel: CGFloat { max(visibleHeight - thumbHeight, 0) }
    private var thumbOffset: CGFloat {
        guard maxScroll > 0 else { return 0 }
        return (scrollOffset / maxScroll) * thumbTravel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: itemSpacing) {
                if devices.isEmpty {
                    Text("掃描中…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: itemHeight)
                } else {
                    ForEach(devices) { device in
                        let isSupported = device.name.hasPrefix("ZE1")
                        Button {
                            onSelect(device)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(darkGreen)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(brightGreen)
                                    .padding(3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)
                                    Text(device.id.uuidString)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(.black.opacity(0.6))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)

                                if device.id == connectingDeviceId {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.black)
                                    }
                                    .padding(.trailing, 14)
                                }
                            }
                            .frame(height: itemHeight)
                            .opacity(isSupported ? 1 : 0.4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSupported)
                    }
                }
            }
            .offset(y: -scrollOffset)
            .frame(height: visibleHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize()
                    .offset(y: -44)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(darkGreen)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.85))
                    .frame(width: 15, height: thumbHeight)
                    .offset(y: thumbOffset)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 8, height: max(thumbHeight - 20, 10))
                    .offset(y: thumbOffset + 10)
            }
            .frame(width: trackWidth, height: visibleHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard maxScroll > 0, thumbTravel > 0 else { return }
                        let newThumbOffset = min(max(0, value.location.y - thumbHeight / 2), thumbTravel)
                        scrollOffset = (newThumbOffset / thumbTravel) * maxScroll
                    }
            )
        }
    }
}

// MARK: - Device Image Card

private struct DeviceImageCard: View {
    let imageName: String
    let title: String
    let mint: Color
    var isConnected: Bool = false
    var connectedInfo: String? = nil
    var dimWhenDisconnected: Bool = true

    /// 以 knee_pads_thigh.png / knee_pads_calf.png 的原始尺寸（557 x 844）為圖片區域比例基準
    private static let referenceAspectRatio: CGFloat = 557.0 / 844.0
    private let darkGreen = Color(red: 0.15, green: 0.5, blue: 0.45)

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                }
                .aspectRatio(Self.referenceAspectRatio, contentMode: .fit)

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            mint
                            HStack(spacing: 14) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 46, height: 200)
                                    .rotationEffect(.degrees(20))
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 26, height: 200)
                                    .rotationEffect(.degrees(20))
                            }
                        }
                    }
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black, lineWidth: 4)
            )

            Text(isConnected ? (connectedInfo ?? "") : "--")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(darkGreen)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 4)
                )
        }
        .opacity(dimWhenDisconnected && !isConnected ? 0.5 : 1)
    }
}

// MARK: - Icon Legend

private struct IconLegend: View {
    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 6) {
                Image("FinishIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text("完成")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 6) {
                Image("UnfinishIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text("未完成")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Training Card

private struct TrainingCard: View {
    let imageName: String
    let title: String
    let subtitle: String
    let mint: Color
    var isDone: Bool = false
    var isSelectable: Bool = true
    var isSelected: Bool = false

    /// 統一以 terminal_knee_extension_nobg.png 的原始尺寸（1651 x 1886）為圖片區域比例基準
    private static let referenceAspectRatio: CGFloat = 1651.0 / 1886.0
    private let darkGreen = Color(red: 0.15, green: 0.5, blue: 0.45)

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        Color.black
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                    }
                    Image(isDone ? "FinishIcon" : "UnfinishIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .padding(6)
                }
                .aspectRatio(Self.referenceAspectRatio, contentMode: .fit)

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            mint
                            HStack(spacing: 14) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 46, height: 200)
                                    .rotationEffect(.degrees(20))
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 26, height: 200)
                                    .rotationEffect(.degrees(20))
                            }
                        }
                    }
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black, lineWidth: 4)
            )

            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(darkGreen)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 4)
                )
        }
        .opacity(isSelectable ? 1 : 0.4)
        .allowsHitTesting(isSelectable)
    }
}

#Preview {
    Test1()
        .environment(BluetoothViewModel())
}

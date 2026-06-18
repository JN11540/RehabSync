import SwiftUI

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
    @State private var contentVM = TreatmentContentViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var showCompletedAlert = false

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

    private var startDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.start_time))
            .formatted(.dateTime.year().month().day())
    }

    private var endDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.end_time))
            .formatted(.dateTime.year().month().day())
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
                Text(treatment.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("\(startDate) ～ \(endDate)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if isAllCompleted {
                    Button {
                        showCompletedAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Start")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    }
                    .alert("治療計畫已完成", isPresented: $showCompletedAlert) {
                        Button("確定", role: .cancel) {}
                    } message: {
                        Text("您已完成此治療計畫的所有訓練動作，恭喜您！")
                    }
                } else if let content = activeContent {
                    NavigationLink(value: content) {
                        HStack(spacing: 6) {
                            Text("Start")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    }
                }
                NavigationLink(value: treatment) {
                    Text("動作列表")
                        .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 16, weight: .medium))
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

struct BluetoothDeviceCard: View {
    @State private var btVM = BluetoothViewModel()
    @State private var showSheet = false

    private let pairedDevices: [(icon: String, name: String, status: String)] = [
        ("headphones",        "WF-C510",          "已連線"),
        ("computermouse",     "MX Anywhere 3S",   "已連線"),
        ("waveform.path.ecg", "ZE1RC0025290009",  "已配對"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.1, green: 0.25, blue: 0.4)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)
                    Text("藍芽與裝置")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pairedDevices, id: \.name) { device in
                            DeviceTile(icon: device.icon,
                                       name: device.name,
                                       status: device.status)
                        }
                        AddDeviceTile {
                            btVM.startScan()
                            showSheet = true
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showSheet, onDismiss: { btVM.stopScan() }) {
            AddDeviceSheet(vm: btVM)
                .presentationDetents([.medium])
                .presentationCornerRadius(16)
        }
    }
}

struct DeviceTile: View {
    let icon: String
    let name: String
    let status: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 80, height: 90)
        .padding(10)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AddDeviceTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
                Text("新增裝置")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 90)
            .padding(10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Device Sheet

struct AddDeviceSheet: View {
    let vm: BluetoothViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("新增裝置")
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Text("確定您的裝置已開啟且可供探索。在下面選取裝置以連線。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Divider().padding(.vertical, 16)

            if vm.discoveredDevices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在掃描…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.discoveredDevices) { device in
                            HStack(spacing: 14) {
                                Image(systemName: "dot.radiowaves.right")
                                    .foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.system(size: 15))
                                    Text("RSSI: \(device.rssi) dBm")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            Spacer()

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .font(.system(size: 15))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
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

import SwiftUI
import GRDB
import CoreBluetooth

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    private var anyConnected: Bool {
        !btVM.connectedPeripherals.isEmpty
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            VStack(spacing: 16) {
                // 共用按鈕列
                HStack(spacing: 12) {
                    Button("開始收集") { btVM.startRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(anyConnected && !btVM.isRecording ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!anyConnected || btVM.isRecording)

                    Button("停止收集") { btVM.stopRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(btVM.isRecording ? Color.red.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!btVM.isRecording)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // 裝置卡片
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 20) {
                        DeviceTestCard(btVM: btVM, limb: 0, label: "大腿裝置")
                        DeviceTestCard(btVM: btVM, limb: 1, label: "小腿裝置")
                    }
                    .padding(.horizontal, 24)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - DeviceTestCard

struct DeviceTestCard: View {
    let btVM: BluetoothViewModel
    let limb: Int
    let label: String

    @State private var device: Device? = nil
    @State private var accRows:  [Acc]  = []
    @State private var gyroRows: [Gyro] = []
    @State private var exgRows:  [Exg]  = []
    @State private var accObs:  AnyDatabaseCancellable? = nil
    @State private var gyroObs: AnyDatabaseCancellable? = nil
    @State private var exgObs:  AnyDatabaseCancellable? = nil

    private var peripheral: CBPeripheral? {
        guard let uuidStr = device?.device_uuid,
              let uuid = UUID(uuidString: uuidStr) else { return nil }
        return btVM.connectedPeripherals[uuid]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
                Text(label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(peripheral != nil ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(peripheral != nil ? "已連線" : "未連線")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, 14)

            Divider().background(.white.opacity(0.3)).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ACC
                    SensorSection(title: "ACC") {
                        if let r = accRows.first {
                            Text("X: \(r.x, specifier: "%.3f")  Y: \(r.y, specifier: "%.3f")  Z: \(r.z, specifier: "%.3f") mg")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(accRows) { r in
                            Text("\(r.timestamp)  \(r.x, specifier: "%.2f")  \(r.y, specifier: "%.2f")  \(r.z, specifier: "%.2f")")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    // GYRO
                    SensorSection(title: "GYRO") {
                        if let r = gyroRows.first {
                            Text("P: \(r.pitch, specifier: "%.3f")  R: \(r.roll, specifier: "%.3f")  Y: \(r.yaw, specifier: "%.3f") dps")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(gyroRows) { r in
                            Text("\(r.timestamp)  \(r.pitch, specifier: "%.2f")  \(r.roll, specifier: "%.2f")  \(r.yaw, specifier: "%.2f")")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    // EXG
                    SensorSection(title: "EXG") {
                        if let r = exgRows.first {
                            Text("Value: \(r.value)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(exgRows) { r in
                            Text("\(r.timestamp)  \(r.value)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.1, green: 0.25, blue: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
    }

    private func startObserving() {
        device = DeviceViewModel().fetch(limb: limb)
        guard let deviceId = device?.id else { return }
        let db = DatabaseManager.shared.dbQueue

        accObs = ValueObservation.tracking {
            try Acc.filter(Column("device_id") == deviceId)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { accRows = $0 })

        gyroObs = ValueObservation.tracking {
            try Gyro.filter(Column("device_id") == deviceId)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { gyroRows = $0 })

        exgObs = ValueObservation.tracking {
            try Exg.filter(Column("device_id") == deviceId)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { exgRows = $0 })
    }

    private func stopObserving() {
        accObs  = nil
        gyroObs = nil
        exgObs  = nil
    }
}

// MARK: - SensorSection

private struct SensorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(1)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

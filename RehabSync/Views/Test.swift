import SwiftUI
import GRDB
import CoreBluetooth
import UIKit

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    private var anyConnected: Bool {
        !btVM.connectedPeripherals.isEmpty
    }

    private var allCalibrated: Bool {
        btVM.connectedPeripherals.values.allSatisfy {
            btVM.gyroBiases[$0.identifier] != nil
        }
    }

    private var canExport: Bool {
        btVM.recordingStartTime != nil && btVM.recordingEndTime != nil
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
                        .background(anyConnected && !btVM.isRecording && allCalibrated
                            ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!anyConnected || btVM.isRecording || !allCalibrated)

                    Button("停止收集") { btVM.stopRecordingAll() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(btVM.isRecording ? Color.red.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!btVM.isRecording)

                    Button("匯出") { exportCSV() }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canExport ? Color.blue.opacity(0.85) : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!canExport)
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

    private func exportCSV() {
        guard let from = btVM.recordingStartTime,
              let to   = btVM.recordingEndTime else { return }

        let dvm = DeviceViewModel()
        let thighAcc  = dvm.fetchACC(deviceId: 0, from: from, to: to)
        let thighGyro = dvm.fetchGYRO(deviceId: 0, from: from, to: to)
        let calfAcc   = dvm.fetchACC(deviceId: 1, from: from, to: to)
        let calfGyro  = dvm.fetchGYRO(deviceId: 1, from: from, to: to)

        let count = min(thighAcc.count, thighGyro.count, calfAcc.count, calfGyro.count)
        guard count > 0 else { return }

        var lines = ["timestamp,thigh_ax,thigh_ay,thigh_az,thigh_pitch,thigh_roll,thigh_yaw,calf_ax,calf_ay,calf_az,calf_pitch,calf_roll,calf_yaw"]
        for i in 0..<count {
            let ts = thighAcc[i].timestamp
            let ta = thighAcc[i]; let tg = thighGyro[i]
            let ca = calfAcc[i];  let cg = calfGyro[i]
            lines.append("\(ts),\(ta.x),\(ta.y),\(ta.z),\(tg.pitch),\(tg.roll),\(tg.yaw),\(ca.x),\(ca.y),\(ca.z),\(cg.pitch),\(cg.roll),\(cg.yaw)")
        }

        let csv = lines.joined(separator: "\n")
        let filename = "rehabsync_\(from).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root  = scene.windows.first?.rootViewController {
            if let popover = av.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            root.present(av, animated: true)
        }
    }
}

// MARK: - DeviceTestCard

struct DeviceTestCard: View {
    let btVM: BluetoothViewModel
    let limb: Int
    let label: String

    @State private var device: Device? = nil
    @State private var accRows:    [Acc]  = []
    @State private var gyroRows:   [Gyro] = []
    @State private var exgCh0Rows: [Exg]  = []
    @State private var exgCh1Rows: [Exg]  = []
    @State private var accObs:    AnyDatabaseCancellable? = nil
    @State private var gyroObs:   AnyDatabaseCancellable? = nil
    @State private var exgCh0Obs: AnyDatabaseCancellable? = nil
    @State private var exgCh1Obs: AnyDatabaseCancellable? = nil

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
            .padding(.bottom, 10)

            // 校正列
            HStack(spacing: 12) {
                let pid          = peripheral?.identifier ?? UUID()
                let isCalibrating = btVM.calibratingUUIDs.contains(pid)
                let isCalibrated  = btVM.gyroBiases[pid] != nil

                Button(isCalibrating ? "校正中..." : (isCalibrated ? "重新校正" : "校正")) {
                    if let p = peripheral { btVM.startCalibration(peripheral: p) }
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isCalibrated ? Color.cyan.opacity(0.7) : Color.orange.opacity(0.75))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(peripheral == nil || isCalibrating || btVM.isRecording)

                if isCalibrated {
                    Text("✓ 已校正")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.cyan)
                } else if !isCalibrating && peripheral != nil {
                    Text("請先校正再收集")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            .padding(.bottom, 12)

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

                    // EXG Channel 0
                    SensorSection(title: "EXG CH0") {
                        if let r = exgCh0Rows.first {
                            Text("Value: \(r.value)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(exgCh0Rows) { r in
                            Text("\(r.timestamp)  \(r.value)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    // EXG Channel 1
                    SensorSection(title: "EXG CH1") {
                        if let r = exgCh1Rows.first {
                            Text("Value: \(r.value)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        ForEach(exgCh1Rows) { r in
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

        exgCh0Obs = ValueObservation.tracking {
            try Exg.filter(Column("device_id") == deviceId && Column("channel") == 0)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { exgCh0Rows = $0 })

        exgCh1Obs = ValueObservation.tracking {
            try Exg.filter(Column("device_id") == deviceId && Column("channel") == 1)
                .order(Column("id").desc).limit(20).fetchAll($0)
        }.start(in: db, onError: { _ in }, onChange: { exgCh1Rows = $0 })
    }

    private func stopObserving() {
        accObs    = nil
        gyroObs   = nil
        exgCh0Obs = nil
        exgCh1Obs = nil
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

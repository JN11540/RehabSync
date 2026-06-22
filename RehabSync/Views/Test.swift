import SwiftUI
import CoreBluetooth
import UIKit
import SceneKit

// MARK: - TestPage

struct TestPage: View {
    let btVM: BluetoothViewModel

    private var anyConnected: Bool {
        !btVM.connectedPeripherals.isEmpty
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
                        .background(anyConnected && !btVM.isRecording
                            ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
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
                HStack(spacing: 20) {
                    DeviceTestCard(btVM: btVM, limb: 0, label: "大腿裝置")
                    DeviceTestCard(btVM: btVM, limb: 1, label: "小腿裝置")
                }
                .padding(.horizontal, 24)

                // 3D 動作引導
                KneeExtensionView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 20)
        }
    }

    private func exportCSV() {
        guard let from = btVM.recordingStartTime,
              let to   = btVM.recordingEndTime else { return }

        let dvm = DeviceViewModel()
        var thighAcc  = dvm.fetchACC(deviceId: 0, from: from, to: to)
        var thighGyro = dvm.fetchGYRO(deviceId: 0, from: from, to: to)
        var calfAcc   = dvm.fetchACC(deviceId: 1, from: from, to: to)
        var calfGyro  = dvm.fetchGYRO(deviceId: 1, from: from, to: to)

        guard !thighAcc.isEmpty, !thighGyro.isEmpty,
              !calfAcc.isEmpty,  !calfGyro.isEmpty else { return }

        let windowStart = max(thighAcc.first!.timestamp, thighGyro.first!.timestamp,
                              calfAcc.first!.timestamp,  calfGyro.first!.timestamp)
        let windowEnd   = min(thighAcc.last!.timestamp,  thighGyro.last!.timestamp,
                              calfAcc.last!.timestamp,   calfGyro.last!.timestamp)

        guard windowStart <= windowEnd else { return }

        thighAcc  = thighAcc.filter  { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        thighGyro = thighGyro.filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        calfAcc   = calfAcc.filter   { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        calfGyro  = calfGyro.filter  { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }

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

    private var peripheral: CBPeripheral? {
        guard let uuidStr = device?.device_uuid,
              let uuid = UUID(uuidString: uuidStr) else { return nil }
        return btVM.connectedPeripherals[uuid]
    }

    var body: some View {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(red: 0.1, green: 0.25, blue: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
    }

    private func startObserving() {
        device = DeviceViewModel().fetch(limb: limb)
    }

    private func stopObserving() {}
}

// MARK: - 3D Model View

private struct KneeExtensionView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1)
        view.loops = true
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X

        guard let url = Bundle.main.url(forResource: "knee_extension", withExtension: "usdz") else {
            print("[3D] knee_extension.usdz not found in bundle")
            return view
        }
        do {
            let scene = try SCNScene(url: url, options: [.checkConsistency: false])

            // 將所有模型節點放入 pivot（避免 scale 影響 camera）
            let pivot = SCNNode()
            for child in scene.rootNode.childNodes {
                child.removeFromParentNode()
                pivot.addChildNode(child)
            }
            scene.rootNode.addChildNode(pivot)

            // 計算 bounding sphere 並縮放 pivot
            let (sphereCenter, radius) = pivot.boundingSphere
            let targetRadius: Float = 1.5
            let s: Float = radius > 0 ? targetRadius / Float(radius) : 1.0
            pivot.scale = SCNVector3(s, s, s)

            // 模型世界中心（pivot 已縮放）
            let worldCenter = SCNVector3(
                Float(sphereCenter.x) * s,
                Float(sphereCenter.y) * s,
                Float(sphereCenter.z) * s
            )

            // 攝影機加入 rootNode（不受 pivot scale 影響）
            let camera = SCNCamera()
            camera.zNear = 0.01
            camera.zFar = 10000
            camera.fieldOfView = 45
            let camNode = SCNNode()
            camNode.camera = camera
            camNode.position = SCNVector3(worldCenter.x, worldCenter.y, worldCenter.z + targetRadius * 3.0)
            let lookAt = SCNLookAtConstraint(target: pivot)
            lookAt.isGimbalLockEnabled = true
            camNode.constraints = [lookAt]
            scene.rootNode.addChildNode(camNode)

            view.scene = scene
            view.pointOfView = camNode
        } catch {
            print("[3D] SCNScene load error: \(error)")
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}


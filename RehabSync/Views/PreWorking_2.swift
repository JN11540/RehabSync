import SwiftUI

struct PreWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    @Environment(\.dismiss) private var dismiss

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 24) {
                PreWorking2EquipmentPanel()
                    .frame(maxWidth: .infinity)

                PreWorking2AboutPanel()
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Self.midPurple)
                    .frame(width: 50, height: 50)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
            .offset(x: 10, y: 10)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Equipment Check Panel

private struct PreWorking2EquipmentPanel: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.80, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            PreWorking2CloudDecoration()

            VStack(spacing: 40) {
                PreWorking2EquipmentItem(label: "裝置連線了嗎？") {
                    BluetoothIcon()
                        .stroke(PreWorking_2.midPurple, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 60, height: 88)
                }
                PreWorking2EquipmentItem(label: "護膝穿戴了嗎？") {
                    Image("WearPadAndGearsIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PreWorking2CloudDecoration: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 140, height: 140)
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.12)
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .position(x: geo.size.width * 0.75, y: geo.size.height * 0.18)
                Image(systemName: "sparkle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .position(x: geo.size.width * 0.9, y: geo.size.height * 0.35)
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .position(x: geo.size.width * 0.1, y: geo.size.height * 0.45)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .allowsHitTesting(false)
    }
}

private struct PreWorking2EquipmentItem<Icon: View>: View {
    let label: String
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.white)
                .frame(width: 200, height: 200)
                .overlay { icon() }
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.75, green: 0.68, blue: 0.95), lineWidth: 3))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Text(label)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(PreWorking_2.darkPurple)
        }
    }
}

extension PreWorking2EquipmentItem where Icon == EmptyView {
    init(label: String) {
        self.label = label
        self.icon = { EmptyView() }
    }
}

/// 藍牙標誌（SF Symbols 沒有官方藍牙圖示，改用路徑手繪經典的藍牙符文外形）。
private struct BluetoothIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.24))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.38))
        path.closeSubpath()
        return path
    }
}

// MARK: - About Us Panel

private struct PreWorking2AboutPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 8) {
                Text("確認裝備齊全")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)
                Image(systemName: "sparkle")
                    .font(.system(size: 25))
                    .foregroundStyle(Color(red: 0.7, green: 0.62, blue: 0.95))
            }

            HStack(alignment: .center, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_2.midPurple)
                    .frame(width: 4, height: 24)
                Text("請確認是否都已準備就緒")
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
            }

            Button {} label: {
                HStack(spacing: 8) {
                    Text("下一步")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(PreWorking_2.darkPurple)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color(red: 0.90, green: 0.87, blue: 0.98))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(40)
    }
}

#Preview {
    PreWorking_2(
        content: TreatmentContent(treatment_id: 1, exercise_id: 2, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil
    )
}

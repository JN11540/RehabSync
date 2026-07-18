import SwiftUI

/// 訓練前的準備流程，依序為：確認裝備 → 準備椅子 → 放置平板 → 成果數據頁。
private enum PreWorkingStep: Equatable {
    case equipment
    case chair
    case tablet
    case numbers

    var title: String {
        switch self {
        case .equipment: "確認裝備齊全"
        case .chair: "準備椅子"
        case .tablet: "放置平板"
        case .numbers: ""
        }
    }

    var subtitle: String {
        switch self {
        case .equipment: "請確認是否都已準備就緒"
        case .chair: "請先找一張高度剛好到您膝蓋的椅子"
        case .tablet: "請將平板放置於桌面上"
        case .numbers: ""
        }
    }

    var next: PreWorkingStep? {
        switch self {
        case .equipment: .chair
        case .chair: .tablet
        case .tablet: .numbers
        case .numbers: nil
        }
    }
}

struct PreWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    @Environment(\.dismiss) private var dismiss
    @State private var step: PreWorkingStep = .equipment

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if step == .numbers {
                    PreWorking2ImpactPage()
                } else {
                    HStack(spacing: 24) {
                        PreWorking2EquipmentPanel(step: step)
                            .frame(maxWidth: .infinity)

                        PreWorking2AboutPanel(title: step.title, subtitle: step.subtitle) {
                            if let next = step.next { step = next }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
            .offset(x: 20, y: 20)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Equipment Check Panel

private struct PreWorking2EquipmentPanel: View {
    let step: PreWorkingStep

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

            switch step {
            case .equipment:
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
            case .chair:
                Image("ChairIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 500)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .tablet:
                Image("TabletDeskIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 500)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .numbers:
                EmptyView()
            }
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
    let title: String
    let subtitle: String
    var onNext: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 8) {
                Text(title)
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
                Text(subtitle)
                    .font(.system(size: 25))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
            }

            Button(action: onNext) {
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

// MARK: - Impact / Numbers Page

private struct PreWorking2ImpactPage: View {
    private enum PoseAngle {
        case side
        case front
    }

    @State private var side: Int = 0
    @State private var selectedAngle: PoseAngle = .side

    /// side = 0（左，含資料庫查無資料時的預設值）或 1（右），對應到匯入的示範圖 asset 名稱。
    private var sideViewImageName: String {
        side == 1 ? "Exercise2SideViewReadyRight" : "Exercise2SideViewReadyLeft"
    }

    private var frontViewImageName: String {
        side == 1 ? "Exercise2FrontViewReadyRight" : "Exercise2FrontViewReadyLeft"
    }

    private var mainImageName: String {
        switch selectedAngle {
        case .side: sideViewImageName
        case .front: frontViewImageName
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                Text("動作逐步指南\n1. 準備姿勢")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)
                    .lineSpacing(6)

                Text("Lorem ipsum dolor sit amet consectetur condimentum aliquet auctor diam vulputate est ullamcorper tincidunt arcu orci et elit.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineSpacing(6)
                    .frame(maxWidth: 320, alignment: .leading)

                Button {} label: {
                    HStack(spacing: 12) {
                        Text("SUPPORT OUR CAUSE")
                            .font(.system(size: 14, weight: .bold))
                        ZStack {
                            Circle().fill(Color.white.opacity(0.2))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(width: 26, height: 26)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(PreWorking_2.darkPurple)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 380, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                PreWorking2PoseImageCard(imageName: mainImageName)
                    .frame(width: 500, height: 500)

                HStack(spacing: 16) {
                    PreWorking2PoseImageCard(imageName: sideViewImageName, isSelected: selectedAngle == .side)
                        .frame(width: 100, height: 100)
                        .onTapGesture { selectedAngle = .side }
                    PreWorking2PoseImageCard(imageName: frontViewImageName, isSelected: selectedAngle == .front)
                        .frame(width: 100, height: 100)
                        .onTapGesture { selectedAngle = .front }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            side = DeviceViewModel().fetchAnySide() ?? 0
        }
    }
}

private struct PreWorking2PoseImageCard: View {
    let imageName: String
    var isSelected: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(PreWorking_2.midPurple, lineWidth: isSelected ? 3 : 0)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

#Preview {
    PreWorking_2(
        content: TreatmentContent(treatment_id: 1, exercise_id: 2, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil
    )
}

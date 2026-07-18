import SwiftUI

struct PreWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?

    @Environment(\.dismiss) private var dismiss

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
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

            VStack(alignment: .leading, spacing: 12) {
                Text("確認裝備齊全")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)
                Text("請確認以下兩項裝備是否已就緒")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PreWorking_2.midPurple)

                Spacer().frame(height: 28)

                HStack(spacing: 40) {
                    PreWorking2EquipmentItem(iconSystemName: "cpu", label: "裝置連線了嗎？")
                    PreWorking2EquipmentItem(iconSystemName: "figure.walk", label: "護膝穿戴了嗎？")
                }
            }
            .padding(40)
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

private struct PreWorking2EquipmentItem: View {
    let iconSystemName: String
    let label: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 160, height: 160)
                    .overlay(Circle().stroke(Color(red: 0.75, green: 0.68, blue: 0.95), lineWidth: 3))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                Image(systemName: iconSystemName)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(PreWorking_2.midPurple)
            }
            Text(label)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(PreWorking_2.darkPurple)
        }
    }
}

// MARK: - About Us Panel

private struct PreWorking2AboutPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            HStack(spacing: 8) {
                Text("確認裝備齊全")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PreWorking_2.darkPurple)
                Image(systemName: "sparkle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.7, green: 0.62, blue: 0.95))
            }

            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(PreWorking_2.midPurple)
                    .frame(width: 4)
                Text("請確認是否都已準備就緒")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(8)
            }

            Button {} label: {
                HStack(spacing: 8) {
                    Text("了解更多")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 17, weight: .semibold))
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

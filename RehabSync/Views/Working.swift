import SwiftUI

// MARK: - Working

struct Working: View {
    let content: TreatmentContent
    let exercise: Exercise

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    WorkingLeftPanel(exercise: exercise, content: content)
                        .frame(width: geo.size.width * 0.5)
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Left Panel

private struct WorkingLeftPanel: View {
    let exercise: Exercise
    let content: TreatmentContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            WorkingTopBar(title: exercise.name, onDismiss: { dismiss() })

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.93, green: 0.91, blue: 0.88))
                VStack(spacing: 14) {
                    WorkingStickFigure()
                        .frame(width: 90, height: 130)
                    Text("3D 動畫引導區")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)

            WorkingRingTimer(stageName: "前傾伸展", currentSec: 6, totalSec: 5, currentStage: 2, stageProgress: 1.0)
                .frame(width: 160, height: 160)
                .padding(.vertical, 20)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.90, green: 0.88, blue: 0.85))
                                .frame(width: 34, height: 34)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 6)
                }

                HStack(spacing: 8) {
                    WorkingStatCard(label: "總時間",     value: "07:08")
                    WorkingStatCard(label: "目前組數",   value: "2 / 3")
                    WorkingStatCard(label: "目前動作數", value: "6 / 10")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Top Bar

private struct WorkingTopBar: View {
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.88, blue: 0.85))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                .lineLimit(1)

            Spacer()

            outlineIconButton(systemName: "info")
            outlineIconButton(systemName: "speaker.wave.1")

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func outlineIconButton(systemName: String) -> some View {
        Button(action: {}) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Ring Timer

private struct WorkingRingTimer: View {
    let stageName: String
    let currentSec: Int
    let totalSec: Int
    let currentStage: Int      // 0–3
    let stageProgress: CGFloat // 0.0–1.0

    // Each segment: 82° arc + 8° gap (4° each side) = 90° per quarter
    private let halfGap: CGFloat = 4.0 / 360.0
    private let arcLen:  CGFloat = 82.0 / 360.0
    private let lineWidth: CGFloat = 14

    private let tealDark   = Color(red: 0.12, green: 0.42, blue: 0.38)
    private let trackColor = Color(white: 0.88, opacity: 1)

    private func segStart(_ i: Int) -> CGFloat { CGFloat(i) * 0.25 + halfGap }
    private func segEnd(_ i: Int)   -> CGFloat { CGFloat(i) * 0.25 + 0.25 - halfGap }

    var body: some View {
        ZStack {
            // Background tracks
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .trim(from: segStart(i), to: segEnd(i))
                    .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            // Completed stages — full arc
            ForEach(0..<currentStage, id: \.self) { i in
                Circle()
                    .trim(from: segStart(i), to: segEnd(i))
                    .stroke(tealDark, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            // Current stage — partial arc
            if currentStage < 4 && stageProgress > 0 {
                let s = segStart(currentStage)
                let e = s + arcLen * min(stageProgress, 1.0)
                Circle()
                    .trim(from: s, to: max(s, e))
                    .stroke(tealDark, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(stageName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(currentSec)\"")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text("/\(totalSec)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Stat Card

private struct WorkingStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Stick Figure

private struct WorkingStickFigure: View {
    private let bodyColor = Color.gray.opacity(0.6)
    private let legColor  = Color(red: 0.15, green: 0.48, blue: 0.43)

    var body: some View {
        Canvas { ctx, size in
            let cx  = size.width / 2
            let r: CGFloat = size.width * 0.11

            // Head
            let head = Path(ellipseIn: CGRect(
                x: cx - r, y: 0, width: r * 2, height: r * 2
            ))
            ctx.stroke(head, with: .color(bodyColor), lineWidth: 1.8)

            // Body
            var body = Path()
            body.move(to: CGPoint(x: cx, y: r * 2))
            body.addLine(to: CGPoint(x: cx, y: size.height * 0.57))
            ctx.stroke(body, with: .color(bodyColor), lineWidth: 1.8)

            // Left arm
            let shoulderY = size.height * 0.30
            var lArm = Path()
            lArm.move(to: CGPoint(x: cx, y: shoulderY))
            lArm.addLine(to: CGPoint(x: cx - size.width * 0.38, y: shoulderY + size.height * 0.13))
            ctx.stroke(lArm, with: .color(bodyColor), lineWidth: 1.8)

            // Right arm
            var rArm = Path()
            rArm.move(to: CGPoint(x: cx, y: shoulderY))
            rArm.addLine(to: CGPoint(x: cx + size.width * 0.38, y: shoulderY + size.height * 0.13))
            ctx.stroke(rArm, with: .color(bodyColor), lineWidth: 1.8)

            // Left leg (teal)
            let hipY = size.height * 0.57
            var lLeg = Path()
            lLeg.move(to: CGPoint(x: cx, y: hipY))
            lLeg.addLine(to: CGPoint(x: cx - size.width * 0.30, y: size.height * 0.97))
            ctx.stroke(lLeg, with: .color(legColor), lineWidth: 2.2)

            // Right leg (teal)
            var rLeg = Path()
            rLeg.move(to: CGPoint(x: cx, y: hipY))
            rLeg.addLine(to: CGPoint(x: cx + size.width * 0.30, y: size.height * 0.97))
            ctx.stroke(rLeg, with: .color(legColor), lineWidth: 2.2)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Working(
            content: TreatmentContent(
                treatment_id: 1, exercise_id: 1,
                sets: 3, set_rest_time: 30,
                reps: 10, rep_training_time: 5, rep_rest_time: 5,
                date: Int(Date().timeIntervalSince1970)
            ),
            exercise: Exercise(
                id: nil,
                name: "股四頭肌等長收縮",
                info: "保持站姿，緩慢向前傾",
                device: nil,
                target: "股四頭肌",
                joint: "膝關節",
                rep_stage1: 5, act_stage1: "起始站立",
                rep_stage2: 5, act_stage2: "前傾伸展",
                rep_stage3: 5, act_stage3: "回復站立",
                rep_stage4: nil, act_stage4: nil
            )
        )
    }
}

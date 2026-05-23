import SwiftUI
import Combine

// MARK: - Working

struct Working: View {
    let content: TreatmentContent
    let exercise: Exercise

    @State private var isPaused = false
    @State private var totalElapsed = 0
    @State private var currentSet = 1
    @State private var currentRep = 1
    @State private var currentStageIndex = 0
    @State private var stageElapsed = 0
    @State private var isResting = false
    @State private var restElapsed = 0
    @State private var isComplete = false

    @Environment(\.dismiss) private var dismiss

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var stages: [(name: String, duration: Int)] {
        [(exercise.act_stage1, exercise.rep_stage1),
         (exercise.act_stage2, exercise.rep_stage2),
         (exercise.act_stage3, exercise.rep_stage3),
         (exercise.act_stage4, exercise.rep_stage4)]
            .compactMap { name, dur in
                guard let name, let dur else { return nil }
                return (name, dur)
            }
    }

    private var currentStage: (name: String, duration: Int)? {
        guard !isResting, currentStageIndex < stages.count else { return nil }
        return stages[currentStageIndex]
    }

    private var stageDuration: Int {
        isResting ? content.set_rest_time : (currentStage?.duration ?? 1)
    }

    private var timeRemaining: Int {
        let elapsed = isResting ? restElapsed : stageElapsed
        return max(stageDuration - elapsed, 0)
    }

    private var progress: Double {
        let elapsed = isResting ? restElapsed : stageElapsed
        guard stageDuration > 0 else { return 0 }
        return min(Double(elapsed) / Double(stageDuration), 1.0)
    }

    private var phaseLabel: String {
        if isComplete { return "完成" }
        if isResting  { return "組間休息" }
        return currentStage?.name ?? ""
    }

    private var totalTimeLabel: String {
        String(format: "%02d:%02d", totalElapsed / 60, totalElapsed % 60)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
                HStack(spacing: 0) {
                    // Left panel — all content
                    VStack(spacing: 0) {
                        topBar
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)

                        animationArea
                            .frame(height: geo.size.height * 0.44)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        Spacer()

                        timerControls
                            .padding(.vertical, 20)

                        Spacer()

                        bottomStats
                    }
                    .frame(width: geo.size.width * 0.5)

                    // Right panel — empty for now
                    Spacer()
                        .frame(width: geo.size.width * 0.5)
                }
            }
        }
        .navigationBarHidden(true)
        .onReceive(ticker) { _ in
            guard !isPaused, !isComplete else { return }
            tick()
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.08), radius: 4)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
            Text(exercise.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            Spacer()
            HStack(spacing: 10) {
                WorkingIconButton(systemName: "info.circle")
                WorkingIconButton(systemName: "speaker.wave.2")
            }
        }
    }

    private var animationArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.93, green: 0.91, blue: 0.89))
            VStack(spacing: 14) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 90))
                    .foregroundStyle(Color(red: 0.28, green: 0.28, blue: 0.33))
                Text("3D 動畫引導區")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timerControls: some View {
        HStack(spacing: 48) {
            Button { isPaused.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.91, green: 0.89, blue: 0.87))
                        .frame(width: 52, height: 52)
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                }
            }

            ZStack {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                    ringSegment(index: i, stage: stage)
                    ringLabel(index: i, stage: stage)
                }
                // Center content
                VStack(spacing: 2) {
                    Text(phaseLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("\(timeRemaining)\"")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                        .monospacedDigit()
                    Text("/\(stageDuration)\"")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
        }
    }

    private var bottomStats: some View {
        HStack(spacing: 10) {
            WorkingStatCell(label: "總時間",    value: totalTimeLabel)
            WorkingStatCell(label: "目前組數",   value: "\(currentSet) / \(content.sets)")
            WorkingStatCell(label: "目前動作數", value: "\(currentRep) / \(content.reps)")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Ring Helpers

    private let ringLineW: CGFloat = 40
    private let ringTextR: CGFloat = 66
    private let ringGap: Double    = 0.012

    @ViewBuilder
    private func ringSegment(index i: Int, stage: (name: String, duration: Int)) -> some View {
        let count    = stages.count
        let segFrac  = 1.0 / Double(count)
        let segStart = Double(i) * segFrac + ringGap
        let segEnd   = Double(i + 1) * segFrac - ringGap
        let teal     = Color(red: 0.1, green: 0.55, blue: 0.5)
        let style    = StrokeStyle(lineWidth: ringLineW, lineCap: .butt)

        // Background
        Circle()
            .trim(from: segStart, to: segEnd)
            .stroke(Color.gray.opacity(0.15), style: style)
            .rotationEffect(.degrees(-90))

        if isResting {
            Circle()
                .trim(from: segStart, to: segEnd)
                .stroke(teal.opacity(0.5), style: style)
                .rotationEffect(.degrees(-90))
        } else if i < currentStageIndex {
            Circle()
                .trim(from: segStart, to: segEnd)
                .stroke(teal.opacity(0.5), style: style)
                .rotationEffect(.degrees(-90))
        } else if i == currentStageIndex {
            let dur     = Double(max(stage.duration, 1))
            let stageP  = min(Double(stageElapsed) / dur, 1.0)
            let fillEnd = segStart + (segEnd - segStart) * stageP
            Circle()
                .trim(from: segStart, to: max(segStart + 0.0001, fillEnd))
                .stroke(teal, style: style)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: stageElapsed)
        }
    }

    @ViewBuilder
    private func ringLabel(index i: Int, stage: (name: String, duration: Int)) -> some View {
        let count    = stages.count
        let segFrac  = 1.0 / Double(count)
        let midDeg   = (Double(i) * segFrac + segFrac / 2) * 360 - 90
        let midRad   = Angle(degrees: midDeg).radians
        let isActive = !isResting && i == currentStageIndex
        let isDone   = isResting || i < currentStageIndex

        Text(stage.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(
                isActive ? Color.white :
                isDone   ? Color.white.opacity(0.75) :
                           Color.gray.opacity(0.5)
            )
            .offset(x: cos(midRad) * ringTextR,
                    y: sin(midRad) * ringTextR)
    }

    // MARK: - Timer Logic

    private func tick() {
        totalElapsed += 1

        if isResting {
            restElapsed += 1
            if restElapsed >= content.set_rest_time {
                isResting = false
                restElapsed = 0
                currentStageIndex = 0
                stageElapsed = 0
                currentRep = 1
            }
            return
        }

        stageElapsed += 1
        guard let stage = currentStage else { return }

        if stageElapsed >= stage.duration {
            stageElapsed = 0
            currentStageIndex += 1

            if currentStageIndex >= stages.count {
                currentStageIndex = 0
                currentRep += 1

                if currentRep > content.reps {
                    currentRep = 1
                    currentSet += 1

                    if currentSet > content.sets {
                        isComplete = true
                        currentSet = content.sets
                        currentRep = content.reps
                    } else {
                        isResting = true
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct WorkingIconButton: View {
    let systemName: String
    var body: some View {
        Button {} label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.08), radius: 4)
                Image(systemName: systemName)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            }
        }
    }
}

struct WorkingStatCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.15, green: 0.6, blue: 0.55))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#Preview {
    Working(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 1,
            sets: 3, set_rest_time: 30,
            reps: 10, rep_training_time: 5, rep_rest_time: 5,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: Exercise(
            name: "股四頭肌等長收縮", info: "",
            target: "股四頭肌", joint: "膝關節",
            rep_stage1: 5, act_stage1: "起始放鬆",
            rep_stage2: 1, act_stage2: "收縮壓直",
            rep_stage3: 5, act_stage3: "靜態維持",
            rep_stage4: 1, act_stage4: "緩慢放鬆"
        )
    )
}

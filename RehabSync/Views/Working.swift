import SwiftUI
import Combine

// MARK: - Phase

private enum WorkingPhase: Equatable {
    case preparation
    case exercise(set: Int, rep: Int, stage: Int)
    case setRest(afterSet: Int)
    case finished
}

// MARK: - State

@Observable
private class WorkingState {
    let exerciseName: String
    let sets: Int
    let reps: Int
    let setRestTime: Int
    let prepTime = 10
    let stages: [(name: String, duration: Int)]

    var phase: WorkingPhase = .preparation
    var elapsed: Int = 0
    var totalElapsed: Int = 0
    var isPaused: Bool = false

    private var cancellable: AnyCancellable?

    init(content: TreatmentContent, exercise: Exercise) {
        exerciseName = exercise.name
        sets         = content.sets
        reps         = content.reps
        setRestTime  = content.set_rest_time

        var s: [(String, Int)] = []
        if let n = exercise.act_stage1, let d = exercise.rep_stage1 { s.append((n, d)) }
        if let n = exercise.act_stage2, let d = exercise.rep_stage2 { s.append((n, d)) }
        if let n = exercise.act_stage3, let d = exercise.rep_stage3 { s.append((n, d)) }
        if let n = exercise.act_stage4, let d = exercise.rep_stage4 { s.append((n, d)) }
        stages = s
    }

    func start() {
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPaused else { return }
                self.tick()
            }
    }

    func cancel() { cancellable?.cancel() }

    func togglePause() { isPaused.toggle() }

    // MARK: Computed display

    var stageName: String {
        switch phase {
        case .preparation:             return "預備"
        case .exercise(_, _, let s):   return stages[safe: s]?.name ?? ""
        case .setRest:                 return "組間休息"
        case .finished:                return "完成"
        }
    }

    var currentDuration: Int {
        switch phase {
        case .preparation:             return prepTime
        case .exercise(_, _, let s):   return stages[safe: s]?.duration ?? 5
        case .setRest:                 return setRestTime
        case .finished:                return 0
        }
    }

    // Elapsed seconds within the current rep (accumulates across stages)
    var repElapsed: Int {
        guard case .exercise(_, _, let stage) = phase else { return 0 }
        let prior = (0..<stage).reduce(0) { $0 + (stages[safe: $1]?.duration ?? 0) }
        return prior + elapsed
    }

    // Total seconds for one rep
    var repTotal: Int { stages.reduce(0) { $0 + $1.duration } }

    // Ring-driving elapsed/total — covers preparation and exercise phases
    var ringElapsed: Int {
        switch phase {
        case .preparation:           return elapsed
        case .exercise:              return repElapsed
        case .setRest:               return elapsed
        default:                     return 0
        }
    }

    var ringTotal: Int {
        switch phase {
        case .preparation:           return prepTime
        case .exercise:              return repTotal
        case .setRest:               return setRestTime
        default:                     return 0
        }
    }

    var setDisplay: String {
        switch phase {
        case .exercise(let set, _, _): return "\(set + 1) / \(sets)"
        case .setRest(let s):          return "\(s + 1) / \(sets)"
        case .finished:                return "\(sets) / \(sets)"
        default:                       return "- / \(sets)"
        }
    }

    var repDisplay: String {
        switch phase {
        case .exercise(_, let rep, _): return "\(rep + 1) / \(reps)"
        case .setRest:                 return "\(reps) / \(reps)"
        case .finished:                return "\(reps) / \(reps)"
        default:                       return "- / \(reps)"
        }
    }

    var totalTimeDisplay: String {
        String(format: "%02d:%02d", totalElapsed / 60, totalElapsed % 60)
    }

    // MARK: Timer

    private func tick() {
        elapsed       += 1
        totalElapsed  += 1
        if elapsed >= currentDuration { advance() }
    }

    private func advance() {
        elapsed = 0
        switch phase {
        case .preparation:
            phase = .exercise(set: 0, rep: 0, stage: 0)

        case .exercise(let set, let rep, let stage):
            if stage + 1 < stages.count {
                phase = .exercise(set: set, rep: rep, stage: stage + 1)
            } else if rep + 1 < reps {
                phase = .exercise(set: set, rep: rep + 1, stage: 0)
            } else if set + 1 < sets {
                phase = .setRest(afterSet: set)
            } else {
                phase = .finished
                cancel()
            }

        case .setRest(let afterSet):
            phase = .exercise(set: afterSet + 1, rep: 0, stage: 0)

        case .finished:
            cancel()
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Working

struct Working: View {
    let content: TreatmentContent
    let exercise: Exercise
    @State private var state: WorkingState
    @State private var navigateToPost = false
    @State private var resultVM = TreatmentResultViewModel()
    @Environment(\.goHome) private var goHome

    init(content: TreatmentContent, exercise: Exercise) {
        self.content  = content
        self.exercise = exercise
        _state = State(wrappedValue: WorkingState(content: content, exercise: exercise))
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    WorkingLeftPanel(state: state, onExit: {
                        state.cancel()
                        goHome()
                    })
                    .frame(width: geo.size.width * 0.5)
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToPost) {
            PostWorking(content: content, exercise: exercise, totalElapsed: state.totalElapsed)
        }
        .onAppear  { state.start() }
        .onDisappear { state.cancel() }
        .onChange(of: state.phase) { _, newPhase in
            if newPhase == .finished {
                var result = TreatmentResult(
                    treatment_id: content.treatment_id,
                    treatment_content_id: Int(content.id ?? 0),
                    reps: content.sets * content.reps,
                    total_time: state.totalElapsed,
                    date: Int(Date().timeIntervalSince1970)
                )
                resultVM.insert(&result)
                navigateToPost = true
            }
        }
    }
}

// MARK: - Left Panel

private struct WorkingLeftPanel: View {
    let state: WorkingState
    let onExit: () -> Void
    @State private var arcProgress: CGFloat = 0
    @State private var showExitConfirm = false
    @State private var autoPaused = false

    var body: some View {
        VStack(spacing: 0) {
            WorkingTopBar(title: state.exerciseName, onDismiss: {
                if !state.isPaused {
                    state.isPaused = true
                    autoPaused = true
                }
                showExitConfirm = true
            })

            // Animation guide
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

            // Ring + labels
            ZStack {
                WorkingRingTimer(
                    progress:   arcProgress,
                    currentSec: state.ringElapsed,
                    totalSec:   state.ringTotal
                )
                .frame(width: 160, height: 160)

                // Stage name — outside right
                Text(state.stageName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                    .offset(x: 200)

                // Pause / resume — outside left
                Button(action: { state.togglePause() }) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 50, height: 50)
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
                }
                .offset(x: -200)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .padding(.vertical, 20)

            // Stats
            HStack(spacing: 8) {
                WorkingStatCard(label: "總時間",     value: state.totalTimeDisplay)
                WorkingStatCard(label: "目前組數",   value: state.setDisplay)
                WorkingStatCard(label: "目前動作數", value: state.repDisplay)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onChange(of: state.ringElapsed) { oldValue, newValue in
            let totalSeg = state.ringTotal - 1
            guard totalSeg > 0 else { return }
            if newValue == 0 && oldValue > 0 {
                withAnimation(.linear(duration: 0.5)) {
                    arcProgress = 0
                }
            } else if newValue > 0 {
                withAnimation(.linear(duration: 1)) {
                    arcProgress = CGFloat(newValue) / CGFloat(totalSeg)
                }
            }
        }
        .confirmationDialog("確定要結束訓練嗎？", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("結束訓練", role: .destructive, action: onExit)
            Button("繼續訓練", role: .cancel) {
                if autoPaused {
                    state.isPaused = false
                    autoPaused = false
                }
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
                        .frame(width: 50, height: 50)
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                .lineLimit(1)

            Spacer()

            outlineIconButton(systemName: "info")
            outlineIconButton(systemName: "speaker.wave.1")
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
                    .frame(width: 50, height: 50)
                Image(systemName: systemName)
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Ring Timer

private struct WorkingRingTimer: View {
    let progress: CGFloat   // 0.0–1.0
    let currentSec: Int
    let totalSec: Int

    private let lineWidth: CGFloat = 14
    private let tealDark   = Color(red: 0.12, green: 0.42, blue: 0.38)
    private let trackColor = Color(white: 0.88, opacity: 1)

    // Maps 0–1 fraction into the top-semicircle window [0.5, 1.0]
    // 0 = left (9 o'clock), 1 = right (3 o'clock), clockwise via top
    private func semi(_ x: CGFloat) -> CGFloat { 0.5 + x * 0.5 }

    var body: some View {
        ZStack {
            // Continuous background track (full semicircle)
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            // Progress arc: fills clockwise; erases counter-clockwise when progress decreases
            Circle()
                .trim(from: 0.5, to: semi(progress))
                .stroke(tealDark, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            VStack(spacing: 2) {
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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold))
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

            let head = Path(ellipseIn: CGRect(x: cx - r, y: 0, width: r * 2, height: r * 2))
            ctx.stroke(head, with: .color(bodyColor), lineWidth: 1.8)

            var body = Path()
            body.move(to: CGPoint(x: cx, y: r * 2))
            body.addLine(to: CGPoint(x: cx, y: size.height * 0.57))
            ctx.stroke(body, with: .color(bodyColor), lineWidth: 1.8)

            let shoulderY = size.height * 0.30
            var lArm = Path()
            lArm.move(to: CGPoint(x: cx, y: shoulderY))
            lArm.addLine(to: CGPoint(x: cx - size.width * 0.38, y: shoulderY + size.height * 0.13))
            ctx.stroke(lArm, with: .color(bodyColor), lineWidth: 1.8)

            var rArm = Path()
            rArm.move(to: CGPoint(x: cx, y: shoulderY))
            rArm.addLine(to: CGPoint(x: cx + size.width * 0.38, y: shoulderY + size.height * 0.13))
            ctx.stroke(rArm, with: .color(bodyColor), lineWidth: 1.8)

            let hipY = size.height * 0.57
            var lLeg = Path()
            lLeg.move(to: CGPoint(x: cx, y: hipY))
            lLeg.addLine(to: CGPoint(x: cx - size.width * 0.30, y: size.height * 0.97))
            ctx.stroke(lLeg, with: .color(legColor), lineWidth: 2.2)

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
                sets: 2, set_rest_time: 10,
                reps: 2,
                date: Int(Date().timeIntervalSince1970)
            ),
            exercise: Exercise(
                id: nil,
                name: "前後滑行運動",
                info: "雙腳併攏微屈膝呈預備姿勢，核心收縮。快速向前滑步後立即煞停，再快速滑回起始位置",
                device: nil,
                target: "膝伸展肌群",
                joint: "膝關節",
                rep_stage1: 1, act_stage1: "滑步向前",
                rep_stage2: 1, act_stage2: "逐漸收回",
                rep_stage3: nil, act_stage3: nil,
                rep_stage4: nil, act_stage4: nil
            ),
        )
    }
}

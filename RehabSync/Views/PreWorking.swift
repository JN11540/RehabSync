import SwiftUI

// MARK: - PreWorking

struct PreWorking: View {
    let content: TreatmentContent
    @State private var exerciseVM = ExerciseViewModel()
    @State private var exercise: Exercise? = nil
    @State private var navigateToWorking = false

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    PreWorkingLeftPanel(
                        exerciseName: exercise?.name ?? "",
                        info: exercise?.info ?? "",
                        canStart: exercise != nil,
                        onStart: { navigateToWorking = true }
                    )
                    .frame(width: geo.size.width * 0.5)

                    ScrollView {
                        PreWorkingRightPanel(content: content, exercise: exercise)
                            .padding(24)
                    }
                    .frame(width: geo.size.width * 0.5)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToWorking) {
            if let exercise {
                Working(content: content, exercise: exercise)
            }
        }
        .onAppear {
            exercise = exerciseVM.fetch(by: content.exercise_id)
        }
    }
}

// MARK: - Left Panel

private struct PreWorkingLeftPanel: View {
    let exerciseName: String
    let info: String
    var canStart: Bool = false
    var onStart: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exerciseName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))

            ZStack {
                Color.black
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text("\(exerciseName)示範圖")
                        .font(.system(size: 14))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !info.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("訓練姿勢")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(info)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(red: 0.92, green: 0.91, blue: 0.89))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button(action: onStart) {
                HStack(spacing: 8) {
                    Text("Start")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white)
                .foregroundStyle(canStart ? .primary : Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
            }
            .disabled(!canStart)
        }
        .padding(24)
    }
}

// MARK: - Right Panel

private struct PreWorkingRightPanel: View {
    let content: TreatmentContent
    let exercise: Exercise?

    private var timeLabel: String {
        let repTotal = [exercise?.rep_stage1, exercise?.rep_stage2,
                        exercise?.rep_stage3, exercise?.rep_stage4]
            .compactMap { $0 }.reduce(0, +)
        let s = 10 + content.sets * content.reps * repTotal
              + content.set_rest_time * (content.sets - 1)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var procedureSteps: [(duration: String, name: String)] {
        guard let e = exercise else { return [] }
        return [(e.rep_stage1, e.act_stage1),
                (e.rep_stage2, e.act_stage2),
                (e.rep_stage3, e.act_stage3),
                (e.rep_stage4, e.act_stage4)]
            .compactMap { rep, act in
                guard let rep, let act else { return nil }
                return ("\(rep) sec.", act)
            }
    }

    private var observations: [(String, String)] {
        var rows: [(String, String)] = []
        if let device = exercise?.device { rows.append(("輔具", device)) }
        if let target = exercise?.target { rows.append(("目標肌群", target)) }
        if let joint  = exercise?.joint  { rows.append(("關節", joint)) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Exercises
            Text("Exercises")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))

            HStack(spacing: 12) {
                ExerciseStatCard(icon: "clock",           iconColor: Color(red: 0.94, green: 0.33, blue: 0.33), value: timeLabel,                   label: "Time")
                ExerciseStatCard(icon: "repeat",          iconColor: Color(red: 0.5,  green: 0.44, blue: 0.86), value: "\(content.sets)",            label: "Sets")
                ExerciseStatCard(icon: "waveform.path.ecg", iconColor: Color(red: 0.95, green: 0.62, blue: 0.18), value: "\(content.reps)",          label: "Reps")
            }

            // Procedure
            if !procedureSteps.isEmpty {
                Text("Procedure")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        ForEach(procedureSteps, id: \.name) { step in
                            ProcedureStepCard(duration: step.duration, stepName: step.name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 觀察重點
            if !observations.isEmpty {
                Text("觀察重點")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))

                VStack(spacing: 0) {
                    ForEach(Array(observations.enumerated()), id: \.offset) { index, row in
                        ObservationRow(label: row.0, value: row.1)
                        if index < observations.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }
        }
    }
}

// MARK: - Exercise Stat Card

private struct ExerciseStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Procedure Step Card

private struct ProcedureStepCard: View {
    let duration: String
    let stepName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(duration)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack {
                Color(red: 1.0, green: 0.9, blue: 0.9)
                Image(systemName: "person")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(red: 0.84, green: 0.28, blue: 0.28))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(stepName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
        }
        .padding(12)
        .frame(width: 130)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Observation Row

private struct ObservationRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack {
        PreWorking(content: TreatmentContent(
            treatment_id: 1, exercise_id: 1,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ))
    }
}

import SwiftUI

// MARK: - PostWorking

struct PostWorking: View {
    let content: TreatmentContent
    let exercise: Exercise
    let totalElapsed: Int

    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()
    @State private var completedIds: Set<Int> = []
    @Environment(\.dismiss) private var dismiss

    private var timeLabel: String {
        String(format: "%02d:%02d", totalElapsed / 60, totalElapsed % 60)
    }

    private var todayContents: [TreatmentContent] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(content.date)))
        return contentVM.contents.filter {
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.date))) == day
        }
    }

    private var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            ?? DateInterval(start: Date(), duration: 7 * 86400)
    }

    private var weeklyCompletedCount: Int {
        resultVM.results.filter {
            weekInterval.contains(Date(timeIntervalSince1970: TimeInterval($0.date)))
        }.count
    }

    private var weeklyTotalCount: Int {
        contentVM.contents.filter {
            weekInterval.contains(Date(timeIntervalSince1970: TimeInterval($0.date)))
        }.count
    }

    private var weeklyActiveMinutes: Int {
        resultVM.results.filter {
            weekInterval.contains(Date(timeIntervalSince1970: TimeInterval($0.date)))
        }.reduce(0) { $0 + $1.total_time } / 60
    }

    private var weeklyTargetMinutes: Int {
        let weekContents = contentVM.contents.filter {
            weekInterval.contains(Date(timeIntervalSince1970: TimeInterval($0.date)))
        }
        return weekContents.reduce(0) {
            $0 + TreatmentContentViewModel.totalSeconds(
                content: $1,
                exercise: exerciseVM.exercises.first { Int($0.id ?? 0) == $1.exercise_id }
            )
        } / 60
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    PostCompletionCard()

                    VStack(spacing: 6) {
                        Text("Workout complete!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                        Text("You're one step closer to pain-free movement.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        PostStatCard(
                            icon: "clock",
                            iconBg: Color(red: 1.0, green: 0.90, blue: 0.90),
                            iconColor: Color(red: 0.94, green: 0.33, blue: 0.33),
                            value: timeLabel,
                            label: "Time"
                        )
                        PostStatCard(
                            icon: "square.stack",
                            iconBg: Color(red: 1.0, green: 0.90, blue: 0.90),
                            iconColor: Color(red: 0.94, green: 0.33, blue: 0.33),
                            value: "\(content.sets)",
                            label: "Sets"
                        )
                        PostStatCard(
                            icon: "repeat",
                            iconBg: Color(red: 0.93, green: 0.91, blue: 1.0),
                            iconColor: Color(red: 0.50, green: 0.44, blue: 0.86),
                            value: "\(content.sets * content.reps)",
                            label: "Reps"
                        )
                    }

                    if !todayContents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TODAY'S SESSIONS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(todayContents, id: \.id) { item in
                                let itemExercise = exerciseVM.exercises.first { Int($0.id ?? 0) == item.exercise_id }
                                let isDone = completedIds.contains(Int(item.id ?? -1))
                                    || item.id == content.id
                                PostSessionRow(
                                    exerciseName: itemExercise?.name ?? "未知動作",
                                    sets: item.sets,
                                    reps: item.reps,
                                    totalSeconds: TreatmentContentViewModel.totalSeconds(content: item, exercise: itemExercise),
                                    isDone: isDone
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("THIS WEEK")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            PostProgressRow(
                                label: "Weekly workout goal",
                                valueLabel: "\(weeklyCompletedCount) / \(weeklyTotalCount)",
                                progress: weeklyTotalCount > 0
                                    ? Double(weeklyCompletedCount) / Double(weeklyTotalCount) : 0
                            )
                            Divider().padding(.horizontal, 4)
                            PostProgressRow(
                                label: "Active minutes",
                                valueLabel: "\(weeklyActiveMinutes) / \(weeklyTargetMinutes) min",
                                progress: weeklyTargetMinutes > 0
                                    ? Double(weeklyActiveMinutes) / Double(weeklyTargetMinutes) : 0
                            )
                        }
                        .padding(.horizontal, 16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    }

                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Text("Finish")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.25)))
                    }
                }
                .padding(24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            contentVM.fetchAll(for: content.treatment_id)
            exerciseVM.fetchAll()
            resultVM.fetchAll(for: content.treatment_id)
            completedIds = resultVM.fetchCompletedContentIds(for: content.treatment_id)
        }
    }
}

// MARK: - Completion Card

private struct PostCompletionCard: View {
    private let foldSize: CGFloat = 22

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

            // Left fold triangle
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: foldSize, y: 0))
                p.addLine(to: CGPoint(x: 0, y: foldSize))
                p.closeSubpath()
            }
            .fill(Color(white: 0.82))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16))

            // Right fold triangle
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width - foldSize, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: foldSize))
                    p.closeSubpath()
                }
                .fill(Color(white: 0.82))
                .clipShape(UnevenRoundedRectangle(topTrailingRadius: 16))
            }

            // Content centred inside the card
            VStack(spacing: 14) {
                Text("Great\nJob!")
                    .font(.system(size: 30, weight: .bold))
                    .italic()
                    .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.50))
                    .multilineTextAlignment(.center)
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.15))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
        .frame(width: 210, height: 195)
    }
}

// MARK: - Stat Card

private struct PostStatCard: View {
    let icon: String
    let iconBg: Color
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBg)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Session Row

private struct PostSessionRow: View {
    let exerciseName: String
    let sets: Int
    let reps: Int
    let totalSeconds: Int
    let isDone: Bool

    private var subtitleLabel: String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        let timeStr = s == 0 ? "\(m) min" : String(format: "%d:%02d", m, s)
        return "\(sets) sets · \(sets * reps) reps · \(timeStr)"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDone
                        ? Color(red: 0.88, green: 0.97, blue: 0.92)
                        : Color(red: 0.90, green: 0.97, blue: 0.95))
                    .frame(width: 48, height: 48)
                Image(systemName: "figure.run")
                    .font(.system(size: 20))
                    .foregroundStyle(isDone
                        ? Color(red: 0.18, green: 0.65, blue: 0.42)
                        : Color(red: 0.15, green: 0.55, blue: 0.50))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(exerciseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text(subtitleLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDone {
                Text("Done")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.42))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color(red: 0.18, green: 0.65, blue: 0.42), lineWidth: 1.5))
            } else {
                Text("Up next")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.92, green: 0.92, blue: 0.98))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

// MARK: - Progress Row

private struct PostProgressRow: View {
    let label: String
    let valueLabel: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.40, blue: 0.82))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.91, green: 0.91, blue: 0.96))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color(red: 0.42, green: 0.40, blue: 0.82))
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PostWorking(
            content: TreatmentContent(
                treatment_id: 1, exercise_id: 20,
                sets: 6, set_rest_time: 60,
                reps: 8,
                date: Int(Date().timeIntervalSince1970)
            ),
            exercise: Exercise(
                id: 20,
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
            totalElapsed: 21
        )
    }
}

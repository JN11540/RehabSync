import SwiftUI

struct TreatmentView: View {
    let treatment: Treatment
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()

    private var completedContentIds: Set<Int> {
        Set(resultVM.results.map { $0.treatment_content_id })
    }

    private var activeContentId: Int64? {
        contentVM.contents
            .filter { !completedContentIds.contains(Int($0.id ?? -1)) }
            .min(by: { ($0.id ?? .max) < ($1.id ?? .max) })?
            .id
    }

    private var groupedByDate: [(day: Date, items: [(idx: Int, content: TreatmentContent)])] {
        var dict: [Date: [(Int, TreatmentContent)]] = [:]
        for (i, c) in contentVM.contents.enumerated() {
            let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(c.date)))
            dict[day, default: []].append((i, c))
        }
        return dict.keys.sorted().map { day in
            (day, dict[day]!.sorted { $0.0 < $1.0 })
        }
    }

    private var startDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.start_time))
            .formatted(.dateTime.year().month().day())
    }
    private var endDate: String {
        Date(timeIntervalSince1970: TimeInterval(treatment.end_time))
            .formatted(.dateTime.year().month().day())
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(treatment.name)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                        Text("\(startDate) ～ \(endDate)")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedByDate, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.day.formatted(.dateTime.month().day()))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 2)

                                ForEach(group.items, id: \.idx) { item in
                                    let status: DayStatus =
                                        completedContentIds.contains(Int(item.content.id ?? -1)) ? .done :
                                        item.content.id == activeContentId ? .active :
                                        .upcoming
                                    TreatmentSessionRow(
                                        exerciseName: exerciseName(for: item.content.exercise_id),
                                        content: item.content,
                                        exercise: exercise(for: item.content.exercise_id),
                                        status: status
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            contentVM.fetchAll(for: Int(treatment.id ?? 0))
            exerciseVM.fetchAll()
            resultVM.fetchAll(for: Int(treatment.id ?? 0))
        }
    }

    private func exerciseName(for id: Int) -> String {
        exerciseVM.exercises.first { Int($0.id ?? 0) == id }?.name ?? "未知動作"
    }

    private func exercise(for id: Int) -> Exercise? {
        exerciseVM.exercises.first { Int($0.id ?? 0) == id }
    }
}

// MARK: - Session Row

struct TreatmentSessionRow: View {
    let exerciseName: String
    let content: TreatmentContent
    let exercise: Exercise?
    let status: DayStatus

    private var totalSeconds: Int {
        TreatmentContentViewModel.totalSeconds(content: content, exercise: exercise)
    }

    private var subtitleLabel: String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        let timeStr = s == 0 ? "\(m) min" : String(format: "%d:%02d", m, s)
        return "\(content.sets) sets · \(content.sets * content.reps) reps · \(timeStr)"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(status == .done
                        ? Color(red: 0.88, green: 0.97, blue: 0.92)
                        : Color(red: 0.90, green: 0.97, blue: 0.95))
                    .frame(width: 48, height: 48)
                Image(systemName: "figure.run")
                    .font(.system(size: 20))
                    .foregroundStyle(status == .done
                        ? Color(red: 0.18, green: 0.65, blue: 0.42)
                        : Color(red: 0.15, green: 0.55, blue: 0.50))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(exerciseName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text(subtitleLabel)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            DayStatusBadge(status: status)
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

// MARK: - Status Badge

struct DayStatusBadge: View {
    let status: DayStatus

    var body: some View {
        switch status {
        case .done:
            Text("Done")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.42))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(Color(red: 0.18, green: 0.65, blue: 0.42), lineWidth: 1.5))
        case .active:
            Text("In progress")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(red: 0.15, green: 0.6, blue: 0.55))
                .clipShape(Capsule())
        case .upcoming:
            Text("Up next")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.70))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(red: 0.92, green: 0.92, blue: 0.98))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Day Status

enum DayStatus {
    case done, active, upcoming
}

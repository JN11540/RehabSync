import SwiftUI

struct TreatmentView: View {
    let treatment: Treatment
    @Environment(TreatmentSelectionState.self) private var selectionState
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var resultVM = TreatmentResultViewModel()

    private var completedContentIds: Set<Int> {
        Set(resultVM.results.map { $0.treatment_content_id })
    }

    private static let cal = Calendar.current

    private func isToday(_ date: Date) -> Bool {
        Self.cal.isDateInToday(date)
    }

    private var todayEffectiveSelectedId: Int64? {
        let todayItems = contentVM.contents.filter {
            Self.cal.isDateInToday(Date(timeIntervalSince1970: TimeInterval($0.date)))
        }
        let completed = Set(resultVM.results.map { $0.treatment_content_id })
        // 使用者選取今日任一動作（含已完成）→ 尊重選取
        if let uid = selectionState.userSelectedContentId,
           todayItems.contains(where: { $0.id == uid }) {
            return uid
        }
        // 無使用者選取 → 今日第一個未完成
        if let first = todayItems.first(where: { !completed.contains(Int($0.id ?? -1)) }) {
            return first.id
        }
        // 全部做完 → 跳回今日第一個
        return todayItems.first?.id
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

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.91).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedByDate, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                let cal = Calendar.current
                                let d = group.day
                                let dateStr = String(format: "%d年%d月%d日",
                                    cal.component(.year, from: d),
                                    cal.component(.month, from: d),
                                    cal.component(.day, from: d))
                                Text(dateStr)
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                                    .padding(.leading, 2)

                                ForEach(group.items, id: \.idx) { item in
                                    let isDone = completedContentIds.contains(Int(item.content.id ?? -1))
                                    let todayGroup = isToday(group.day)
                                    let status: DayStatus =
                                        isDone ? .done :
                                        todayGroup ? .active :
                                        .upcoming
                                    let isSelected = todayGroup &&
                                        item.content.id == todayEffectiveSelectedId
                                    TreatmentSessionRow(
                                        exerciseName: exerciseName(for: item.content.exercise_id),
                                        content: item.content,
                                        exercise: exercise(for: item.content.exercise_id),
                                        status: status,
                                        isSelected: isSelected
                                    )
                                    .onTapGesture {
                                        if todayGroup {
                                            selectionState.userSelectedContentId = item.content.id
                                        }
                                    }
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
    var isSelected: Bool = false

    private var subtitleLabel: String {
        "\(content.sets) 組 · \(content.reps) 次"
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
                    .font(.system(size: 22))
                    .foregroundStyle(status == .done
                        ? Color(red: 0.18, green: 0.65, blue: 0.42)
                        : Color(red: 0.15, green: 0.55, blue: 0.50))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(exerciseName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                Text(subtitleLabel)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            DayStatusBadge(status: status)
        }
        .padding(14)
        .background(isSelected ? Color(red: 0.15, green: 0.6, blue: 0.55).opacity(0.08) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.15, green: 0.6, blue: 0.55), lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

// MARK: - Status Badge

struct DayStatusBadge: View {
    let status: DayStatus

    var body: some View {
        switch status {
        case .done:
            Text("完成")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.42))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(Color(red: 0.18, green: 0.65, blue: 0.42), lineWidth: 1.5))
        case .active:
            Text("進行中")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(red: 0.15, green: 0.6, blue: 0.55))
                .clipShape(Capsule())
        case .upcoming:
            Text("即將進行")
                .font(.system(size: 22, weight: .medium))
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

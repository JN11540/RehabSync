import SwiftUI

struct TreatmentView: View {
    let treatment: Treatment
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()
    @State private var activeIndex: Int = 0
    @State private var resultVM = TreatmentResultViewModel()
    @State private var completedContentIds: Set<Int> = []

    private var activeIndexKey: String {
        "activeIndex_\(treatment.id ?? 0)"
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
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(treatment.name)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(Color(red: 0.1, green: 0.25, blue: 0.4))
                        Text("\(startDate) ～ \(endDate)")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        Text("A simple, beginner-friendly program designed to release tension, improve posture, and build the essential strength of your neck muscles.")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Label("左右滑動查看全部訓練日", systemImage: "arrow.left.and.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    let cardHeight = geo.size.height - 320
                    let cardWidth = cardHeight * (9.0 / 13.0)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(Array(contentVM.contents.enumerated()), id: \.element.id) { index, content in
                                    let cardStatus: DayStatus =
                                        index == activeIndex ? .active :
                                        completedContentIds.contains(Int(content.id ?? -1)) ? .done :
                                        .upcoming
                                    DayCard(
                                        content: content,
                                        exerciseName: exerciseName(for: content.exercise_id),
                                        width: cardWidth,
                                        height: cardHeight,
                                        status: cardStatus,
                                        onTap: {
                                        activeIndex = index
                                        UserDefaults.standard.set(index, forKey: activeIndexKey)
                                    }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                        }
                        .onChange(of: contentVM.contents.count) { _, _ in
                            DispatchQueue.main.async {
                                proxy.scrollTo(activeIndex, anchor: .leading)
                            }
                        }
                    }
                }
                .padding(.top, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let saved = UserDefaults.standard.object(forKey: activeIndexKey) as? Int {
                activeIndex = saved
            }
            contentVM.fetchAll(for: Int(treatment.id ?? 0))
            exerciseVM.fetchAll()
            completedContentIds = resultVM.fetchCompletedContentIds(for: Int(treatment.id ?? 0))
        }
    }

    private func exerciseName(for id: Int) -> String {
        exerciseVM.exercises.first { Int($0.id ?? 0) == id }?.name ?? "未知動作"
    }
}

// MARK: - Day Card

struct DayCard: View {
    let content: TreatmentContent
    let exerciseName: String
    let width: CGFloat
    let height: CGFloat
    let status: DayStatus
    let onTap: () -> Void

    private var date: Date {
        Date(timeIntervalSince1970: TimeInterval(content.date))
    }
    private var dateLabel: String {
        date.formatted(.dateTime.month().day())
    }
    private var totalSeconds: Int {
        (content.rep_training_time + content.rep_rest_time) * content.reps * content.sets
            + content.set_rest_time * (content.sets - 1)
    }
    private var timeLabel: String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: status.icon)
                .font(.system(size: 36))
                .foregroundStyle(
                    status == .done   ? Color.green :
                    status == .active ? Color.white :
                    Color(red: 0.15, green: 0.6, blue: 0.55)
                )

            Text(dateLabel)
                .font(.system(size: 18))
                .foregroundStyle(status == .done ? Color.gray : (status == .active ? .white.opacity(0.8) : .secondary))
                .strikethrough(status == .done, color: .gray)

            Text(exerciseName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    status == .done   ? Color.gray :
                    status == .active ? Color.white :
                    Color(red: 0.1, green: 0.25, blue: 0.4)
                )
                .strikethrough(status == .done, color: .gray)
                .lineLimit(2)

            Text(status.label)
                .font(.system(size: 17))
                .foregroundStyle(status == .done ? Color.gray : (status == .active ? .white.opacity(0.8) : .secondary))

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        status == .done   ? Color.gray :
                        status == .active ? Color.white :
                        Color(red: 0.1, green: 0.25, blue: 0.4)
                    )
                Text("分鐘")
                    .font(.system(size: 17))
                    .foregroundStyle(status == .done ? Color.gray : (status == .active ? .white.opacity(0.7) : .secondary))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 24)
        .frame(width: width, height: height)
        .background(status == .active ? Color(red: 0.1, green: 0.25, blue: 0.4) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .onTapGesture { onTap() }
    }
}

// MARK: - Day Status

enum DayStatus {
    case done, active, upcoming

    var icon: String {
        switch self {
        case .done:     return "checkmark.circle"
        case .active:   return "play.circle.fill"
        case .upcoming: return "clock"
        }
    }
    var label: String {
        switch self {
        case .done:     return "已完成"
        case .active:   return "進行中"
        case .upcoming: return "即將開始"
        }
    }
}

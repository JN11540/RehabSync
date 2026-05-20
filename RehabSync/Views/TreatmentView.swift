import SwiftUI

struct TreatmentView: View {
    let treatment: Treatment
    @State private var contentVM = TreatmentContentViewModel()
    @State private var exerciseVM = ExerciseViewModel()

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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(contentVM.contents, id: \.id) { content in
                                DayCard(
                                    content: content,
                                    exerciseName: exerciseName(for: content.exercise_id),
                                    width: cardWidth,
                                    height: cardHeight
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.top, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            contentVM.fetchAll(for: Int(treatment.id ?? 0))
            exerciseVM.fetchAll()
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

    private var date: Date {
        Date(timeIntervalSince1970: TimeInterval(content.date))
    }
    private var dateLabel: String {
        date.formatted(.dateTime.month().day())
    }
    private var totalSeconds: Int {
        content.sets * (content.reps * content.rep_training_time + content.set_rest_time)
    }
    private var timeLabel: String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    private var status: DayStatus {
        let today = Calendar.current.startOfDay(for: Date())
        let cardDay = Calendar.current.startOfDay(for: date)
        if cardDay < today { return .done }
        if cardDay == today { return .active }
        return .upcoming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: status.icon)
                .font(.system(size: 36))
                .foregroundStyle(
                    status == .done   ? Color.gray :
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

            Text(status == .done ? "完成：\(dateLabel)" : status.label)
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
        .padding(24)
        .frame(width: width, height: height)
        .background(status == .active ? Color(red: 0.1, green: 0.25, blue: 0.4) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
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

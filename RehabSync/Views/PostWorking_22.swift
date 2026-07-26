import SwiftUI
import Charts

struct PostWorking_22: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalReps: Int
    let totalElapsedSeconds: Int
    let treatmentResult: TreatmentResult
    let onReturnToDashboard: () -> Void

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)
    fileprivate static let lightPurple = Color(red: 0.94, green: 0.92, blue: 0.99)
    fileprivate static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.99)
    fileprivate static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    fileprivate static let green = Color(red: 0.20, green: 0.70, blue: 0.45)
    fileprivate static let blue = Color(red: 0.25, green: 0.55, blue: 0.95)
    fileprivate static let pink = Color(red: 0.90, green: 0.30, blue: 0.45)

    /// 毫秒轉成「X 分 YY 秒」，`ms <= 0` 一律視為沒有資料。
    fileprivate static func formatMinutesSeconds(ms: Int) -> String {
        guard ms > 0 else { return "－" }
        let totalSeconds = ms / 1000
        return String(format: "%d 分 %02d 秒", totalSeconds / 60, totalSeconds % 60)
    }

    /// 毫秒轉成「X.X 秒」。
    fileprivate static func formatSeconds(ms: Double) -> String {
        String(format: "%.1f 秒", ms / 1000.0)
    }

    @State private var showReturnConfirm = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            PostWorking22Header()
                            PostWorking22StatRow(treatmentResult: treatmentResult, onRequestReturn: { showReturnConfirm = true })

                            PostWorking22OverviewCard(content: content, treatmentResult: treatmentResult)
                                .frame(maxHeight: .infinity)
                        }
                        .padding(28)
                        .frame(minHeight: geo.size.height)
                    }
                }
                .background(Self.panelBackground)
            }
            .background(Color.white)

            if showReturnConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                PostWorking22ReturnConfirmDialog(
                    onCancel: { showReturnConfirm = false },
                    onConfirm: onReturnToDashboard
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct PostWorking22Header: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你好棒！")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 20))
                    .foregroundStyle(PostWorking_22.mutedText)
            }

            Spacer()
        }
    }
}

// MARK: - Stat Row

private struct PostWorking22Stat {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let change: String
    let isPositive: Bool
    let note: String
}

private struct PostWorking22StatRow: View {
    let treatmentResult: TreatmentResult
    let onRequestReturn: () -> Void

    /// 「第一組開始」到「最後一組結束」的絕對時間差（毫秒），天然包含組間休息時間。
    private var totalTimeText: String {
        let firstStart = treatmentResult.set_start_time.first(where: { $0 > 0 }) ?? 0
        let lastEnd = treatmentResult.set_end_time.last(where: { $0 > 0 }) ?? 0
        return PostWorking_22.formatMinutesSeconds(ms: max(0, lastEnd - firstStart))
    }

    private var totalReps: Int {
        treatmentResult.reps.reduce(0, +)
    }

    /// sum(extension_length) / sum(reps)：未完成的次數固定補 0，不會影響平均值。
    private var averageExtensionText: String {
        guard totalReps > 0 else { return "－" }
        let totalMs = treatmentResult.extension_length.reduce(0, +)
        return PostWorking_22.formatSeconds(ms: Double(totalMs) / Double(totalReps))
    }

    private var stats: [PostWorking22Stat] {
        [
            PostWorking22Stat(icon: "clock.fill", color: PostWorking_22.midPurple, label: "總時間", value: totalTimeText, change: "", isPositive: true, note: ""),
            PostWorking22Stat(icon: "repeat.circle.fill", color: PostWorking_22.blue, label: "總次數", value: "\(totalReps) 次", change: "", isPositive: true, note: ""),
            PostWorking22Stat(icon: "figure.strengthtraining.functional", color: PostWorking_22.green, label: "整局平均弓步維持時長", value: averageExtensionText, change: "", isPositive: true, note: "")
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(stats, id: \.label) { stat in
                PostWorking22StatCard(stat: stat)
            }

            Button {
                onRequestReturn()
            } label: {
                Text("回到總覽")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 「回到總覽」的確認視窗：以小視窗疊在目前這頁上面顯示，比照 `PostWorking_9`／`PostWorking_2` 的做法，
/// 不用 `.fullScreenCover` 另外跳出一個全白頁面。
private struct PostWorking22ReturnConfirmDialog: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                Text("確定要回到總覽嗎？")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)

                Button {
                    onConfirm()
                } label: {
                    Text("確定")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PostWorking_22.darkPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .padding(.top, 12)
            .frame(width: 320)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PostWorking_22.darkPurple)
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
        }
    }
}

private struct PostWorking22StatCard: View {
    let stat: PostWorking22Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(stat.color.opacity(0.15))
                    Image(systemName: stat.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(stat.color)
                }
                .frame(width: 32, height: 32)
                Spacer()
            }
            Text(stat.label)
                .font(.system(size: 20))
                .foregroundStyle(PostWorking_22.mutedText)
            Text(stat.value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.black)

            if !stat.change.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: stat.isPositive ? "arrow.up" : "arrow.down")
                    Text(stat.change)
                    Text(stat.note)
                        .foregroundStyle(PostWorking_22.mutedText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stat.isPositive ? PostWorking_22.green : PostWorking_22.pink)
            } else if !stat.note.isEmpty {
                Text(stat.note)
                    .font(.system(size: 11))
                    .foregroundStyle(PostWorking_22.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Overview (Bar Chart)

private struct PostWorking22AttemptDuration: Identifiable {
    let attempt: Int
    let seconds: Double
    var id: Int { attempt }
}

/// 一組的統計資料，從 `treatmentResult` 依索引現算。
private struct PostWorking22GroupStats {
    let index: Int
    let reps: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int
    let barData: [PostWorking22AttemptDuration]

    /// 「這組從未開始」跟「這組有開始／結束但 0 次完成」視為同一種狀況。
    var hasData: Bool { reps > 0 }

    var label: String { "第 \(index + 1) 組" }

    var totalTimeText: String {
        guard hasData else { return "－" }
        return PostWorking_22.formatMinutesSeconds(ms: setEndTimeMs - setStartTimeMs)
    }

    var averageDurationText: String {
        guard hasData else { return "－" }
        let totalMs = barData.reduce(0.0) { $0 + $1.seconds * 1000 }
        return PostWorking_22.formatSeconds(ms: totalMs / Double(reps))
    }

    static func compute(index: Int, treatmentResult: TreatmentResult, repsPerSet: Int) -> PostWorking22GroupStats {
        let reps = treatmentResult.reps.indices.contains(index) ? treatmentResult.reps[index] : 0
        let startMs = treatmentResult.set_start_time.indices.contains(index) ? treatmentResult.set_start_time[index] : 0
        let endMs = treatmentResult.set_end_time.indices.contains(index) ? treatmentResult.set_end_time[index] : 0

        let sliceStart = index * repsPerSet
        let sliceEnd = min(sliceStart + repsPerSet, treatmentResult.extension_length.count)
        let slice = sliceStart < sliceEnd ? Array(treatmentResult.extension_length[sliceStart..<sliceEnd]) : []
        // 只取前 reps 個（實際完成的次數），其餘是 0 補值，不應該畫出來。
        let realValues = Array(slice.prefix(reps))
        let barData = realValues.enumerated().map { i, ms in
            PostWorking22AttemptDuration(attempt: i + 1, seconds: Double(ms) / 1000.0)
        }

        return PostWorking22GroupStats(index: index, reps: reps, setStartTimeMs: startMs, setEndTimeMs: endMs, barData: barData)
    }
}

private struct PostWorking22OverviewCard: View {
    let content: TreatmentContent
    let treatmentResult: TreatmentResult

    @State private var selectedIndex: Int = 0
    @State private var showRetentionDetail = false

    private var groups: [PostWorking22GroupStats] {
        (0..<content.sets).map { PostWorking22GroupStats.compute(index: $0, treatmentResult: treatmentResult, repsPerSet: content.reps) }
    }

    private var selected: PostWorking22GroupStats {
        groups.first(where: { $0.index == selectedIndex }) ?? PostWorking22GroupStats.compute(index: 0, treatmentResult: treatmentResult, repsPerSet: content.reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                HStack(spacing: 16) {
                    ForEach(groups, id: \.index) { group in
                        Button {
                            selectedIndex = group.index
                        } label: {
                            Text(group.label)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(group.index == selectedIndex ? Color.white : PostWorking_22.mutedText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(group.index == selectedIndex ? PostWorking_22.darkPurple : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Button {
                    showRetentionDetail = true
                } label: {
                    Text("檢視")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PostWorking_22.mutedText)
                }
                .buttonStyle(.plain)
                .disabled(!selected.hasData)
                .opacity(selected.hasData ? 1 : 0.4)
            }

            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_22.mutedText)
                    Text(selected.totalTimeText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_22.mutedText)
                    Text("\(selected.reps) 次")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("本組平均弓步維持時長")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_22.mutedText)
                    Text(selected.averageDurationText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                Chart(selected.barData) { point in
                    BarMark(
                        x: .value("次數", point.attempt),
                        y: .value("單次弓步維持時長（秒）", point.seconds),
                        width: .fixed(22)
                    )
                    .foregroundStyle(PostWorking_22.darkPurple)
                    .cornerRadius(2)
                }
                .chartXScale(domain: 0.5...(Double(content.reps) + 0.5))
                .chartYScale(domain: 0...7)
                .chartXAxis {
                    AxisMarks(values: Array(1...content.reps)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                                    .font(.system(size: 16))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(0...7)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.system(size: 16))
                    }
                }
                .chartXAxisLabel(alignment: .center) {
                    Text("次數")
                        .font(.system(size: 18))
                }
                .chartYAxisLabel(position: .leading, alignment: .center) {
                    Text("單次弓步維持時長（秒）")
                        .font(.system(size: 18))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220, alignment: .leading)
                .offset(y: 15)
            }
            .padding(.trailing, 20)
            .frame(height: 300)
        }
        .padding(20)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        .fullScreenCover(isPresented: $showRetentionDetail) {
            PostWorking22RetentionDetailSheet(
                treatmentResultId: treatmentResult.id ?? 0,
                setStartTimeMs: selected.setStartTimeMs,
                setEndTimeMs: selected.setEndTimeMs
            )
        }
    }
}

// MARK: - Knee Angle Detail

private struct PostWorking22KneeAnglePoint: Identifiable {
    let time: Double
    let angle: Double
    var id: Double { time }
}

private struct PostWorking22RetentionCard: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    /// 不預先讀取進記憶體：只有這個畫面真的顯示出來（也就是使用者點了「檢視」）才查詢，
    /// 用帶時間範圍的查詢函式只查當下這一組，不會撈其他組別的資料。
    @State private var dataPoints: [PostWorking22KneeAnglePoint] = []

    private var durationSeconds: Double {
        max(0.001, Double(setEndTimeMs - setStartTimeMs) / 1000.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("即時膝角度")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
            }

            Chart(dataPoints) { point in
                LineMark(
                    x: .value("時間（秒）", point.time),
                    y: .value("膝角度", point.angle)
                )
                .foregroundStyle(PostWorking_22.darkPurple)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: 0...durationSeconds)
            .chartYScale(domain: 0...90)
            .chartXAxisLabel("時間（秒）", alignment: .center)
            .chartYAxisLabel("膝角度（度）", position: .leading, alignment: .center)
            .frame(height: 220)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        .onAppear {
            let rows = DeviceViewModel().fetchAdvancedStatistics(
                treatmentResultId: treatmentResultId,
                from: Int64(setStartTimeMs),
                to: Int64(setEndTimeMs)
            )
            dataPoints = rows.map { row in
                PostWorking22KneeAnglePoint(time: Double(row.timestamp - Int64(setStartTimeMs)) / 1000.0, angle: row.angle)
            }
        }
    }
}

// 分頁式 EXG 趨勢圖（比照 PostWorking_2／PostWorking_9／PostWorking_12 已完成的做法）
// 是 working22-database-port-plan.md 明確列為之後才評估的範圍，這個畫面先只顯示膝角度。
private struct PostWorking22RetentionDetailSheet: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            PostWorking_22.panelBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    PostWorking22RetentionCard(treatmentResultId: treatmentResultId, setStartTimeMs: setStartTimeMs, setEndTimeMs: setEndTimeMs)
                }
                .padding(28)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PostWorking_22.darkPurple)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }
}

#Preview {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    PostWorking_22(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 22,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 1500,
        totalReps: 12,
        totalElapsedSeconds: 245,
        treatmentResult: TreatmentResult(
            treatment_id: 1,
            treatment_content_id: 22,
            reps: [2, 2],
            extension_length: [3000, 4000, 2500, 5000],
            set_start_time: [now, now + 200_000],
            set_end_time: [now + 180_000, now + 380_000],
            date: now
        ),
        onReturnToDashboard: {}
    )
}

import SwiftUI
import Charts

// MARK: - PostWorking_9

struct PostWorking_9: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalReps: Int
    let totalElapsedSeconds: Int
    let blueHitCount: Int
    let redHitCount: Int
    let yellowHitCount: Int
    let treatmentResult: TreatmentResult
    @Environment(\.goHome) private var goHome

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack {
                HStack(alignment: .bottom, spacing: 60) {
                    Image("FinishGameLeftIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)

                    Image("FinishGameRightIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        PostWorking9StatRow(treatmentResult: treatmentResult)
                        PostWorking9DonationOverviewCard(content: content, treatmentResult: treatmentResult)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 40)
            .padding(.leading, 60)
            .padding(.trailing, 60)

            Button(action: { goHome() }) {
                Image("ArrowIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(24)
            .offset(y: 50)
        }
    }
}

// MARK: - Stat Row

private struct PostWorking9Stat {
    let icon: String
    let color: Color
    let label: String
    let value: String
}

private struct PostWorking9StatRow: View {
    let treatmentResult: TreatmentResult

    /// 「第一組開始」到「最後一組結束」的絕對時間差（毫秒），天然包含組間休息時間。
    private var totalTimeText: String {
        let firstStart = treatmentResult.set_start_time.first(where: { $0 > 0 }) ?? 0
        let lastEnd = treatmentResult.set_end_time.last(where: { $0 > 0 }) ?? 0
        return PostWorking_9.formatMinutesSeconds(ms: max(0, lastEnd - firstStart))
    }

    private var totalReps: Int {
        treatmentResult.reps.reduce(0, +)
    }

    /// sum(extension_length) / sum(reps)：未完成的次數固定補 0，不會影響平均值。
    private var averageExtensionText: String {
        guard totalReps > 0 else { return "－" }
        let totalMs = treatmentResult.extension_length.reduce(0, +)
        return PostWorking_9.formatSeconds(ms: Double(totalMs) / Double(totalReps))
    }

    private var stats: [PostWorking9Stat] {
        [
            PostWorking9Stat(icon: "clock.fill", color: Color(red: 0.275, green: 0.706, blue: 0.831), label: "總時間", value: totalTimeText),
            PostWorking9Stat(icon: "repeat.circle.fill", color: Color(red: 0.369, green: 0.690, blue: 0.824), label: "總次數", value: "\(totalReps) 次"),
            PostWorking9Stat(icon: "figure.strengthtraining.functional", color: Color(red: 0.35, green: 0.75, blue: 0.50), label: "整局平均部分蹲時長", value: averageExtensionText)
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(stats, id: \.label) { stat in
                PostWorking9StatCard(stat: stat)
            }
        }
    }
}

private struct PostWorking9StatCard: View {
    let stat: PostWorking9Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(stat.color.opacity(0.2))
                    Image(systemName: stat.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(stat.color)
                }
                .frame(width: 32, height: 32)
                Spacer()
            }
            Text(stat.label)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.65))
            Text(stat.value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15)))
    }
}

// MARK: - Donation Overview (Bar Chart)

private struct PostWorking9AttemptDuration: Identifiable {
    let attempt: Int
    let seconds: Double
    var id: Int { attempt }
}

/// 一組的統計資料，從 `treatmentResult` 依索引現算。
private struct PostWorking9GroupStats {
    let index: Int
    let reps: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int
    let barData: [PostWorking9AttemptDuration]

    /// 「這組從未開始」跟「這組有開始／結束但 0 次完成」視為同一種狀況。
    var hasData: Bool { reps > 0 }

    var label: String { "第 \(index + 1) 組" }

    var totalTimeText: String {
        guard hasData else { return "－" }
        return PostWorking_9.formatMinutesSeconds(ms: setEndTimeMs - setStartTimeMs)
    }

    var averageDurationText: String {
        guard hasData else { return "－" }
        let totalMs = barData.reduce(0.0) { $0 + $1.seconds * 1000 }
        return PostWorking_9.formatSeconds(ms: totalMs / Double(reps))
    }

    static func compute(index: Int, treatmentResult: TreatmentResult, repsPerSet: Int) -> PostWorking9GroupStats {
        let reps = treatmentResult.reps.indices.contains(index) ? treatmentResult.reps[index] : 0
        let startMs = treatmentResult.set_start_time.indices.contains(index) ? treatmentResult.set_start_time[index] : 0
        let endMs = treatmentResult.set_end_time.indices.contains(index) ? treatmentResult.set_end_time[index] : 0

        let sliceStart = index * repsPerSet
        let sliceEnd = min(sliceStart + repsPerSet, treatmentResult.extension_length.count)
        let slice = sliceStart < sliceEnd ? Array(treatmentResult.extension_length[sliceStart..<sliceEnd]) : []
        // 只取前 reps 個（實際完成的次數），其餘是 0 補值，不應該畫出來。
        let realValues = Array(slice.prefix(reps))
        let barData = realValues.enumerated().map { i, ms in
            PostWorking9AttemptDuration(attempt: i + 1, seconds: Double(ms) / 1000.0)
        }

        return PostWorking9GroupStats(index: index, reps: reps, setStartTimeMs: startMs, setEndTimeMs: endMs, barData: barData)
    }
}

private struct PostWorking9DonationOverviewCard: View {
    let content: TreatmentContent
    let treatmentResult: TreatmentResult

    @State private var selectedIndex: Int = 0
    @State private var showRetentionDetail = false

    private var groups: [PostWorking9GroupStats] {
        (0..<content.sets).map { PostWorking9GroupStats.compute(index: $0, treatmentResult: treatmentResult, repsPerSet: content.reps) }
    }

    private var selected: PostWorking9GroupStats {
        groups.first(where: { $0.index == selectedIndex }) ?? PostWorking9GroupStats.compute(index: 0, treatmentResult: treatmentResult, repsPerSet: content.reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                HStack(spacing: 12) {
                    ForEach(groups, id: \.index) { group in
                        Button {
                            selectedIndex = group.index
                        } label: {
                            Text(group.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(group.index == selectedIndex ? Color.black : Color.white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(group.index == selectedIndex ? Color.white : Color.clear)
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(!selected.hasData)
                .opacity(selected.hasData ? 1 : 0.4)
            }

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(selected.totalTimeText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(selected.reps) 次")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("本組平均部分蹲時長")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(selected.averageDurationText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Chart(selected.barData) { point in
                BarMark(
                    x: .value("次數", point.attempt),
                    y: .value("單次部分蹲時長（秒）", point.seconds),
                    width: .fixed(20)
                )
                .foregroundStyle(Color.white.opacity(0.85))
                .cornerRadius(2)
            }
            .chartXScale(domain: 0.5...(Double(content.reps) + 0.5))
            .chartYScale(domain: 0...7)
            .chartXAxis {
                AxisMarks(values: Array(1...content.reps)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.2))
                    AxisTick().foregroundStyle(Color.white.opacity(0.4))
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0...7)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.2))
                    AxisTick().foregroundStyle(Color.white.opacity(0.4))
                    AxisValueLabel()
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .chartXAxisLabel(alignment: .center) {
                Text("次數")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text("單次部分蹲時長（秒）")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(height: 200)
        }
        .padding(20)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15)))
        .fullScreenCover(isPresented: $showRetentionDetail) {
            PostWorking9RetentionDetailSheet(
                treatmentResultId: treatmentResult.id ?? 0,
                setStartTimeMs: selected.setStartTimeMs,
                setEndTimeMs: selected.setEndTimeMs
            )
        }
    }
}

// MARK: - Knee Angle Detail

private struct PostWorking9KneeAnglePoint: Identifiable {
    let time: Double
    let angle: Double
    var id: Double { time }
}

private struct PostWorking9RetentionCard: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    /// 不預先讀取進記憶體：只有這個畫面真的顯示出來（也就是使用者點了「檢視」）才查詢，
    /// 用帶時間範圍的查詢函式只查當下這一組，不會撈其他組別的資料。
    @State private var dataPoints: [PostWorking9KneeAnglePoint] = []

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
                .foregroundStyle(Color.black)
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
                PostWorking9KneeAnglePoint(time: Double(row.timestamp - Int64(setStartTimeMs)) / 1000.0, angle: row.angle)
            }
        }
    }
}

private struct PostWorking9RetentionDetailSheet: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.97, green: 0.97, blue: 0.99).ignoresSafeArea()

            PostWorking9RetentionCard(treatmentResultId: treatmentResultId, setStartTimeMs: setStartTimeMs, setEndTimeMs: setEndTimeMs)
                .padding(28)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
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
    PostWorking_9(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 9,
            sets: 2, set_rest_time: 10,
            reps: 2,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 1500,
        totalReps: 12,
        totalElapsedSeconds: 245,
        blueHitCount: 5,
        redHitCount: 4,
        yellowHitCount: 3,
        treatmentResult: TreatmentResult(
            treatment_id: 1,
            treatment_content_id: 9,
            reps: [2, 2],
            extension_length: [3000, 4000, 2500, 5000],
            set_start_time: [now, now + 200_000],
            set_end_time: [now + 180_000, now + 380_000],
            date: now
        )
    )
}

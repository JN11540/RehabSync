import SwiftUI
import Charts

struct PostWorking_12: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalSets: Int
    let totalElapsedSeconds: Int
    let comingMoodCount: Int
    let badMoodCount: Int
    let angryMoodCount: Int
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

    @State private var showReturnConfirm = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            PostWorking12Header()
                            PostWorking12StatRow(treatmentResult: treatmentResult, onRequestReturn: { showReturnConfirm = true })

                            PostWorking12DonationOverviewCard(content: content, treatmentResult: treatmentResult)
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

                PostWorking12ReturnConfirmDialog(
                    onCancel: { showReturnConfirm = false },
                    onConfirm: onReturnToDashboard
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct PostWorking12Header: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你好棒！")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 20))
                    .foregroundStyle(PostWorking_12.mutedText)
            }

            Spacer()
        }
    }
}

// MARK: - Stat Row

private struct PostWorking12Stat {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let change: String
    let isPositive: Bool
    let note: String
}

/// 頂部統計卡：只有「總時間」「總次數」兩項——`Working12`（登階）的 `extension_length` 永遠是 0（不計算），
/// 沒有真實數字可以顯示「單次時長」，比照 `postworking12-realdata-plan.md` 第 2 節的決定直接省略第三張卡，
/// 不用其他數字頂替，也不強行保留空白佔位。
private struct PostWorking12StatRow: View {
    let treatmentResult: TreatmentResult
    let onRequestReturn: () -> Void

    /// 「第一組開始」到「最後一組結束」的絕對時間差（毫秒），天然包含組間休息時間。
    private var totalTimeText: String {
        let firstStart = treatmentResult.set_start_time.first(where: { $0 > 0 }) ?? 0
        let lastEnd = treatmentResult.set_end_time.last(where: { $0 > 0 }) ?? 0
        return PostWorking_12.formatMinutesSeconds(ms: max(0, lastEnd - firstStart))
    }

    private var totalReps: Int {
        treatmentResult.reps.reduce(0, +)
    }

    private var stats: [PostWorking12Stat] {
        [
            PostWorking12Stat(icon: "clock.fill", color: PostWorking_12.midPurple, label: "總時間", value: totalTimeText, change: "", isPositive: true, note: ""),
            PostWorking12Stat(icon: "repeat.circle.fill", color: PostWorking_12.blue, label: "總次數", value: "\(totalReps) 次", change: "", isPositive: true, note: "")
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(stats, id: \.label) { stat in
                PostWorking12StatCard(stat: stat)
            }

            // `Working12` 沒有「單次時長」可顯示的第三張統計卡，但版面上仍要湊滿 4 張卡（跟 `PostWorking_9`
            // 一樣的卡片大小／排版），所以放一張外觀跟其他卡片一致（白底、圓角、邊框）但內容空白的卡片。
            Color.white
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))

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

/// 「回到總覽」的確認視窗：以小視窗疊在目前這頁上面顯示，比照 `PostWorking_9` 的做法，
/// 不用 `.fullScreenCover` 另外跳出一個全白頁面。
private struct PostWorking12ReturnConfirmDialog: View {
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
                        .background(PostWorking_12.darkPurple)
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
                    .foregroundStyle(PostWorking_12.darkPurple)
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

private struct PostWorking12StatCard: View {
    let stat: PostWorking12Stat

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
                .foregroundStyle(PostWorking_12.mutedText)
            Text(stat.value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.black)

            if !stat.change.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: stat.isPositive ? "arrow.up" : "arrow.down")
                    Text(stat.change)
                    Text(stat.note)
                        .foregroundStyle(PostWorking_12.mutedText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stat.isPositive ? PostWorking_12.green : PostWorking_12.pink)
            } else if !stat.note.isEmpty {
                Text(stat.note)
                    .font(.system(size: 11))
                    .foregroundStyle(PostWorking_12.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Group Stats (Set Tabs)

private struct PostWorking12AttemptDuration: Identifiable {
    let attempt: Int
    let seconds: Double
    var id: Int { attempt }
}

/// 一組的統計資料，從 `treatmentResult` 依索引現算。**不做「本組平均部分蹲時長」文字**（`Working12` 的
/// `extension_length` 永遠是 0，沒有真實數字可以顯示這個平均值），但 `barData` 保留、邏輯逐字比照
/// `PostWorking9GroupStats.compute`——柱狀圖只是版面上的裝飾用途，不顯示座標軸名稱，見
/// `PostWorking12DonationOverviewCard` 的 `Chart`。
private struct PostWorking12GroupStats {
    let index: Int
    let reps: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int
    let barData: [PostWorking12AttemptDuration]

    /// 「這組從未開始」跟「這組有開始／結束但 0 次完成」視為同一種狀況。
    var hasData: Bool { reps > 0 }

    var label: String { "第 \(index + 1) 組" }

    var totalTimeText: String {
        guard hasData else { return "－" }
        return PostWorking_12.formatMinutesSeconds(ms: setEndTimeMs - setStartTimeMs)
    }

    static func compute(index: Int, treatmentResult: TreatmentResult, repsPerSet: Int) -> PostWorking12GroupStats {
        let reps = treatmentResult.reps.indices.contains(index) ? treatmentResult.reps[index] : 0
        let startMs = treatmentResult.set_start_time.indices.contains(index) ? treatmentResult.set_start_time[index] : 0
        let endMs = treatmentResult.set_end_time.indices.contains(index) ? treatmentResult.set_end_time[index] : 0

        let sliceStart = index * repsPerSet
        let sliceEnd = min(sliceStart + repsPerSet, treatmentResult.extension_length.count)
        let slice = sliceStart < sliceEnd ? Array(treatmentResult.extension_length[sliceStart..<sliceEnd]) : []
        // 只取前 reps 個（實際完成的次數），其餘是 0 補值，不應該畫出來。
        let realValues = Array(slice.prefix(reps))
        let barData = realValues.enumerated().map { i, ms in
            PostWorking12AttemptDuration(attempt: i + 1, seconds: Double(ms) / 1000.0)
        }

        return PostWorking12GroupStats(index: index, reps: reps, setStartTimeMs: startMs, setEndTimeMs: endMs, barData: barData)
    }
}

private struct PostWorking12DonationOverviewCard: View {
    let content: TreatmentContent
    let treatmentResult: TreatmentResult

    @State private var selectedIndex: Int = 0
    @State private var showRetentionDetail = false

    private var groups: [PostWorking12GroupStats] {
        (0..<content.sets).map { PostWorking12GroupStats.compute(index: $0, treatmentResult: treatmentResult, repsPerSet: content.reps) }
    }

    private var selected: PostWorking12GroupStats {
        groups.first(where: { $0.index == selectedIndex }) ?? PostWorking12GroupStats.compute(index: 0, treatmentResult: treatmentResult, repsPerSet: content.reps)
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
                                .foregroundStyle(group.index == selectedIndex ? Color.white : PostWorking_12.mutedText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(group.index == selectedIndex ? PostWorking_12.darkPurple : Color.clear)
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
                        .foregroundStyle(PostWorking_12.mutedText)
                }
                .buttonStyle(.plain)
                .disabled(!selected.hasData)
                .opacity(selected.hasData ? 1 : 0.4)
            }

            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_12.mutedText)
                    Text(selected.totalTimeText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_12.mutedText)
                    Text("\(selected.reps) 次")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }

            // 柱狀圖只是版面裝飾，不顯示縱軸／橫軸名稱（`Working12` 沒有可標示單位的「單次時長」數據）。
            HStack(alignment: .top, spacing: 20) {
                Chart(selected.barData) { point in
                    BarMark(
                        x: .value("次數", point.attempt),
                        y: .value("秒數", point.seconds),
                        width: .fixed(22)
                    )
                    .foregroundStyle(PostWorking_12.darkPurple)
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
            PostWorking12RetentionDetailSheet(
                treatmentResultId: treatmentResult.id ?? 0,
                setStartTimeMs: selected.setStartTimeMs,
                setEndTimeMs: selected.setEndTimeMs
            )
        }
    }
}

// MARK: - Knee Angle Detail

private struct PostWorking12KneeAnglePoint: Identifiable {
    let time: Double
    let angle: Double
    var id: Double { time }
}

private struct PostWorking12RetentionCard: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    /// 不預先讀取進記憶體：只有這個畫面真的顯示出來（也就是使用者點了「檢視」）才查詢，
    /// 用帶時間範圍的查詢函式只查當下這一組，不會撈其他組別的資料。
    @State private var dataPoints: [PostWorking12KneeAnglePoint] = []

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
                .foregroundStyle(PostWorking_12.darkPurple)
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
                PostWorking12KneeAnglePoint(time: Double(row.timestamp - Int64(setStartTimeMs)) / 1000.0, angle: row.angle)
            }
        }
    }
}

// MARK: - EXG Trend Charts

private struct PostWorking12ExgPoint: Identifiable {
    let time: Double
    let uv: Double
    var id: Double { time }
}

/// 大腿／小腿、channel 0／1 共用的 EXG 趨勢圖卡片：不預先讀取進記憶體，只有使用者在「檢視」視窗點選
/// 對應分頁、這張卡片才會被建立出來（見 `PostWorking12RetentionDetailSheet`），建立後才用時間範圍查這一組
/// 的區間，換算 μV 的係數跟匯出 CSV（`GameDataExporter`）用同一個常數。
private struct PostWorking12ExgCard: View {
    let title: String
    let treatmentResultId: Int64
    let deviceId: Int64?
    let channel: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    @State private var dataPoints: [PostWorking12ExgPoint] = []

    private var durationSeconds: Double {
        max(0.001, Double(setEndTimeMs - setStartTimeMs) / 1000.0)
    }

    /// 分頁切換時（例如大腿 Ch0 → 大腿 Ch1）`deviceId` 可能不變，只有 `channel` 變了；
    /// `.task(id:)` 一定要同時綁 `deviceId` 跟 `channel`，只綁 `deviceId` 會漏掉「同裝置換 channel」這個情境。
    private var queryKey: String { "\(deviceId?.description ?? "nil")-\(channel)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
            }

            Chart(dataPoints) { point in
                LineMark(
                    x: .value("時間（秒）", point.time),
                    y: .value("μV", point.uv)
                )
                .foregroundStyle(PostWorking_12.darkPurple)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: 0...durationSeconds)
            .chartXAxisLabel("時間（秒）", alignment: .center)
            .chartYAxisLabel("μV", position: .leading, alignment: .center)
            .frame(height: 220)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        .task(id: queryKey) {
            dataPoints = []
            guard let deviceId else { return }
            let rows = DeviceViewModel().fetchEXG(
                treatmentResultId: treatmentResultId, deviceId: deviceId, channel: channel,
                from: Int64(setStartTimeMs), to: Int64(setEndTimeMs)
            )
            let uvValues = rows.map { Double($0.value) * GameDataExporter.exgMicrovoltScale }
            guard let (avgValues, centerIndices) = try? EMGAlgo.movingAverage(uv: uvValues) else { return }
            let sampleRate = 32.0
            dataPoints = zip(centerIndices, avgValues).map { center, avg in
                PostWorking12ExgPoint(time: center / sampleRate, uv: avg)
            }
        }
    }
}

private struct PostWorking12RetentionDetailSheet: View {
    let treatmentResultId: Int64
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    @Environment(\.dismiss) private var dismiss
    @State private var thighDeviceId: Int64?
    @State private var calfDeviceId: Int64?
    /// `nil` = 沒有任何分頁被選中（預設狀態，底下完全空白，不查詢任何 EXG 資料）。
    @State private var selectedExgChannel: Int? = nil

    private var exgTabs: [(title: String, deviceId: Int64?, channel: Int)] {
        [
            ("大腿通道 0", thighDeviceId, 0),
            ("大腿通道 1", thighDeviceId, 1),
            ("小腿通道 0", calfDeviceId, 0),
            ("小腿通道 1", calfDeviceId, 1)
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PostWorking_12.panelBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    PostWorking12RetentionCard(treatmentResultId: treatmentResultId, setStartTimeMs: setStartTimeMs, setEndTimeMs: setEndTimeMs)

                    HStack(spacing: 12) {
                        ForEach(exgTabs.indices, id: \.self) { index in
                            Button {
                                selectedExgChannel = index
                            } label: {
                                Text(exgTabs[index].title)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(selectedExgChannel == index ? Color.white : PostWorking_12.mutedText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedExgChannel == index ? PostWorking_12.darkPurple : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    if let selectedExgChannel, exgTabs.indices.contains(selectedExgChannel) {
                        let tab = exgTabs[selectedExgChannel]
                        PostWorking12ExgCard(title: tab.title, treatmentResultId: treatmentResultId, deviceId: tab.deviceId, channel: tab.channel, setStartTimeMs: setStartTimeMs, setEndTimeMs: setEndTimeMs)
                    }
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
                    .foregroundStyle(PostWorking_12.darkPurple)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .onAppear {
            let deviceVM = DeviceViewModel()
            let side = deviceVM.fetchAnySide() ?? 0
            thighDeviceId = deviceVM.fetch(side: side, limb: 0)?.id
            calfDeviceId = deviceVM.fetch(side: side, limb: 1)?.id
        }
    }
}

#Preview {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    PostWorking_12(
        content: TreatmentContent(
            treatment_id: 1, exercise_id: 12,
            sets: 2, set_rest_time: 10,
            reps: 5,
            date: Int(Date().timeIntervalSince1970)
        ),
        exercise: nil,
        totalCoins: 0,
        totalSets: 2,
        totalElapsedSeconds: 120,
        comingMoodCount: 0,
        badMoodCount: 0,
        angryMoodCount: 0,
        treatmentResult: TreatmentResult(
            treatment_id: 1,
            treatment_content_id: 12,
            reps: [5, 3],
            extension_length: [0, 0, 0, 0, 0, 0, 0, 0],
            set_start_time: [now, now + 200_000],
            set_end_time: [now + 180_000, now + 380_000],
            date: now
        ),
        onReturnToDashboard: {}
    )
}

import SwiftUI
import Charts

struct PostWorking_2: View {
    let content: TreatmentContent
    let exercise: Exercise?
    let totalCoins: Int
    let totalReps: Int
    let totalElapsedSeconds: Int
    let bigFishCaught: Int
    let middleFishCaught: Int
    let smallFishCaught: Int
    let treatmentResult: TreatmentResult
    let onReturnToDashboard: () -> Void

    /// 毫秒轉成「X 分 YY 秒」，`ms <= 0` 一律視為沒有資料。
    fileprivate static func formatMinutesSeconds(ms: Int) -> String {
        guard ms > 0 else { return "－" }
        let totalSeconds = ms / 1000
        return String(format: "%d 分 %02d 秒", totalSeconds / 60, totalSeconds % 60)
    }

    // `formatSeconds(ms:)`（毫秒 → 「X.X 秒」）已隨 §11.1／§11.2 移除 ——
    // 它的兩個使用者「整局平均伸展時長」與「本組平均伸直時長」都不在了。
    // `PostWorking_9／22` 的同名函式後來也一併移除（動作 12 本來就沒有）。

    fileprivate static let darkPurple = Color(red: 0.30, green: 0.16, blue: 0.65)
    fileprivate static let midPurple = Color(red: 0.45, green: 0.35, blue: 0.85)
    fileprivate static let lightPurple = Color(red: 0.94, green: 0.92, blue: 0.99)
    fileprivate static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.99)
    fileprivate static let mutedText = Color(red: 0.55, green: 0.56, blue: 0.62)
    fileprivate static let green = Color(red: 0.20, green: 0.70, blue: 0.45)
    fileprivate static let blue = Color(red: 0.25, green: 0.55, blue: 0.95)
    fileprivate static let orange = Color(red: 0.95, green: 0.65, blue: 0.20)
    fileprivate static let pink = Color(red: 0.90, green: 0.30, blue: 0.45)
    fileprivate static let teal = Color(red: 0.35, green: 0.80, blue: 0.75)
    fileprivate static let yellow = Color(red: 0.95, green: 0.75, blue: 0.30)

    @State private var showReturnConfirm = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            PostWorking2Header()
                            PostWorking2StatRow(treatmentResult: treatmentResult, onRequestReturn: { showReturnConfirm = true })

                            // 🔴 不可以加 `.frame(maxHeight: .infinity)`（§11.5）——
                            // 那會把卡片撐滿畫面高度、內容再多也不長高，外層 ScrollView
                            // 就永遠沒有東西可捲。卡片高度必須由內容決定。
                            PostWorking2DonationOverviewCard(content: content, treatmentResult: treatmentResult)
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

                PostWorking2ReturnConfirmDialog(
                    onCancel: { showReturnConfirm = false },
                    onConfirm: onReturnToDashboard
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct PostWorking2Header: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你好棒！")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("來看看遊戲結果吧！")
                    .font(.system(size: 20))
                    .foregroundStyle(PostWorking_2.mutedText)
            }

            Spacer()
        }
    }
}

// MARK: - Stat Row

private struct PostWorking2Stat {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let change: String
    let isPositive: Bool
    let note: String
}

private struct PostWorking2StatRow: View {
    let treatmentResult: TreatmentResult
    let onRequestReturn: () -> Void

    /// 「第一組開始」到「最後一組結束」的絕對時間差（毫秒），天然包含組間休息時間。
    private var totalTimeText: String {
        let firstStart = treatmentResult.set_start_time.first(where: { $0 > 0 }) ?? 0
        let lastEnd = treatmentResult.set_end_time.last(where: { $0 > 0 }) ?? 0
        return PostWorking_2.formatMinutesSeconds(ms: max(0, lastEnd - firstStart))
    }

    private var totalReps: Int {
        treatmentResult.reps.reduce(0, +)
    }

    /// 這一場**當時**的目標角度，讀 `treatment_result.target_angle`（migration v13）。
    ///
    /// 🔴 **不是讀 `exercise.target_angle`。** 那是「現在設定的值」，可編輯 ——
    /// 一次 `UPDATE` 就會讓所有歷史場次的卡片跟著變。這一欄是遊戲開始時寫下的快照，
    /// 之後不會再變（working2-database-port-plan.md §22.5）。
    ///
    /// ⚠️ `0` = **這一場沒有記錄目標角度**（v13 之前的舊場次，migration 刻意不回填 ——
    /// 當時的門檻寫死在當時那一版程式裡，已經無從得知）。顯示「－」，不是「0 度」。
    ///
    /// 🔴 這裡**不需要** `Exercise.fallbackTargetAngle`：遊戲當時若走了保底值，
    /// 那個值已經被寫進快照，讀出來就是它。顯示端再算一次只會多一個算錯的地方。
    ///
    /// ⚠️ `target_angle` 是 `Double`（欄位是 INTEGER，型別刻意不一致，§22.3.1），
    /// 所以要用 `String(format:)`，字串插值會印成「45.0 度」。
    private var targetAngleText: String {
        guard treatmentResult.target_angle > 0 else { return "－" }
        return String(format: "%.0f 度", treatmentResult.target_angle)
    }

    private var stats: [PostWorking2Stat] {
        [
            PostWorking2Stat(icon: "clock.fill", color: PostWorking_2.midPurple, label: "總時間", value: totalTimeText, change: "", isPositive: true, note: ""),
            PostWorking2Stat(icon: "repeat.circle.fill", color: PostWorking_2.blue, label: "總次數", value: "\(totalReps) 次", change: "", isPositive: true, note: ""),
            PostWorking2Stat(icon: "figure.flexibility", color: PostWorking_2.green, label: "目標角度（膝屈曲角）", value: targetAngleText, change: "", isPositive: true, note: "")
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(stats, id: \.label) { stat in
                PostWorking2StatCard(stat: stat)
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

/// 「回到總覽」的確認視窗：以小視窗疊在目前這頁上面顯示（見呼叫端 `PostWorking_2` 的 `showReturnConfirm` 遮罩），
/// 不再用 `.fullScreenCover` 另外跳出一個全白頁面。
private struct PostWorking2ReturnConfirmDialog: View {
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
                        .background(PostWorking_2.darkPurple)
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
                    .foregroundStyle(PostWorking_2.darkPurple)
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

private struct PostWorking2StatCard: View {
    let stat: PostWorking2Stat

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
                .foregroundStyle(PostWorking_2.mutedText)
            Text(stat.value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.black)

            if !stat.change.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: stat.isPositive ? "arrow.up" : "arrow.down")
                    Text(stat.change)
                    Text(stat.note)
                        .foregroundStyle(PostWorking_2.mutedText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stat.isPositive ? PostWorking_2.green : PostWorking_2.pink)
            } else if !stat.note.isEmpty {
                Text(stat.note)
                    .font(.system(size: 11))
                    .foregroundStyle(PostWorking_2.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
    }
}

// MARK: - Group Overview (Angle Trend Charts)

/// 一組的統計資料，從 `treatmentResult` 依索引現算。
///
/// §11.2 之後**不再攜帶任何 `extension_length` 衍生資料** —— 原本的
/// `barData`（每次伸直秒數）與 `averageDurationText`（本組平均伸直時長）
/// 隨著柱狀圖與第三欄統計一起移除。
///
/// ⚠️ `extension_length` 仍然照常寫入資料庫、也仍然出現在匯出的 CSV／JSON，
/// 只是結果頁不再顯示它。不要因為這裡沒用就把 `Working2.recordExtensionLength` 拿掉。
private struct PostWorking2GroupStats {
    let index: Int
    let reps: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    /// 「這組從未開始」跟「這組有開始／結束但 0 次動作完成」視為同一種狀況，統一用這個判斷。
    var hasData: Bool { reps > 0 }

    var label: String { "第 \(index + 1) 組" }

    var totalTimeText: String {
        guard hasData else { return "－" }
        return PostWorking_2.formatMinutesSeconds(ms: setEndTimeMs - setStartTimeMs)
    }

    /// 兩張趨勢圖共用的 X 軸長度。下限 0.001 避免 `domain: 0...0` 讓 Charts 除以 0。
    var durationSeconds: Double {
        max(0.001, Double(setEndTimeMs - setStartTimeMs) / 1000.0)
    }

    static func compute(index: Int, treatmentResult: TreatmentResult) -> PostWorking2GroupStats {
        let reps = treatmentResult.reps.indices.contains(index) ? treatmentResult.reps[index] : 0
        let startMs = treatmentResult.set_start_time.indices.contains(index) ? treatmentResult.set_start_time[index] : 0
        let endMs = treatmentResult.set_end_time.indices.contains(index) ? treatmentResult.set_end_time[index] : 0
        return PostWorking2GroupStats(index: index, reps: reps, setStartTimeMs: startMs, setEndTimeMs: endMs)
    }
}

private struct PostWorking2DonationOverviewCard: View {
    let content: TreatmentContent
    let treatmentResult: TreatmentResult

    @State private var selectedIndex: Int = 0

    /// 兩張趨勢圖的資料來自 `advanced_statistics` 的**同一批 row**，在這裡查一次、
    /// 拆成兩個陣列往下傳（§11.4）。
    ///
    /// 🔴 不要讓兩個子元件各自查一次 —— 那是同一組時間範圍查兩次一模一樣的東西。
    /// 子元件也不可以把這兩個陣列複製進自己的 `@State` 再用生命週期事件寫入
    /// （第 7.1 節結尾那條警告）：它們必須是單純的傳入參數，父層一變 `Chart` 就重畫。
    @State private var kneePoints: [PostWorking2AnglePoint] = []
    @State private var hipPoints: [PostWorking2AnglePoint] = []

    private var groups: [PostWorking2GroupStats] {
        (0..<content.sets).map { PostWorking2GroupStats.compute(index: $0, treatmentResult: treatmentResult) }
    }

    private var selected: PostWorking2GroupStats {
        groups.first(where: { $0.index == selectedIndex }) ?? PostWorking2GroupStats.compute(index: 0, treatmentResult: treatmentResult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 16) {
                ForEach(groups, id: \.index) { group in
                    Button {
                        selectedIndex = group.index
                    } label: {
                        Text(group.label)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(group.index == selectedIndex ? Color.white : PostWorking_2.mutedText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(group.index == selectedIndex ? PostWorking_2.darkPurple : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // §11.2：原本這裡有第三欄「本組平均伸直時長」，已隨柱狀圖一起移除。
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總時間")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text(selected.totalTimeText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("次數")
                        .font(.system(size: 20))
                        .foregroundStyle(PostWorking_2.mutedText)
                    Text("\(selected.reps) 次")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }

            // §11.3／§11.4：原本是「每次伸直秒數」的柱狀圖，改成兩張時間軸趨勢圖。
            // 兩張圖共用同一組 setStart／setEndTimeMs 與 durationSeconds，上下可直接對照。
            VStack(alignment: .leading, spacing: 24) {
                PostWorking2AngleTrendCard(
                    title: "即時膝屈曲度",
                    yAxisLabel: "膝屈曲度（度）",
                    points: kneePoints,
                    durationSeconds: selected.durationSeconds,
                    // 膝屈曲角：**自動**。伸直到底含校正殘差會落到負值
                    //（實測 −12.7／−15.6），固定 0...90 會把負的部分裁掉，
                    // 看起來像貼在軸底的平線 —— 而那正是使用者最在意的「有沒有伸直」那一段。
                    yDomain: nil
                )
                PostWorking2AngleTrendCard(
                    title: "即時髖屈曲角",
                    yAxisLabel: "髖屈曲角（度）",
                    points: hipPoints,
                    durationSeconds: selected.durationSeconds,
                    // 髖屈曲角：固定 **0...180**。坐姿 TKE 全程大腿水平（≈ 90°）幾乎不動，
                    // 自動範圍會把 89.6～90.4 這種窄值域拉滿整個軸高、看起來像劇烈震盪。
                    // 固定成 0...180 之後，這條線就會如實地呈現成「一條穩定的水平線」，
                    // 真正發生漂移時才看得出來 —— 這張圖的用途本來就是診斷大腿裝置。
                    yDomain: 0...180
                )
            }
        }
        .padding(20)
        .padding(.top, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        // 🔴 一定要 `.task(id:)`，不能用 `.onAppear`（§11.3）——
        // 切換組別分頁時 SwiftUI 視為「同一個畫面身份、只是參數更新」，`.onAppear`
        // 不會再觸發，圖表會卡在第一組的資料，但上方統計已經換成第二組。
        // 這就是第 6.2 節 `deviceId` 那個 bug 的同一種情境。
        //
        // ⚠️ 這推翻了第 4 節「不預先讀取進記憶體」的決定：趨勢圖搬到主畫面之後，
        // 一進結果頁就會查一次、每切一次分頁再查一次。這是需求的必然結果。
        .task(id: selectedIndex) {
            kneePoints = []
            hipPoints = []
            guard selected.hasData else { return }
            let rows = DeviceViewModel().fetchAdvancedStatistics(
                treatmentResultId: treatmentResult.id ?? 0,
                from: Int64(selected.setStartTimeMs),
                to: Int64(selected.setEndTimeMs)
            )
            // 🔴 v11 之前的既有場次 knee_flexion／hip_flexion 恆為 0
            //（ALTER TABLE 的 DEFAULT），折線圖會是一條貼底的直線。
            // 那不是量到 0，是當時沒有記錄這兩個欄位。
            let base = Int64(selected.setStartTimeMs)
            kneePoints = rows.map { PostWorking2AnglePoint(time: Double($0.timestamp - base) / 1000.0, angle: $0.knee_flexion) }
            hipPoints  = rows.map { PostWorking2AnglePoint(time: Double($0.timestamp - base) / 1000.0, angle: $0.hip_flexion) }
        }
    }
}

// MARK: - Angle Trend Charts

private struct PostWorking2AnglePoint: Identifiable {
    let time: Double
    let angle: Double
    var id: Double { time }
}

/// 膝屈曲角／髖屈曲角共用的趨勢圖。
///
/// **純顯示元件，自己不查資料庫** —— 資料由 `PostWorking2DonationOverviewCard`
/// 查一次後當一般參數傳進來（§11.4）。這樣兩張圖只查一次資料庫，
/// 也避開了「子元件把參數複製進 @State、父層更新後不重畫」那個反覆踩到的 bug。
///
/// 取代了原本的 `PostWorking2RetentionCard`（第 4 節）：那個元件自己在 `.onAppear`
/// 查資料，搬到主畫面後切換組別分頁不會重查，所以沒有沿用而是改寫成這個版本。
private struct PostWorking2AngleTrendCard: View {
    let title: String
    let yAxisLabel: String
    let points: [PostWorking2AnglePoint]
    let durationSeconds: Double
    /// `nil` = 不寫 `.chartYScale(domain:)`，讓 Charts 依實際資料自動決定範圍。
    ///
    /// 動作 2 的兩張圖用相反的設定（§11.4，2026-08-23 調整）：
    /// - **膝屈曲角 → `nil`（自動）**：主圖，伸直到底會落到負值（實測 −12.7／−15.6），
    ///   固定範圍會裁掉負的那一段，而那正是使用者最在意的部分。
    /// - **髖屈曲角 → `0...180`（固定）**：副圖，坐姿下幾乎不動（≈ 90°），
    ///   自動範圍會把零點幾度的雜訊放大成假震盪；固定範圍才看得出「穩定」與「漂移」的差別。
    ///
    /// ⚠️ 兩張圖的 Y 軸刻度因此不同，**不能用線的高低互相比較**，判讀只能看實際數字。
    /// 自動那張還會**每組刻度都不一樣**，切換組別分頁時線的形狀相似不代表幅度相同。
    let yDomain: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
            }

            chart
                .chartXScale(domain: 0...durationSeconds)
                .chartXAxisLabel("時間（秒）", alignment: .center)
                .chartYAxisLabel(yAxisLabel, position: .leading, alignment: .center)
                .frame(height: 220)
        }
    }

    /// `.chartYScale` 沒有「傳 nil 就當作沒寫」的用法，只能靠分支決定要不要套。
    @ViewBuilder
    private var chart: some View {
        let base = Chart(points) { point in
            LineMark(
                x: .value("時間（秒）", point.time),
                y: .value(yAxisLabel, point.angle)
            )
            .foregroundStyle(PostWorking_2.darkPurple)
            .interpolationMethod(.catmullRom)
        }
        if let yDomain {
            base.chartYScale(domain: yDomain)
        } else {
            base
        }
    }
}

#Preview {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    PostWorking_2(
        content: TreatmentContent(treatment_id: 1, exercise_id: 2, sets: 3, set_rest_time: 30, reps: 10, date: Int(Date().timeIntervalSince1970)),
        exercise: nil,
        totalCoins: 120,
        totalReps: 30,
        totalElapsedSeconds: 600,
        bigFishCaught: 5,
        middleFishCaught: 10,
        smallFishCaught: 15,
        treatmentResult: TreatmentResult(
            treatment_id: 1,
            treatment_content_id: 2,
            reps: [10, 10, 10],
            extension_length: Array(repeating: 5000, count: 30),
            set_start_time: [now, now + 200_000, now + 400_000],
            set_end_time: [now + 180_000, now + 380_000, now + 580_000],
            date: now,
            exercise_id: 2,
            target_angle: 45
        ),
        onReturnToDashboard: {}
    )
}

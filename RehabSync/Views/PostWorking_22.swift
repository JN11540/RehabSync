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

    // `formatSeconds(ms:)` 已隨 §4 移除 —— 它的兩個使用者
    // 「整局平均弓步維持時長」與「本組平均弓步維持時長」都不在了。

    @State private var showReturnConfirm = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            PostWorking22Header()
                            PostWorking22StatRow(treatmentResult: treatmentResult, onRequestReturn: { showReturnConfirm = true })

                            // 🔴 不可以加 `.frame(maxHeight: .infinity)`（§4.4）——
                            // 那會把卡片撐滿畫面高度、內容再多也不長高，外層 ScrollView
                            // 就永遠沒有東西可捲。卡片高度必須由內容決定。
                            PostWorking22OverviewCard(content: content, treatmentResult: treatmentResult)
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

    private var stats: [PostWorking22Stat] {
        [
            PostWorking22Stat(icon: "clock.fill", color: PostWorking_22.midPurple, label: "總時間", value: totalTimeText, change: "", isPositive: true, note: ""),
            PostWorking22Stat(icon: "repeat.circle.fill", color: PostWorking_22.blue, label: "總次數", value: "\(totalReps) 次", change: "", isPositive: true, note: ""),
            PostWorking22Stat(icon: "figure.strengthtraining.functional", color: PostWorking_22.green, label: "目標角度（髖屈曲角）", value: targetAngleText, change: "", isPositive: true, note: "")
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

// MARK: - Group Overview (Angle Trend Charts)

/// 一組的統計資料，從 `treatmentResult` 依索引現算。
///
/// §4 之後**不再攜帶任何 `extension_length` 衍生資料** —— 原本的
/// `barData`（柱狀圖用）與「本組平均時長」文字都隨柱狀圖一起移除。
///
/// ⚠️ `extension_length` 仍然照常寫入資料庫、也仍然出現在匯出的 CSV／JSON，
/// 只是結果頁不再顯示它。不要因為這裡沒用就把遊戲畫面的寫入拿掉。
private struct PostWorking22GroupStats {
    let index: Int
    let reps: Int
    let setStartTimeMs: Int
    let setEndTimeMs: Int

    /// 「這組從未開始」跟「這組有開始／結束但 0 次完成」視為同一種狀況，統一用這個判斷。
    var hasData: Bool { reps > 0 }

    var label: String { "第 \(index + 1) 組" }

    var totalTimeText: String {
        guard hasData else { return "－" }
        return PostWorking_22.formatMinutesSeconds(ms: setEndTimeMs - setStartTimeMs)
    }

    /// 兩張趨勢圖共用的 X 軸長度。下限 0.001 避免 `domain: 0...0` 讓 Charts 除以 0。
    var durationSeconds: Double {
        max(0.001, Double(setEndTimeMs - setStartTimeMs) / 1000.0)
    }

    static func compute(index: Int, treatmentResult: TreatmentResult) -> PostWorking22GroupStats {
        let reps = treatmentResult.reps.indices.contains(index) ? treatmentResult.reps[index] : 0
        let startMs = treatmentResult.set_start_time.indices.contains(index) ? treatmentResult.set_start_time[index] : 0
        let endMs = treatmentResult.set_end_time.indices.contains(index) ? treatmentResult.set_end_time[index] : 0
        return PostWorking22GroupStats(index: index, reps: reps, setStartTimeMs: startMs, setEndTimeMs: endMs)
    }
}

private struct PostWorking22OverviewCard: View {
    let content: TreatmentContent
    let treatmentResult: TreatmentResult

    @State private var selectedIndex: Int = 0

    /// 兩張趨勢圖的資料來自 `advanced_statistics` 的**同一批 row**，在這裡查一次、
    /// 拆成兩個陣列往下傳（postworking22-realdata-plan.md §4）。
    ///
    /// 🔴 不要讓兩個子元件各自查一次 —— 那是同一組時間範圍查兩次一模一樣的東西。
    /// 子元件也不可以把這兩個陣列複製進自己的 `@State` 再用生命週期事件寫入：
    /// 它們必須是單純的傳入參數，父層一變 `Chart` 就重畫。
    @State private var hipPoints: [PostWorking22AnglePoint] = []
    @State private var kneePoints: [PostWorking22AnglePoint] = []

    private var groups: [PostWorking22GroupStats] {
        (0..<content.sets).map { PostWorking22GroupStats.compute(index: $0, treatmentResult: treatmentResult) }
    }

    private var selected: PostWorking22GroupStats {
        groups.first(where: { $0.index == selectedIndex }) ?? PostWorking22GroupStats.compute(index: 0, treatmentResult: treatmentResult)
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
                            .foregroundStyle(group.index == selectedIndex ? Color.white : PostWorking_22.mutedText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(group.index == selectedIndex ? PostWorking_22.darkPurple : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
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
            }

            // 原本是「單次時長」的柱狀圖，改成兩張時間軸趨勢圖（postworking22-realdata-plan.md §4）。
            // 兩張圖共用同一組 setStart／setEndTimeMs 與 durationSeconds，上下可直接對照。
            VStack(alignment: .leading, spacing: 24) {
                PostWorking22AngleTrendCard(
                    title: "即時髖屈曲角",
                    yAxisLabel: "髖屈曲角（度）",
                    points: hipPoints,
                    durationSeconds: selected.durationSeconds,
                    // 髖屈曲角：**自動**。這是主圖、活動範圍因人／因動作而異
                    //（站直 0、蹲到底可能破 90），固定範圍不是裁掉就是壓扁。
                    yDomain: nil
                )
                PostWorking22AngleTrendCard(
                    title: "即時膝屈曲角",
                    yAxisLabel: "膝屈曲角（度）",
                    points: kneePoints,
                    durationSeconds: selected.durationSeconds,
                    // 膝屈曲角：固定 **−90...90**。站姿這一欄不是真的膝角度
                    //（見下方型別註解），數值以站直姿勢為 0、**兩個方向都會跑**，
                    // 所以範圍必須對稱含負值 —— 用 0...90 會把一半的資料裁掉。
                    yDomain: -90...90
                )
            }
        }
        .padding(20)
        .padding(.top, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05)))
        // 🔴 一定要 `.task(id:)`，不能用 `.onAppear`（postworking22-realdata-plan.md §4）——
        // 切換組別分頁時 SwiftUI 視為「同一個畫面身份、只是參數更新」，`.onAppear`
        // 不會再觸發，圖表會卡在第一組的資料，但上方統計已經換成第二組。
        //
        // ⚠️ 這推翻了第 4 節「不預先讀取進記憶體」的決定：趨勢圖搬到主畫面之後，
        // 一進結果頁就會查一次、每切一次分頁再查一次。這是需求的必然結果。
        .task(id: selectedIndex) {
            hipPoints = []
            kneePoints = []
            guard selected.hasData else { return }
            let rows = DeviceViewModel().fetchAdvancedStatistics(
                treatmentResultId: treatmentResult.id ?? 0,
                from: Int64(selected.setStartTimeMs),
                to: Int64(selected.setEndTimeMs)
            )
            // 🔴 v11 之前的既有場次 hip_flexion／knee_flexion 恆為 0
            //（ALTER TABLE 的 DEFAULT），折線圖會是一條貼底的直線。
            // 那不是量到 0，是當時沒有記錄這兩個欄位。
            let base = Int64(selected.setStartTimeMs)
            hipPoints  = rows.map { PostWorking22AnglePoint(time: Double($0.timestamp - base) / 1000.0, angle: $0.hip_flexion) }
            kneePoints = rows.map { PostWorking22AnglePoint(time: Double($0.timestamp - base) / 1000.0, angle: $0.knee_flexion) }
        }
    }
}

// MARK: - Angle Trend Charts

private struct PostWorking22AnglePoint: Identifiable {
    let time: Double
    let angle: Double
    var id: Double { time }
}

/// 髖屈曲角／膝屈曲角共用的趨勢圖。
///
/// **純顯示元件，自己不查資料庫** —— 資料由 `PostWorking22OverviewCard` 查一次後
/// 當一般參數傳進來（postworking22-realdata-plan.md §4）。這樣兩張圖只查一次資料庫，也避開了
/// 「子元件把參數複製進 @State、父層更新後不重畫」那個反覆踩到的 bug。
///
/// 取代了原本的 `PostWorking22RetentionCard`：那個元件自己在 `.onAppear` 查資料，
/// 搬到主畫面後切換組別分頁不會重查，所以沒有沿用而是改寫成這個版本。
///
/// **Y 軸兩張圖不同**（2026-08-23 調整）：
/// - **髖屈曲角 → 自動**。主圖，活動範圍因人／因動作而異（站直 0、蹲到底可能破 90），
///   舊版寫死的 `0...90` 會把超出的部分靜默裁掉，看起來像「撐在天花板」的平頂。
/// - **膝屈曲角 → 固定 `−90...90`**。這一欄以站直姿勢為 0、**兩個方向都會跑**，
///   範圍必須對稱含負值；`0...90` 會裁掉一半的資料。
///
/// ⚠️ 兩張圖的 Y 軸刻度因此不同，**不能用線的高低互相比較**。
/// 髖那張還會**每組刻度都不一樣** —— 第 1 組蹲到 95°、第 2 組只到 60°，
/// 兩張圖會「長得一樣高」，比較幅度只能讀 Y 軸數字。
///
/// 🔴 **「膝屈曲角」這個名稱在站姿三動作並不成立。**
/// `knee_flexion` 只有動作 2 是真的膝屈曲角（校正姿勢是大腿水平、小腿垂直，
/// 剛好落在「完全伸直 = 0、垂直 = 90」的刻度上）。9／12／22 的校正姿勢是站直，
/// 同一條公式算出來的數字**沒有膝關節角度的物理意義**，而且 `calfReportSign = −1`
/// 還把它翻過號。它真正的用途是**診斷**：小腿分項在一場訓練中明顯漂移
/// ⇒ 小腿裝置鬆脫／貼歪／訊號漂移，那正是髖屈曲角同時失準的原因。
/// 使用者已知情並決定沿用這個名稱（postworking22-realdata-plan.md §4）—— 不要把畫面上的數字當成膝關節活動度讀。
private struct PostWorking22AngleTrendCard: View {
    let title: String
    let yAxisLabel: String
    let points: [PostWorking22AnglePoint]
    let durationSeconds: Double
    /// `nil` = 不寫 `.chartYScale(domain:)`，讓 Charts 依實際資料自動決定範圍。
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
            .foregroundStyle(PostWorking_22.darkPurple)
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
            date: now,
            exercise_id: 22,
            target_angle: 50
        ),
        onReturnToDashboard: {}
    )
}

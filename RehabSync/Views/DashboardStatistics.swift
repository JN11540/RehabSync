import SwiftUI

// MARK: - Statistics Page（統計頁）
//
// 版面：標題列 → 分頁列 → 分頁內容。
//
// | 分頁 | 內容 |
// |---|---|
// | 數值比較 | 兩張數值卡（本週訓練時長／次數）＋ 訓練時長長條圖 ＋ 訓練次數長條圖 |
// | 執行紀錄表 | 每一週一張表格卡片 |
//
// ✅ **資料全部來自 `StatisticsViewModel`**（statistics-plan.md 階段 1～5），
// 這個檔案裡**沒有任何假資料**。所有區間切割、單位換算、時區處理都在 ViewModel，
// 畫面只負責顯示算好的數字。
//
// 🔴 **不要在這個檔案裡自己算統計。** 四張長條圖 ＋ 兩張卡片 ＋ 執行紀錄表
// 共用 ViewModel 的同一份 buckets——各自算會出現「圖上有、表上沒有」這種對不起來的狀況。
//
// ⚠️ 這個檔案**自帶一份調色盤**（`StatsPalette`），沒有共用 `dashboard.swift` 的
// `DashboardPalette`——後者是 `private`，跨檔案讀不到。

private enum StatsPalette {
    static let indigo = Color(red: 0.36, green: 0.30, blue: 0.88)
    static let indigoDark = Color(red: 0.16, green: 0.13, blue: 0.35)
    static let barLight = Color(red: 0.86, green: 0.85, blue: 0.97)
    static let cardBlue = Color(red: 0.91, green: 0.93, blue: 0.99)
    static let cardPink = Color(red: 0.99, green: 0.91, blue: 0.91)
    static let muted = Color(red: 0.55, green: 0.56, blue: 0.62)
    static let hairline = Color(red: 0.90, green: 0.90, blue: 0.94)
    static let red = Color(red: 0.90, green: 0.28, blue: 0.30)
    /// 「較上週」上升時用（§4.2.1）。先前因為沒有使用者被刪掉，階段 2 加回來。
    static let green = Color(red: 0.13, green: 0.63, blue: 0.42)
    static let pillBackground = Color(red: 0.96, green: 0.96, blue: 0.98)
}

struct DashboardStatisticsContent: View {
    /// 分頁列目前選中的項目。兩個分頁顯示**不同內容**，見 `body`。
    @State private var selectedTab = 0
    /// statistics-plan.md 階段 1 的資料層。
    /// ⚠️ 階段 2 只有下面兩張數值卡片接上它，長條圖與執行紀錄表仍是假資料。
    @State private var statsVM = StatisticsViewModel()

    private let tabs = [
        ("chart.pie", "數值比較"),
        ("list.bullet.rectangle", "執行紀錄表")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                tabRow
                Divider().overlay(StatsPalette.hairline)

                if selectedTab == 0 {
                    // 數值比較
                    summaryRow
                    StatsTrainingChartCard(title: "訓練時長", unit: "分鐘",
                                           metric: .duration, vm: statsVM)
                    StatsTrainingChartCard(title: "訓練次數", unit: "次",
                                           metric: .count, vm: statsVM)
                } else if statsVM.weekBuckets.isEmpty {
                    // 沒設定起訖點、又沒匯入任何菜單時連一張卡片都切不出來（§2.3.1.3）。
                    Text("尚無資料")
                        .font(.system(size: 12))
                        .foregroundStyle(StatsPalette.muted)
                } else {
                    // 執行紀錄表：與長條圖同一份 buckets，未來的週照樣顯示（§4.7.1）。
                    ForEach(statsVM.weekBuckets) { bucket in
                        StatsRecordTableCard(bucket: bucket, vm: statsVM)
                    }
                }
            }
        }
        .onAppear { statsVM.reload() }
    }

    // MARK: 標題列

    private var header: some View {
        HStack(spacing: 12) {
            // ⚠️ 字級／顏色與 `DashboardOverviewContent` 的「總覽」一致，
            // 兩頁切換時標題不可以跳動。
            Text("統計")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.black)

            // 搜尋框、提醒鈴鐺、設定齒輪都已依指示移除，這一列現在只有標題。
            Spacer(minLength: 24)
        }
    }

    // MARK: 分頁列

    private var tabRow: some View {
        HStack(spacing: 28) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    selectedTab = index
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.0)
                                .font(.system(size: 13))
                            Text(tab.1)
                                .font(.system(size: 14, weight: selectedTab == index ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedTab == index ? StatsPalette.indigo : StatsPalette.muted)

                        Rectangle()
                            .fill(selectedTab == index ? StatsPalette.indigo : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer()
        }
    }

    // MARK: 兩張數值卡

    /// ⚠️ 兩張卡片永遠用**自然週**，不跟著起訖點設定走（§2.3）——
    /// 「本週」講的是使用者當下這一週，跟療程第幾週無關。
    /// 🔴 所以有設定 baseline 時，這兩張卡片與下面長條圖的「週」定義不同，
    /// 數字對不上是**預期的**（§6.1.2）。
    private var summaryRow: some View {
        HStack(spacing: 16) {
            StatsSummaryCard(
                title: "本週訓練時長",
                value: Self.durationText(statsVM.thisWeekDurationMs),
                ratio: Self.ratio(current: statsVM.thisWeekDurationMs, previous: statsVM.lastWeekDurationMs),
                tint: StatsPalette.cardBlue
            )
            StatsSummaryCard(
                title: "本週訓練次數",
                value: "\(statsVM.thisWeekReps) 次",
                ratio: Self.ratio(current: statsVM.thisWeekReps, previous: statsVM.lastWeekReps),
                tint: StatsPalette.cardPink
            )
        }
    }

    /// 毫秒 → 「N 小時 M 分」。不足一小時只顯示分鐘。
    /// ⚠️ 沒有訓練時顯示 `0 分`，不是「－」——0 是真的沒訓練，不是沒記錄（§4.1）。
    private static func durationText(_ ms: Int) -> String {
        let totalMinutes = ms / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) 小時 \(minutes) 分" : "\(minutes) 分"
    }

    /// 「較上週」的變化率（§4.2.1）。
    ///
    /// 🔴 **上週為 0 時回 `nil`，不是 0。** 除以零在 `Double` 會得到 `inf`／`nan`，
    /// 格式化出來是 `inf%`，看起來像程式壞掉。`nil` 由膠囊顯示成「－」。
    private static func ratio(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }
}

// MARK: - 共用小元件

/// 白底圓角卡片的共用外框，四個角落與邊框跟參考圖一致。
private struct StatsCard<Content: View>: View {
    var background: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(StatsPalette.hairline, lineWidth: 1)
            )
    }
}

/// 「較上週」漲跌幅膠囊（statistics-plan.md §4.2.1）。
///
/// | 情況 | 顯示 |
/// |---|---|
/// | `ratio == nil`（上週為 0）| 「－」，沒有箭頭 |
/// | `ratio >= 0` | 綠色向上三角 ＋ 百分比 |
/// | `ratio < 0` | 紅色向下三角 ＋ 百分比 |
///
/// ⚠️ **`0%` 歸在「上升」**（綠色向上），不另外做第三種樣式——
/// 0% 的箭頭朝哪邊都沒有意義，多一種狀態只是多一個分支。
private struct StatsDeltaPill: View {
    let ratio: Double?

    var body: some View {
        HStack(spacing: 2) {
            if let ratio {
                Text(String(format: "%.1f%%", abs(ratio) * 100))
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: ratio >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
            } else {
                Text("－")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.7))
        .clipShape(Capsule())
    }

    private var color: Color {
        guard let ratio else { return StatsPalette.muted }
        return ratio >= 0 ? StatsPalette.green : StatsPalette.red
    }
}

private struct StatsSummaryCard: View {
    let title: String
    let value: String
    /// `nil` = 上週為 0，無從比較（§4.2.1）。
    let ratio: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 右上角原本有一條迷你折線圖（參考圖的鋸齒線），已依指示移除。
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(StatsPalette.muted)
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                Spacer()
            }

            // 靠卡片右下角：前置 Spacer 讓這一列吃滿寬度並把內容推到右邊。
            // ⚠️ 沒有 Spacer 的話 HStack 只有內容寬度，會被外層 VStack 的
            // `alignment: .leading` 貼在左邊。
            HStack(spacing: 8) {
                Spacer()
                Text("較上週")
                    .font(.system(size: 11))
                    .foregroundStyle(StatsPalette.muted)
                StatsDeltaPill(ratio: ratio)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 長條圖卡片（訓練時長／訓練次數共用）

/// ⚠️ 兩張卡片各自持有自己的 `selectedRange`，所以**週單位／天單位是分開切換的**——
/// 切上面那張不會連動下面那張。
///
/// 🔴 資料全部來自 `StatisticsViewModel`（statistics-plan.md 階段 3），
/// 這個 struct 只負責畫，不做任何區間切割或單位換算。
private struct StatsTrainingChartCard: View {
    let title: String
    /// 數值後綴：訓練時長是「分鐘」、訓練次數是「次」。
    let unit: String
    let metric: StatsMetric
    let vm: StatisticsViewModel

    @State private var selectedRange = 0
    private let ranges = ["週單位", "天單位"]

    private var isDayMode: Bool { selectedRange == 1 }
    /// 天單位永遠是本週 7 天；週單位依 baseline／`treatment` 表決定根數（§4.3／§4.4）。
    private var buckets: [StatsBucket] { isDayMode ? vm.dayBuckets : vm.weekBuckets }
    /// ⚠️ `nil` = 今天不在範圍內（療程已結束或還沒開始）→ **不 highlight 任何一根**（§4.4.2）。
    private var highlighted: Int? { vm.todayIndex(in: buckets) }
    private var averageTitle: String { isDayMode ? "每天平均" : "每週平均" }

    /// 超過 12 根就改成水平捲動（statistics-plan.md §6.1.1）。
    /// ⚠️ 天單位永遠 7 根，只有週單位會觸發。
    private var needsScroll: Bool { buckets.count > 12 }

    /// 捲動模式下每一欄的固定寬度。
    /// ⚠️ 56 是為了裝下最寬的標籤（`第12週` 被 highlight 時還有左右各 6 的 padding）——
    /// 標籤用了 `fixedSize()`，欄位太窄的話文字會溢出、相鄰兩欄疊在一起。
    private static let scrollColumnWidth: CGFloat = 56

    /// 原始值 → 畫面文字。時長的原始值是**毫秒**，要換算成分鐘。
    private func display(_ raw: Double) -> String {
        switch metric {
        case .duration: "\(Int((raw / 60_000).rounded()))\(unit)"
        case .count:    "\(Int(raw.rounded()))\(unit)"
        }
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

                    ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                        Button { selectedRange = i } label: {
                            Text(r)
                                .font(.system(size: 12, weight: selectedRange == i ? .semibold : .regular))
                                .foregroundStyle(selectedRange == i ? Color.black : StatsPalette.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedRange == i ? StatsPalette.pillBackground : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(averageTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(StatsPalette.muted)
                    Text(display(vm.average(buckets, metric: metric)))
                        .font(.system(size: 22, weight: .bold))
                }

                HStack(spacing: 6) {
                    Circle().fill(StatsPalette.red).frame(width: 6, height: 6)
                    Text("中位數 \(display(vm.median(buckets, metric: metric)))")
                        .font(.system(size: 11))
                        .foregroundStyle(StatsPalette.muted)
                }

                if buckets.isEmpty {
                    // 🔴 `treatment` 表是空的、又沒設定起訖點時會走到這裡（§2.3.1.3）。
                    Text("尚無資料")
                        .font(.system(size: 12))
                        .foregroundStyle(StatsPalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 175)
                } else {
                    chart
                }
            }
        }
    }

    /// 🔴 **只有長條那一列會捲動**，標題／平均／中位數／週單位天單位膠囊都留在外面固定不動
    /// （§6.1.1）——否則捲到一半會看不到自己在看什麼。
    @ViewBuilder
    private var chart: some View {
        if needsScroll {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    barsRow
                        .padding(.horizontal, 2)
                }
                .onAppear {
                    // 打開時自動捲到「今天所在的那一根」（§6.1.1）。
                    // ⚠️ 要等版面算完才捲得到，直接呼叫會沒有作用。
                    // ⚠️ `highlighted` 為 nil（今天不在範圍內）時**不捲**，停在最舊那一端。
                    guard let target = highlighted else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .trailing)
                    }
                }
            }
        } else {
            barsRow
        }
    }

    private var barsRow: some View {
        // ⚠️ 全部長條都是 0 時（只匯入菜單、還沒打過）不能拿來當分母。
        let maxV = max(buckets.map { metric.value(of: $0) }.max() ?? 0, 1)
        // ⚠️ 週單位用 6：`第12週` 較寬，12 欄排下來會擠不下。
        // 天單位只有 7 欄、標籤又短（9/1），可以放寬到 14 才不會太擁擠。
        return HStack(alignment: .bottom, spacing: isDayMode ? 14 : 6) {
            ForEach(buckets) { bucket in
                let isHighlighted = highlighted == bucket.id
                VStack(spacing: 8) {
                    // tooltip 只掛在「今天所在的那一根」上，顯示該根的實際值。
                    // ⚠️ 一定要 fixedSize()：tooltip 比長條本身寬，不加會被欄寬擠成「35…」。
                    Text(display(metric.value(of: bucket)))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(StatsPalette.indigoDark)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .opacity(isHighlighted ? 1 : 0)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHighlighted ? StatsPalette.indigo : StatsPalette.barLight)
                        .frame(height: 120 * CGFloat(metric.value(of: bucket) / maxV))

                    // fixedSize()：理由同上面的 tooltip，不加會被欄寬截成「第12…」。
                    Text(bucket.label)
                        .font(.system(size: 10, weight: isHighlighted ? .semibold : .regular))
                        .fixedSize()
                        .foregroundStyle(isHighlighted ? Color.white : StatsPalette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isHighlighted ? StatsPalette.indigo : Color.clear)
                        .clipShape(Capsule())
                }
                // 捲動模式下每欄固定寬度；不捲動時維持等分填滿。
                .frame(width: needsScroll ? Self.scrollColumnWidth : nil)
                .id(bucket.id)
            }
        }
        .frame(height: 175, alignment: .bottom)
    }
}


// MARK: - 執行紀錄表（表格）

/// 一張週卡片（statistics-plan.md §4.7）。
///
/// 🔴 資料全部來自 `StatisticsViewModel` 的 `weekBuckets`，
/// 與長條圖是**同一份 buckets**——切法一致，不會出現「圖上有、表上沒有」。
private struct StatsRecordTableCard: View {
    let bucket: StatsBucket
    let vm: StatisticsViewModel

    /// ⚠️ **同一天可能有多場**（一天打好幾次遊戲），所以一天可能對應多列。
    /// 編號是**這張卡片內的流水號**，不是 `treatment_result.id`，所以要先排序再編號。
    private var sortedSessions: [StatsSession] {
        bucket.sessions.sorted { $0.date < $1.date }
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(bucket.label)
                    .font(.system(size: 16, weight: .semibold))

                // ⚠️ 標頭用 alignment: .top —— 「運動後疼痛」是兩行，
                // 其餘單行標頭要跟它的第一行對齊，不能垂直置中。
                HStack(alignment: .top, spacing: 0) {
                    headerCell("編號", width: 60)
                    headerCell("日期", width: 100)
                    headerCell("訓練時長", width: 120)
                    headerCell("運動後疼痛\n（0不痛-10最痛）", width: 170)
                    headerCell("備註（身體狀況）", width: 260)
                }
                Divider().overlay(StatsPalette.hairline)

                if sortedSessions.isEmpty {
                    // 🔴 未來的週照樣顯示卡片，但沒有資料列（§4.7.1）。
                    // 留空白會讓人以為載入失敗，所以明講。
                    Text("本週尚無紀錄")
                        .font(.system(size: 12))
                        .foregroundStyle(StatsPalette.muted)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 12))
                                .foregroundStyle(StatsPalette.muted)
                                .frame(width: 60, alignment: .leading)
                            Text(Self.dayText(session.date))
                                .font(.system(size: 12))
                                .frame(width: 100, alignment: .leading)
                            Text(Self.durationText(session.durationMs))
                                .font(.system(size: 12))
                                .frame(width: 120, alignment: .leading)
                            // 🔴 `nil` → 「－」；`0` → 「0」。
                            // 0 是「完全不痛」的有效評分，不能跟「沒記錄」混為一談。
                            Text(session.vas.map(String.init) ?? "－")
                                .font(.system(size: 12))
                                .frame(width: 170, alignment: .leading)
                            Text(vm.noteText(for: session.noteIds))
                                .font(.system(size: 12))
                                .frame(width: 260, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(StatsPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .topLeading)
    }

    private static func dayText(_ ms: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "M/d"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    private static func durationText(_ ms: Int) -> String {
        "\(Int((Double(ms) / 60_000).rounded())) 分鐘"
    }
}

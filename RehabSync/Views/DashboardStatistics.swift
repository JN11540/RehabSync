import SwiftUI

// MARK: - Statistics Page（統計頁）
//
// 版面：標題列 → 分頁列 → 分頁內容。
//
// | 分頁 | 內容 |
// |---|---|
// | 數值比較 | 兩張數值卡（本週訓練時長／場次）＋ 訓練時長長條圖 ＋ 訓練場次長條圖 |
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
                    StatsTrainingChartCard(title: "訓練場次", unit: "場",
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
                                .font(.system(size: 18))
                            Text(tab.1)
                                .font(.system(size: 18, weight: selectedTab == index ? .semibold : .regular))
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

    /// 兩張卡片跟著起訖點設定走（§2.3）：
    ///
    /// | 起訖點設定 | 算的區間 | 標題 |
    /// |---|---|---|
    /// | **有值** | 療程第 N 週（今天所在的那一段）| 「第 N 週訓練時長／場次」|
    /// | 沒有 | 自然週（台北週一～週日）| 「本週訓練時長／場次」|
    ///
    /// 🔴 **標題一定要跟著模式換。** baseline 模式下寫「本週」會不準——
    /// 那一段的起點可能是週三，今天落在療程範圍外時更會是被夾到的
    /// 第 1 週或最後一週（§4.4.1.1），跟「本週」完全無關。
    private var weekPrefix: String {
        statsVM.currentWeekNumber.map { "第\($0)週" } ?? "本週"
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            StatsSummaryCard(
                title: "\(weekPrefix)訓練時長",
                value: Self.durationText(statsVM.thisWeekDurationMs),
                ratio: Self.ratio(current: statsVM.thisWeekDurationMs, previous: statsVM.lastWeekDurationMs),
                tint: StatsPalette.cardBlue
            )
            StatsSummaryCard(
                title: "\(weekPrefix)訓練場次",
                value: "\(statsVM.thisWeekSessions) 場",
                ratio: Self.ratio(current: statsVM.thisWeekSessions, previous: statsVM.lastWeekSessions),
                tint: StatsPalette.cardPink
            )
        }
    }

    /// 毫秒 → 「N 小時 M 分鐘」。不足一小時只顯示分鐘。
    /// ⚠️ 沒有訓練時顯示 `0 分鐘`，不是「－」——0 是真的沒訓練，不是沒記錄（§4.1）。
    private static func durationText(_ ms: Int) -> String {
        // 🔴 **一定要用四捨五入，不能用 `ms / 60_000` 的整數除法。**
        //
        // 這一頁有三個地方把毫秒轉成分鐘：這裡、長條圖的 tooltip／平均
        // （`display`）、執行紀錄表的時長欄。後兩者都是 `.rounded()`，
        // 只有這裡曾經是整數除法（無條件捨去）——同一個 bucket 的
        // 5.6 分鐘會變成卡片「5 分鐘」、長條「6 分鐘」，
        // 看起來像兩邊算出不同的資料，其實只是進位規則不同。
        //
        // ⚠️ 日後再加第四個顯示時長的地方，也要用 `.rounded()`。
        let totalMinutes = Int((Double(ms) / 60_000).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) 小時 \(minutes) 分鐘" : "\(minutes) 分鐘"
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
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: ratio >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 16))
            } else {
                Text("－")
                    .font(.system(size: 16, weight: .semibold))
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
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(StatsPalette.muted)

            // 數值與「較上週」膠囊同一列：數值靠左、漲跌幅靠右。
            // ⚠️ 中間的 Spacer 同時負責「把膠囊推到右邊」與「讓這一列吃滿卡片寬度」。
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.black)
                    // 數值長度會變（「48 次」vs「3 小時 42 分鐘」），
                    // 不加的話窄卡片上會被膠囊擠到換行或截斷。
                    .fixedSize()

                Spacer(minLength: 8)

                Text("較上週")
                    .font(.system(size: 16))
                    .foregroundStyle(StatsPalette.muted)
                    .fixedSize()
                StatsDeltaPill(ratio: ratio)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 長條圖卡片（訓練時長／訓練場次共用）

/// ⚠️ 兩張卡片各自持有自己的 `selectedRange`，所以**週單位／天單位是分開切換的**——
/// 切上面那張不會連動下面那張。
///
/// 🔴 資料全部來自 `StatisticsViewModel`（statistics-plan.md 階段 3），
/// 這個 struct 只負責畫，不做任何區間切割或單位換算。
private struct StatsTrainingChartCard: View {
    let title: String
    /// 數值後綴：訓練時長是「分鐘」、訓練場次是「場」。
    let unit: String
    let metric: StatsMetric
    let vm: StatisticsViewModel

    @State private var selectedRange = 0
    private let ranges = ["週單位", "天單位"]

    /// 使用者點選的長條。`nil` = 沒點過，用預設的「今天那一根」。
    ///
    /// 🔴 **不要把預設值直接寫成今天的索引** —— 那樣 `reload()` 之後根數變了、
    /// 或今天不在範圍內時，這個索引會指向錯的一根。`nil` 代表「跟著今天走」，
    /// 語意才不會過期。
    @State private var selectedBar: Int?

    private var isDayMode: Bool { selectedRange == 1 }
    /// 天單位永遠是本週 7 天；週單位依 baseline／`treatment` 表決定根數（§4.3／§4.4）。
    private var buckets: [StatsBucket] { isDayMode ? vm.dayBuckets : vm.weekBuckets }
    /// 目前深紫色（含 tooltip）的那一根：**使用者點選的優先，否則是今天那一根**。
    ///
    /// ⚠️ `nil` = 沒點過、而且今天不在範圍內（療程已結束或還沒開始）
    /// → **不 highlight 任何一根**（§4.4.2）。這時點一下任何一根就會有了。
    private var highlighted: Int? { selectedBar ?? vm.todayIndex(in: buckets) }
    private var averageTitle: String { isDayMode ? "每天平均" : "每週平均" }

    /// 超過 12 根就改成水平捲動（statistics-plan.md §6.1.1）。
    /// ⚠️ 天單位永遠 7 根，只有週單位會觸發。
    /// 畫面上一次最多顯示幾根長條。超過就固定欄寬、改成左右捲動。
    ///
    /// 🔴 這個數字同時決定**捲動門檻**與**捲動時的欄寬**（欄寬 ＝ 可用寬度 ÷ 9），
    /// 所以「一次剛好看到 9 根」是靠這一個常數保證的，改它就兩邊一起變。
    private static let visibleColumns = 9

    /// 欄與欄的間距。週／天單位一致。
    private static let columnSpacing: CGFloat = 16

    private var needsScroll: Bool { buckets.count > Self.visibleColumns }

    /// 捲動模式下的單欄寬度：可用寬度扣掉 8 個間距後除以 9。
    ///
    /// ⚠️ 不能寫死。先前是固定 80，導致「一次看到幾根」隨畫面寬度浮動。
    private func columnWidth(available: CGFloat) -> CGFloat {
        let gaps = Self.columnSpacing * CGFloat(Self.visibleColumns - 1)
        return max((available - gaps) / CGFloat(Self.visibleColumns), 1)
    }

    /// 長條圖區域的總高度。
    ///
    /// 🔴 **這個數字是加出來的，不是隨便給的**：
    /// tooltip 28（16pt 文字 ＋ 上下各 3 的 padding）
    /// ＋ 間距 8 ＋ 長條最高 120 ＋ 間距 8 ＋ 標籤 28
    /// ＋ 間距 8 ＋ 日期區間 16（12pt 文字）＝ **216**，留 4 的餘裕。
    ///
    /// ⚠️ 外層是 `alignment: .bottom`，所以**高度不夠時是從上面溢出**——
    /// 被切掉的會是 tooltip，不是長條也不是標籤。
    /// 先前這裡是 175（tooltip 與標籤還是 10pt 時算的），字級改成 16 之後
    /// 內容變成 192，最高的那根長條就把 tooltip 頂出去、上半截被切掉。
    /// 🔴 **日後再改 tooltip／標籤字級或長條最大高度，這個數字要跟著重算。**
    private static let chartHeight: CGFloat = 220

    /// 原始值 → 畫面文字。時長的原始值是**毫秒**，要換算成分鐘。
    private func display(_ raw: Double) -> String {
        switch metric {
        case .duration: "\(Int((raw / 60_000).rounded()))\(unit)"
        case .count:    "\(Int(raw.rounded()))\(unit)"
        }
    }

    /// 「每週平均／每天平均」專用的格式（§2.2.2）。
    ///
    /// 🔴 **場次的平均一定要有小數位。** 14 場 ÷ 10 週 ＝ 1.4，
    /// 用 `display` 四捨五入成「1 場」是 **−29%** 的誤差。
    /// ⚠️ **時長維持整數分鐘**，不要一起改——兩者可容忍的誤差量級不同
    /// （分鐘的四捨五入只差幾十秒）。
    private func displayAverage(_ raw: Double) -> String {
        switch metric {
        case .duration: display(raw)
        case .count:    String(format: "%.1f", raw) + unit
        }
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

                    ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                        Button {
                            selectedRange = i
                            // 🔴 換粒度就把選取清掉：週單位的「第 3 根」與天單位的
                            // 「第 3 根」是完全不同的東西，沿用只會指到不相干的一天。
                            selectedBar = nil
                        } label: {
                            Text(r)
                                .font(.system(size: 16, weight: selectedRange == i ? .semibold : .regular))
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
                        .font(.system(size: 16))
                        .foregroundStyle(StatsPalette.muted)
                    Text(displayAverage(vm.average(buckets, metric: metric)))
                        .font(.system(size: 24, weight: .bold))
                }

                if buckets.isEmpty {
                    // 🔴 `treatment` 表是空的、又沒設定起訖點時會走到這裡（§2.3.1.3）。
                    Text("尚無資料")
                        .font(.system(size: 16))
                        .foregroundStyle(StatsPalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 175)
                } else {
                    chart
                }
            }
        }
        // 重新進入統計頁 = 一次新的瀏覽，回到「今天那一根」。
        // ⚠️ 外層 `ScrollView` 用的是一般 `VStack`（非 Lazy），所以這裡只會觸發一次；
        // 若日後改成 `LazyVStack`，捲動時卡片重新出現也會觸發，選取會被莫名清掉。
        .onAppear { selectedBar = nil }
    }

    /// 🔴 **只有長條那一列會捲動**，標題／平均／中位數／週單位天單位膠囊都留在外面固定不動
    /// （§6.1.1）——否則捲到一半會看不到自己在看什麼。
    @ViewBuilder
    private var chart: some View {
        // GeometryReader：欄寬要從「實際可用寬度」除出來，寫死就沒辦法保證一次 9 根。
        GeometryReader { geo in
            if needsScroll {
                scrollingChart(columnWidth: columnWidth(available: geo.size.width))
            } else {
                // ≤ 9 根：不捲動，等分填滿整個寬度。
                barsRow(columnWidth: nil)
            }
        }
        .frame(height: Self.chartHeight)
    }

    private func scrollingChart(columnWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                barsRow(columnWidth: columnWidth)
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
    }

    /// - Parameter columnWidth: `nil` 代表不捲動、等分填滿。
    private func barsRow(columnWidth: CGFloat?) -> some View {
        // ⚠️ 全部長條都是 0 時（只匯入菜單、還沒打過）不能拿來當分母。
        let maxV = max(buckets.map { metric.value(of: $0) }.max() ?? 0, 1)
        // 週／天用同一個間距：一次最多只排 9 欄，週單位不再需要為了塞下 12 欄而縮到 6。
        return HStack(alignment: .bottom, spacing: Self.columnSpacing) {
            ForEach(buckets) { bucket in
                let isHighlighted = highlighted == bucket.id
                VStack(spacing: 8) {
                    // **每一根都顯示自己的值**，不是只有被選取的那一根。
                    // 差別在樣式：選取的是深紫底白字的膠囊，其餘是灰色純文字，
                    // 這樣「哪一根被選取」仍然一眼看得出來（長條顏色 ＋ 標籤膠囊 ＋ 這裡）。
                    // ⚠️ 一定要 fixedSize()：文字比長條本身寬，不加會被欄寬擠成「35…」。
                    Text(display(metric.value(of: bucket)))
                        .font(.system(size: 16, weight: isHighlighted ? .semibold : .regular))
                        .foregroundStyle(isHighlighted ? Color.white : StatsPalette.muted)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isHighlighted ? StatsPalette.indigoDark : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHighlighted ? StatsPalette.indigo : StatsPalette.barLight)
                        .frame(height: 120 * CGFloat(metric.value(of: bucket) / maxV))

                    // fixedSize()：理由同上面的 tooltip，不加會被欄寬截成「第12…」。
                    Text(bucket.label)
                        .font(.system(size: 16, weight: isHighlighted ? .semibold : .regular))
                        .fixedSize()
                        .foregroundStyle(isHighlighted ? Color.white : StatsPalette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isHighlighted ? StatsPalette.indigo : Color.clear)
                        .clipShape(Capsule())

                    // 「第 N 週」看不出是哪幾天，補上實際日期區間。
                    // ⚠️ 只有週單位需要——天單位的標籤本身就是日期（9/1），再加一次是重複。
                    if !isDayMode {
                        Text(statsRangeText(bucket))
                            .font(.system(size: 12))
                            .fixedSize()
                            .foregroundStyle(StatsPalette.muted)
                    }
                }
                // 捲動模式下每欄固定寬度；不捲動時維持等分填滿。
                .frame(width: columnWidth)
                // 🔴 `contentShape` 不能省：值為 0 的長條 `frame(height: 0)`，
                // 沒有這一行就**點不到**——而「這一週沒訓練」正是使用者會想點來確認的情況。
                // 整欄（含 tooltip 位置與標籤）都算命中區，不是只有長條本身。
                .contentShape(Rectangle())
                .onTapGesture { selectedBar = bucket.id }
                .id(bucket.id)
            }
        }
        .frame(height: Self.chartHeight, alignment: .bottom)
    }
}


// MARK: - 執行紀錄表（表格）

/// 一張週卡片（statistics-plan.md §4.7）。
///
/// 🔴 資料全部來自 `StatisticsViewModel` 的 `weekBuckets`，
/// 與長條圖是**同一份 buckets**——切法一致，不會出現「圖上有、表上沒有」。
/// 一段 bucket 涵蓋的日期區間，`MM/DD-MM/DD`。長條標籤與執行紀錄表卡片標題共用。
///
/// 🔴 結束日要用 `end - 1 天`。bucket 是**半開區間** `[start, end)`，
/// `end` 已經是下一段的起點——直接印會變成「08/03-08/10」，
/// 而 08/10 其實屬於下一根。
private func statsRangeText(_ bucket: StatsBucket) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
    formatter.dateFormat = "MM/dd"
    let start = Date(timeIntervalSince1970: TimeInterval(bucket.start) / 1000)
    let last = Date(timeIntervalSince1970: TimeInterval(bucket.end - 86_400_000) / 1000)
    return "\(formatter.string(from: start))-\(formatter.string(from: last))"
}

/// 量出執行紀錄表可用寬度，供比例欄寬使用。
private struct StatsTableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StatsRecordTableCard: View {
    let bucket: StatsBucket
    let vm: StatisticsViewModel

    /// 卡片內容區的實際寬度。
    /// ⚠️ 用 GeometryReader ＋ PreferenceKey **量**，不是拿 GeometryReader 直接包內容——
    /// 表格高度是變動的（列數不固定），包起來會撐不開。
    @State private var tableWidth: CGFloat = 0

    /// 同一天的多場場次。編號與日期在這個群組裡是**合併儲存格**。
    private struct DayGroup: Identifiable {
        /// 台北時區當天 00:00 的毫秒值，同時當分組鍵與 `ForEach` 的 id。
        let id: Int
        let sessions: [StatsSession]
    }

    /// 依「台北時區的日期」分組。
    ///
    /// ⚠️ **同一天可能有多場**（一天打好幾次遊戲）——這正是要合併儲存格的原因。
    /// 🔴 分組鍵一定要用 `Calendar.startOfDay` 搭配 `Asia/Taipei`，
    /// 不能拿 `date / 86_400_000` 去除——那切出來的是 **UTC** 的日界，
    /// 台北時間 08:00 之前的場次會被算到前一天。
    ///
    /// ⚠️ 用 `order` 陣列保留首次出現的順序，不要對 Dictionary 的 key 排序後再組——
    /// 場次已經先依時間排好，跟著它走就是正確的日期順序。
    private var dayGroups: [DayGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

        var order: [Int] = []
        var grouped: [Int: [StatsSession]] = [:]
        for session in bucket.sessions.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(session.date) / 1000))
            let key = Int(day.timeIntervalSince1970) * 1000
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(session)
        }
        return order.map { DayGroup(id: $0, sessions: grouped[$0] ?? []) }
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                // firstTextBaseline：兩段字級差很多（24 / 16），
                // 用預設的置中對齊會讓小的那段看起來浮在半空。
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bucket.label)
                        .font(.system(size: 24, weight: .semibold))
                    Text(statsRangeText(bucket))
                        .font(.system(size: 16))
                        .foregroundStyle(StatsPalette.muted)
                }

                // ⚠️ 標頭用 alignment: .top —— 「運動後疼痛」是兩行，
                // 其餘單行標頭要跟它的第一行對齊，不能垂直置中。
                HStack(alignment: .top, spacing: 0) {
                    headerCell("編號", width: w(Self.rNo))
                    headerCell("日期", width: w(Self.rDate))
                    headerCell("單日訓練時長", width: w(Self.rDayDur))
                    headerCell("動作", width: w(Self.rAction))
                    headerCell("單場訓練時長", width: w(Self.rDuration))
                    headerCell("運動後疼痛\n（0不痛-10最痛）", width: w(Self.rPain))
                    headerCell("備註（身體狀況）", width: w(Self.rNote))
                }
                Divider().overlay(StatsPalette.hairline)

                if dayGroups.isEmpty {
                    // 🔴 未來的週照樣顯示卡片，但沒有資料列（§4.7.1）。
                    // 留空白會讓人以為載入失敗，所以明講。
                    Text("本週尚無紀錄")
                        .font(.system(size: 16))
                        .foregroundStyle(StatsPalette.muted)
                        .padding(.vertical, 12)
                } else {
                    // 🔴 編號是**「這張卡片裡的第幾天」**，不是場次流水號，
                    // 也不是 `treatment_result.id`——一天打三場也只會有一個編號。
                    ForEach(Array(dayGroups.enumerated()), id: \.element.id) { index, group in
                        // alignment: .center ＝ 合併儲存格的垂直置中。
                        // 高度由右邊那疊場次決定，編號與日期自然落在正中間。
                        HStack(alignment: .center, spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 16))
                                .foregroundStyle(StatsPalette.muted)
                                .frame(width: w(Self.rNo), alignment: .leading)
                            Text(Self.dayText(group.id))
                                .font(.system(size: 16))
                                .frame(width: w(Self.rDate), alignment: .leading)
                            // 🔴 單日訓練時長也是**合併格**——它是當天所有場次的加總，
                            // 一天一個值，跟編號／日期同一層，不能放進右邊逐場的那一疊。
                            Text(Self.durationText(group.sessions.reduce(0) { $0 + $1.durationMs }))
                                .font(.system(size: 16))
                                .frame(width: w(Self.rDayDur), alignment: .leading)

                            VStack(spacing: 0) {
                                ForEach(group.sessions) { session in
                                    HStack(spacing: 0) {
                                        // ⚠️ 動作名稱最長 11 字（「大腿後側肌群伸展（一）」），
                                        // 窄畫面塞不下時截斷成「…」，不要讓它折行把整列撐高。
                                        Text(vm.exerciseName(for: session.exerciseId))
                                            .font(.system(size: 16))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: w(Self.rAction), alignment: .leading)
                                        Text(Self.durationText(session.durationMs))
                                            .font(.system(size: 16))
                                            .frame(width: w(Self.rDuration), alignment: .leading)
                                        // 🔴 `nil` → 「－」；`0` → 「0」。
                                        // 0 是「完全不痛」的有效評分，不能跟「沒記錄」混為一談。
                                        Text(session.vas.map(String.init) ?? "－")
                                            .font(.system(size: 16))
                                            .frame(width: w(Self.rPain), alignment: .leading)
                                        Text(vm.noteText(for: session.noteIds))
                                            .font(.system(size: 16))
                                            .frame(width: w(Self.rNote), alignment: .leading)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // 🔴 橫線只畫在**日與日之間**，同一天的多場之間不畫——
                        // 畫下去會從中間切穿合併的編號／日期格，合併就白做了。
                        // 最後一組後面也不畫，否則卡片底部會多一條懸空的線。
                        if index < dayGroups.count - 1 {
                            Divider().overlay(StatsPalette.hairline)
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: StatsTableWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(StatsTableWidthKey.self) { tableWidth = $0 }
        }
    }

    // 欄寬。🔴 **比例制，不是固定 pt。**
    //
    // 先前是寫死的 pt，每加一次欄位、每改一次字級就得重量（已經發生三次）。
    // 七欄之後固定寬度加起來超過 1000pt，窄一點的 iPad 會直接切掉右邊兩欄，
    // 所以改成「量到卡片實際寬度，再按比例分」。
    // ⚠️ 比例加總必須 = 1.0，改任何一個都要同時調另一個。
    private static let rNo: CGFloat = 0.06       // 「編號」／一位數
    private static let rDate: CGFloat = 0.09     // 「日期」／`9/6`
    private static let rDayDur: CGFloat = 0.14   // 「單日訓練時長」（合併格）
    private static let rAction: CGFloat = 0.18   // 「動作」／最長「大腿後側肌群伸展（一）」
    private static let rDuration: CGFloat = 0.14 // 「單場訓練時長」
    private static let rPain: CGFloat = 0.18     // 「（0不痛-10最痛）」，標頭比內容寬
    private static let rNote: CGFloat = 0.21     // 備註，多則以「、」相連

    /// 比例 → 實際寬度。
    /// ⚠️ 第一次 layout 時 `tableWidth` 還是 0，用 700 當底避免那一幀擠成一直條。
    private func w(_ ratio: CGFloat) -> CGFloat { max(tableWidth, 700) * ratio }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 16))
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

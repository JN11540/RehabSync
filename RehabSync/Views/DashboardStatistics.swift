import SwiftUI

// MARK: - Statistics Page（統計頁右側預覽區）
//
// 版面照使用者提供的 dashboard 參考圖搭出來，再依後續指示刪減：
// 標題列（只有標題）→ 分頁列 → 分頁內容。
//
// 分頁內容各不相同：
// - 數值比較：兩張數值卡 ＋ 訓練時長長條圖 ＋ 訓練次數長條圖
// - 執行紀錄表：兩張表格卡片（第一週、第二週）
//
// ⚠️ **已移除的區塊**（使用者指定）：右欄的訂單列表（堆疊長條圖）、月銷售、總訂單、搜尋框，
// 以及分頁列的「分析設定」與「篩選分析」、數值卡的「總客戶數」與兩張卡右上角的迷你折線圖。
// 改名：分頁「平均值」→「執行紀錄表」；數值卡「總銷售額」→「本週訓練時長」、
// 「總訂單數」→「本週訓練次數」、卡片「銷售報表」→「訓練時長」；
// 該卡的區間膠囊「12 個月」→「週單位」、「6 個月」→「天單位」，並移除「30 天」「7 天」。
// 右欄三張卡片全部移除後整欄就空了，所以左右兩欄的 `HStack` 也一併拿掉，
// 剩下的內容改成單欄全寬。
//
// ⚠️ 參考圖裡有**兩張同名的「訂單列表」**——左欄的表格與右欄的堆疊長條圖。
// **保留的是左欄那張表格**，移除的是右欄的圖。
//
// 🔴 **目前全部是靜態假資料**，數字與月份都寫死在這個檔案裡，沒有接任何資料庫查詢。
// 這是刻意的：本輪只做版面，資料來源另議。
//
// ⚠️ 這個檔案**自帶一份調色盤**（`StatsPalette`），沒有共用 `dashboard.swift` 的
// `DashboardPalette` —— 後者是 `private`，跨檔案讀不到。

private enum StatsPalette {
    static let indigo = Color(red: 0.36, green: 0.30, blue: 0.88)
    static let indigoDark = Color(red: 0.16, green: 0.13, blue: 0.35)
    static let barLight = Color(red: 0.86, green: 0.85, blue: 0.97)
    static let cardBlue = Color(red: 0.91, green: 0.93, blue: 0.99)
    static let cardPink = Color(red: 0.99, green: 0.91, blue: 0.91)
    static let muted = Color(red: 0.55, green: 0.56, blue: 0.62)
    static let hairline = Color(red: 0.90, green: 0.90, blue: 0.94)
    static let red = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let pillBackground = Color(red: 0.96, green: 0.96, blue: 0.98)
}

struct DashboardStatisticsContent: View {
    /// 分頁列目前選中的項目。兩個分頁顯示**不同內容**，見 `body`。
    @State private var selectedTab = 0

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
                    StatsTrainingChartCard(title: "訓練時長", unit: "分鐘")
                    // ⚠️ 長條的高度資料與訓練時長**完全相同**，只有標題與單位不同。
                    StatsTrainingChartCard(title: "訓練次數", unit: "次")
                } else {
                    // 執行紀錄表
                    StatsRecordTableCard(title: "第一週", rows: StatsRecordTableCard.week1)
                    StatsRecordTableCard(title: "第二週", rows: StatsRecordTableCard.week2)
                }
            }
        }
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

    /// ⚠️ 數值仍是**假資料**。標題改成訓練語意之後，原本的 `$59,690`／`4,865`
    /// 放在「訓練時長」「訓練次數」底下會前後矛盾，所以一併換成合理的佔位值；
    /// 但它們**沒有接任何查詢**，跟資料庫無關。
    private var summaryRow: some View {
        HStack(spacing: 16) {
            StatsSummaryCard(title: "本週訓練時長", value: "3 小時 42 分",
                             tint: StatsPalette.cardBlue)
            StatsSummaryCard(title: "本週訓練次數", value: "48 次",
                             tint: StatsPalette.cardPink)
        }
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

/// 漲跌幅膠囊。
private struct StatsDeltaPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7))
        }
        .foregroundStyle(Color.black.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.7))
        .clipShape(Capsule())
    }
}

private struct StatsSummaryCard: View {
    let title: String
    let value: String
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
                StatsDeltaPill(text: "13.4%")
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
/// 切上面那張不會連動下面那張。目前這樣比較單純；要連動的話得把狀態提到外層。
private struct StatsTrainingChartCard: View {
    let title: String
    /// 數值後綴：訓練時長是「分鐘」、訓練次數是「次」。
    /// ⚠️ 平均、中位數、長條 tooltip 三處共用同一個後綴，改一個地方三處都會跟著變。
    let unit: String

    /// 兩種區間各有一組假資料，切換膠囊時整組換掉（長條數量也跟著變）。
    private let weekValues: [Double] = [30, 34, 46, 40, 33, 44, 56, 38, 62, 50, 66, 54]
    private let weekLabels = ["第1週", "第2週", "第3週", "第4週", "第5週", "第6週",
                              "第7週", "第8週", "第9週", "第10週", "第11週", "第12週"]
    private let weekHighlighted = 8

    private let dayValues: [Double] = [38, 52, 44, 60, 41, 56, 48]
    private let dayLabels = ["9/1", "9/2", "9/3", "9/4", "9/5", "9/6", "9/7"]
    private let dayHighlighted = 5

    @State private var selectedRange = 0
    private let ranges = ["週單位", "天單位"]

    private var isDayMode: Bool { selectedRange == 1 }
    private var values: [Double] { isDayMode ? dayValues : weekValues }
    private var labels: [String] { isDayMode ? dayLabels : weekLabels }
    private var highlighted: Int { isDayMode ? dayHighlighted : weekHighlighted }
    /// ⚠️ 只有標題跟著切換，下面的「30分鐘」與「中位數 25分鐘」兩個數字**兩種模式共用**，
    /// 因為沒有指定天單位要顯示什麼值。要分開的話得再各給一組。
    private var averageTitle: String { isDayMode ? "每天平均" : "每週平均" }

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

                    // 右側原本有下載與「⋯」兩個 icon，已依指示移除。
                    // Spacer 留著，讓標題與區間膠囊維持靠左。
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(averageTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(StatsPalette.muted)
                    // 數值旁原本有綠色上三角／紅色下三角，已依指示移除。
                    Text("30\(unit)")
                        .font(.system(size: 22, weight: .bold))
                }

                HStack(spacing: 6) {
                    Circle().fill(StatsPalette.red).frame(width: 6, height: 6)
                    Text("中位數 25\(unit)")
                        .font(.system(size: 11))
                        .foregroundStyle(StatsPalette.muted)
                }

                chart
            }
        }
    }

    private var chart: some View {
        let maxV = values.max() ?? 1
        // ⚠️ 週單位用 6：「第12週」較寬，12 欄排下來會擠不下。
        // 天單位只有 7 欄、標籤又短（9/1），可以放寬到 14 才不會太擁擠。
        return HStack(alignment: .bottom, spacing: isDayMode ? 14 : 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 8) {
                    // ⚠️ 一定要 fixedSize()：tooltip 的寬度比長條本身寬，
                    // 不加會被欄寬擠成「$47,...」。
                    Text("35\(unit)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(StatsPalette.indigoDark)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .opacity(i == highlighted ? 1 : 0)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(i == highlighted ? StatsPalette.indigo : StatsPalette.barLight)
                        .frame(height: 120 * CGFloat(v / maxV))

                    // fixedSize()：理由同上面的 tooltip，不加會被欄寬截成「第12…」。
                    Text(labels[i])
                        .font(.system(size: 10, weight: i == highlighted ? .semibold : .regular))
                        .fixedSize()
                        .foregroundStyle(i == highlighted ? Color.white : StatsPalette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(i == highlighted ? StatsPalette.indigo : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: 175, alignment: .bottom)
    }
}

// MARK: - 執行紀錄表（表格）

/// ⚠️ 欄位已從電商語意換成訓練語意（日期／訓練時長／運動後疼痛／備註）。
/// 🔴 **資料仍是假的**：日期、時長、疼痛分數、備註都寫死在下面的 `rows` 裡，
/// 沒有接 `treatment_result`。備註文字取自 `Util/note.json` 的實際選項，
/// 只是為了讓假資料看起來合理，**不代表有查表**。
private struct StatsRecordRow {
    let num: Int
    let date: String
    let duration: String
    let pain: String
    let note: String
}

private struct StatsRecordTableCard: View {
    let title: String
    let rows: [StatsRecordRow]

    /// ⚠️ 兩週的日期刻意不重疊（第一週 9/1–9/5、第二週 9/8–9/12）——
    /// 兩張卡片若都顯示同一批日期，「第一週／第二週」就沒有意義了。
    static let week1: [StatsRecordRow] = [
        .init(num: 1, date: "9/1", duration: "32 分鐘", pain: "3", note: "大腿有點痠（鐵腿）"),
        .init(num: 2, date: "9/3", duration: "28 分鐘", pain: "5", note: "膝蓋微微痠痛，休息就好"),
        .init(num: 3, date: "9/5", duration: "35 分鐘", pain: "2", note: "沒有不適，感覺輕鬆")
    ]
    static let week2: [StatsRecordRow] = [
        .init(num: 1, date: "9/8", duration: "30 分鐘", pain: "4", note: "膝蓋腫脹、發熱或卡卡的"),
        .init(num: 2, date: "9/10", duration: "33 分鐘", pain: "3", note: "大腿有點痠（鐵腿）"),
        .init(num: 3, date: "9/12", duration: "27 分鐘", pain: "6", note: "膝蓋明顯疼痛")
    ]

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                // 右側原本有篩選／下載／「⋯」三個 icon，已依指示移除。
                Text(title)
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

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        Text("\(row.num)")
                            .font(.system(size: 12))
                            .foregroundStyle(StatsPalette.muted)
                            .frame(width: 60, alignment: .leading)
                        Text(row.date)
                            .font(.system(size: 12))
                            .frame(width: 100, alignment: .leading)
                        Text(row.duration)
                            .font(.system(size: 12))
                            .frame(width: 120, alignment: .leading)
                        Text(row.pain)
                            .font(.system(size: 12))
                            .frame(width: 170, alignment: .leading)
                        Text(row.note)
                            .font(.system(size: 12))
                            .frame(width: 260, alignment: .leading)
                    }
                    .padding(.vertical, 6)
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
}

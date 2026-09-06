import Foundation
import GRDB
import Observation

// MARK: - 統計頁的資料層（statistics-plan.md 階段 1）
//
// 🔴 **這一層不碰畫面。** 所有區間切割、單位換算、時區處理都集中在這裡，
// 畫面只負責顯示算好的數字。四張長條圖 ＋ 兩張卡片 ＋ 執行紀錄表共用同一份 buckets，
// 避免六個地方各切一次區間、各算錯一次。

/// 一場訓練（`treatment_result` 的一列，只留統計要用的欄位）。
struct StatsSession: Identifiable {
    let id: Int64
    /// 🔴 **毫秒** Unix epoch。
    let date: Int
    /// 這一場的訓練時長（毫秒）。⚠️ **各組加總**，不含組間休息（§2.1）。
    let durationMs: Int
    /// 這一場的總次數（`Σ reps`，§2.2）。
    let reps: Int
    let vas: Int?
    let noteIds: [Int]?
}

/// 一根長條／一張週卡片所涵蓋的區間。
struct StatsBucket: Identifiable {
    /// 由 0 起算的序號，也是 `ScrollViewReader` 用的 id。
    let id: Int
    let label: String
    /// 半開區間 `[start, end)`，單位**毫秒**。
    let start: Int
    let end: Int
    let sessions: [StatsSession]

    var durationMs: Int { sessions.reduce(0) { $0 + $1.durationMs } }
    var reps: Int { sessions.reduce(0) { $0 + $1.reps } }
}

enum StatsMetric {
    case duration
    case count

    func value(of bucket: StatsBucket) -> Double {
        switch self {
        case .duration: Double(bucket.durationMs)
        case .count:    Double(bucket.reps)
        }
    }
}

@Observable
class StatisticsViewModel {
    private let db = DatabaseManager.shared.dbQueue

    /// 週單位長條／執行紀錄表共用（§4.3／§4.7）。
    private(set) var weekBuckets: [StatsBucket] = []
    /// 天單位長條：永遠是**本週**的週一～週日（§4.4）。
    private(set) var dayBuckets: [StatsBucket] = []

    /// 兩張數值卡片用（§4.1／§4.2）。⚠️ 永遠是**自然週**，不跟著 baseline 走。
    private(set) var thisWeekDurationMs = 0
    private(set) var thisWeekReps = 0
    /// 「較上週」膠囊用（§4.2.1）。
    private(set) var lastWeekDurationMs = 0
    private(set) var lastWeekReps = 0

    /// 備註編號 → 文字。執行紀錄表用（§4.7）。
    ///
    /// ⚠️ 這是專案裡**第四個**查 `notes` 表的地方（輸入端 `CompletionPopup`、
    /// 匯出端 `noteTexts(for:)`、結果頁 `PostWorking*VasNoteRow`、這裡）。
    /// 四處各自組 lookup、各自處理「查不到」的佔位字串，翻譯規則改動時四個地方都要改。
    private(set) var noteNames: [Int: String] = [:]

    /// 週單位用的是哪一種模式，除錯與 UI 標示用。
    private(set) var usesBaseline = false
    /// 週單位的整體範圍（毫秒）。`nil` = 沒有 baseline 也沒有任何 treatment。
    private(set) var rangeStartMs: Int?
    private(set) var rangeEndMs: Int?

    // MARK: - 常數

    private static let dayMs = 86_400_000
    private static let weekMs = 7 * 86_400_000

    /// ⚠️ 與 `dashboard.swift` 的 `taipeiCalendar()` 是同一份設定，
    /// 但那個是 `private` 的檔案層函式，跨檔案讀不到，只能再寫一份。
    /// 🔴 兩邊必須保持一致（`Asia/Taipei` ＋ `firstWeekday = 2`），
    /// 否則「本週」在兩個地方會是不同的七天。
    private static func taipeiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: - 載入

    func reload() {
        let calendar = Self.taipeiCalendar()
        let now = Date()

        let sessions = fetchAllSessions()
        noteNames = Dictionary(
            uniqueKeysWithValues: ((try? db.read { db in try Note.fetchAll(db) }) ?? [])
                .map { ($0.id, $0.name) }
        )

        // ── 兩張卡片：本週／上週（永遠自然週）──────────────────
        let thisWeekStart = calendar.startOfWeek(for: now)
        let thisWeekEnd = thisWeekStart.addingTimeInterval(TimeInterval(Self.weekMs / 1000))
        let lastWeekStart = thisWeekStart.addingTimeInterval(-TimeInterval(Self.weekMs / 1000))

        let thisWeek = sessions.filter { $0.date >= thisWeekStart.ms && $0.date < thisWeekEnd.ms }
        let lastWeek = sessions.filter { $0.date >= lastWeekStart.ms && $0.date < thisWeekStart.ms }
        thisWeekDurationMs = thisWeek.reduce(0) { $0 + $1.durationMs }
        thisWeekReps = thisWeek.reduce(0) { $0 + $1.reps }
        lastWeekDurationMs = lastWeek.reduce(0) { $0 + $1.durationMs }
        lastWeekReps = lastWeek.reduce(0) { $0 + $1.reps }

        // ── 天單位：本週七天 ───────────────────────────────
        dayBuckets = (0..<7).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: thisWeekStart) else { return nil }
            let start = dayStart.ms
            let end = start + Self.dayMs
            let formatter = DateFormatter()
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "M/d"
            return StatsBucket(
                id: offset,
                label: formatter.string(from: dayStart),
                start: start,
                end: end,
                sessions: sessions.filter { $0.date >= start && $0.date < end }
            )
        }

        // ── 週單位：baseline 或 treatment 表 ────────────────
        weekBuckets = buildWeekBuckets(sessions: sessions, calendar: calendar)
    }

    /// 撈出所有 `treatment_result` 並換算成 `StatsSession`。
    ///
    /// ⚠️ 一次全撈、在記憶體裡分組（§5）——不要每一根長條各下一次查詢，
    /// 根數是動態的（`PLAN-AUTO` 14 根、一年 52 根）。
    private func fetchAllSessions() -> [StatsSession] {
        let rows = (try? db.read { db in try TreatmentResult.fetchAll(db) }) ?? []
        return rows.compactMap { row in
            guard let id = row.id else { return nil }
            return StatsSession(
                id: id,
                date: row.date,
                durationMs: Self.duration(of: row),
                reps: row.reps.reduce(0, +),
                vas: row.vas,
                noteIds: row.notes
            )
        }
    }

    /// 一場的訓練時長：**逐組配對相減後加總**（§2.1.1）。
    ///
    /// 🔴 **不可以用 `first`／`last`**——那是結果頁「跨距」算法的寫法，
    /// 對「各組加總」沒有意義。
    /// 🔴 兩端都要 `> 0`：陣列初始化為 `0`，提前結束的組會留 `0`；
    /// `start > 0` 但 `end == 0`（開始了沒結束）的組時長無從得知，整組跳過。
    private static func duration(of row: TreatmentResult) -> Int {
        zip(row.set_start_time, row.set_end_time)
            .filter { $0 > 0 && $1 > 0 }
            .map { $1 - $0 }
            .reduce(0, +)
    }

    private func buildWeekBuckets(sessions: [StatsSession], calendar: Calendar) -> [StatsBucket] {
        guard let (start, end) = weekRange(calendar: calendar) else {
            rangeStartMs = nil
            rangeEndMs = nil
            return []
        }
        rangeStartMs = start
        rangeEndMs = end

        // 無條件進位：最後一段不滿 7 天也要有一根。
        let count = max(1, Int(ceil(Double(end - start) / Double(Self.weekMs))))
        return (0..<count).map { k in
            let bucketStart = start + k * Self.weekMs
            let bucketEnd = bucketStart + Self.weekMs
            return StatsBucket(
                id: k,
                label: "第\(k + 1)週",
                start: bucketStart,
                end: bucketEnd,
                sessions: sessions.filter { $0.date >= bucketStart && $0.date < bucketEnd }
            )
        }
    }

    /// 週單位的整體範圍（毫秒）。
    ///
    /// | 起訖點設定 | 範圍 | 第 1 根的起點 |
    /// |---|---|---|
    /// | 有值 | 設定的 start～end | `start` **那一天**（不一定是週一）|
    /// | 沒有 | `treatment` 表的 `MIN(start_time)`～`MAX(end_time)` | 該日所在**台北週一** |
    ///
    /// 🔴 兩個來源都是**秒**，要 ×1000（§3）。
    private func weekRange(calendar: Calendar) -> (start: Int, end: Int)? {
        let setting = SettingViewModel()
        setting.fetchDateRange()
        if let s = setting.startTime, let e = setting.endTime, s < e {
            usesBaseline = true
            return (s * 1000, e * 1000)
        }

        usesBaseline = false
        // 🔴 用 MIN／MAX，不是「第一筆／最後一筆」——匯入順序不保證與時間順序一致
        //（settings-plan.md A.5 只擋重疊、不擋順序），而且最早開始的菜單
        // 不一定最晚結束，兩個端點要各自取極值（§2.3.1.1）。
        let treatments = (try? db.read { db in try Treatment.fetchAll(db) }) ?? []
        guard let minStart = treatments.map(\.start_time).min(),
              let maxEnd = treatments.map(\.end_time).max(),
              minStart < maxEnd else { return nil }

        // 自然週模式：第 1 根對齊該日所在的台北週一。
        let firstMonday = calendar.startOfWeek(for: Date(timeIntervalSince1970: TimeInterval(minStart)))
        return (firstMonday.ms, maxEnd * 1000)
    }

    // MARK: - 平均／中位數（§4.6）

    /// 統計母體：**含今天／本週**（已開始的都算），只排除**完全在未來**的 bucket。
    ///
    /// 🔴 母體為空時平均與中位數都回 `0`（§4.6.2）——
    /// 空陣列取平均會得到 `NaN`、取中位數會 crash。
    private func population(_ buckets: [StatsBucket]) -> [StatsBucket] {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return buckets.filter { $0.start <= now }
    }

    func average(_ buckets: [StatsBucket], metric: StatsMetric) -> Double {
        let values = population(buckets).map { metric.value(of: $0) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    func median(_ buckets: [StatsBucket], metric: StatsMetric) -> Double {
        let values = population(buckets).map { metric.value(of: $0) }.sorted()
        guard !values.isEmpty else { return 0 }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }

    /// 備註欄的顯示文字（§4.7）。
    ///
    /// 🔴 三種狀態要顯示成三種字：
    /// `nil` = 這一場沒問到、`[]` = 問了但沒有症狀、有值 = 逐則列出。
    /// ⚠️ 查不到的編號給 `#N（已刪除）` 佔位，**不要 `compactMap` 掉**——
    /// 靜默丟掉會讓病歷少一項而畫面看起來正常。
    func noteText(for ids: [Int]?) -> String {
        guard let ids else { return "－" }
        if ids.isEmpty { return "無" }
        return ids.map { noteNames[$0] ?? "#\($0)（已刪除）" }.joined(separator: "、")
    }

    /// 「今天所在的那一根」的索引（§4.4.2）。
    ///
    /// ⚠️ 回傳 `nil` 代表今天不在範圍內（療程已結束或還沒開始）——
    /// 這時**不要 highlight 任何一根**，不要退而求其次選最後一根或最大值。
    func todayIndex(in buckets: [StatsBucket]) -> Int? {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return buckets.first(where: { now >= $0.start && now < $0.end })?.id
    }
}

// MARK: - 小工具

private extension Date {
    /// 這個時間點的毫秒 Unix epoch。
    var ms: Int { Int(timeIntervalSince1970 * 1000) }
}

private extension Calendar {
    /// 這一天所在那一週的起點（`firstWeekday = 2`，所以是台北時區的週一 00:00）。
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

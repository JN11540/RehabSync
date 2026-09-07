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
    let vas: Int?
    let noteIds: [Int]?
    /// 這一場是哪個動作。⚠️ 可為 `nil`（孤兒列，見 `TreatmentResult.exercise_id`）。
    let exerciseId: Int?
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
    /// 這一段有幾**場**（§2.2 A）。
    ///
    /// 🔴 **就是列數，不做任何過濾**——時長 0 的場次照算（§2.2.1）。
    /// 所以「時長 0 分鐘、場次 3 場」是可能且已接受的組合：那三場每一組都是
    /// `start > 0` 但 `end == 0`，依 §2.1.1 整組跳過，算不出時長但確實打過。
    ///
    /// > 📌 這一欄原本是 `Σ reps`（總次數）。使用者改成「用場次計算」，
    /// > 名稱與公式一起換掉——只改名不改公式會名不副實。
    var sessionCount: Int { sessions.count }
}

enum StatsMetric {
    case duration
    case count

    func value(of bucket: StatsBucket) -> Double {
        switch self {
        case .duration: Double(bucket.durationMs)
        case .count:    Double(bucket.sessionCount)
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

    /// 兩張數值卡片用（§4.1／§4.2）。
    /// ⚠️ 有起訖點設定時是**療程第 N 週**，沒有才是自然週（見 `windowIndex`）。
    private(set) var thisWeekDurationMs = 0
    private(set) var thisWeekSessions = 0
    /// 「較上週」膠囊用（§4.2.1）。
    private(set) var lastWeekDurationMs = 0
    private(set) var lastWeekSessions = 0

    /// 卡片標題要顯示的療程週次（1 起算）。`nil` = 沒有 baseline，標題用「本週」。
    ///
    /// 🔴 這一欄存在的唯一理由是**標題**：baseline 模式下卡片算的是「療程第 N 週」，
    /// 標題卻寫「本週」會不準——尤其今天落在療程範圍外被夾到端點時（§4.4.1.1），
    /// 那個「本週」其實是三個月前的第 1 週或早就結束的最後一週。
    private(set) var currentWeekNumber: Int?

    /// 備註編號 → 文字。執行紀錄表用（§4.7）。
    ///
    /// ⚠️ 這是專案裡**第四個**查 `notes` 表的地方（輸入端 `CompletionPopup`、
    /// 匯出端 `noteTexts(for:)`、結果頁 `PostWorking*VasNoteRow`、這裡）。
    /// 四處各自組 lookup、各自處理「查不到」的佔位字串，翻譯規則改動時四個地方都要改。
    private(set) var noteNames: [Int: String] = [:]
    /// `exercise.id` → 動作名稱。執行紀錄表的「動作」欄用。
    private(set) var exerciseNames: [Int: String] = [:]

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
        // ⚠️ 與 noteNames 同樣的理由：一次撈成字典，不要每一列各查一次資料庫。
        // `Exercise.id` 是 `Int64?`，只有非 nil 的才進字典。
        exerciseNames = Dictionary(
            uniqueKeysWithValues: ((try? db.read { db in try Exercise.fetchAll(db) }) ?? [])
                .compactMap { exercise in exercise.id.map { (Int($0), exercise.name) } }
        )

        // ── 週單位：baseline 或 treatment 表 ────────────────
        // 🔴 必須**排在最前面**：兩張卡片與天單位在有 baseline 時都要跟著
        // 週單位切出來的那一段走（見 `windowIndex`），需要 `weekBuckets` 先算好。
        // 這個呼叫同時決定了 `usesBaseline`。
        weekBuckets = buildWeekBuckets(sessions: sessions, calendar: calendar)

        let thisWeekStart = calendar.startOfWeek(for: now)
        let window = windowIndex(now: now)

        // ── 兩張卡片：本週／上週 ────────────────────────────
        //
        // | 起訖點設定 | 「本週」是 | 「上週」是 |
        // |---|---|---|
        // | **有值** | 療程第 N 週（今天所在的那一段）| 療程第 N−1 週 |
        // | 沒有 | 自然週的週一～週日 | 前一個自然週 |
        //
        // 🔴 有 baseline 時**不能用自然週**：卡片與長條圖會變成兩段不同的時間，
        // 「本週 3 小時」對不上被 highlight 那根的高度（先前 §6.1.2 記錄的落差）。
        // 現在兩者同源，數字必定一致。
        // 🔴 標題用的週次與卡片數值來自**同一個 `window`**，
        // 不要另外算一次——兩者一旦分開算就有機會不一致。
        currentWeekNumber = window.map { $0 + 1 }

        if let window {
            let current = weekBuckets[window]
            thisWeekDurationMs = current.durationMs
            thisWeekSessions = current.sessionCount
            // ⚠️ 第 1 週沒有「上一段」→ 當成 0，「較上週」會顯示「－」（§4.2.1）。
            let previous = window > 0 ? weekBuckets[window - 1] : nil
            lastWeekDurationMs = previous?.durationMs ?? 0
            lastWeekSessions = previous?.sessionCount ?? 0
        } else {
            let thisWeekEnd = thisWeekStart.addingTimeInterval(TimeInterval(Self.weekMs / 1000))
            let lastWeekStart = thisWeekStart.addingTimeInterval(-TimeInterval(Self.weekMs / 1000))

            let thisWeek = sessions.filter { $0.date >= thisWeekStart.ms && $0.date < thisWeekEnd.ms }
            let lastWeek = sessions.filter { $0.date >= lastWeekStart.ms && $0.date < thisWeekStart.ms }
            thisWeekDurationMs = thisWeek.reduce(0) { $0 + $1.durationMs }
            thisWeekSessions = thisWeek.count
            lastWeekDurationMs = lastWeek.reduce(0) { $0 + $1.durationMs }
            lastWeekSessions = lastWeek.count
        }

        // ── 天單位：baseline 的那一週，或自然週 ─────────────
        let windowStart = window.map {
            Date(timeIntervalSince1970: TimeInterval(weekBuckets[$0].start) / 1000)
        } ?? thisWeekStart
        dayBuckets = (0..<7).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: windowStart) else { return nil }
            let start = dayStart.ms
            let end = start + Self.dayMs
            let formatter = DateFormatter()
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "M/d"
            return StatsBucket(
                id: offset,
                label: "\(formatter.string(from: dayStart))(\(Self.weekdaySymbol(of: dayStart, calendar: calendar)))",
                start: start,
                end: end,
                sessions: sessions.filter { $0.date >= start && $0.date < end }
            )
        }
    }

    /// 星期的單字：`日`『一』…『六』。
    ///
    /// 🔴 **不要用 `DateFormatter` 的 `EEEEE`／`shortWeekdaySymbols`**——
    /// 那會跟著**裝置語系**跑，英文機器上會變成 `Sun`，把標籤撐寬又不是中文。
    /// 這裡要的是固定中文，所以直接查表。
    ///
    /// ⚠️ `Calendar.component(.weekday)` 是 **1 = 週日**，與 `firstWeekday = 2`
    /// 無關（`firstWeekday` 只影響「一週從哪天開始」，不改 weekday 的編號）。
    private static func weekdaySymbol(of date: Date, calendar: Calendar) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols[calendar.component(.weekday, from: date) - 1]
    }

    /// 「本週」對應到 `weekBuckets` 的哪一個索引。`nil` = 沒有 baseline，用自然週。
    ///
    /// 🔴 **兩張數值卡片與天單位那 7 天共用這一個答案。**
    /// 有 baseline 時三者就是同一段時間的不同呈現，數字必定互相對得上；
    /// 各自算各自的才是先前 §6.1.2 那個落差的成因。
    ///
    /// | 起訖點設定 | 「本週」是哪一段 |
    /// |---|---|
    /// | **有值** | 今天所在的療程週（起點可能是任何一天，不一定是週一）|
    /// | 沒有（回傳 `nil`）| 自然週的**台北週一**起算 |
    ///
    /// ⚠️ **今天可能不在 baseline 範圍內**（療程已結束或還沒開始）。
    /// 這時夾到最近的一端——早於範圍取第 1 段、晚於範圍取最後一段——
    /// 而不是退回自然週：退回去會讓卡片與長條圖又變成不同區間，
    /// 而療程結束後「最後一週」比「空白的本週」有用。
    /// 🔴 夾到端點時**今天不在那一段裡**，長條圖不會有任何一根被 highlight、
    /// 也不會有 tooltip（§4.4.2），但卡片仍然顯示那一段的數字——這是預期行為。
    private func windowIndex(now: Date) -> Int? {
        guard usesBaseline, !weekBuckets.isEmpty else { return nil }

        let t = now.ms
        if let hit = weekBuckets.firstIndex(where: { t >= $0.start && t < $0.end }) { return hit }
        return t < weekBuckets[0].start ? 0 : weekBuckets.count - 1
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
                vas: row.vas,
                noteIds: row.notes,
                exerciseId: row.exercise_id
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

    /// ⚠️ **統計頁的畫面上已經沒有中位數了**（那一列已移除），
    /// 目前唯一的使用者是測試頁的除錯面板。
    /// 保留是因為它與 `average` 共用同一個母體規則（§4.6），
    /// 日後若要把中位數放回畫面，規則不用重新推導一次。
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
    /// `exercise_id` → 動作名稱。
    ///
    /// 🔴 `nil`（孤兒列）與「字典裡查不到」都回「－」，不要回空字串——
    /// 空字串在表格裡看起來像是排版壞掉，「－」才看得出是「沒有這筆資料」。
    func exerciseName(for id: Int?) -> String {
        guard let id, let name = exerciseNames[id] else { return "－" }
        return name
    }

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

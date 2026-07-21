import Foundation

/// 匯出功能專用：把大腿／小腿（或 exg 的 4 條序列）依「按組分段的索引位置對位」規則合併，
/// 對應 database-update-plan.md「大腿／小腿合併策略（acc／gyro／exg）」的規劃。
enum GameDataMerger {

    /// 對多條序列做「按組分段」的索引位置對位：先用 `treatment_result` 的 `set_start_time`／`set_end_time`
    /// 把每條序列切成一組一組的區段，每組各自獨立呼叫 `alignByIndex` 對位，再把各組結果依序串接起來。
    /// `set_start_time`／`set_end_time` 皆為 0（該組從未開始）的組別直接跳過。
    static func mergeByIndexPerSet<T>(
        sequences: [[T]],
        setStartTimes: [Int],
        setEndTimes: [Int],
        timestamp: (T) -> Int64
    ) -> [[T]] {
        var merged: [[T]] = Array(repeating: [], count: sequences.count)

        for i in setStartTimes.indices {
            guard setEndTimes.indices.contains(i) else { continue }
            let start = setStartTimes[i]
            let end = setEndTimes[i]
            guard start > 0, end > 0 else { continue }

            let segments = sequences.map { seq in
                seq.filter { let t = timestamp($0); return t >= Int64(start) && t <= Int64(end) }
            }
            let aligned = alignByIndex(segments, timestamp: timestamp)
            for idx in aligned.indices {
                merged[idx].append(contentsOf: aligned[idx])
            }
        }

        return merged
    }

    /// 單一區段內的索引位置對位：取各序列 timestamp 的共同重疊區間、過濾範圍外的資料，
    /// 再取各序列較短的長度裁切，回傳等長、可依索引直接逐筆對位的序列陣列。
    /// 任一序列是空的（或重疊區間不存在）就回傳全部皆為空陣列。
    static func alignByIndex<T>(_ sequences: [[T]], timestamp: (T) -> Int64) -> [[T]] {
        guard !sequences.isEmpty, sequences.allSatisfy({ !$0.isEmpty }) else {
            return sequences.map { _ in [] }
        }

        let windowStart = sequences.map { timestamp($0.first!) }.max()!
        let windowEnd = sequences.map { timestamp($0.last!) }.min()!
        guard windowStart <= windowEnd else {
            return sequences.map { _ in [] }
        }

        let filtered = sequences.map { seq in
            seq.filter { let t = timestamp($0); return t >= windowStart && t <= windowEnd }
        }

        let count = filtered.map(\.count).min()!
        guard count > 0 else {
            return sequences.map { _ in [] }
        }

        return filtered.map { Array($0.prefix(count)) }
    }
}

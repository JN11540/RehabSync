import Foundation

/// 膝關節終端伸展 - 校正期「自動偵測穩定平台」演算法
///
/// 移植自 calibration_phase.py（run_calibration），對照 acc-calibration-design.md：
///   inclination_deg          → inclinationDeg(x:y:z:)
///   （逐列算 knee_angle 後依 timestamp 分組平均）→ smoothedIncline(_:)（大腿、小腿各呼叫一次）+ index 配對
///   detect_stable_segments   → detectStableSegments(tSec:angles:windowSec:stdThresholdDeg:minDurationSec:)
///   detect_stable_plateau    → detectStablePlateau(tSec:angles:windowSec:stdThresholdDeg:minDurationSec:)
///   robust_min_angle         → robustMinAngle(_:lowestFraction:)
///   run_calibration          → computeBaseline(thighSamples:calfSamples:...)
///
/// 跟 calibration_phase.py 的兩個差異(對照設計文件):
///   1. 全程保留正負號,不做任何 abs() 正規化(跟原始 python 行為一致)。
///   2. 大腿、小腿是兩個獨立的 BLE 周邊,各自依自己的 timestamp 分組平均出
///      thighIncline／calfIncline 兩條獨立曲線,再用陣列 index(排序後第 i 筆對第 i 筆)相減
///      得到膝角,不是像 python 版那樣假設同一列 CSV 本來就同時間對齊好。
enum ACCCalibration {

    // MARK: - Public

    /// 對大腿、小腿加速度計樣本套用「自動偵測穩定平台」演算法,算出校正基準角度。
    ///
    /// - Parameters:
    ///   - thighSamples: 大腿加速度計樣本(timestamp 毫秒,x/y/z 已乘過 acc_sensitivity)。
    ///   - calfSamples: 小腿加速度計樣本,結構同上。
    ///   - windowSec: 局部標準差滑動視窗長度(秒),預設 1.0。
    ///   - stdThresholdDeg: 局部標準差低於這個值才算「穩定」(度),預設 1.5。
    ///   - minDurationSec: 平台至少要維持這麼久(秒)才算數,預設 1.0。
    ///   - fallbackLowestFraction: 完全偵測不到合格平台時,取角度最低的這個比例的點當備案,預設 0.2(20%)。
    /// - Returns: baseline 角度(保留正負號,四捨五入到小數1位)。只有在大腿、小腿樣本配對後完全沒有
    ///   任何資料點時回傳 nil；只要有資料,即使偵測不到穩定平台,也會透過 robustMinAngle 備案算出一個值。
    static func computeBaseline(
        thighSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        calfSamples: [(timestamp: Int64, x: Double, y: Double, z: Double)],
        windowSec: Double = 1.0,
        stdThresholdDeg: Double = 1.5,
        minDurationSec: Double = 1.0,
        fallbackLowestFraction: Double = 0.2
    ) -> Double? {
        let thighIncline = smoothedIncline(thighSamples)
        let calfIncline = smoothedIncline(calfSamples)
        let count = min(thighIncline.count, calfIncline.count)
        guard count > 0 else { return nil }

        var kneeAngles: [Double] = []
        var tSecs: [Double] = []
        kneeAngles.reserveCapacity(count)
        tSecs.reserveCapacity(count)
        for i in 0 ..< count {
            kneeAngles.append(thighIncline[i].incline - calfIncline[i].incline)
            tSecs.append(Double(thighIncline[i].t) / 1000.0)
        }

        let baseline: Double
        if let plateau = detectStablePlateau(
            tSec: tSecs, angles: kneeAngles,
            windowSec: windowSec, stdThresholdDeg: stdThresholdDeg, minDurationSec: minDurationSec
        ) {
            baseline = plateau.meanAngleDeg
        } else {
            baseline = robustMinAngle(kneeAngles, lowestFraction: fallbackLowestFraction)
        }

        return (baseline * 10).rounded() / 10
    }

    // MARK: - Private：角度計算 / 分組平滑

    /// 對應 inclination_deg：以重力向量計算肢段相對垂直線的傾角(度)。
    /// 跟 BluetoothViewModel.computeBaselineAngle 裡的同名私有函式邏輯一致,但因為 private 跨檔案用不到,
    /// 這裡獨立維護一份(見 acc-calibration-design.md「已確認的決定」)。
    private static func inclinationDeg(_ x: Double, _ y: Double, _ z: Double) -> Double {
        atan2(x, (y * y + z * z).squareRoot()) * 180 / .pi
    }

    /// 依 timestamp 分組平均,濾掉同一個 timestamp(同一個 BLE 封包)底下多筆瞬間取樣的高頻雜訊。
    private static func smoothedIncline(
        _ samples: [(timestamp: Int64, x: Double, y: Double, z: Double)]
    ) -> [(t: Int64, incline: Double)] {
        var sums: [Int64: (sum: Double, count: Int)] = [:]
        for s in samples {
            let incline = inclinationDeg(s.x, s.y, s.z)
            var g = sums[s.timestamp] ?? (0, 0)
            g.sum += incline
            g.count += 1
            sums[s.timestamp] = g
        }
        return sums.map { (t: $0.key, incline: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.t < $1.t }
    }

    // MARK: - Private：穩定平台偵測

    private struct StableSegment {
        let startSec: Double
        let endSec: Double
        let durationSec: Double
        let meanAngleDeg: Double
        let nPoints: Int
    }

    /// 對應 detect_stable_segments：用滑動視窗算每個時間點附近的局部標準差(centered rolling std, ddof=1),
    /// 局部標準差 <= stdThresholdDeg 的點視為穩定,把連續穩定點串成一段段平台,只保留
    /// 持續時間 >= minDurationSec 的平台。
    private static func detectStableSegments(
        tSec: [Double],
        angles: [Double],
        windowSec: Double,
        stdThresholdDeg: Double,
        minDurationSec: Double
    ) -> [StableSegment] {
        let n = angles.count
        guard n > 0 else { return [] }

        let dt: Double
        if n >= 2 {
            let diffs = (1 ..< n).map { tSec[$0] - tSec[$0 - 1] }
            let medianDt = median(diffs)
            dt = medianDt > 0 ? medianDt : (tSec[n - 1] - tSec[0]) / Double(max(1, n - 1))
        } else {
            dt = 1.0
        }
        let windowPts = dt > 0 ? max(3, Int((windowSec / dt).rounded())) : 3

        let rollingStd = centeredRollingStd(angles, window: windowPts)
        let stableMask = rollingStd.map { $0 != nil && $0! <= stdThresholdDeg }

        var rawSegments: [(start: Int, end: Int)] = []
        var start: Int? = nil
        for i in 0 ..< n {
            if stableMask[i], start == nil {
                start = i
            } else if !stableMask[i], let s = start {
                rawSegments.append((s, i - 1))
                start = nil
            }
        }
        if let s = start { rawSegments.append((s, n - 1)) }

        var segments: [StableSegment] = []
        for (s, e) in rawSegments {
            let duration = tSec[e] - tSec[s]
            guard duration >= minDurationSec else { continue }
            let segAngles = angles[s ... e]
            let mean = segAngles.reduce(0, +) / Double(segAngles.count)
            segments.append(StableSegment(
                startSec: (tSec[s] * 100).rounded() / 100,
                endSec: (tSec[e] * 100).rounded() / 100,
                durationSec: (duration * 100).rounded() / 100,
                meanAngleDeg: (mean * 10).rounded() / 10,
                nPoints: e - s + 1
            ))
        }
        return segments
    }

    /// 對應 detect_stable_plateau：在所有合格平台中,挑「平均角度最小」(最伸直)的那一個。
    private static func detectStablePlateau(
        tSec: [Double],
        angles: [Double],
        windowSec: Double,
        stdThresholdDeg: Double,
        minDurationSec: Double
    ) -> StableSegment? {
        let segments = detectStableSegments(
            tSec: tSec, angles: angles,
            windowSec: windowSec, stdThresholdDeg: stdThresholdDeg, minDurationSec: minDurationSec
        )
        return segments.min { $0.meanAngleDeg < $1.meanAngleDeg }
    }

    /// 對應 robust_min_angle：完全偵測不到合格平台時的備案,取角度最低的 lowestFraction 比例的點,回傳其平均值。
    private static func robustMinAngle(_ angles: [Double], lowestFraction: Double) -> Double {
        let n = angles.count
        let k = max(1, Int((Double(n) * lowestFraction).rounded(.up)))
        let lowestK = angles.sorted().prefix(k)
        return lowestK.reduce(0, +) / Double(lowestK.count)
    }

    // MARK: - Private：數學工具

    /// centered rolling std(樣本標準差,ddof=1),min_periods = window：
    /// 每個中心點 j 用左 (window-1)/2、右 (window-1)-左 個點湊成完整視窗,湊不滿(邊緣)一律回傳 nil,
    /// 對應 pandas Series.rolling(window:, center: true, min_periods: window).std() 的語意
    /// (window 為偶數時,視窗會偏向未來多取一點,不是嚴格對稱)。
    private static func centeredRollingStd(_ values: [Double], window: Int) -> [Double?] {
        let n = values.count
        var result = [Double?](repeating: nil, count: n)
        guard window >= 2, window <= n else { return result }

        let left = (window - 1) / 2
        let right = (window - 1) - left

        for j in 0 ..< n {
            let lo = j - left
            let hi = j + right
            guard lo >= 0, hi <= n - 1 else { continue }
            let windowVals = values[lo ... hi]
            let mean = windowVals.reduce(0, +) / Double(window)
            let variance = windowVals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window - 1)
            result[j] = variance.squareRoot()
        }
        return result
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        guard n > 0 else { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}

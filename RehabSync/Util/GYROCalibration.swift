import Foundation

struct IMUSample {
    let ax: Double, ay: Double, az: Double
    let gx: Double, gy: Double, gz: Double
}

struct GyroBias {
    let biasX: Double
    let biasY: Double
    let biasZ: Double
}

enum GYROCalibration {

    // MARK: - Public

    /// 從 IMU 樣本估計 gyro bias。
    /// - Parameters:
    ///   - samples:           N 筆六軸原始資料
    ///   - windowSize:        靜止偵測滑動窗口大小（samples），預設 50
    ///   - accStdThreshold:   acc 三軸標準差閾值（g 或 m/s²），預設 0.02
    ///   - minStaticSamples:  最少靜止樣本數，不足時回傳 nil，預設 200
    /// - Returns: GyroBias，靜止樣本不足時回傳 nil
    static func calibrate(
        samples: [IMUSample],
        windowSize: Int = 50,
        accStdThreshold: Double = 0.02,
        minStaticSamples: Int = 200
    ) -> GyroBias? {
        let staticMask = detectStaticWindows(
            samples: samples,
            windowSize: windowSize,
            accStdThreshold: accStdThreshold
        )
        let staticCount = staticMask.filter { $0 }.count
        guard staticCount >= minStaticSamples else { return nil }
        return estimateBias(samples: samples, staticMask: staticMask)
    }

    // MARK: - Private

    private static func detectStaticWindows(
        samples: [IMUSample],
        windowSize: Int,
        accStdThreshold: Double
    ) -> [Bool] {
        let n = samples.count
        var mask = [Bool](repeating: false, count: n)
        let half = windowSize / 2
        guard n > windowSize else { return mask }

        for i in half ..< (n - half) {
            let window = Array(samples[(i - half) ..< (i + half)])
            if stdBelowThreshold(window: window, threshold: accStdThreshold) {
                mask[i] = true
            }
        }
        return mask
    }

    private static func stdBelowThreshold(window: [IMUSample], threshold: Double) -> Bool {
        let n = Double(window.count)
        guard n > 1 else { return false }

        let axes: [(IMUSample) -> Double] = [ { $0.ax }, { $0.ay }, { $0.az } ]
        for axis in axes {
            let values = window.map(axis)
            let mean = values.reduce(0, +) / n
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
            if variance.squareRoot() >= threshold { return false }
        }
        return true
    }

    private static func estimateBias(samples: [IMUSample], staticMask: [Bool]) -> GyroBias {
        var sumX = 0.0, sumY = 0.0, sumZ = 0.0, count = 0.0
        for (i, isStatic) in staticMask.enumerated() where isStatic {
            sumX += samples[i].gx
            sumY += samples[i].gy
            sumZ += samples[i].gz
            count += 1
        }
        return GyroBias(biasX: sumX / count, biasY: sumY / count, biasZ: sumZ / count)
    }
}

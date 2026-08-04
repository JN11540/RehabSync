import UIKit

/// EMG(小腿通道)- 移動平均(Moving Average)平滑 + 折線圖繪製
///
/// 對照 emg_moving_average.py:
///   - moving_average()      → EMGAlgo.movingAverage(uv:windowSize:overlap:)
///   - load_and_smooth()     → tSec 換算(centerIndices / sampleRate)
///   - plot_moving_average() → EMGAlgo.movingAveragePNG(...) 內的繪圖邏輯
enum EMGAlgo {

    enum EMGAlgoError: Error, LocalizedError {
        case mismatchedInputCount(timestampCount: Int, uvCount: Int)
        case invalidOverlap(windowSize: Int, overlap: Int)
        case insufficientSamples(count: Int, windowSize: Int)

        var errorDescription: String? {
            switch self {
            case let .mismatchedInputCount(timestampCount, uvCount):
                return "timestamp(\(timestampCount) 筆) 與 uv(\(uvCount) 筆) 筆數不一致"
            case let .invalidOverlap(windowSize, overlap):
                return "overlap(\(overlap)) 必須小於 windowSize(\(windowSize))"
            case let .insufficientSamples(count, windowSize):
                return "資料筆數(\(count)) 少於 windowSize(\(windowSize)),無法計算移動平均"
            }
        }
    }

    // MARK: - Public

    /// 對 EMG 取樣資料(timestamp／uv)套用移動平均,輸出時間序列折線圖的 PNG 資料。
    ///
    /// - Parameters:
    ///   - timestamp:  取樣時間戳(毫秒)。因更新頻率遠低於實際取樣率,不拿來計算時間軸,
    ///                 僅用來確認與 uv 筆數一致(對照 CSV 的 timestamp 欄位)。
    ///   - uv:         EMG 訊號數值(要做移動平均的欄位)。
    ///   - windowSize: 移動平均視窗大小,預設 16。
    ///   - overlap:    相鄰視窗重疊的取樣數,預設 15。
    ///   - sampleRate: 假設的固定取樣率(Hz),用來把取樣索引換算成秒數時間軸,預設 32。
    /// - Returns: 折線圖 PNG 資料(x 軸為時間(秒),y 軸為移動平均後的 uv 值)。
    static func movingAveragePNG(
        timestamp: [Int64],
        uv: [Double],
        windowSize: Int = 16,
        overlap: Int = 15,
        sampleRate: Double = 32.0,
        imageSize: CGSize = CGSize(width: 1500, height: 500)
    ) throws -> Data {
        guard timestamp.count == uv.count else {
            throw EMGAlgoError.mismatchedInputCount(timestampCount: timestamp.count, uvCount: uv.count)
        }

        let (avgValues, centerIndices) = try movingAverage(uv: uv, windowSize: windowSize, overlap: overlap)
        let tSec = centerIndices.map { $0 / sampleRate }

        return renderLineChartPNG(
            tSec: tSec,
            values: avgValues,
            windowSize: windowSize,
            overlap: overlap,
            imageSize: imageSize
        )
    }

    /// 以 windowSize / overlap 定義的滑動視窗計算移動平均。
    ///
    /// hop(每次視窗滑動的取樣數) = windowSize - overlap,必須 >= 1。
    ///
    /// - Returns: (avgValues: 每個視窗的平均值, centerIndices: 每個視窗對應的「代表取樣索引」(取窗內中間點),用來換算成時間軸)
    static func movingAverage(
        uv: [Double],
        windowSize: Int = 16,
        overlap: Int = 15
    ) throws -> (avgValues: [Double], centerIndices: [Double]) {
        let hop = windowSize - overlap
        guard hop >= 1 else {
            throw EMGAlgoError.invalidOverlap(windowSize: windowSize, overlap: overlap)
        }
        let n = uv.count
        guard n >= windowSize else {
            throw EMGAlgoError.insufficientSamples(count: n, windowSize: windowSize)
        }

        let starts = stride(from: 0, through: n - windowSize, by: hop)
        var avgValues: [Double] = []
        var centerIndices: [Double] = []
        for s in starts {
            let window = uv[s ..< s + windowSize]
            avgValues.append(window.reduce(0, +) / Double(windowSize))
            centerIndices.append(Double(s) + Double(windowSize - 1) / 2.0)
        }
        return (avgValues, centerIndices)
    }

    // MARK: - Private (繪圖)

    private static let lineColor = UIColor(red: 24.0 / 255, green: 95.0 / 255, blue: 165.0 / 255, alpha: 1)

    private static func renderLineChartPNG(
        tSec: [Double],
        values: [Double],
        windowSize: Int,
        overlap: Int,
        imageSize: CGSize
    ) -> Data {
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.pngData { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: imageSize))

            let margin = UIEdgeInsets(top: 40, left: 70, bottom: 50, right: 20)
            let plotRect = CGRect(
                x: margin.left,
                y: margin.top,
                width: imageSize.width - margin.left - margin.right,
                height: imageSize.height - margin.top - margin.bottom
            )

            drawTitle("uv 移動平均 (window=\(windowSize), overlap=\(overlap))", in: imageSize, top: 12)

            guard let tMin = tSec.min(), let tMax = tSec.max(),
                  let vMin = values.min(), let vMax = values.max() else {
                return
            }

            let xTicks = niceTicks(min: tMin, max: tMax, targetCount: 6)
            let yTicks = niceTicks(min: vMin, max: vMax, targetCount: 5)
            let xRange = max(xTicks.last! - xTicks.first!, .leastNonzeroMagnitude)
            let yRange = max(yTicks.last! - yTicks.first!, .leastNonzeroMagnitude)

            func xPixel(_ t: Double) -> CGFloat {
                plotRect.minX + CGFloat((t - xTicks.first!) / xRange) * plotRect.width
            }
            func yPixel(_ v: Double) -> CGFloat {
                plotRect.maxY - CGFloat((v - yTicks.first!) / yRange) * plotRect.height
            }

            // 格線 + 刻度文字
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.3).cgColor)
            cg.setLineWidth(0.6)
            for t in xTicks {
                let x = xPixel(t)
                cg.move(to: CGPoint(x: x, y: plotRect.minY))
                cg.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                drawCenteredText(formatTick(t, step: xTicks.count > 1 ? xTicks[1] - xTicks[0] : 1),
                                  center: CGPoint(x: x, y: plotRect.maxY + 16), fontSize: 11)
            }
            for v in yTicks {
                let y = yPixel(v)
                cg.move(to: CGPoint(x: plotRect.minX, y: y))
                cg.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                drawText(formatTick(v, step: yTicks.count > 1 ? yTicks[1] - yTicks[0] : 1),
                         rightAlignedAt: CGPoint(x: plotRect.minX - 8, y: y), fontSize: 11)
            }
            cg.strokePath()

            // 座標軸外框
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            cg.setLineWidth(1)
            cg.stroke(plotRect)

            // 折線
            if tSec.count >= 2 {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: xPixel(tSec[0]), y: yPixel(values[0])))
                for i in 1 ..< tSec.count {
                    path.addLine(to: CGPoint(x: xPixel(tSec[i]), y: yPixel(values[i])))
                }
                lineColor.setStroke()
                path.lineWidth = 2.5
                path.lineJoinStyle = .round
                path.stroke()
            }

            drawCenteredText("時間 (秒)", center: CGPoint(x: plotRect.midX, y: imageSize.height - 16), fontSize: 12)
            drawRotatedYLabel("uv", plotRect: plotRect, fontSize: 12)
        }
    }

    /// 類似 matplotlib 自動刻度的「好整數」刻度演算法。
    private static func niceTicks(min: Double, max: Double, targetCount: Int) -> [Double] {
        guard max > min else { return [min, min + 1] }
        let rawStep = (max - min) / Double(targetCount)
        let magnitude = pow(10, floor(log10(rawStep)))
        let residual = rawStep / magnitude
        let niceResidual: Double = residual > 5 ? 10 : (residual > 2 ? 5 : (residual > 1 ? 2 : 1))
        let step = niceResidual * magnitude
        let niceMin = floor(min / step) * step
        let niceMax = ceil(max / step) * step

        var ticks: [Double] = []
        var v = niceMin
        while v <= niceMax + step * 0.5 {
            ticks.append(v)
            v += step
        }
        return ticks
    }

    private static func formatTick(_ value: Double, step: Double) -> String {
        let decimals = max(0, min(6, Int(ceil(-log10(step))) + (step < 1 ? 1 : 0)))
        return String(format: "%.\(decimals)f", value)
    }

    private static func drawTitle(_ text: String, in size: CGSize, top: CGFloat) {
        drawCenteredText(text, center: CGPoint(x: size.width / 2, y: top), fontSize: 14, bold: true)
    }

    private static func drawCenteredText(_ text: String, center: CGPoint, fontSize: CGFloat, bold: Bool = false) {
        let font = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()
        attrString.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
    }

    private static func drawText(_ text: String, rightAlignedAt point: CGPoint, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()
        attrString.draw(at: CGPoint(x: point.x - textSize.width, y: point.y - textSize.height / 2))
    }

    private static func drawRotatedYLabel(_ text: String, plotRect: CGRect, fontSize: CGFloat) {
        UIGraphicsGetCurrentContext().map { cg in
            cg.saveGState()
            cg.translateBy(x: 20, y: plotRect.midY)
            cg.rotate(by: -.pi / 2)
            drawCenteredText(text, center: .zero, fontSize: fontSize)
            cg.restoreGState()
        }
    }
}

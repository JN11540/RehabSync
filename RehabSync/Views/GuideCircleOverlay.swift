import SwiftUI
import AVFoundation

// MARK: - Guide Circle Overlay

/// 遊戲畫面的引導圈圈：400×400 圓形示範影片＋三層外框（黑2pt/白6pt/黑2pt，實際佔用 420×420）＋
/// 顯示/隱藏開關按鈕。給 `2/9/12/22_Working.swift` 用，比照 `Test.swift` 已定案的外觀，
/// 差異只在這裡是「顯示/隱藏」單一開關（Test.swift 是「上一個/下一個」左右切換）。
struct GuideCircleOverlay: View {
    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            ZStack(alignment: .leading) {
                VideoCircleToggleButton(systemName: "eye.slash.fill") {
                    isVisible = false
                }
                .offset(x: -55)

                CircularLoopingVideo(resourceName: resourceName, videoGravity: videoGravity)
                    .frame(width: 400, height: 400)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2).frame(width: 404, height: 404))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 6).frame(width: 416, height: 416))
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2).frame(width: 420, height: 420))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            }
        } else {
            VideoCircleToggleButton(systemName: "eye.fill") {
                isVisible = true
            }
        }
    }
}

// MARK: - Video Circle Toggle Button

/// 白底、黑框 2pt 圓角矩形按鈕，`Test.swift` 的左右切換／`GuideCircleOverlay` 的顯示隱藏都共用同一套外觀。
struct VideoCircleToggleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 110)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Circular Looping Video

/// 播放 bundle 裡的影片並自動循環（用 AVQueuePlayer + AVPlayerLooper 做無縫 loop），給圓形展示區塊用；
/// `videoGravity` 預設 `.resizeAspectFill`（填滿圓形、多餘部分裁掉），動作 12 改傳 `.resizeAspect`
/// （完整顯示、等比例縮放、不裁切）。
struct CircularLoopingVideo: View {
    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            CircularLoopingVideoPlayer(url: url, videoGravity: videoGravity)
        } else {
            Color.clear
        }
    }
}

struct CircularLoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> CircularLoopingVideoUIView {
        CircularLoopingVideoUIView(url: url, videoGravity: videoGravity)
    }

    func updateUIView(_ uiView: CircularLoopingVideoUIView, context: Context) {
        uiView.update(url: url, videoGravity: videoGravity)
    }
}

final class CircularLoopingVideoUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL, videoGravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        playerLayer.videoGravity = videoGravity
        layer.addSublayer(playerLayer)
        update(url: url, videoGravity: videoGravity)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func update(url: URL, videoGravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = videoGravity
        guard url != currentURL else { return }
        currentURL = url
        let player = AVQueuePlayer()
        player.isMuted = true
        playerLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }
}

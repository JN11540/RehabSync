import AVFoundation

/// 輕量的單一音效播放包裝，管理一顆 `AVAudioPlayer` 的播放/停止/是否循環，
/// 給 `Working2` 讀秒／捕獲／金幣三段音效使用（working2-database-port-plan.md 第 15 節）。
/// 每個音效各自持有一份獨立的實例，互不打斷（15.2）。
final class SoundEffectPlayer {
    private var player: AVAudioPlayer?
    private let resourceName: String

    var isPlaying: Bool { player?.isPlaying ?? false }

    init(resourceName: String) {
        self.resourceName = resourceName
    }

    /// `loop == true` 時無縫循環播放，直到呼叫 `stop()`；`false` 時只播一次，播完自然停止。
    /// 每次呼叫都會從頭開始播放（`currentTime = 0`），呼叫端要自行決定要不要在已經在播放時跳過呼叫
    /// （例如 `coins.mp3` 依 15.4 節規劃，重疊時不重新觸發，維持現有播放不被打斷）。
    func play(loop: Bool) {
        if player == nil {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
                print("[SoundEffectPlayer] ❌ 找不到 \(resourceName).mp3，請確認 Target Membership 有勾選")
                return
            }
            player = try? AVAudioPlayer(contentsOf: url)
        }
        player?.numberOfLoops = loop ? -1 : 0
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
    }
}

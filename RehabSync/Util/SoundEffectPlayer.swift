import AVFoundation

/// 輕量的單一音效播放包裝，管理一顆 `AVAudioPlayer` 的播放/停止/是否循環，
/// 給 `Working2` 讀秒／捕獲／金幣／鼓勵語音使用（working2-database-port-plan.md 第 15、16 節）。
/// 每個音效各自持有一份獨立的實例，互不打斷（15.2）。
final class SoundEffectPlayer {
    private var player: AVAudioPlayer?
    private var resourceName: String

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// `resourceName` 給空字串時，這個實例沒有單一固定檔案，每次播放都要透過 `play(resourceName:loop:)`
    /// 明確指定要播哪個檔案（給 16 節的隨機鼓勵語音用）。
    init(resourceName: String = "") {
        self.resourceName = resourceName
    }

    /// `loop == true` 時無縫循環播放，直到呼叫 `stop()`；`false` 時只播一次，播完自然停止。
    /// 每次呼叫都會從頭開始播放（`currentTime = 0`），呼叫端要自行決定要不要在已經在播放時跳過呼叫
    /// （例如 `coins.mp3` 依 15.4 節規劃，重疊時不重新觸發，維持現有播放不被打斷）。
    func play(loop: Bool) {
        loadIfNeeded(resourceName: resourceName)
        player?.numberOfLoops = loop ? -1 : 0
        player?.currentTime = 0
        player?.play()
    }

    /// 每次呼叫都可以指定不同的檔案（給 16 節「每次觸發從 5 個檔案隨機挑一個」用）。
    /// 檔名跟目前已載入的相同時不重新讀檔，但 `currentTime = 0`／`play()` 仍然無條件執行——
    /// 即使巧合連續兩次選到同一個檔案，也要真正重新播放，不能因為檔名沒變就被誤判成不需要呼叫
    /// （working2-database-port-plan.md 16.3／16.4：語音重疊時要直接打斷前一個、重新播放）。
    func play(resourceName: String, loop: Bool) {
        if resourceName != self.resourceName || player == nil {
            self.resourceName = resourceName
            loadIfNeeded(resourceName: resourceName, forceReload: true)
        }
        player?.numberOfLoops = loop ? -1 : 0
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
    }

    private func loadIfNeeded(resourceName: String, forceReload: Bool = false) {
        guard player == nil || forceReload else { return }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            print("[SoundEffectPlayer] ❌ 找不到 \(resourceName).mp3，請確認 Target Membership 有勾選")
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
    }
}

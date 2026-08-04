import Foundation
import Observation

/// 讀取 `Util/setting.json` 裡的軟體版本號；這是純靜態設定值，沒有對應的資料庫表，
/// 不走 GRDB，直接讀 app bundle 裡的 JSON。
private struct SettingDTO: Decodable {
    let software_version: String
}

@Observable
class SettingViewModel {
    var softwareVersion: String = ""

    func fetchSoftwareVersion() {
        guard let url = Bundle.main.url(forResource: "setting", withExtension: "json") else {
            print("[SettingViewModel] ❌ 找不到 setting.json，請確認 Target Membership 有勾選")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[SettingViewModel] ❌ 無法讀取檔案內容")
            return
        }

        do {
            let dto = try JSONDecoder().decode(SettingDTO.self, from: data)
            softwareVersion = dto.software_version
        } catch {
            print("[SettingViewModel] ❌ JSON 解析失敗：\(error)")
        }
    }
}

import Foundation
import Observation

/// `Util/setting.json` 的內容。
///
/// ⚠️ `start_time`／`end_time` 在檔案裡的初始值是 `null`，所以是 Optional。
private struct SettingDTO: Codable {
    let software_version: String
    var start_time: Int?
    var end_time: Int?
}

/// 讀寫 `setting.json`。這是純設定值，沒有對應的資料庫表，不走 GRDB。
///
/// 🔴 **兩個來源，刻意分開讀**（settings-plan.md 附錄 B.2.1）：
///
/// | 欄位 | 從哪讀 | 理由 |
/// |---|---|---|
/// | `software_version` | **永遠讀 bundle** | 它是建置產物 |
/// | `start_time`／`end_time` | 讀 Documents 副本 | 使用者資料 |
///
/// 為什麼不能都讀副本：app bundle 執行時唯讀，所以使用者編輯的值必須寫到
/// Documents 的副本；而副本是「不存在才建立」，**一旦建立過就永遠不會被
/// bundle 的新版蓋掉**——若版本號也讀副本，app 升版後會一直顯示舊版號，
/// 而且改 bundle 也救不回既有使用者。
@Observable
class SettingViewModel {
    var softwareVersion: String = ""
    /// 統計頁的 baseline 起訖點。⚠️ 台北時區午夜的 **秒** 數（B.4.1）。
    var startTime: Int?
    var endTime: Int?

    /// Documents 目錄裡的可寫副本。
    private var documentsURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("setting.json")
    }

    private var bundleURL: URL? {
        Bundle.main.url(forResource: "setting", withExtension: "json")
    }

    /// 副本不存在時，從 bundle 複製一份整檔過去（B.2：存整份 JSON，不拆欄位）。
    private func ensureDocumentsCopy() {
        guard let documentsURL, let bundleURL else { return }
        guard !FileManager.default.fileExists(atPath: documentsURL.path) else { return }
        try? FileManager.default.copyItem(at: bundleURL, to: documentsURL)
    }

    /// 讀軟體版本。🔴 **只讀 bundle**，副本裡那一份刻意忽略（見類別說明）。
    func fetchSoftwareVersion() {
        guard let bundleURL, let data = try? Data(contentsOf: bundleURL) else {
            print("[SettingViewModel] ❌ 找不到或無法讀取 bundle 的 setting.json")
            return
        }
        do {
            softwareVersion = try JSONDecoder().decode(SettingDTO.self, from: data).software_version
        } catch {
            print("[SettingViewModel] ❌ JSON 解析失敗：\(error)")
        }
    }

    /// 讀統計 baseline 的起訖點。**只讀 Documents 副本**。
    func fetchDateRange() {
        ensureDocumentsCopy()
        guard let documentsURL, let data = try? Data(contentsOf: documentsURL),
              let dto = try? JSONDecoder().decode(SettingDTO.self, from: data) else {
            print("[SettingViewModel] ❌ 無法讀取 Documents 的 setting.json")
            return
        }
        startTime = dto.start_time
        endTime = dto.end_time
    }

    /// 寫回起訖點。**只寫 Documents 副本**，永遠不碰 bundle（bundle 唯讀）。
    ///
    /// ⚠️ 副本裡的 `software_version` **原封保留、不更新** ——
    /// 它是整份複製的副作用，沒有任何程式會讀它（B.2.1）。
    /// 在這裡「順手把它更新成 bundle 的值」會讓下一個人以為那一欄是有用的。
    @discardableResult
    func saveDateRange(start: Int, end: Int) -> Bool {
        ensureDocumentsCopy()
        guard let documentsURL, let data = try? Data(contentsOf: documentsURL),
              var dto = try? JSONDecoder().decode(SettingDTO.self, from: data) else {
            print("[SettingViewModel] ❌ 寫入前讀不到 Documents 的 setting.json")
            return false
        }
        dto.start_time = start
        dto.end_time = end

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let out = try? encoder.encode(dto),
              (try? out.write(to: documentsURL, options: .atomic)) != nil else {
            print("[SettingViewModel] ❌ 寫入失敗")
            return false
        }
        startTime = start
        endTime = end
        return true
    }
}

import Foundation

/// 使用者在「匯出」設定頁指定的資料夾（見 database-export-implementation-steps.md 階段 7）。
/// 用 security-scoped bookmark 存進 UserDefaults，讓遊戲完成視窗匯出時可以直接解析回同一個資料夾寫檔，
/// 不用每次匯出都重新跳資料夾選擇器。
enum ExportDestinationStore {

    private static let bookmarkKey = "exportDestinationFolderBookmark"

    /// 只檢查 UserDefaults 有沒有存過 bookmark data，不嘗試真的解析——供階段 8 卡片點擊時的「是否已設定」判斷用。
    static func hasDesignatedFolder() -> Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// 把存起來的 bookmark data 解析回 URL；解析失敗（bookmark 壞掉/資料夾被移除）回傳 nil。
    /// 解析成功但已經過期（`isStale`）時，順手用這次解析出來的 URL 重新存一份新 bookmark 蓋掉舊的，
    /// 避免放著不管、之後真的失效——這一步不會動到資料夾本身或裡面的檔案。
    static func resolveDesignatedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            save(folderURL: url)
        }

        return url
    }

    /// 使用者選定（或重新選定）資料夾後呼叫：建立 security-scoped bookmark 並存進 UserDefaults，覆蓋舊的設定。
    /// iOS 上要用預設／空白 options（或 `.minimalBookmark`），不要加 `.withSecurityScope`——
    /// 那是 macOS 專屬的 BookmarkCreationOptions，iOS 沒有這個選項；從 UIDocumentPickerViewController
    /// 拿到的 URL 在 iOS 上本身就已經是 security-scoped，用預設選項建立 bookmark 就會自動保留這個安全範圍。
    static func save(folderURL url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

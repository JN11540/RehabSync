import SwiftUI

// MARK: - Treatment Selection State

@Observable
final class TreatmentSelectionState {
    var userSelectedContentId: Int64? = nil
}

// MARK: - goHome Environment Key

private struct GoHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var goHome: () -> Void {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}


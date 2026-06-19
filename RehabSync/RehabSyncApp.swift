import SwiftUI

@main
struct RehabSyncApp: App {
    init() {
        ExerciseViewModel().seedIfNeeded()
        BluetoothViewModel().seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Home()
        }
    }
}

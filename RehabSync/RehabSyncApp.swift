import SwiftUI

@main
struct RehabSyncApp: App {
    init() {
        ExerciseViewModel().seedIfNeeded()
        BluetoothViewModel().seedIfNeeded()
        DeviceViewModel().cleanupIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Home()
        }
    }
}

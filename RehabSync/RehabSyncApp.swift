import SwiftUI

@main
struct RehabSyncApp: App {
    init() {
        ExerciseViewModel().seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Home()
        }
    }
}

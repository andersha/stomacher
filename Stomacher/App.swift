import SwiftUI

@main
struct StomacherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(store: PatternStore())
        }
    }
}


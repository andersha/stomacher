import SwiftUI

@main
struct StomacherApp: App {
    @StateObject private var store = PatternStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}

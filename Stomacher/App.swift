import SwiftUI

@main
struct StomacherApp: App {
    @StateObject private var store = PatternStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onOpenURL { url in
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        try store.load(url: url)
                    } catch {
                        store.statusMessage = "Kunne ikke åpne fil: \(error.localizedDescription)"
                    }
                }
        }
    }
}


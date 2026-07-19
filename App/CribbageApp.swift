import SwiftUI
import CribbageEngine

@main
struct CribbageApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(app)
        }
    }
}

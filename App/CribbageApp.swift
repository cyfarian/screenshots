import SwiftUI
import CribbageEngine

enum AppTab: Hashable {
    case game, calc, history, settings
}

@main
struct CribbageApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(app)
        }
    }
}

struct RootTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            GameTabView()
                .tabItem { Label("Game", systemImage: "target") }
                .tag(AppTab.game)
            NavigationStack { HandCalculatorView() }
                .tabItem { Label("Cards", systemImage: "square.grid.3x2") }
                .tag(AppTab.calc)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "chart.bar") }
                .tag(AppTab.history)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { app.lastError != nil },
                set: { if !$0 { app.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.lastError ?? "")
        }
    }
}

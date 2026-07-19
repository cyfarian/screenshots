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
    @AppStorage("scoreStyle") private var scoreStyle = "numbers"
    @AppStorage("theme") private var theme = "system"
    @State private var showingCountChooser = false

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            GameTabView()
                .tabItem { Label("Game", systemImage: "target") }
                .tag(AppTab.game)
            NavigationStack { HandCalculatorView() }
                .tabItem { Label("Count", systemImage: "plus") }
                .tag(AppTab.calc)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "chart.bar") }
                .tag(AppTab.history)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onChange(of: app.selectedTab) { _, newTab in
            // During a game, the Count tab first asks HOW to count.
            if newTab == .calc && app.hasLiveGame {
                showingCountChooser = true
            }
        }
        .confirmationDialog(
            "How do you want to count?",
            isPresented: $showingCountChooser,
            titleVisibility: .visible
        ) {
            Button("Big numbers (+1…+5)") {
                scoreStyle = "numbers"
                app.selectedTab = .game
            }
            Button("Named combos (15, Pair…)") {
                scoreStyle = "named"
                app.selectedTab = .game
            }
            Button("Log the cards") {
                // Stay on the calculator.
            }
            Button("Cancel", role: .cancel) {
                app.selectedTab = .game
            }
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
        .preferredColorScheme(
            theme == "light" ? .light : theme == "dark" ? .dark : nil
        )
    }
}

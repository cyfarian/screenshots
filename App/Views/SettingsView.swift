import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage("scoreStyle") private var scoreStyle = "numbers"
    @AppStorage("theme") private var theme = "system"
    @AppStorage("palette") private var palette = "classic"
    @AppStorage("defaultMuggins") private var defaultMuggins = false
    @AppStorage("defaultSkunksCountExtra") private var defaultSkunksCountExtra = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        Form {
            Section("Scoring") {
                Picker("Scoring buttons", selection: $scoreStyle) {
                    Text("Big numbers (+1…+5)").tag("numbers")
                    Text("Named combos (15, Pair…)").tag("named")
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Match device").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Default peg colors", selection: $palette) {
                    Text("Classic (red / blue)").tag("classic")
                    Text("Color-blind friendly").tag("colorblind")
                    Text("Violet / teal").tag("modern")
                }
            }
            Section("New game defaults") {
                Toggle("Muggins", isOn: $defaultMuggins)
                Toggle("Skunks count double in matches", isOn: $defaultSkunksCountExtra)
            }
            Section("Feedback") {
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Text("Scores derive from the full peg history, so Undo can always rewind a mis-peg. The screen stays awake during a live game.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.selectedTab = .game
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Back to game")
            }
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

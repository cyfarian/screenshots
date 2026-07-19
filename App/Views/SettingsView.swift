import SwiftUI

struct SettingsView: View {
    @AppStorage("scoreStyle") private var scoreStyle = "numbers"
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
                Picker("Peg colors", selection: $palette) {
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
    }
}

private extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

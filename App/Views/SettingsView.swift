import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultMuggins") private var defaultMuggins = false
    @AppStorage("defaultSkunksCountExtra") private var defaultSkunksCountExtra = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        Form {
            Section("New game defaults") {
                Toggle("Muggins", isOn: $defaultMuggins)
                Toggle("Skunks count double in matches", isOn: $defaultSkunksCountExtra)
            }
            Section("Feedback") {
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Text("Scores derive from the full peg history, so Undo can always rewind a mis-peg.")
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

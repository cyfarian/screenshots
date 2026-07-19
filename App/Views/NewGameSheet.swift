import SwiftUI
import CribbageEngine

struct NewGameSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @AppStorage("defaultMuggins") private var defaultMuggins = false
    @AppStorage("defaultSkunksCountExtra") private var defaultSkunksCountExtra = false

    @State private var mode: GameMode = .twoPlayer
    @State private var playerNames: [String] = ["", "", "", ""]
    @State private var teamNames: [String] = ["", ""]
    @State private var mugginsEnabled = false
    @State private var dealerSeat = 0
    @State private var playMatch = false
    @State private var bestOf = 3
    @State private var skunksCountExtra = false
    @State private var appliedDefaults = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    Picker("Mode", selection: $mode) {
                        ForEach(GameMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    ForEach(0..<mode.playerCount, id: \.self) { seat in
                        TextField(defaultName(seat: seat), text: $playerNames[seat])
                            .textInputAutocapitalization(.words)
                    }
                    if mode == .fourPlayerPartners {
                        TextField("Team 1 name (optional)", text: $teamNames[0])
                        TextField("Team 2 name (optional)", text: $teamNames[1])
                    }
                }

                Section("First deal") {
                    Picker("Dealer", selection: $dealerSeat) {
                        ForEach(0..<mode.playerCount, id: \.self) { seat in
                            Text(resolvedName(seat: seat)).tag(seat)
                        }
                    }
                    Button("Cut for deal (random)") {
                        dealerSeat = Int.random(in: 0..<mode.playerCount)
                    }
                }

                Section("Rules") {
                    Toggle("Muggins", isOn: $mugginsEnabled)
                    Toggle("Play a match", isOn: $playMatch)
                    if playMatch {
                        Picker("Length", selection: $bestOf) {
                            Text("Best of 3").tag(3)
                            Text("Best of 5").tag(5)
                            Text("Best of 7").tag(7)
                        }
                        Toggle("Skunks count double", isOn: $skunksCountExtra)
                    }
                }

                Section {
                    Button {
                        start()
                    } label: {
                        Text("Start Game")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !appliedDefaults {
                    mugginsEnabled = defaultMuggins
                    skunksCountExtra = defaultSkunksCountExtra
                    appliedDefaults = true
                }
            }
            .onChange(of: mode) {
                if dealerSeat >= mode.playerCount { dealerSeat = 0 }
            }
        }
    }

    private func defaultName(seat: Int) -> String { "Player \(seat + 1)" }

    private func resolvedName(seat: Int) -> String {
        let typed = playerNames[seat].trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? defaultName(seat: seat) : typed
    }

    private func start() {
        let names = (0..<mode.playerCount).map { resolvedName(seat: $0) }
        let teams = teamNames.map { $0.trimmingCharacters(in: .whitespaces) }
        let config = GameConfig(
            mode: mode,
            playerNames: names,
            teamNames: mode == .fourPlayerPartners ? teams : [],
            mugginsEnabled: mugginsEnabled,
            startingDealerSeat: dealerSeat
        )
        let matchConfig = playMatch
            ? MatchConfig(bestOf: bestOf, skunksCountExtra: skunksCountExtra)
            : nil
        app.startGame(config: config, matchConfig: matchConfig)
        dismiss()
    }
}

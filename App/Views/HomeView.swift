import SwiftUI
import CribbageEngine

/// The Game tab: new-game setup when idle, the live board when playing.
struct GameTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.hasLiveGame {
                    GameView()
                } else {
                    NewGameForm()
                }
            }
            .navigationTitle("Cribbage")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NewGameForm: View {
    @Environment(AppState.self) private var app

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
    @State private var pegColors: [Color] = [
        TrackStyle.color(0), TrackStyle.color(1), TrackStyle.color(2),
    ]

    var body: some View {
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
                ForEach(0..<mode.trackCount, id: \.self) { track in
                    ColorPicker(
                        mode == .fourPlayerPartners
                            ? "Team \(track + 1) peg color"
                            : "\(resolvedName(seat: track)) peg color",
                        selection: $pegColors[track],
                        supportsOpacity: false
                    )
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
            startingDealerSeat: dealerSeat,
            trackColors: (0..<mode.trackCount).map { pegColors[$0].hexString }
        )
        let matchConfig = playMatch
            ? MatchConfig(bestOf: bestOf, skunksCountExtra: skunksCountExtra)
            : nil
        app.startGame(config: config, matchConfig: matchConfig)
    }
}

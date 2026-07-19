import Foundation

/// Aggregate record for one player/team name across finished games.
public struct PlayerStats: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public var gamesPlayed: Int = 0
    public var wins: Int = 0
    public var skunksGiven: Int = 0
    public var skunksTaken: Int = 0
    public var handsCounted: Int = 0
    public var handPointsTotal: Int = 0
    public var bestHand: Int = 0

    public var id: String { name }
    public var losses: Int { gamesPlayed - wins }

    public var averageHand: Double {
        handsCounted == 0 ? 0 : Double(handPointsTotal) / Double(handsCounted)
    }

    public init(name: String) {
        self.name = name
    }
}

public enum Stats {

    /// Folds finished games into per-name aggregates, sorted by wins.
    public static func compute(from games: [Game]) -> [PlayerStats] {
        var byName: [String: PlayerStats] = [:]

        func stats(_ name: String) -> PlayerStats {
            byName[name] ?? PlayerStats(name: name)
        }

        for game in games {
            guard let winner = game.winnerTrack else { continue }
            let config = game.config
            for track in 0..<config.mode.trackCount {
                let name = config.trackName(track)
                var s = stats(name)
                s.gamesPlayed += 1
                if track == winner {
                    s.wins += 1
                    let losers = (0..<config.mode.trackCount).filter { $0 != winner }
                    s.skunksGiven += losers.filter {
                        let level = game.skunkResult(ofTrack: $0)
                        return level == .skunk || level == .doubleSkunk
                    }.count
                } else {
                    let level = game.skunkResult(ofTrack: track)
                    if level == .skunk || level == .doubleSkunk {
                        s.skunksTaken += 1
                    }
                }
                for event in game.events
                where event.trackIndex == track && (event.reason == .handCount || event.reason == .cribCount) {
                    s.handsCounted += 1
                    s.handPointsTotal += event.points
                    s.bestHand = max(s.bestHand, event.points)
                }
                byName[name] = s
            }
        }
        return byName.values.sorted {
            $0.wins != $1.wins ? $0.wins > $1.wins : $0.name < $1.name
        }
    }
}

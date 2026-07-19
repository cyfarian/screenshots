# Cribbage Score

An iPhone app for scoring cribbage games — a digital board and pegging
tracker for games played with real cards. Built to grow into full gameplay
later (the scoring engine is already a standalone module).

## Features

- **Visual cribbage board** — serpentine 121-hole track, front/back pegs per
  player, skunk (S) and double-skunk (SS) lines
- **2, 3, or 4 players** — head-to-head, three-hand, or partners (team) play
- **Quick pegging buttons** — 15s, pairs, runs, go, 31, nobs, heels, last
  card, plus any custom amount
- **Undo everything** — scores derive from a full event log, so any mis-peg
  can be rewound
- **Dealer & crib tracking** — rotates automatically each hand
- **Hand calculator** — tap 4 cards + the starter, get the itemized count
  (fifteens, pairs, runs, flush, nobs) with crib rules applied
- **Muggins** — under-claimed points can be claimed by an opponent
- **Match play** — best of 3/5/7, optional skunks-count-double
- **History & stats** — win/loss records, skunks given/taken, average and
  best hands

## Project layout

| Path | What it is |
|------|------------|
| `CribbageEngine/` | Pure-Swift package: scoring rules, game state, board geometry, persistence. No UI imports — tests run on Linux. |
| `App/` | SwiftUI app layer (iOS 17+). |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; the Xcode project is generated on CI, never committed. |
| `.github/workflows/engine-tests.yml` | Runs `swift test` on every push (free Linux runner). |
| `.github/workflows/testflight.yml` | Builds, signs, and uploads to TestFlight on a cloud Mac — no local Mac needed. |
| `SETUP.md` | One-time App Store Connect / GitHub secrets walkthrough. |

## Development without a Mac

This project is designed to be developed and shipped entirely from
non-Apple hardware:

- All game logic lives in `CribbageEngine` and is exercised by unit tests on
  Linux CI (including a brute-force cross-check of the hand scorer against
  an independent implementation).
- The app is compiled and signed by GitHub Actions on a macOS runner using
  Xcode cloud-managed signing (App Store Connect API key — no certificates
  to export).
- Installation is via TestFlight. See [SETUP.md](SETUP.md).

To work on it *with* a Mac instead: `brew install xcodegen`,
`xcodegen generate`, open `Cribbage.xcodeproj`.

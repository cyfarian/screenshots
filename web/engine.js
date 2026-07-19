/* Cribbage engine — JS port of CribbageEngine (Swift). Pure logic, no DOM.
   Kept behaviorally identical to the Swift engine so the two apps agree. */

export const SUITS = ["clubs", "diamonds", "hearts", "spades"];
export const SUIT_SYMBOL = { clubs: "♣", diamonds: "♦", hearts: "♥", spades: "♠" };
export const RANK_SYMBOL = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];

export function card(rank, suit) {
  return { rank, suit };
}

export function cardValue(rank) {
  return Math.min(rank, 10);
}

export function cardName(c) {
  return RANK_SYMBOL[c.rank] + SUIT_SYMBOL[c.suit];
}

export function isRed(suit) {
  return suit === "diamonds" || suit === "hearts";
}

export function sameCard(a, b) {
  return a.rank === b.rank && a.suit === b.suit;
}

export function fullDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (let rank = 1; rank <= 13; rank++) deck.push(card(rank, suit));
  }
  return deck;
}

// ---------------------------------------------------------------- Hand scorer

/** Scores 4 hand cards + starter. Returns { items: [{kind, cards, points, label}], total }. */
export function scoreHand(hand, starter, isCrib = false) {
  if (hand.length !== 4) throw new Error("hand must have 4 cards");
  const all = [...hand, starter];
  const items = [];

  // Fifteens: every subset of 2+ cards summing to 15 scores 2.
  for (let mask = 1; mask < 1 << 5; mask++) {
    const subset = [];
    let sum = 0;
    for (let i = 0; i < 5; i++) {
      if (mask & (1 << i)) {
        subset.push(all[i]);
        sum += cardValue(all[i].rank);
      }
    }
    if (subset.length >= 2 && sum === 15) {
      items.push({ kind: "fifteen", cards: subset, points: 2, label: "Fifteen" });
    }
  }

  // Pairs: each distinct same-rank pair scores 2.
  for (let i = 0; i < 5; i++) {
    for (let j = i + 1; j < 5; j++) {
      if (all[i].rank === all[j].rank) {
        items.push({ kind: "pair", cards: [all[i], all[j]], points: 2, label: "Pair" });
      }
    }
  }

  // Runs: maximal consecutive-rank streaks of 3+, once per card combination.
  const byRank = new Map();
  for (const c of all) {
    if (!byRank.has(c.rank)) byRank.set(c.rank, []);
    byRank.get(c.rank).push(c);
  }
  const present = [...byRank.keys()].sort((a, b) => a - b);
  let i = 0;
  while (i < present.length) {
    let j = i;
    while (j + 1 < present.length && present[j + 1] === present[j] + 1) j++;
    const length = j - i + 1;
    if (length >= 3) {
      let combos = [[]];
      for (let k = i; k <= j; k++) {
        combos = combos.flatMap((prefix) => byRank.get(present[k]).map((c) => [...prefix, c]));
      }
      for (const cards of combos) {
        items.push({ kind: "run", cards, points: length, label: `Run of ${length}` });
      }
    }
    i = j + 1;
  }

  // Flush: 4 hand cards one suit = 4 (+1 with starter). Crib: 5-card only.
  const suit = hand[0].suit;
  if (hand.every((c) => c.suit === suit)) {
    if (starter.suit === suit) {
      items.push({ kind: "flush", cards: [...hand, starter], points: 5, label: "Flush" });
    } else if (!isCrib) {
      items.push({ kind: "flush", cards: [...hand], points: 4, label: "Flush" });
    }
  }

  // Nobs: jack in hand matching starter suit.
  for (const c of hand) {
    if (c.rank === 11 && c.suit === starter.suit) {
      items.push({ kind: "nobs", cards: [c, starter], points: 1, label: "Nobs" });
    }
  }

  return { items, total: items.reduce((s, it) => s + it.points, 0) };
}

export function starterIsHeels(starter) {
  return starter.rank === 11;
}

// ---------------------------------------------------------------------- Modes

export const MODES = {
  twoPlayer: { playerCount: 2, trackCount: 2, label: "2 Players" },
  threePlayer: { playerCount: 3, trackCount: 3, label: "3 Players" },
  fourPlayerPartners: { playerCount: 4, trackCount: 2, label: "4 Players (Teams)" },
};

export function trackForSeat(mode, seat) {
  return mode === "fourPlayerPartners" ? seat % 2 : seat;
}

export function trackName(config, track) {
  if (config.mode === "fourPlayerPartners") {
    if (config.teamNames && config.teamNames[track]) return config.teamNames[track];
    const members = config.playerNames.filter((_, seat) => trackForSeat(config.mode, seat) === track);
    return members.join(" & ");
  }
  return config.playerNames[track] ?? `Player ${track + 1}`;
}

// ----------------------------------------------------------------------- Game

export const REASON_LABEL = {
  fifteen: "Fifteen", pair: "Pair", run3: "Run of 3", run4: "Run of 4", run5: "Run of 5",
  nobs: "Nobs", heels: "Heels", go: "Go", lastCard: "Last card", thirtyOne: "Thirty-one",
  handCount: "Hand", cribCount: "Crib", muggins: "Muggins", manual: "Points",
  handComplete: "Next hand",
};

/** config: { mode, playerNames, teamNames, targetScore=121, skunkThreshold=91,
    doubleSkunkThreshold=61, mugginsEnabled, startingDealerSeat } */
export function newGame(config) {
  return {
    id: crypto.randomUUID(),
    config: {
      targetScore: 121, skunkThreshold: 91, doubleSkunkThreshold: 61,
      mugginsEnabled: false, startingDealerSeat: 0, teamNames: [], ...config,
    },
    events: [],
    createdAt: Date.now(),
    completedAt: null,
  };
}

export function trackScore(game, track) {
  let sum = 0;
  for (const e of game.events) if (e.track === track) sum += e.points;
  return Math.min(sum, game.config.targetScore);
}

export function pegPositions(game, track) {
  const front = trackScore(game, track);
  let lastPoints = 0;
  for (let i = game.events.length - 1; i >= 0; i--) {
    const e = game.events[i];
    if (e.track === track && e.points > 0) { lastPoints = e.points; break; }
  }
  return { front, back: Math.max(0, front - lastPoints) };
}

export function winnerTrack(game) {
  const sums = new Map();
  for (const e of game.events) {
    if (e.points <= 0) continue;
    const s = (sums.get(e.track) ?? 0) + e.points;
    sums.set(e.track, s);
    if (s >= game.config.targetScore) return e.track;
  }
  return null;
}

export function isOver(game) {
  return winnerTrack(game) !== null;
}

export function handNumber(game) {
  return game.events.filter((e) => e.reason === "handComplete").length;
}

export function dealerSeat(game) {
  const players = MODES[game.config.mode].playerCount;
  return (game.config.startingDealerSeat + handNumber(game)) % players;
}

export function cribTrack(game) {
  return trackForSeat(game.config.mode, dealerSeat(game));
}

/** null while in play or for the winner; "none" | "skunk" | "doubleSkunk" for losers. */
export function skunkResult(game, track) {
  const winner = winnerTrack(game);
  if (winner === null || track === winner) return null;
  const s = trackScore(game, track);
  if (s < game.config.doubleSkunkThreshold) return "doubleSkunk";
  if (s < game.config.skunkThreshold) return "skunk";
  return "none";
}

export function peg(game, track, points, reason, breakdown = null) {
  if (isOver(game)) throw new Error("game over");
  if (track < 0 || track >= MODES[game.config.mode].trackCount) throw new Error("bad track");
  if (points <= 0) throw new Error("bad points");
  game.events.push({ id: crypto.randomUUID(), track, points, reason, breakdown, at: Date.now() });
  if (isOver(game)) game.completedAt = Date.now();
}

export function completeHand(game) {
  if (isOver(game)) throw new Error("game over");
  game.events.push({
    id: crypto.randomUUID(), track: cribTrack(game), points: 0,
    reason: "handComplete", breakdown: null, at: Date.now(),
  });
}

export function undo(game) {
  const last = game.events.pop() ?? null;
  if (!isOver(game)) game.completedAt = null;
  return last;
}

// ---------------------------------------------------------------------- Match

export const SKUNK_MATCH_VALUE = { none: 1, skunk: 2, doubleSkunk: 3 };

export function gameResult(game) {
  const trackCount = MODES[game.config.mode].trackCount;
  const tracks = [...Array(trackCount).keys()];
  return {
    id: game.id,
    winnerTrack: winnerTrack(game),
    scores: tracks.map((t) => trackScore(game, t)),
    skunks: tracks.map((t) => skunkResult(game, t)),
    date: game.completedAt ?? game.createdAt,
  };
}

export function newMatch(config) {
  return { config: { bestOf: 3, skunksCountExtra: false, ...config }, results: [] };
}

export function matchPoints(match, track) {
  let points = 0;
  for (const r of match.results) {
    if (r.winnerTrack !== track) continue;
    if (match.config.skunksCountExtra) {
      const worst = Math.max(1, ...r.skunks.filter(Boolean).map((s) => SKUNK_MATCH_VALUE[s]));
      points += worst;
    } else {
      points += 1;
    }
  }
  return points;
}

export function matchWinner(match, trackCount) {
  const needed = Math.floor(match.config.bestOf / 2) + 1;
  for (let t = 0; t < trackCount; t++) {
    if (matchPoints(match, t) >= needed) return t;
  }
  return null;
}

// ---------------------------------------------------------------------- Stats

export function computeStats(finishedGames) {
  const byName = new Map();
  const get = (name) => {
    if (!byName.has(name)) {
      byName.set(name, {
        name, gamesPlayed: 0, wins: 0, skunksGiven: 0, skunksTaken: 0,
        handsCounted: 0, handPointsTotal: 0, bestHand: 0,
      });
    }
    return byName.get(name);
  };

  for (const game of finishedGames) {
    const winner = winnerTrack(game);
    if (winner === null) continue;
    const trackCount = MODES[game.config.mode].trackCount;
    for (let track = 0; track < trackCount; track++) {
      const s = get(trackName(game.config, track));
      s.gamesPlayed += 1;
      if (track === winner) {
        s.wins += 1;
        for (let other = 0; other < trackCount; other++) {
          if (other === winner) continue;
          const level = skunkResult(game, other);
          if (level === "skunk" || level === "doubleSkunk") s.skunksGiven += 1;
        }
      } else {
        const level = skunkResult(game, track);
        if (level === "skunk" || level === "doubleSkunk") s.skunksTaken += 1;
      }
      for (const e of game.events) {
        if (e.track === track && (e.reason === "handCount" || e.reason === "cribCount")) {
          s.handsCounted += 1;
          s.handPointsTotal += e.points;
          s.bestHand = Math.max(s.bestHand, e.points);
        }
      }
    }
  }
  return [...byName.values()].sort((a, b) => b.wins - a.wins || a.name.localeCompare(b.name));
}

// --------------------------------------------------------------- Board layout

/** Serpentine board geometry — same math as BoardLayout.swift. */
export function boardLayout(trackCount, legs = 6, targetScore = 121) {
  const laneGap = 1.0;
  const trackWidth = (trackCount - 1) * laneGap;
  const C = trackWidth + 2.5;
  const R = C / 2;
  const arcTotal = (legs - 1) * Math.PI * R;
  const L = (targetScore - arcTotal) / legs;
  const maxE = trackWidth / 2;
  const m = 1.6;
  const ox = m + maxE;
  const topY = m + maxE + R;

  const size = {
    width: (legs - 1) * C + 2 * (maxE + m),
    height: L + 2 * R + 2 * (maxE + m),
  };

  function locate(d) {
    d = Math.max(0, Math.min(d, targetScore));
    let seg = 0;
    for (;;) {
      const len = seg % 2 === 0 ? L : Math.PI * R;
      if (d <= len || seg === 2 * (legs - 1)) return [seg, Math.min(d, len)];
      d -= len;
      seg += 1;
    }
  }

  function center(d) {
    const [seg, off] = locate(d);
    const li = Math.floor(seg / 2);
    const x = ox + li * C;
    const yb = topY + L;
    if (seg % 2 === 0) return li % 2 === 0 ? { x, y: yb - off } : { x, y: topY + off };
    const cx = x + C / 2;
    if (li % 2 === 0) {
      const phi = Math.PI - off / R;
      return { x: cx + R * Math.cos(phi), y: topY - R * Math.sin(phi) };
    }
    const phi = Math.PI + off / R;
    return { x: cx + R * Math.cos(phi), y: yb - R * Math.sin(phi) };
  }

  function normal(d) {
    const [seg, off] = locate(d);
    const li = Math.floor(seg / 2);
    if (seg % 2 === 0) return li % 2 === 0 ? { x: -1, y: 0 } : { x: 1, y: 0 };
    if (li % 2 === 0) {
      const phi = Math.PI - off / R;
      return { x: Math.cos(phi), y: -Math.sin(phi) };
    }
    const phi = Math.PI + off / R;
    return { x: -Math.cos(phi), y: Math.sin(phi) };
  }

  function lane(d, track) {
    const p = center(d);
    const n = normal(d);
    const e = (track - (trackCount - 1) / 2) * laneGap;
    return { x: p.x + e * n.x, y: p.y + e * n.y };
  }

  return {
    trackCount, legs, targetScore, laneGap,
    maxLaneOffset: maxE, size,
    aspectRatio: size.width / size.height,
    position: (hole, track) => lane(hole, track),
    centerPosition: (d) => center(d),
    perpendicular: (d) => normal(d),
    lanePoints(track, samplesPerUnit = 4) {
      const count = targetScore * samplesPerUnit;
      const points = [];
      for (let i = 0; i <= count; i++) points.push(lane((targetScore * i) / count, track));
      return points;
    },
  };
}

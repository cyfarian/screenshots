// Node test for the JS engine port. Mirrors CribbageEngineTests anchors.
// Run: node --test web/engine.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  card, scoreHand, starterIsHeels, fullDeck, cardValue,
  newGame, peg, undo, completeHand, trackScore, pegPositions,
  winnerTrack, isOver, dealerSeat, cribTrack, skunkResult,
  newMatch, matchPoints, matchWinner, gameResult, computeStats,
  boardLayout, trackName,
} from "./engine.js";

const C = (r, s) => card(r, s);

test("perfect 29 hand", () => {
  const b = scoreHand([C(5, "hearts"), C(5, "diamonds"), C(5, "spades"), C(11, "clubs")], C(5, "clubs"));
  assert.equal(b.total, 29);
  assert.equal(b.items.filter((i) => i.kind === "fifteen").length, 8);
  assert.equal(b.items.filter((i) => i.kind === "pair").length, 6);
  assert.equal(b.items.filter((i) => i.kind === "nobs").length, 1);
});

test("zero hand", () => {
  const b = scoreHand([C(2, "clubs"), C(4, "hearts"), C(6, "diamonds"), C(8, "spades")], C(10, "hearts"));
  assert.equal(b.total, 0);
});

test("4-4-5-6-6 double double run = 24", () => {
  const b = scoreHand([C(4, "clubs"), C(4, "diamonds"), C(5, "hearts"), C(6, "spades")], C(6, "diamonds"));
  assert.equal(b.total, 24);
  assert.equal(b.items.filter((i) => i.kind === "run").reduce((s, i) => s + i.points, 0), 12);
});

test("triple run 3-3-3-4 + 5 = 21", () => {
  const b = scoreHand([C(3, "clubs"), C(3, "diamonds"), C(3, "hearts"), C(4, "spades")], C(5, "clubs"));
  assert.equal(b.total, 21);
});

test("run of five = 9", () => {
  const b = scoreHand([C(6, "clubs"), C(7, "diamonds"), C(8, "hearts"), C(9, "spades")], C(10, "clubs"));
  assert.equal(b.total, 9);
  const runs = b.items.filter((i) => i.kind === "run");
  assert.equal(runs.length, 1);
  assert.equal(runs[0].points, 5);
});

test("no wrap-around runs", () => {
  const b = scoreHand([C(12, "clubs"), C(13, "diamonds"), C(1, "hearts"), C(7, "spades")], C(4, "clubs"));
  assert.equal(b.items.filter((i) => i.kind === "run").length, 0);
});

test("flush rules incl. crib", () => {
  const hand = [C(2, "hearts"), C(6, "hearts"), C(9, "hearts"), C(13, "hearts")];
  assert.equal(scoreHand(hand, C(4, "clubs")).total, 8);
  assert.equal(scoreHand(hand, C(4, "clubs"), true).total, 4);
  assert.equal(scoreHand(hand, C(4, "hearts"), true).total, 9);
});

test("nobs and heels", () => {
  const b = scoreHand([C(11, "diamonds"), C(2, "clubs"), C(6, "hearts"), C(9, "spades")], C(13, "diamonds"));
  assert.equal(b.total, 3);
  assert.ok(starterIsHeels(C(11, "clubs")));
  assert.ok(!starterIsHeels(C(10, "clubs")));
});

test("brute force vs naive scorer over random hands", () => {
  let seed = 0xc41bba6e >>> 0;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  for (let trial = 0; trial < 2000; trial++) {
    const deck = fullDeck();
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(rand() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    const hand = deck.slice(0, 4);
    const starter = deck[4];
    const isCrib = rand() < 0.5;
    assert.equal(
      scoreHand(hand, starter, isCrib).total,
      naiveScore(hand, starter, isCrib),
      JSON.stringify({ hand, starter, isCrib })
    );
  }
});

function naiveScore(hand, starter, isCrib) {
  const all = [...hand, starter];
  let points = 0;
  // fifteens by recursion
  const count15 = (idx, sum, size) => {
    if (idx === all.length) return sum === 15 && size >= 2 ? 1 : 0;
    return count15(idx + 1, sum, size) + count15(idx + 1, sum + cardValue(all[idx].rank), size + 1);
  };
  points += 2 * count15(0, 0, 0);
  // pairs from rank counts
  const counts = {};
  for (const c of all) counts[c.rank] = (counts[c.rank] ?? 0) + 1;
  for (const n of Object.values(counts)) points += n * (n - 1);
  // runs: longest straight subsets
  outer: for (let len = 5; len >= 3; len--) {
    let straights = 0;
    for (let mask = 0; mask < 32; mask++) {
      const subset = all.filter((_, i) => mask & (1 << i));
      if (subset.length !== len) continue;
      const ranks = subset.map((c) => c.rank).sort((a, b) => a - b);
      const distinct = new Set(ranks).size === len;
      if (distinct && ranks[len - 1] - ranks[0] === len - 1) straights++;
    }
    if (straights > 0) { points += len * straights; break outer; }
  }
  // flush
  if (hand.every((c) => c.suit === hand[0].suit)) {
    if (starter.suit === hand[0].suit) points += 5;
    else if (!isCrib) points += 4;
  }
  // nobs
  if (hand.some((c) => c.rank === 11 && c.suit === starter.suit)) points += 1;
  return points;
}

test("game: scores, pegs, undo, win, skunk", () => {
  const game = newGame({ mode: "twoPlayer", playerNames: ["Alice", "Bob"] });
  peg(game, 0, 6, "handCount");
  peg(game, 0, 4, "cribCount");
  peg(game, 1, 3, "run3");
  assert.equal(trackScore(game, 0), 10);
  assert.deepEqual(pegPositions(game, 0), { front: 10, back: 6 });
  undo(game);
  assert.equal(trackScore(game, 1), 0);

  peg(game, 1, 70, "manual");
  peg(game, 0, 120, "manual");
  assert.ok(isOver(game));
  assert.equal(winnerTrack(game), 0);
  assert.equal(trackScore(game, 0), 121);
  assert.equal(skunkResult(game, 1), "skunk");
  assert.equal(skunkResult(game, 0), null);
  assert.throws(() => peg(game, 1, 2, "pair"));
  undo(game);
  assert.ok(!isOver(game));
});

test("dealer rotation incl. partners", () => {
  const game = newGame({ mode: "fourPlayerPartners", playerNames: ["A", "B", "C", "D"], teamNames: ["T1", "T2"] });
  assert.equal(dealerSeat(game), 0);
  assert.equal(cribTrack(game), 0);
  completeHand(game);
  assert.equal(dealerSeat(game), 1);
  assert.equal(cribTrack(game), 1);
  completeHand(game);
  assert.equal(cribTrack(game), 0);
  undo(game);
  assert.equal(dealerSeat(game), 1);
  assert.equal(trackName(game.config, 0), "T1");
});

test("match with skunk weighting", () => {
  const game = newGame({ mode: "twoPlayer", playerNames: ["A", "B"] });
  peg(game, 1, 70, "manual");
  peg(game, 0, 121, "manual");
  const match = newMatch({ bestOf: 3, skunksCountExtra: true });
  match.results.push(gameResult(game));
  assert.equal(matchPoints(match, 0), 2);
  assert.equal(matchWinner(match, 2), 0);
  const plain = newMatch({ bestOf: 3, skunksCountExtra: false });
  plain.results.push(gameResult(game));
  assert.equal(matchWinner(plain, 2), null);
});

test("stats", () => {
  const game = newGame({ mode: "twoPlayer", playerNames: ["Alice", "Bob"] });
  peg(game, 0, 12, "handCount");
  peg(game, 1, 8, "handCount");
  peg(game, 0, 121, "manual");
  const stats = computeStats([game]);
  const alice = stats.find((s) => s.name === "Alice");
  const bob = stats.find((s) => s.name === "Bob");
  assert.equal(alice.wins, 1);
  assert.equal(alice.bestHand, 12);
  assert.equal(alice.skunksGiven, 1);
  assert.equal(bob.skunksTaken, 1);
  assert.equal(bob.handPointsTotal / bob.handsCounted, 8);
});

test("board layout geometry", () => {
  for (const tc of [1, 2, 3]) {
    const lay = boardLayout(tc);
    for (let t = 0; t < tc; t++) {
      for (let h = 0; h <= 121; h++) {
        const p = lay.position(h, t);
        assert.ok(p.x > 0 && p.x < lay.size.width);
        assert.ok(p.y > 0 && p.y < lay.size.height);
      }
    }
  }
  const lay = boardLayout(2);
  // even spacing along the path
  for (let h = 0; h < 121; h++) {
    const a = lay.centerPosition(h);
    const b = lay.centerPosition(h + 1);
    const d = Math.hypot(a.x - b.x, a.y - b.y);
    assert.ok(d > 0.5 && d < 1.01, `hole ${h}: ${d}`);
  }
  // constant lane separation
  const three = boardLayout(3);
  for (let h = 0; h <= 121; h++) {
    const a = three.position(h, 0);
    const b = three.position(h, 1);
    assert.ok(Math.abs(Math.hypot(a.x - b.x, a.y - b.y) - 1) < 1e-6);
  }
  // start bottom-left, finish bottom-right
  const start = lay.centerPosition(0);
  const finish = lay.centerPosition(121);
  assert.ok(start.x < lay.size.width * 0.3 && start.y > lay.size.height * 0.55);
  assert.ok(finish.x > lay.size.width * 0.7 && finish.y > lay.size.height * 0.55);
});

test("shared fixtures (same file the Swift engine tests use)", async () => {
  const fs = await import("node:fs");
  const data = JSON.parse(fs.readFileSync(new URL("../shared/hand-fixtures.json", import.meta.url)));
  for (const f of data.fixtures) {
    const total = scoreHand(f.hand, f.starter, f.isCrib).total;
    assert.equal(total, f.expectedTotal, f.name);
  }
});

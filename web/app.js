/* Cribbage Score — UI layer. All rules live in engine.js. */
import * as E from "./engine.js";

const $ = (id) => document.getElementById(id);
const VERSION = "1.0.0";

// ------------------------------------------------------------------- Storage

const store = {
  load(key, fallback) {
    try {
      const raw = localStorage.getItem("cribbage." + key);
      return raw ? JSON.parse(raw) : fallback;
    } catch {
      return fallback;
    }
  },
  save(key, value) {
    localStorage.setItem("cribbage." + key, JSON.stringify(value));
  },
  remove(key) {
    localStorage.removeItem("cribbage." + key);
  },
};

let session = store.load("session", null); // { game, match|null }
let finished = store.load("finished", []); // [game]
let settings = store.load("settings", { muggins: false, skunkx: false });

function persistSession() {
  if (session) store.save("session", session);
  else store.remove("session");
}

// ---------------------------------------------------------------- Navigation

const VIEWS = ["home", "game", "calc", "history", "settings"];
const TITLES = { home: "Cribbage", game: "Game", calc: "Hand Calculator", history: "History", settings: "Settings" };
let navStack = ["home"];
let selectedTrack = 0;
let calcPegTarget = null; // track index when opened from a game

function show(view, { fromGame = false } = {}) {
  if (view === "calc") calcPegTarget = fromGame ? selectedTrack : null;
  navStack.push(view);
  render();
}

function back() {
  if (navStack.length > 1) navStack.pop();
  render();
}

$("nav-back").addEventListener("click", back);
document.querySelectorAll("[data-nav]").forEach((el) =>
  el.addEventListener("click", () => show(el.dataset.nav, { fromGame: el.id === "btn-count" }))
);

// ------------------------------------------------------------------- Render

function render() {
  const view = navStack[navStack.length - 1];
  for (const v of VIEWS) $("view-" + v).hidden = v !== view;
  $("title").textContent = TITLES[view];
  $("nav-back").hidden = navStack.length <= 1;
  if (view === "home") renderHome();
  if (view === "game") renderGame();
  if (view === "calc") renderCalc();
  if (view === "history") renderHistory();
  if (view === "settings") renderSettings();
}

// ---------------------------------------------------------------------- Home

function renderHome() {
  const resume = $("resume-card");
  if (session) {
    resume.hidden = false;
    const g = session.game;
    const tc = E.MODES[g.config.mode].trackCount;
    const parts = [];
    for (let t = 0; t < tc; t++) parts.push(`${E.trackName(g.config, t)} ${E.trackScore(g, t)}`);
    let line = parts.join("  •  ");
    if (session.match) line += `  ·  game ${session.match.results.length + 1} of best-of-${session.match.config.bestOf}`;
    $("resume-summary").textContent = line;
  } else {
    resume.hidden = true;
  }
  syncNewGameForm();
}

$("resume-card").addEventListener("click", () => show("game"));

function syncNewGameForm() {
  const mode = $("ng-mode").value;
  const count = E.MODES[mode].playerCount;
  const namesBox = $("ng-names");
  while (namesBox.children.length > count) namesBox.lastChild.remove();
  while (namesBox.children.length < count) {
    const i = namesBox.children.length;
    const label = document.createElement("label");
    label.className = "field";
    label.innerHTML = `<span>Player ${i + 1}</span><input id="ng-name-${i}" placeholder="Player ${i + 1}">`;
    namesBox.appendChild(label);
  }
  $("ng-teams").hidden = mode !== "fourPlayerPartners";
  const dealer = $("ng-dealer");
  const prev = Number(dealer.value || 0);
  dealer.innerHTML = "";
  for (let i = 0; i < count; i++) {
    const opt = document.createElement("option");
    opt.value = i;
    opt.textContent = playerNameInput(i);
    dealer.appendChild(opt);
  }
  dealer.value = prev < count ? prev : 0;
  $("ng-match-opts").hidden = !$("ng-match").checked;
}

function playerNameInput(i) {
  const el = $("ng-name-" + i);
  const typed = el ? el.value.trim() : "";
  return typed || `Player ${i + 1}`;
}

$("ng-mode").addEventListener("change", syncNewGameForm);
$("ng-match").addEventListener("change", syncNewGameForm);
$("ng-names").addEventListener("input", syncNewGameForm);
$("ng-cut").addEventListener("click", () => {
  const count = E.MODES[$("ng-mode").value].playerCount;
  $("ng-dealer").value = Math.floor(Math.random() * count);
});

$("ng-start").addEventListener("click", () => {
  const mode = $("ng-mode").value;
  const count = E.MODES[mode].playerCount;
  const playerNames = [...Array(count).keys()].map(playerNameInput);
  const teamNames =
    mode === "fourPlayerPartners"
      ? [$("ng-team-0").value.trim(), $("ng-team-1").value.trim()]
      : [];
  const game = E.newGame({
    mode, playerNames, teamNames,
    mugginsEnabled: $("ng-muggins").checked,
    startingDealerSeat: Number($("ng-dealer").value),
  });
  const match = $("ng-match").checked
    ? E.newMatch({ bestOf: Number($("ng-bestof").value), skunksCountExtra: $("ng-skunkx").checked })
    : null;
  session = { game, match };
  selectedTrack = 0;
  persistSession();
  navStack = ["home"];
  show("game");
});

// ---------------------------------------------------------------------- Game

const QUICK = [
  { label: "15", pts: 2, reason: "fifteen" },
  { label: "Pair", pts: 2, reason: "pair" },
  { label: "Run 3", pts: 3, reason: "run3" },
  { label: "Run 4", pts: 4, reason: "run4" },
  { label: "Run 5", pts: 5, reason: "run5" },
  { label: "Go", pts: 1, reason: "go" },
  { label: "Last", pts: 1, reason: "lastCard" },
  { label: "31", pts: 2, reason: "thirtyOne" },
  { label: "Nobs", pts: 1, reason: "nobs" },
  { label: "Heels", pts: 2, reason: "heels" },
];
let customPoints = 1;

function trackColor(t) {
  return getComputedStyle(document.documentElement).getPropertyValue(`--track${t}`).trim();
}

function renderGame() {
  if (!session) {
    navStack = ["home"];
    render();
    return;
  }
  const g = session.game;
  const tc = E.MODES[g.config.mode].trackCount;
  if (selectedTrack >= tc) selectedTrack = 0;

  // Score cards
  const cards = $("score-cards");
  cards.innerHTML = "";
  const crib = E.cribTrack(g);
  for (let t = 0; t < tc; t++) {
    const el = document.createElement("div");
    el.className = "score-card";
    const selected = t === selectedTrack;
    el.style.borderColor = selected ? trackColor(t) : "transparent";
    el.style.background = selected ? `color-mix(in srgb, ${trackColor(t)} 14%, var(--card))` : "";
    el.innerHTML = `
      <div class="name">${esc(E.trackName(g.config, t))}</div>
      <div class="pts" style="color:${trackColor(t)}">${E.trackScore(g, t)}</div>
      <div class="crib-badge">${t === crib ? "🂠 crib" : "&nbsp;"}</div>`;
    el.addEventListener("click", () => { selectedTrack = t; renderGame(); });
    cards.appendChild(el);
  }

  // Meta line
  const dealer = g.config.playerNames[E.dealerSeat(g)];
  let meta = `<span>${esc(dealer)} deals</span>`;
  if (session.match) {
    const pts = [...Array(tc).keys()].map((t) => E.matchPoints(session.match, t));
    meta += `<span>Match ${pts.join("–")} · best of ${session.match.config.bestOf}</span>`;
  }
  $("game-meta").innerHTML = meta;

  drawBoard(g);

  // Game over vs peg pad
  const over = E.isOver(g);
  $("game-over").hidden = !over;
  $("peg-pad").hidden = over;
  if (over) renderGameOver(g, tc);
  else renderPegPad(g);
}

function renderPegPad(g) {
  const grid = $("quick-grid");
  grid.innerHTML = "";
  for (const q of QUICK) {
    const b = document.createElement("button");
    b.innerHTML = `<span class="q-label">${q.label}</span><span class="q-pts">+${q.pts}</span>`;
    b.style.borderColor = trackColor(selectedTrack);
    b.addEventListener("click", () => doPeg(selectedTrack, q.pts, q.reason));
    grid.appendChild(b);
  }
  $("custom-peg").textContent = `Peg +${customPoints}`;
  $("custom-peg").style.background = trackColor(selectedTrack);
  $("custom-peg").style.borderColor = trackColor(selectedTrack);
  $("btn-undo").disabled = g.events.length === 0;

  const list = $("events-list");
  list.innerHTML = "";
  for (const e of [...g.events].reverse()) {
    const li = document.createElement("li");
    li.innerHTML = `
      <span class="dot" style="background:${trackColor(e.track)}"></span>
      <span>${esc(E.trackName(g.config, e.track))}</span>
      <span class="muted">${E.REASON_LABEL[e.reason] ?? e.reason}</span>
      ${e.points > 0 ? `<span class="pts">+${e.points}</span>` : ""}`;
    list.appendChild(li);
  }
}

function renderGameOver(g, tc) {
  const winner = E.winnerTrack(g);
  const name = E.trackName(g.config, winner);
  const losers = [...Array(tc).keys()].filter((t) => t !== winner);
  const scoreline = `${E.trackScore(g, winner)}–${losers.map((t) => E.trackScore(g, t)).join("–")}`;
  const skunkLines = losers
    .map((t) => {
      const level = E.skunkResult(g, t);
      if (level === "skunk") return `${E.trackName(g.config, t)} was skunked!`;
      if (level === "doubleSkunk") return `${E.trackName(g.config, t)} was double-skunked!`;
      return null;
    })
    .filter(Boolean);
  const matchOngoing = session.match && E.matchWinner(withResult(session.match, g), tc) === null;

  const box = $("game-over");
  box.innerHTML = `
    <div class="headline">🏆 ${esc(name)} wins ${scoreline}</div>
    ${skunkLines.map((l) => `<div class="skunkline">${esc(l)}</div>`).join("")}
    <div class="buttons">
      <button id="go-undo">↩︎ Undo last peg</button>
      <button id="go-next" class="primary" style="width:auto">
        ${matchOngoing ? "Next game" : "Finish"}
      </button>
    </div>`;
  $("go-undo").addEventListener("click", () => { E.undo(session.game); persistSession(); renderGame(); });
  $("go-next").addEventListener("click", () => concludeGame(matchOngoing));
}

function withResult(match, game) {
  return { ...match, results: [...match.results, E.gameResult(game)] };
}

function concludeGame(startNext) {
  const g = session.game;
  finished.unshift(g);
  store.save("finished", finished);
  if (session.match) session.match.results.push(E.gameResult(g));

  if (startNext && session.match) {
    const config = { ...g.config };
    const winner = E.winnerTrack(g);
    const seats = [...Array(E.MODES[config.mode].playerCount).keys()];
    const loserSeats = seats.filter((s) => E.trackForSeat(config.mode, s) !== winner);
    config.startingDealerSeat = loserSeats[0] ?? 0; // loser deals first next game
    session.game = E.newGame(config);
    persistSession();
    renderGame();
  } else {
    session = null;
    persistSession();
    navStack = ["home"];
    render();
  }
}

function doPeg(track, points, reason, breakdown = null) {
  try {
    E.peg(session.game, track, points, reason, breakdown);
    persistSession();
    if (navigator.vibrate) navigator.vibrate(8);
    renderGame();
  } catch {
    /* game over — board already showing the panel */
  }
}

$("custom-minus").addEventListener("click", () => { customPoints = Math.max(1, customPoints - 1); renderGame(); });
$("custom-plus").addEventListener("click", () => { customPoints = Math.min(29, customPoints + 1); renderGame(); });
$("custom-peg").addEventListener("click", () => doPeg(selectedTrack, customPoints, "manual"));
$("btn-undo").addEventListener("click", () => { E.undo(session.game); persistSession(); renderGame(); });
$("btn-nexthand").addEventListener("click", () => {
  try { E.completeHand(session.game); persistSession(); renderGame(); } catch { /* over */ }
});
$("btn-abandon").addEventListener("click", () => {
  if (confirm("Abandon this game? It won't be saved.")) {
    session = null;
    persistSession();
    navStack = ["home"];
    render();
  }
});

// ---------------------------------------------------------------- The board

function drawBoard(g) {
  const canvas = $("board");
  const layout = E.boardLayout(E.MODES[g.config.mode].trackCount, 6, g.config.targetScore);
  const cssWidth = canvas.parentElement.clientWidth - 0;
  const cssHeight = Math.round(cssWidth / layout.aspectRatio);
  const dpr = window.devicePixelRatio || 1;
  canvas.style.height = cssHeight + "px";
  canvas.width = Math.round(cssWidth * dpr);
  canvas.height = Math.round(cssHeight * dpr);
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);

  const scale = Math.min(cssWidth / layout.size.width, cssHeight / layout.size.height);
  const offX = (cssWidth - layout.size.width * scale) / 2;
  const offY = (cssHeight - layout.size.height * scale) / 2;
  const P = (p) => [offX + p.x * scale, offY + p.y * scale];

  const styles = getComputedStyle(document.documentElement);
  const textColor = styles.getPropertyValue("--text").trim();
  const mutedColor = styles.getPropertyValue("--muted").trim();
  const orange = styles.getPropertyValue("--orange").trim();
  const tc = layout.trackCount;
  const halfWidth = ((tc - 1) * layout.laneGap) / 2;

  // Lane ribbons
  for (let t = 0; t < tc; t++) {
    const pts = layout.lanePoints(t);
    ctx.beginPath();
    ctx.moveTo(...P(pts[0]));
    for (const p of pts.slice(1)) ctx.lineTo(...P(p));
    ctx.strokeStyle = trackColor(t);
    ctx.globalAlpha = 0.16;
    ctx.lineWidth = 0.82 * layout.laneGap * scale;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // Ticks + labels
  const skunkHoles = new Set([g.config.skunkThreshold - 1, g.config.doubleSkunkThreshold - 1]);
  ctx.strokeStyle = mutedColor;
  ctx.fillStyle = mutedColor;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  for (let hole = 5; hole < layout.targetScore; hole += 5) {
    const c = layout.centerPosition(hole);
    const n = layout.perpendicular(hole);
    if (!skunkHoles.has(hole)) {
      const r = halfWidth + 0.55;
      ctx.globalAlpha = 0.5;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(...P({ x: c.x + r * n.x, y: c.y + r * n.y }));
      ctx.lineTo(...P({ x: c.x - r * n.x, y: c.y - r * n.y }));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    if (hole % 10 === 0 && !skunkHoles.has(hole)) {
      const r = halfWidth + 1.05;
      ctx.font = `500 ${Math.max(7, 0.5 * scale)}px -apple-system, sans-serif`;
      ctx.fillText(String(hole), ...P({ x: c.x + r * n.x, y: c.y + r * n.y }));
    }
  }

  // Holes
  ctx.fillStyle = textColor;
  ctx.globalAlpha = 0.45;
  for (let t = 0; t < tc; t++) {
    for (let hole = 0; hole <= layout.targetScore; hole++) {
      const [x, y] = P(layout.position(hole, t));
      const rad = (hole > 0 && hole % 5 === 0 ? 0.16 : 0.12) * layout.laneGap * scale;
      ctx.beginPath();
      ctx.arc(x, y, rad, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.globalAlpha = 1;

  // Skunk lines
  for (const [hole, label] of [[g.config.skunkThreshold - 1, "S"], [g.config.doubleSkunkThreshold - 1, "SS"]]) {
    if (hole <= 0 || hole >= layout.targetScore) continue;
    const c = layout.centerPosition(hole);
    const n = layout.perpendicular(hole);
    const r = halfWidth + 0.7;
    ctx.strokeStyle = orange;
    ctx.lineWidth = Math.max(2, 0.12 * scale);
    ctx.beginPath();
    ctx.moveTo(...P({ x: c.x + r * n.x, y: c.y + r * n.y }));
    ctx.lineTo(...P({ x: c.x - r * n.x, y: c.y - r * n.y }));
    ctx.stroke();
    ctx.fillStyle = orange;
    ctx.font = `700 ${Math.max(7, 0.45 * scale)}px -apple-system, sans-serif`;
    ctx.fillText(label, ...P({ x: c.x + (r + 0.55) * n.x, y: c.y + (r + 0.55) * n.y }));
  }

  // Start/finish
  ctx.fillStyle = mutedColor;
  ctx.font = `600 ${Math.max(7, 0.42 * scale)}px -apple-system, sans-serif`;
  const start = layout.centerPosition(0);
  const finish = layout.centerPosition(layout.targetScore);
  ctx.fillText("START", ...P({ x: start.x, y: start.y + 0.9 }));
  ctx.fillText("FINISH", ...P({ x: finish.x, y: finish.y + 0.9 }));

  // Pegs
  for (let t = 0; t < tc; t++) {
    const pegs = E.pegPositions(g, t);
    for (const [hole, front] of [[pegs.back, false], [pegs.front, true]]) {
      const [x, y] = P(layout.position(hole, t));
      const rad = (front ? 0.36 : 0.28) * layout.laneGap * scale;
      ctx.beginPath();
      ctx.arc(x, y, rad, 0, Math.PI * 2);
      ctx.fillStyle = trackColor(t);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.9)";
      ctx.lineWidth = Math.max(1, 0.06 * scale);
      ctx.stroke();
    }
  }
}

window.addEventListener("resize", () => {
  if (navStack[navStack.length - 1] === "game" && session) drawBoard(session.game);
});

// ------------------------------------------------------------------- Calc

let calcSelection = [];

function buildCardGrid() {
  const grid = $("card-grid");
  grid.innerHTML = "";
  for (const suit of ["spades", "hearts", "diamonds", "clubs"]) {
    for (let rank = 1; rank <= 13; rank++) {
      const b = document.createElement("button");
      b.className = E.isRed(suit) ? "red" : "";
      b.dataset.rank = rank;
      b.dataset.suit = suit;
      b.innerHTML = `<span class="r">${E.RANK_SYMBOL[rank]}</span>${E.SUIT_SYMBOL[suit]}`;
      b.addEventListener("click", () => toggleCard(rank, suit));
      grid.appendChild(b);
    }
  }
}
buildCardGrid();

function toggleCard(rank, suit) {
  const idx = calcSelection.findIndex((c) => c.rank === rank && c.suit === suit);
  if (idx >= 0) calcSelection.splice(idx, 1);
  else if (calcSelection.length < 5) calcSelection.push(E.card(rank, suit));
  renderCalc();
}

$("calc-crib").addEventListener("change", renderCalc);
$("calc-clear").addEventListener("click", () => { calcSelection = []; renderCalc(); });

function renderCalc() {
  // Slots
  const slots = $("calc-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 5; i++) {
    const div = document.createElement("div");
    const c = calcSelection[i];
    div.className = "slot" + (i === 4 ? " starter" : "") + (c && E.isRed(c.suit) ? " red" : "");
    div.textContent = c ? E.cardName(c) : "—";
    slots.appendChild(div);
  }
  // Grid selection state
  for (const b of $("card-grid").children) {
    const idx = calcSelection.findIndex(
      (c) => c.rank === Number(b.dataset.rank) && c.suit === b.dataset.suit
    );
    b.classList.toggle("sel", idx >= 0 && idx < 4);
    b.classList.toggle("starter-sel", idx === 4);
    b.disabled = idx < 0 && calcSelection.length >= 5;
  }
  $("calc-clear").hidden = calcSelection.length === 0;

  const result = $("calc-result");
  const pegBox = $("calc-peg");
  if (calcSelection.length < 5) {
    result.hidden = true;
    pegBox.hidden = true;
    return;
  }

  const hand = calcSelection.slice(0, 4);
  const starter = calcSelection[4];
  const isCrib = $("calc-crib").checked;
  const breakdown = E.scoreHand(hand, starter, isCrib);

  result.hidden = false;
  let html = `<div class="card-title">Count</div>`;
  if (breakdown.items.length === 0) html += `<div class="muted">Nineteen! (no points)</div>`;
  for (const item of breakdown.items) {
    html += `<div class="item"><span>${item.label}</span>
      <span class="cards">${item.cards.map(E.cardName).join(" ")}</span>
      <span class="p">${item.points}</span></div>`;
  }
  html += `<div class="total"><span>Total</span><span class="p">${breakdown.total}</span></div>`;
  if (E.starterIsHeels(starter)) {
    html += `<div class="muted" style="margin-top:8px">ℹ️ Starter is a jack — dealer pegs 2 for heels at the cut.</div>`;
  }
  result.innerHTML = html;

  renderCalcPeg(breakdown, isCrib);
}

let claimedPoints = null;

function renderCalcPeg(breakdown, isCrib) {
  const pegBox = $("calc-peg");
  const g = session?.game;
  if (calcPegTarget === null || !g || E.isOver(g)) {
    pegBox.hidden = true;
    return;
  }
  pegBox.hidden = false;
  const track = calcPegTarget;
  const name = E.trackName(g.config, track);
  const reason = isCrib ? "cribCount" : "handCount";
  const claimed = claimedPoints ?? breakdown.total;

  let html = `<div class="card-title">Peg it</div>
    <button id="peg-full" class="primary" ${breakdown.total === 0 ? "disabled" : ""}>
      Peg ${breakdown.total} for ${esc(name)}</button>`;

  if (g.config.mugginsEnabled && breakdown.total > 0) {
    html += `<div id="claimed-row">
        <button class="stepper" id="claim-minus">−</button>
        <span class="claimed-val">Claimed: ${claimed}</span>
        <button class="stepper" id="claim-plus">+</button>
      </div>`;
    if (claimed < breakdown.total) {
      const missed = breakdown.total - claimed;
      if (claimed > 0) {
        html += `<button id="peg-claimed">Peg claimed ${claimed} for ${esc(name)}</button>`;
      }
      const tc = E.MODES[g.config.mode].trackCount;
      for (let other = 0; other < tc; other++) {
        if (other === track) continue;
        html += `<button class="muggins-btn" data-mug="${other}">
          Muggins! ${esc(E.trackName(g.config, other))} takes the missed ${missed}</button>`;
      }
    }
  }
  pegBox.innerHTML = html;

  $("peg-full").addEventListener("click", () => {
    doPeg(track, breakdown.total, reason, breakdown);
    finishCalcPeg();
  });
  $("claim-minus")?.addEventListener("click", () => {
    claimedPoints = Math.max(0, (claimedPoints ?? breakdown.total) - 1);
    renderCalc();
  });
  $("claim-plus")?.addEventListener("click", () => {
    claimedPoints = Math.min(breakdown.total, (claimedPoints ?? breakdown.total) + 1);
    renderCalc();
  });
  $("peg-claimed")?.addEventListener("click", () => {
    doPeg(track, claimed, reason, breakdown);
    finishCalcPeg();
  });
  pegBox.querySelectorAll("[data-mug]").forEach((b) =>
    b.addEventListener("click", () => {
      const missed = breakdown.total - claimed;
      if (claimed > 0) doPeg(track, claimed, reason, breakdown);
      doPeg(Number(b.dataset.mug), missed, "muggins");
      finishCalcPeg();
    })
  );
}

function finishCalcPeg() {
  calcSelection = [];
  claimedPoints = null;
  $("calc-crib").checked = false;
  back();
}

// ----------------------------------------------------------------- History

function renderHistory() {
  const statsBox = $("stats-cards");
  statsBox.innerHTML = "";
  const stats = E.computeStats(finished);
  for (const s of stats) {
    const card = document.createElement("div");
    card.className = "card stat-card";
    let html = `<div class="card-title">${esc(s.name)}</div>
      <div class="stat-row"><span>Record</span><span class="v">${s.wins}–${s.gamesPlayed - s.wins}</span></div>
      <div class="stat-row"><span>Skunks given / taken</span><span class="v">${s.skunksGiven} / ${s.skunksTaken}</span></div>`;
    if (s.handsCounted > 0) {
      html += `<div class="stat-row"><span>Average hand</span><span class="v">${(s.handPointsTotal / s.handsCounted).toFixed(1)}</span></div>
        <div class="stat-row"><span>Best hand</span><span class="v">${s.bestHand}</span></div>`;
    }
    card.innerHTML = html;
    statsBox.appendChild(card);
  }

  const list = $("games-list");
  list.innerHTML = "";
  if (finished.length === 0) {
    list.innerHTML = `<li class="muted">No finished games yet.</li>`;
    return;
  }
  finished.forEach((g, index) => {
    const tc = E.MODES[g.config.mode].trackCount;
    const winner = E.winnerTrack(g);
    const scores = [...Array(tc).keys()]
      .map((t) => `${E.trackName(g.config, t)} ${E.trackScore(g, t)}`)
      .join("  •  ");
    const skunk = [...Array(tc).keys()]
      .map((t) => E.skunkResult(g, t))
      .find((lvl) => lvl === "skunk" || lvl === "doubleSkunk");
    const when = new Date(g.completedAt ?? g.createdAt).toLocaleDateString(undefined, {
      month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
    });
    const li = document.createElement("li");
    li.innerHTML = `
      <div class="g-head">🏆 ${esc(E.trackName(g.config, winner))}
        ${skunk ? `<span class="skunk-pill">${skunk === "doubleSkunk" ? "double skunk" : "skunk"}</span>` : ""}
        <span class="g-date">${when}</span></div>
      <div class="g-scores">${esc(scores)}</div>`;
    li.addEventListener("click", () => {
      if (confirm("Delete this game from history?")) {
        finished.splice(index, 1);
        store.save("finished", finished);
        renderHistory();
      }
    });
    list.appendChild(li);
  });
}

// ---------------------------------------------------------------- Settings

function renderSettings() {
  $("set-muggins").checked = settings.muggins;
  $("set-skunkx").checked = settings.skunkx;
  $("version-line").textContent = `Version ${VERSION}`;
}
$("set-muggins").addEventListener("change", (e) => {
  settings.muggins = e.target.checked;
  store.save("settings", settings);
  $("ng-muggins").checked = settings.muggins;
});
$("set-skunkx").addEventListener("change", (e) => {
  settings.skunkx = e.target.checked;
  store.save("settings", settings);
  $("ng-skunkx").checked = settings.skunkx;
});

// ------------------------------------------------------------------- Util

function esc(s) {
  return String(s).replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[ch]);
}

// ------------------------------------------------------------------- Boot

$("ng-muggins").checked = settings.muggins;
$("ng-skunkx").checked = settings.skunkx;
syncNewGameForm();
render();

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

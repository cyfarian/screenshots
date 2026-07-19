/* Cribbage Score — UI layer. All rules live in engine.js. */
import * as E from "./engine.js";

const $ = (id) => document.getElementById(id);
const TROPHY = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 21h8M12 17v4M7 4h10v6a5 5 0 0 1-10 0V4z"/><path d="M7 5H4.5a1.8 1.8 0 0 0 .3 3.6L7 9M17 5h2.5a1.8 1.8 0 0 1-.3 3.6L17 9"/></svg>';
const VERSION = "1.4.0";
const SCHEMA_VERSION = 1;

// ------------------------------------------------------------------- Storage
// Values are wrapped as {v, data}. Legacy (unwrapped) values from 1.0.x are
// migrated transparently on load.

const store = {
  load(key, fallback) {
    try {
      const raw = localStorage.getItem("cribbage." + key);
      if (raw === null) return fallback;
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && "v" in parsed && "data" in parsed) {
        return migrate(parsed.v, parsed.data) ?? fallback;
      }
      return migrate(0, parsed) ?? fallback; // pre-versioning payload
    } catch {
      return fallback;
    }
  },
  save(key, value) {
    try {
      localStorage.setItem("cribbage." + key, JSON.stringify({ v: SCHEMA_VERSION, data: value }));
    } catch (err) {
      showToast("Couldn't save — storage full?", false);
    }
  },
  remove(key) {
    localStorage.removeItem("cribbage." + key);
  },
};

function migrate(fromVersion, data) {
  // v0 -> v1: identical shape, just unwrapped. Future migrations chain here.
  return data;
}

let session = store.load("session", null); // { game, match|null }
let finished = store.load("finished", []); // [game]
let settings = store.load("settings", {
  muggins: false, skunkx: false, palette: "classic", hintSeen: false,
  scoreStyle: "numbers", // "numbers" (big +1..+5 build-up) | "named" (combo buttons)
  boardZoom: false,
});
if (!settings.scoreStyle) settings.scoreStyle = "numbers";

function persistSession() {
  if (session) store.save("session", session);
  else store.remove("session");
}
function persistSettings() {
  store.save("settings", settings);
}

// ------------------------------------------------------------------ Palettes

const PALETTES = {
  classic: ["#c62f2b", "#2757c8", "#1d8a44"],
  colorblind: ["#0072b2", "#e69f00", "#009e73"], // Okabe–Ito: safe for common CVD
  modern: ["#7c4dff", "#00897b", "#f4511e"],
};

function applyPalette() {
  const colors = PALETTES[settings.palette] ?? PALETTES.classic;
  colors.forEach((c, i) => document.documentElement.style.setProperty(`--track${i}`, c));
}
function trackColor(t) {
  return (PALETTES[settings.palette] ?? PALETTES.classic)[t % 3];
}

// ------------------------------------------------------------------- Tabs

const TABS = ["game", "calc", "history", "settings"];
const TITLES = { game: "Cribbage", calc: "Count", history: "History", settings: "Settings" };
let currentTab = "game";
let selectedTrack = 0;

function switchTab(tab, { skipChooser = false } = {}) {
  // During a game, the Count tab first asks HOW to count.
  if (tab === "calc" && session && !skipChooser) {
    $("count-modal").hidden = false;
    return;
  }
  currentTab = tab;
  for (const t of TABS) $("view-" + t).hidden = t !== tab;
  document.querySelectorAll("#tabbar .tab").forEach((b) =>
    b.classList.toggle("active", b.dataset.tab === tab)
  );
  $("title").textContent = TITLES[tab];
  if (tab === "game") renderGameTab();
  if (tab === "calc") renderCalc();
  if (tab === "history") renderHistory();
  if (tab === "settings") renderSettings();
  $("nav-close").hidden = !(tab === "calc" || tab === "settings");
  updateWakeLock();
}

$("nav-close").addEventListener("click", () => switchTab("game"));

$("count-numbers").addEventListener("click", () => {
  settings.scoreStyle = "numbers";
  persistSettings();
  $("count-modal").hidden = true;
  switchTab("game");
});
$("count-named").addEventListener("click", () => {
  settings.scoreStyle = "named";
  persistSettings();
  $("count-modal").hidden = true;
  switchTab("game");
});
$("count-cards").addEventListener("click", () => {
  $("count-modal").hidden = true;
  switchTab("calc", { skipChooser: true });
});
$("count-cancel").addEventListener("click", () => {
  $("count-modal").hidden = true;
});

document.querySelectorAll("#tabbar .tab").forEach((b) =>
  b.addEventListener("click", () => switchTab(b.dataset.tab))
);

// ------------------------------------------------------------------ Wake lock
// Keep the screen on while a game is live (the phone sits on the table).

let wakeLock = null;
async function updateWakeLock() {
  const want = currentTab === "game" && !!session && "wakeLock" in navigator;
  if (want && !wakeLock) {
    try {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", () => { wakeLock = null; });
    } catch { /* low battery mode etc. — not fatal */ }
  } else if (!want && wakeLock) {
    try { await wakeLock.release(); } catch {}
    wakeLock = null;
  }
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") updateWakeLock();
});

// --------------------------------------------------------------------- Toast

let toastTimer = null;
function showToast(text, undoable = true) {
  $("toast-text").textContent = text;
  $("toast-undo").hidden = !undoable;
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $("toast").hidden = true; }, 3500);
}
$("toast-undo").addEventListener("click", () => {
  if (session) {
    E.undo(session.game);
    persistSession();
    renderGameTab();
  }
  $("toast").hidden = true;
});

function announce(text) {
  $("sr-announce").textContent = text;
}

// ------------------------------------------------------------------ Game tab

function renderGameTab() {
  const live = !!session;
  $("game-setup").hidden = live;
  $("game-live").hidden = !live;
  if (live) {
    renderLiveGame();
    maybeShowHint();
  } else {
    syncNewGameForm();
  }
  updateWakeLock();
}

function maybeShowHint() {
  if (!settings.hintSeen) $("hint-overlay").hidden = false;
}
$("hint-done").addEventListener("click", () => {
  settings.hintSeen = true;
  persistSettings();
  $("hint-overlay").hidden = true;
});

// --- New game form ---

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
  pending = 0;
  animState = null;
  persistSession();
  renderGameTab();
});

// --- Live game ---

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
let pending = 0;

function renderLiveGame() {
  const g = session.game;
  const tc = E.MODES[g.config.mode].trackCount;
  if (selectedTrack >= tc) selectedTrack = 0;

  // Score cards
  const cards = $("score-cards");
  cards.innerHTML = "";
  const crib = E.cribTrack(g);
  for (let t = 0; t < tc; t++) {
    const el = document.createElement("button");
    el.className = "score-card";
    const selected = t === selectedTrack;
    el.setAttribute("role", "tab");
    el.setAttribute("aria-selected", selected ? "true" : "false");
    el.setAttribute(
      "aria-label",
      `${E.trackName(g.config, t)}: ${E.trackScore(g, t)} points${t === crib ? ", has the crib" : ""}`
    );
    el.style.borderColor = trackColor(t);
    el.style.background = selected ? trackColor(t) : "var(--card)";
    const inkColor = selected ? "#fff" : trackColor(t);
    el.innerHTML = `
      <div class="name" style="color:${selected ? "#fff" : "var(--text)"}">${esc(E.trackName(g.config, t))}${t === crib ? " · crib" : ""}</div>
      <div class="pts" style="color:${inkColor}">${E.trackScore(g, t)}</div>`;
    el.addEventListener("click", () => {
      if (selectedTrack !== t) pending = 0; // pending points belong to a player
      selectedTrack = t;
      renderLiveGame();
    });
    cards.appendChild(el);
  }

  // Meta line
  const dealer = g.config.playerNames[E.dealerSeat(g)];
  let meta = `${esc(dealer)} deals`;
  if (session.match) {
    const pts = [...Array(tc).keys()].map((t) => E.matchPoints(session.match, t));
    meta += ` · match ${pts.join("–")} (best of ${session.match.config.bestOf})`;
  }
  $("meta-text").textContent = meta;

  scheduleBoardDraw(g);

  const over = E.isOver(g);
  $("game-over").hidden = !over;
  $("peg-pad").hidden = over;
  if (over) renderGameOver(g, tc);
  else renderPegPad(g);
}

function renderPegPad(g) {
  const numbers = settings.scoreStyle === "numbers";
  $("quick-grid").hidden = numbers;
  $("custom-row").hidden = numbers;
  $("numbers-row").hidden = !numbers;
  $("pending-row").hidden = !numbers;

  if (numbers) {
    const row = $("numbers-row");
    row.innerHTML = "";
    for (let n = 1; n <= 5; n++) {
      const b = document.createElement("button");
      b.className = "num-btn";
      b.textContent = `+${n}`;
      b.setAttribute("aria-label", `Add ${n} point${n > 1 ? "s" : ""}`);
      b.style.background = trackColor(selectedTrack);
      b.addEventListener("click", () => {
        pending = Math.min(29, pending + n);
        syncPendingButtons();
      });
      row.appendChild(b);
    }
  } else {
    const grid = $("quick-grid");
    grid.innerHTML = "";
    for (const q of QUICK) {
      const b = document.createElement("button");
      b.innerHTML = `<span class="q-label">${q.label}</span><span class="q-pts">+${q.pts}</span>`;
      b.setAttribute("aria-label", `${q.label}, ${q.pts} point${q.pts > 1 ? "s" : ""}`);
      b.style.background = trackColor(selectedTrack);
      b.addEventListener("click", () => doPeg(selectedTrack, q.pts, q.reason));
      grid.appendChild(b);
    }
  }
  syncPendingButtons();
  $("btn-undo").disabled = g.events.length === 0;
}

function syncPendingButtons() {
  for (const btn of [$("custom-peg"), $("pending-peg")]) {
    btn.textContent = pending > 0 ? `Peg +${pending}` : "Peg";
    btn.disabled = pending === 0;
    btn.style.background = pending > 0 ? trackColor(selectedTrack) : "";
    btn.style.borderColor = trackColor(selectedTrack);
  }
  $("pending-clear").disabled = pending === 0;
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
  const matchOngoing =
    session.match &&
    E.matchWinner({ ...session.match, results: [...session.match.results, E.gameResult(g)] }, tc) === null;

  const box = $("game-over");
  box.innerHTML = `
    <div class="headline">${TROPHY} ${esc(name)} wins ${scoreline}</div>
    ${skunkLines.map((l) => `<div class="skunkline">${esc(l)}</div>`).join("")}
    <div class="buttons">
      <button id="go-undo">↩︎ Undo last peg</button>
      <button id="go-next" class="primary" style="width:auto">
        ${matchOngoing ? "Next game" : "Finish"}
      </button>
    </div>`;
  announce(`${name} wins ${scoreline}`);
  $("go-undo").addEventListener("click", () => { E.undo(session.game); persistSession(); renderLiveGame(); });
  $("go-next").addEventListener("click", () => concludeGame(matchOngoing));
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
    animState = null;
    persistSession();
    renderLiveGame();
  } else {
    session = null;
    persistSession();
    renderGameTab();
  }
}

function doPeg(track, points, reason, breakdown = null) {
  try {
    const before = E.trackScore(session.game, track);
    E.peg(session.game, track, points, reason, breakdown);
    persistSession();
    if (navigator.vibrate) navigator.vibrate(8);
    startPegAnimation(track, before, E.trackScore(session.game, track));
    const name = E.trackName(session.game.config, track);
    const label = E.REASON_LABEL[reason] ?? reason;
    showToast(`+${points} ${label} — ${name}`);
    announce(`${name} pegs ${points} for ${label}, now ${E.trackScore(session.game, track)}`);
    renderLiveGame();
    return true;
  } catch {
    return false; // game already over
  }
}

$("custom-minus").addEventListener("click", () => {
  pending = Math.max(0, pending - 1);
  syncPendingButtons();
});
$("custom-plus").addEventListener("click", () => {
  pending = Math.min(29, pending + 1);
  syncPendingButtons();
});
function commitPending() {
  if (pending > 0 && doPeg(selectedTrack, pending, "manual")) {
    pending = 0; // counter zeroes out after the peg advances
    syncPendingButtons();
  }
}
$("custom-peg").addEventListener("click", commitPending);
$("pending-peg").addEventListener("click", commitPending);
$("pending-clear").addEventListener("click", () => {
  pending = 0;
  syncPendingButtons();
});
$("btn-undo").addEventListener("click", () => {
  E.undo(session.game);
  persistSession();
  renderLiveGame();
});
$("btn-count").addEventListener("click", () => switchTab("calc"));
$("btn-nexthand").addEventListener("click", () => {
  try {
    E.completeHand(session.game);
    persistSession();
    const dealer = session.game.config.playerNames[E.dealerSeat(session.game)];
    showToast(`Next hand — ${dealer} deals`, false);
    renderLiveGame();
  } catch { /* over */ }
});

$("btn-zoom").addEventListener("click", () => {
  settings.boardZoom = !settings.boardZoom;
  persistSettings();
  $("btn-zoom").setAttribute("aria-pressed", String(settings.boardZoom));
  if (session) scheduleBoardDraw(session.game);
});

// End-game modal
$("btn-newgame").addEventListener("click", () => { $("newgame-modal").hidden = false; });
$("nm-cancel").addEventListener("click", () => { $("newgame-modal").hidden = true; });
$("nm-abandon").addEventListener("click", () => {
  $("newgame-modal").hidden = true;
  session = null;
  persistSession();
  renderGameTab();
});

// ---------------------------------------------------------------- The board

let animState = null; // { track, from, to, start }
let drawQueued = false;

function scheduleBoardDraw(g) {
  if (drawQueued) return;
  drawQueued = true;
  requestAnimationFrame(() => {
    drawQueued = false;
    drawBoard(g);
  });
}

function startPegAnimation(track, fromScore, toScore) {
  animState = { track, from: fromScore, to: toScore, start: performance.now() };
}

function animatedFront(g, t) {
  const target = E.pegPositions(g, t).front;
  if (!animState || animState.track !== t) return target;
  const elapsed = performance.now() - animState.start;
  const duration = 450;
  if (elapsed >= duration) { animState = null; return target; }
  const k = 1 - Math.pow(1 - elapsed / duration, 3); // ease-out cubic
  return animState.from + (animState.to - animState.from) * k;
}

function drawBoard(g) {
  const canvas = $("board");
  const wrap = $("board-wrap");
  if (!canvas.isConnected || wrap.clientWidth === 0) return;
  const layout = E.boardLayout(E.MODES[g.config.mode].trackCount, 6, g.config.targetScore);

  // Fit inside the flexible wrapper: never force the page to scroll.
  const availW = wrap.clientWidth;
  const availH = wrap.clientHeight;
  let cssWidth = availW;
  let cssHeight = Math.round(cssWidth / layout.aspectRatio);
  if (cssHeight > availH) {
    cssHeight = availH;
    cssWidth = Math.round(cssHeight * layout.aspectRatio);
  }
  const dpr = window.devicePixelRatio || 1;
  canvas.style.width = cssWidth + "px";
  canvas.style.height = cssHeight + "px";
  canvas.width = Math.round(cssWidth * dpr);
  canvas.height = Math.round(cssHeight * dpr);
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);

  const fitScale = Math.min(cssWidth / layout.size.width, cssHeight / layout.size.height);
  let scale = fitScale;
  let offX = (cssWidth - layout.size.width * scale) / 2;
  let offY = (cssHeight - layout.size.height * scale) / 2;
  if (settings.boardZoom) {
    // Zoomed window centered on the selected player's front peg, clamped to
    // the board edges. Auto-follows because this runs every animation frame.
    scale = fitScale * 2.6;
    const tc0 = E.MODES[g.config.mode].trackCount;
    const track = Math.min(selectedTrack, tc0 - 1);
    const focus = layout.position(animatedFront(g, track), track);
    const winW = cssWidth / scale;
    const winH = cssHeight / scale;
    const cx = Math.min(Math.max(focus.x, winW / 2), layout.size.width - winW / 2);
    const cy = Math.min(Math.max(focus.y, winH / 2), layout.size.height - winH / 2);
    offX = cssWidth / 2 - cx * scale;
    offY = cssHeight / 2 - cy * scale;
  }
  $("btn-zoom").setAttribute("aria-pressed", String(!!settings.boardZoom));
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
    ctx.globalAlpha = 0.34;
    ctx.lineWidth = 0.95 * layout.laneGap * scale;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // Group separators BETWEEN every block of five holes, plus bold milestone
  // numbers in full text color.
  const skunkHoles = new Set([g.config.skunkThreshold - 1, g.config.doubleSkunkThreshold - 1]);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.strokeStyle = textColor;
  ctx.lineWidth = Math.max(1.5, 0.085 * scale);
  ctx.globalAlpha = 0.55;
  for (let group = 5; group < layout.targetScore; group += 5) {
    const d = group + 0.5; // midway between hole `group` and the next block
    const c = layout.centerPosition(d);
    const n = layout.perpendicular(d);
    const r = halfWidth + 0.5;
    ctx.beginPath();
    ctx.moveTo(...P({ x: c.x + r * n.x, y: c.y + r * n.y }));
    ctx.lineTo(...P({ x: c.x - r * n.x, y: c.y - r * n.y }));
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  ctx.fillStyle = textColor;
  for (let hole = 10; hole < layout.targetScore; hole += 10) {
    if (skunkHoles.has(hole)) continue;
    const c = layout.centerPosition(hole);
    const n = layout.perpendicular(hole);
    const r = halfWidth + 1.12;
    ctx.font = `800 ${Math.max(9, 0.72 * scale)}px -apple-system, sans-serif`;
    ctx.fillText(String(hole), ...P({ x: c.x + r * n.x, y: c.y + r * n.y }));
  }

  // Holes
  ctx.fillStyle = textColor;
  ctx.globalAlpha = 0.75;
  for (let t = 0; t < tc; t++) {
    for (let hole = 0; hole <= layout.targetScore; hole++) {
      const [x, y] = P(layout.position(hole, t));
      const rad = (hole > 0 && hole % 5 === 0 ? 0.19 : 0.15) * layout.laneGap * scale;
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

  // Start/finish + lane initials (so lanes aren't identified by color alone)
  ctx.fillStyle = mutedColor;
  ctx.font = `600 ${Math.max(7, 0.42 * scale)}px -apple-system, sans-serif`;
  const start = layout.centerPosition(0);
  const finish = layout.centerPosition(layout.targetScore);
  ctx.fillText("START", ...P({ x: start.x, y: start.y + 1.3 }));
  ctx.fillText("FINISH", ...P({ x: finish.x, y: finish.y + 1.3 }));
  ctx.font = `800 ${Math.max(8, 0.55 * scale)}px -apple-system, sans-serif`;
  for (let t = 0; t < tc; t++) {
    const p0 = layout.position(0, t);
    ctx.fillStyle = trackColor(t);
    ctx.fillText(E.trackName(g.config, t).charAt(0).toUpperCase(), ...P({ x: p0.x, y: p0.y + 0.62 }));
  }

  // Pegs (front peg position may be mid-animation). In the zoomed view the
  // front peg grows enough to print the score right on it.
  let animating = false;
  const zoomed = !!settings.boardZoom;
  for (let t = 0; t < tc; t++) {
    const pegs = E.pegPositions(g, t);
    const front = animatedFront(g, t);
    if (front !== pegs.front) animating = true;
    for (const [pos, isFront] of [[pegs.back, false], [front, true]]) {
      const [x, y] = P(layout.position(pos, t));
      const rad = (isFront ? (zoomed ? 0.55 : 0.42) : 0.32) * layout.laneGap * scale;
      ctx.beginPath();
      ctx.arc(x, y, rad, 0, Math.PI * 2);
      ctx.fillStyle = trackColor(t);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.9)";
      ctx.lineWidth = Math.max(1, 0.06 * scale);
      ctx.stroke();
      if (isFront && zoomed) {
        ctx.fillStyle = "#fff";
        ctx.font = `800 ${0.42 * scale}px -apple-system, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(String(E.trackScore(g, t)), x, y);
      }
    }
  }
  if (animating) scheduleBoardDraw(g);

  // Screen-reader description of the whole board
  const summary = [...Array(tc).keys()]
    .map((t) => `${E.trackName(g.config, t)} at ${E.trackScore(g, t)} of ${g.config.targetScore}`)
    .join(", ");
  canvas.setAttribute("aria-label", `Cribbage board. ${summary}.`);
}

window.addEventListener("resize", () => {
  if (currentTab === "game" && session) scheduleBoardDraw(session.game);
});

// ------------------------------------------------------------------- Calc

let calcSelection = [];
let claimedPoints = null;
let calcPegBusy = false;

function buildCardGrid() {
  const grid = $("card-grid");
  grid.innerHTML = "";
  for (const suit of ["spades", "hearts", "diamonds", "clubs"]) {
    for (let rank = 1; rank <= 13; rank++) {
      const b = document.createElement("button");
      b.className = E.isRed(suit) ? "red" : "";
      b.dataset.rank = rank;
      b.dataset.suit = suit;
      b.setAttribute("aria-label", `${E.RANK_SYMBOL[rank]} of ${suit}`);
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
  claimedPoints = null;
  renderCalc();
}

$("calc-crib").addEventListener("change", renderCalc);
$("calc-clear").addEventListener("click", () => { calcSelection = []; claimedPoints = null; renderCalc(); });

function renderCalc() {
  const slots = $("calc-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 5; i++) {
    const div = document.createElement("div");
    const c = calcSelection[i];
    div.className = "slot" + (i === 4 ? " starter" : "") + (c && E.isRed(c.suit) ? " red" : "");
    div.textContent = c ? E.cardName(c) : "—";
    slots.appendChild(div);
  }
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
  announce(`Hand counts ${breakdown.total}`);

  renderCalcPeg(breakdown, isCrib);
}

function renderCalcPeg(breakdown, isCrib) {
  const pegBox = $("calc-peg");
  const g = session?.game;
  if (!g || E.isOver(g)) {
    pegBox.hidden = true;
    return;
  }
  pegBox.hidden = false;
  const tc = E.MODES[g.config.mode].trackCount;
  if (selectedTrack >= tc) selectedTrack = 0;
  const track = selectedTrack;
  const name = E.trackName(g.config, track);
  const reason = isCrib ? "cribCount" : "handCount";
  const claimed = claimedPoints ?? breakdown.total;

  let html = `<div class="card-title">Peg it</div><div id="calc-track-chips">`;
  for (let t = 0; t < tc; t++) {
    const sel = t === track;
    html += `<button class="track-chip" data-chip="${t}" aria-pressed="${sel}"
      style="border-color:${sel ? trackColor(t) : "var(--line)"};color:${trackColor(t)}">
      ${esc(E.trackName(g.config, t))}</button>`;
  }
  html += `</div>
    <button id="peg-full" class="primary" ${breakdown.total === 0 ? "disabled" : ""}>
      Peg ${breakdown.total} for ${esc(name)}</button>`;

  if (g.config.mugginsEnabled && breakdown.total > 0) {
    html += `<div id="claimed-row">
        <button class="stepper" id="claim-minus" aria-label="Decrease claimed points">−</button>
        <span class="claimed-val">Claimed: ${claimed}</span>
        <button class="stepper" id="claim-plus" aria-label="Increase claimed points">+</button>
      </div>`;
    if (claimed < breakdown.total) {
      const missed = breakdown.total - claimed;
      if (claimed > 0) {
        html += `<button id="peg-claimed">Peg claimed ${claimed} for ${esc(name)}</button>`;
      }
      for (let other = 0; other < tc; other++) {
        if (other === track) continue;
        html += `<button class="muggins-btn" data-mug="${other}">
          Muggins! ${esc(E.trackName(g.config, other))} takes the missed ${missed}</button>`;
      }
    }
  }
  pegBox.innerHTML = html;

  pegBox.querySelectorAll("[data-chip]").forEach((b) =>
    b.addEventListener("click", () => {
      selectedTrack = Number(b.dataset.chip);
      renderCalc();
    })
  );
  $("peg-full").addEventListener("click", () => guardedCalcPeg(() => {
    doPeg(track, breakdown.total, reason, breakdown);
    finishCalcPeg();
  }));
  $("claim-minus")?.addEventListener("click", () => {
    claimedPoints = Math.max(0, (claimedPoints ?? breakdown.total) - 1);
    renderCalc();
  });
  $("claim-plus")?.addEventListener("click", () => {
    claimedPoints = Math.min(breakdown.total, (claimedPoints ?? breakdown.total) + 1);
    renderCalc();
  });
  $("peg-claimed")?.addEventListener("click", () => guardedCalcPeg(() => {
    doPeg(track, claimed, reason, breakdown);
    finishCalcPeg();
  }));
  pegBox.querySelectorAll("[data-mug]").forEach((b) =>
    b.addEventListener("click", () => guardedCalcPeg(() => {
      const missed = breakdown.total - claimed;
      if (claimed > 0) doPeg(track, claimed, reason, breakdown);
      doPeg(Number(b.dataset.mug), missed, "muggins");
      finishCalcPeg();
    }))
  );
}

/** One calc peg per render — blocks accidental double-taps. */
function guardedCalcPeg(action) {
  if (calcPegBusy) return;
  calcPegBusy = true;
  action();
  setTimeout(() => { calcPegBusy = false; }, 400);
}

function finishCalcPeg() {
  calcSelection = [];
  claimedPoints = null;
  $("calc-crib").checked = false;
  switchTab("game");
}

// ----------------------------------------------------------------- History

let historyMode = null; // "current" | "all"; defaults per live-game state

$("hist-current-btn").addEventListener("click", () => { historyMode = "current"; renderHistory(); });
$("hist-all-btn").addEventListener("click", () => { historyMode = "all"; renderHistory(); });

function renderHistory() {
  if (historyMode === null) historyMode = session ? "current" : "all";
  const current = historyMode === "current";
  $("history-current").hidden = !current;
  $("history-all").hidden = current;
  $("hist-current-btn").classList.toggle("active", current);
  $("hist-all-btn").classList.toggle("active", !current);
  $("hist-current-btn").setAttribute("aria-selected", String(current));
  $("hist-all-btn").setAttribute("aria-selected", String(!current));
  if (current) {
    renderCurrentEvents();
  } else {
    renderAllGames();
  }
}

function renderCurrentEvents() {
  const list = $("events-list");
  list.innerHTML = "";
  const g = session?.game;
  if (!g) {
    list.innerHTML = `<li class="muted">No game in progress.</li>`;
    return;
  }
  if (g.events.length === 0) {
    list.innerHTML = `<li class="muted">Nothing pegged yet.</li>`;
    return;
  }
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

function renderAllGames() {
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
      <div class="g-head">${TROPHY} ${esc(E.trackName(g.config, winner))}
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
  $("set-style").value = settings.scoreStyle;
  $("set-muggins").checked = settings.muggins;
  $("set-skunkx").checked = settings.skunkx;
  $("set-palette").value = settings.palette;
  $("version-line").textContent = `Version ${VERSION}`;
}
$("set-muggins").addEventListener("change", (e) => {
  settings.muggins = e.target.checked;
  persistSettings();
  $("ng-muggins").checked = settings.muggins;
});
$("set-skunkx").addEventListener("change", (e) => {
  settings.skunkx = e.target.checked;
  persistSettings();
  $("ng-skunkx").checked = settings.skunkx;
});
$("set-style").addEventListener("change", (e) => {
  settings.scoreStyle = e.target.value;
  pending = 0;
  persistSettings();
});
$("set-palette").addEventListener("change", (e) => {
  settings.palette = e.target.value;
  persistSettings();
  applyPalette();
});

// ------------------------------------------------------------------- Util

function esc(s) {
  return String(s).replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[ch]);
}

// ------------------------------------------------------------------- Boot

applyPalette();
$("ng-muggins").checked = settings.muggins;
$("ng-skunkx").checked = settings.skunkx;
syncNewGameForm();
switchTab("game");

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

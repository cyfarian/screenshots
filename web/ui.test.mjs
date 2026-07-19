// End-to-end UI test. Requires a Chromium binary and playwright-core:
//   npm i playwright-core && CHROMIUM=/path/to/chromium node web/ui.test.mjs
// Serves the web/ directory itself on an ephemeral port.
import { chromium } from "playwright-core";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const webDir = path.dirname(fileURLToPath(import.meta.url));
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".webmanifest": "application/manifest+json", ".png": "image/png" };
const server = http.createServer((req, res) => {
  const urlPath = req.url.split("?")[0];
  let file = path.join(webDir, urlPath === "/" ? "index.html" : urlPath);
  if (urlPath.startsWith("/../") || urlPath.includes("..")) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": MIME[path.extname(file)] ?? "application/octet-stream" });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, r));
const BASE = `http://localhost:${server.address().port}/`;

const iPhone = {
  viewport: { width: 393, height: 852 },
  deviceScaleFactor: 3,
  isMobile: true,
  hasTouch: true,
};

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? "/opt/pw-browsers/chromium" });
const page = await browser.newPage(iPhone);
const errors = [];
page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
page.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text()); });

const foldCheck = async (label) => {
  const fold = await page.evaluate(() => {
    const el = document.querySelector("#view-game");
    return { scroll: el.scrollHeight, client: el.clientHeight };
  });
  console.log(`fold (${label}):`, fold, "fits:", fold.scroll <= fold.client + 1);
};

await page.goto(BASE, { waitUntil: "networkidle" });
console.log("tabs:", await page.locator("#tabbar .tab").count());

// With NO game: Count tab goes straight to the calculator, X returns to game
await page.click("[data-tab='calc']");
console.log("no-game count -> calc:", await page.locator("#view-calc").isVisible(),
  "| chooser:", await page.locator("#count-modal").isVisible());
await page.click("#nav-close");
console.log("X back to game tab:", await page.locator("#view-game").isVisible());

// Start a 2p muggins game
await page.fill("#ng-name-0", "Cy");
await page.fill("#ng-name-1", "Jess");
await page.check("#ng-muggins");
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");
await page.click("#hint-done");

// Numbers style default: build/commit/zero
console.log("numbers row visible:", await page.locator("#numbers-row").isVisible());
await foldCheck("numbers");
await page.click("#numbers-row .num-btn:nth-child(5)");
await page.click("#numbers-row .num-btn:nth-child(3)");
console.log("pending label:", (await page.locator("#pending-peg").textContent()).trim()); // Peg +8
await page.click("#pending-peg");
console.log("after commit:",
  (await page.locator(".score-card").nth(0).locator(".pts").textContent()).trim(),
  "| zeroed:", await page.locator("#pending-peg").isDisabled());

// Pending resets on player switch; clear works
await page.click("#numbers-row .num-btn:nth-child(4)");
await page.locator(".score-card").nth(1).click();
console.log("pending reset on switch:", await page.locator("#pending-peg").isDisabled());
await page.click("#numbers-row .num-btn:nth-child(2)");
await page.click("#pending-clear");
console.log("clear works:", await page.locator("#pending-peg").isDisabled());

// Count chooser during a game: named combos option
await page.click("[data-tab='calc']");
console.log("chooser shown:", await page.locator("#count-modal").isVisible());
await page.click("#count-named");
console.log("named grid after choice:", await page.locator("#quick-grid").isVisible(),
  "| on game tab:", await page.locator("#view-game").isVisible());
await foldCheck("named");
await page.screenshot({ path: "shot-named.png" });
// Named combos queue onto the Score button, then commit itemized
await page.click("#quick-grid button:nth-child(1)"); // 15 (+2)
await page.click("#quick-grid button:nth-child(2)"); // Pair (+2)
console.log("named pending:", (await page.locator("#custom-peg").textContent()).trim()); // Score +4
await page.click("#custom-peg");
console.log("toast:", (await page.locator("#toast-text").textContent()).trim()); // +4 — Jess
console.log("jess after named commit:",
  (await page.locator(".score-card").nth(1).locator(".pts").textContent()).trim()); // 4
await page.click("#toast-undo"); // removes the last part (Pair)
console.log("jess after undo:",
  (await page.locator(".score-card").nth(1).locator(".pts").textContent()).trim()); // 2

// History tab: This game / All games toggle
await page.click("[data-tab='history']");
console.log("history default (live game) = current:",
  await page.locator("#history-current").isVisible());
console.log("event rows:", await page.locator("#events-list li").count());
console.log("itemized combo in log:",
  (await page.locator("#events-list").textContent()).includes("Fifteen"));
await page.click("#hist-all-btn");
console.log("all-games view:", await page.locator("#history-all").isVisible(),
  "| finished:", (await page.locator("#games-list li").textContent()).includes("No finished"));
await page.click("#hist-current-btn");
console.log("back to current:", await page.locator("#history-current").isVisible());

// Count chooser -> log the cards -> calculator, muggins flow, returns to game
await page.click("[data-tab='game']");
await page.click("[data-tab='calc']");
await page.click("#count-cards");
await page.waitForSelector("#view-calc:not([hidden])");
console.log("calc title:", (await page.locator("#title").textContent()).trim());
for (const [r, s] of [[5, "hearts"], [5, "diamonds"], [5, "spades"], [11, "clubs"], [5, "clubs"]]) {
  await page.click(`#card-grid button[data-rank="${r}"][data-suit="${s}"]`);
}
console.log("calc total:", await page.locator("#calc-result .total .p").textContent());
await page.click("[data-chip='1']");
for (let i = 0; i < 4; i++) await page.click("#claim-minus");
await page.click("[data-mug='0']");
await page.waitForSelector("#game-live:not([hidden])");
console.log("after muggins:",
  (await page.locator(".score-card").nth(0).locator(".pts").textContent()).trim(),
  (await page.locator(".score-card").nth(1).locator(".pts").textContent()).trim());

// Board zoom toggle
await page.click("#btn-zoom");
console.log("zoom on:", await page.locator("#btn-zoom").getAttribute("aria-pressed"));
await page.waitForTimeout(600);
await page.screenshot({ path: "shot-zoomed.png" });
await page.click("#btn-zoom");
console.log("zoom off:", await page.locator("#btn-zoom").getAttribute("aria-pressed"));

// Chooser numbers option puts numbers pad back; win the game with it
await page.click("[data-tab='calc']");
await page.click("#count-numbers");
await page.locator(".score-card").nth(1).click();
for (let round = 0; round < 6 && !(await page.locator("#game-over").isVisible()); round++) {
  for (let i = 0; i < 5; i++) await page.click("#numbers-row .num-btn:nth-child(5)"); // +25
  await page.click("#pending-peg");
}
console.log("game over:", await page.locator("#game-over").isVisible());
await page.click("#go-next");
await page.waitForSelector("#game-setup:not([hidden])");

// History after finishing: This game empty, All games has the archive
await page.click("[data-tab='history']");
await page.click("#hist-current-btn");
console.log("no-game current history:",
  (await page.locator("#events-list li").first().textContent()).trim());
await page.click("#hist-all-btn");
console.log("finished games:", await page.locator("#games-list li").count());

// Settings: X back to game; style/palette persistence
await page.click("[data-tab='settings']");
console.log("settings X visible:", await page.locator("#nav-close").isVisible());
await page.selectOption("#set-style", "named");
await page.selectOption("#set-palette", "colorblind");
await page.selectOption("#set-theme", "dark");
console.log("dark theme applied:", await page.evaluate(() => document.documentElement.dataset.theme));
await page.click("#nav-close");
console.log("settings X -> game:", await page.locator("#view-game").isVisible());
await page.goto(BASE, { waitUntil: "networkidle" });
const track0 = await page.evaluate(() =>
  getComputedStyle(document.documentElement).getPropertyValue("--track0").trim());
console.log("palette after reload:", track0);
console.log("theme after reload:", await page.evaluate(() => document.documentElement.dataset.theme));
await page.fill("#ng-name-0", "A");
// Pick a custom color for player 1 via the color-wheel input
await page.evaluate(() => {
  const input = document.querySelector("#ng-color-0");
  input.value = "#8e24aa";
  input.dispatchEvent(new Event("input", { bubbles: true }));
});
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");
const customColor = await page.evaluate(() =>
  document.querySelector("#quick-grid button")?.style.background);
console.log("custom player color on buttons:", customColor); // rgb(142, 36, 170)
await page.waitForSelector("#game-live:not([hidden])");
console.log("style from settings (named):", await page.locator("#quick-grid").isVisible());

// Abandon flow
await page.click("#btn-newgame");
await page.click("#nm-abandon");
await page.waitForSelector("#game-setup:not([hidden])");
console.log("abandoned ok");

console.log("JS errors:", errors.length ? errors : "none");
await browser.close();
server.close();
if (errors.length) process.exit(1);

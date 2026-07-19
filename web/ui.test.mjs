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

await page.goto(BASE, { waitUntil: "networkidle" });

// Tab bar exists; game tab shows setup
console.log("tabs:", await page.locator("#tabbar .tab").count());
await page.screenshot({ path: "shot-1-setup.png" });

// Start a 2p muggins game
await page.fill("#ng-name-0", "Cy");
await page.fill("#ng-name-1", "Jess");
await page.check("#ng-muggins");
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");

// First-run hint should appear once; dismiss it
console.log("hint shown:", await page.locator("#hint-overlay").isVisible());
await page.click("#hint-done");

// ABOVE THE FOLD: the game view must not scroll
const fold = await page.evaluate(() => {
  const el = document.querySelector("#view-game");
  return { scroll: el.scrollHeight, client: el.clientHeight, body: document.body.scrollHeight, win: innerHeight };
});
console.log("fold check:", fold, "fits:", fold.scroll <= fold.client + 1);
await page.screenshot({ path: "shot-2-game.png" });

// Quick peg + toast with undo
await page.click("#quick-grid button:nth-child(1)"); // 15 for Cy
console.log("toast:", (await page.locator("#toast-text").textContent()).trim());
await page.click("#toast-undo"); // undo via toast
let s0 = await page.locator(".score-card").nth(0).locator(".pts").textContent();
console.log("after toast undo:", s0); // expect 0

// Custom counter zeroes after pegging
console.log("peg btn disabled at 0:", await page.locator("#custom-peg").isDisabled());
for (let i = 0; i < 7; i++) await page.click("#custom-plus");
console.log("peg btn label:", (await page.locator("#custom-peg").textContent()).trim()); // Peg +7
await page.click("#custom-peg");
console.log("after custom peg:",
  (await page.locator(".score-card").nth(0).locator(".pts").textContent()).trim(),
  "| label:", (await page.locator("#custom-peg").textContent()).trim(),
  "| disabled:", await page.locator("#custom-peg").isDisabled());

// Calculator via tab: 29 hand pegged to Jess via track chip
await page.click("#btn-count");
await page.waitForSelector("#view-calc:not([hidden])");
for (const [r, s] of [[5, "hearts"], [5, "diamonds"], [5, "spades"], [11, "clubs"], [5, "clubs"]]) {
  await page.click(`#card-grid button[data-rank="${r}"][data-suit="${s}"]`);
}
console.log("calc total:", await page.locator("#calc-result .total .p").textContent());
await page.click("[data-chip='1']"); // switch peg target to Jess
// muggins: claim 25, award 4 to Cy
for (let i = 0; i < 4; i++) await page.click("#claim-minus");
await page.click("[data-mug='0']");
await page.waitForSelector("#game-live:not([hidden])");
console.log("after muggins:",
  (await page.locator(".score-card").nth(0).locator(".pts").textContent()).trim(),
  (await page.locator(".score-card").nth(1).locator(".pts").textContent()).trim()); // 11, 25

// Events modal
await page.click("#btn-events");
console.log("event rows:", await page.locator("#events-list li").count());
await page.click("#events-close");

// Wait for peg animation to settle, then screenshot
await page.waitForTimeout(600);
await page.screenshot({ path: "shot-3-game-mid.png" });

// Win the game, finish, check history tab
await page.locator(".score-card").nth(1).click();
for (let i = 0; i < 29; i++) await page.click("#custom-plus");
for (let i = 0; i < 4 && !(await page.locator("#game-over").isVisible()); i++) {
  await page.click("#custom-peg");
  for (let k = 0; k < 29; k++) await page.click("#custom-plus");
}
console.log("game over:", await page.locator("#game-over").isVisible());
await page.click("#go-next");
await page.waitForSelector("#game-setup:not([hidden])");
await page.click("[data-tab='history']");
console.log("history entries:", await page.locator("#games-list li").count());

// Settings: palette switch persists
await page.click("[data-tab='settings']");
await page.selectOption("#set-palette", "colorblind");
await page.goto(BASE, { waitUntil: "networkidle" });
const track0 = await page.evaluate(() =>
  getComputedStyle(document.documentElement).getPropertyValue("--track0").trim());
console.log("palette after reload:", track0); // expect #0072b2

// Hint should NOT reappear on a second game
await page.fill("#ng-name-0", "A");
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");
console.log("hint on 2nd game:", await page.locator("#hint-overlay").isVisible());

// End-game confirm modal (abandon)
await page.click("#btn-newgame");
await page.click("#nm-abandon");
await page.waitForSelector("#game-setup:not([hidden])");
console.log("abandoned ok");

console.log("JS errors:", errors.length ? errors : "none");
await browser.close();
server.close();
if (errors.length) process.exit(1);

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

// Start a 2p muggins game
await page.fill("#ng-name-0", "Cy");
await page.fill("#ng-name-1", "Jess");
await page.check("#ng-muggins");
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");
console.log("hint shown:", await page.locator("#hint-overlay").isVisible());
await page.click("#hint-done");

// Default scoring style is big numbers
console.log("numbers row visible:", await page.locator("#numbers-row").isVisible());
console.log("named grid hidden:", await page.locator("#quick-grid").isHidden());
await foldCheck("numbers");
await page.screenshot({ path: "shot-numbers.png" });

// +5 +3 build up, commit pegs 8 and zeroes
await page.click("#numbers-row .num-btn:nth-child(5)");
await page.click("#numbers-row .num-btn:nth-child(3)");
console.log("pending label:", (await page.locator("#pending-peg").textContent()).trim()); // Peg +8
await page.click("#pending-peg");
console.log("after commit:",
  (await page.locator(".score-card").nth(0).locator(".pts").textContent()).trim(),
  "| label:", (await page.locator("#pending-peg").textContent()).trim(),
  "| disabled:", await page.locator("#pending-peg").isDisabled());

// Pending resets when switching player
await page.click("#numbers-row .num-btn:nth-child(4)");
await page.locator(".score-card").nth(1).click();
console.log("pending after player switch disabled:", await page.locator("#pending-peg").isDisabled());

// Clear button
await page.click("#numbers-row .num-btn:nth-child(2)");
await page.click("#pending-clear");
console.log("after clear disabled:", await page.locator("#pending-peg").isDisabled());

// Toggle to named style in-game; instant peg + toast undo still work
await page.click("#btn-style");
console.log("named grid visible:", await page.locator("#quick-grid").isVisible());
await foldCheck("named");
await page.screenshot({ path: "shot-named.png" });
await page.click("#quick-grid button:nth-child(1)"); // 15 for Jess
console.log("toast:", (await page.locator("#toast-text").textContent()).trim());
await page.click("#toast-undo");
console.log("jess after toast undo:",
  (await page.locator(".score-card").nth(1).locator(".pts").textContent()).trim());

// Style persists across reload
await page.goto(BASE, { waitUntil: "networkidle" });
await page.waitForSelector("#game-live:not([hidden])");
console.log("named persists after reload:", await page.locator("#quick-grid").isVisible());
await page.click("#btn-style"); // back to numbers

// Calculator: 29 hand pegged to Jess, muggins split 25/4
await page.click("#btn-count");
await page.waitForSelector("#view-calc:not([hidden])");
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

// Events modal
await page.click("#btn-events");
console.log("event rows:", await page.locator("#events-list li").count());
await page.click("#events-close");
await page.waitForTimeout(600);
await page.screenshot({ path: "shot-numbers-mid.png" });

// Win via repeated numbers commits for Jess
await page.locator(".score-card").nth(1).click();
for (let round = 0; round < 6 && !(await page.locator("#game-over").isVisible()); round++) {
  for (let i = 0; i < 5; i++) await page.click("#numbers-row .num-btn:nth-child(5)"); // +25
  await page.click("#pending-peg");
}
console.log("game over:", await page.locator("#game-over").isVisible());
await page.click("#go-next");
await page.waitForSelector("#game-setup:not([hidden])");
await page.click("[data-tab='history']");
console.log("history entries:", await page.locator("#games-list li").count());

// Settings: scoring style picker + palette both persist
await page.click("[data-tab='settings']");
await page.selectOption("#set-style", "named");
await page.selectOption("#set-palette", "colorblind");
await page.goto(BASE, { waitUntil: "networkidle" });
const track0 = await page.evaluate(() =>
  getComputedStyle(document.documentElement).getPropertyValue("--track0").trim());
console.log("palette after reload:", track0);
await page.fill("#ng-name-0", "A");
await page.click("#ng-start");
await page.waitForSelector("#game-live:not([hidden])");
console.log("style from settings (named):", await page.locator("#quick-grid").isVisible());
console.log("hint on later game:", await page.locator("#hint-overlay").isVisible());

// Abandon flow
await page.click("#btn-newgame");
await page.click("#nm-abandon");
await page.waitForSelector("#game-setup:not([hidden])");
console.log("abandoned ok");

console.log("JS errors:", errors.length ? errors : "none");
await browser.close();
server.close();
if (errors.length) process.exit(1);

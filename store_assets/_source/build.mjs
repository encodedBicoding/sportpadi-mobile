// Builds SportPadi store images: iPhone 6.9", iPad 13", Android phone, Play
// feature graphic. HTML → Tailwind CSS → Playwright screenshots.
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { chromium } from "playwright";
import { SCREENS, ic } from "./screens.mjs";

const OUT = path.resolve("store/out");
const PAGES = path.resolve("store/pages");
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(PAGES, { recursive: true });

const SLIDES = [
  { key: "home", theme: "dark", eyebrow: "Your game, organised", title: "All your games.<br>One app.", sub: "Your groups, your calendar and what's next — the moment you open it.", chip: ["flame", "3-week streak", "Keep it going", "orange"] },
  { key: "browse", theme: "light", eyebrow: "Find a game", title: "Pickup games<br>near you, tonight", sub: "Football, padel, basketball and more — filter by sport, distance or what's live.", chip: ["map-pin", "42 games", "within 5 miles", "green"] },
  { key: "match", theme: "dark", eyebrow: "Live scores", title: "Follow every goal<br>as it happens", sub: "Live scores, cards and key moments from every match, in real time.", chip: ["zap", "GOAL! 67'", "Marcus Ade · 3–2", "green"] },
  { key: "ticket", theme: "green", eyebrow: "QR check-in", title: "Scan in.<br>Get picked. Play.", sub: "Your ticket is a QR, and balanced teams are built from who actually turned up.", chip: ["users", "Teams are ready", "You're on Team Green", "green"] },
  { key: "tournament", theme: "orange", eyebrow: "Tournaments", title: "Run a cup<br>like the pros", sub: "Brackets, fixtures, squads, officials and awards — all in one place.", chip: ["trophy", "Semi-final · Live", "East End 3–2 Northside", "orange"] },
  { key: "leaderboard", theme: "light", eyebrow: "Leaderboards", title: "Climb the table.<br>Claim the crown.", sub: "Points, goals, assists and MVPs ranked across every game you play.", chip: ["trending-up", "You moved up 2", "#5 this season", "green"] },
  { key: "profile", theme: "dark", eyebrow: "Your record", title: "Your stats.<br>Every sport.", sub: "Levels, streaks and a record that follows you from game to game.", chip: ["sparkles", "MVP of the match", "+50 XP", "orange"] },
  { key: "group", theme: "mint", eyebrow: "For organisers", title: "Run your group.<br>Get paid.", sub: "Events, teams, tickets, fines and payouts for the people who run the game.", chip: ["wallet", "£186 collected", "Sunday 5-a-side", "green"] },
];

const THEMES = {
  dark: { bg: "background:#0e1411", text: "#fff", sub: "rgba(255,255,255,.72)", eyebrow: "#6edc9e", lines: 0.06, glowA: "rgba(23,166,94,.35)", glowB: "rgba(244,120,31,.28)" },
  light: { bg: "background:#f3f5f2", text: "#0e1411", sub: "#5e6b66", eyebrow: "#0f7a45", lines: 0, glowA: "rgba(23,166,94,.18)", glowB: "rgba(244,120,31,.14)" },
  green: { bg: "background:linear-gradient(160deg,#0f7a45,#17a65e)", text: "#fff", sub: "rgba(255,255,255,.8)", eyebrow: "#d7ffe8", lines: 0.12, glowA: "rgba(110,220,158,.4)", glowB: "rgba(14,20,17,.25)" },
  orange: { bg: "background:linear-gradient(165deg,#0e1411 35%,#7a3a10 80%,#f4781f)", text: "#fff", sub: "rgba(255,255,255,.75)", eyebrow: "#ffb57d", lines: 0.07, glowA: "rgba(244,120,31,.35)", glowB: "rgba(255,181,125,.2)" },
  mint: { bg: "background:#e6f6ec", text: "#0e1411", sub: "#3f5249", eyebrow: "#0f7a45", lines: 0, glowA: "rgba(23,166,94,.25)", glowB: "rgba(244,120,31,.16)" },
};

const SETS = {
  iphone: { w: 440, h: 956, scale: 3, device: "iphone", devW: 340, top: 272, title: 40, pad: 34, eyebrowTop: 70 },
  android: { w: 360, h: 640, scale: 3, device: "android", devW: 256, top: 214, title: 29, pad: 26, eyebrowTop: 42 },
  ipad: { w: 1032, h: 1376, scale: 2, device: "ipad", devW: 840, top: 450, title: 64, pad: 80, eyebrowTop: 100 },
};

function pitchSvg(op) {
  if (!op) return "";
  return `<svg class="absolute inset-0 h-full w-full" viewBox="0 0 440 956" preserveAspectRatio="xMidYMid slice" fill="none" stroke="white" stroke-opacity="${op}" stroke-width="2"><rect x="24" y="24" width="392" height="908" rx="18"/><line x1="24" y1="478" x2="416" y2="478"/><circle cx="220" cy="478" r="70"/><rect x="120" y="24" width="200" height="110"/><rect x="120" y="822" width="200" height="110"/></svg>`;
}

function chipHtml([icon, title, sub, tone], big, originRight = false, small = false) {
  const tile = tone === "orange" ? "background:#feeedf;color:#9a4308" : "background:#e6f6ec;color:#0f7a45";
  const s = big ? 1.7 : small ? 0.82 : 1;
  return `<div class="flex items-center gap-3 rounded-[20px] bg-white py-3 pl-3 pr-5 text-[#0e1411] shadow-[0_24px_48px_-20px_rgba(0,0,0,.45)]" style="transform:scale(${s});transform-origin:${originRight ? "right" : "left"} center">
    <span class="flex h-10 w-10 items-center justify-center rounded-[13px]" style="${tile}">${ic(icon, "h-5 w-5", 2.2)}</span>
    <div class="leading-tight"><p class="text-[15px] font-extrabold">${title}</p><p class="text-[12px] text-[#5e6b66]">${sub}</p></div>
  </div>`;
}

function deviceHtml(kind, width, screenHtml, dark) {
  if (kind === "ipad") {
    const sw = 834, sh = 1150;
    const inner = width - 36;
    const k = inner / sw;
    return `<div class="rounded-[54px] bg-[#0b0f0d] p-[18px] shadow-[0_60px_120px_-40px_rgba(0,0,0,.55)] ring-1 ring-white/10" style="width:${width}px">
      <div class="relative overflow-hidden rounded-[38px] bg-[#f3f5f2]" style="width:${inner}px;height:${sh * k}px">
        <div class="absolute left-0 top-0 origin-top-left text-[#0e1411]" style="width:${sw}px;height:${sh}px;transform:scale(${k})">${screenHtml}</div>
      </div></div>`;
  }
  const sw = 390, sh = 844;
  const bezel = kind === "android" ? 8 : 11;
  const inner = width - bezel * 2;
  const k = inner / sw;
  const radius = kind === "android" ? 36 : 50;
  const island = kind === "android"
    ? `<span class="absolute left-1/2 top-[14px] z-20 h-[14px] w-[14px] -translate-x-1/2 rounded-full bg-[#0b0f0d]"></span>`
    : `<span class="absolute left-1/2 top-[11px] z-20 h-[32px] w-[112px] -translate-x-1/2 rounded-full bg-[#0b0f0d]"></span>`;
  return `<div class="bg-[#0b0f0d] shadow-[0_50px_100px_-30px_rgba(0,0,0,.6)] ring-1 ring-white/10" style="width:${width}px;padding:${bezel}px;border-radius:${radius + bezel}px">
    <div class="relative overflow-hidden bg-[#f3f5f2]" style="width:${inner}px;height:${sh * k}px;border-radius:${radius}px">
      <div class="absolute left-0 top-0 origin-top-left text-[#0e1411]" style="width:${sw}px;height:${sh}px;transform:scale(${k})">${island}${screenHtml}</div>
    </div></div>`;
}

function page(body, w, h) {
  return `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="store.css">
  <style>html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;font-family:Poppins,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
  *{box-sizing:border-box} .emoji{font-family:"Noto Color Emoji"}</style></head><body>${body}</body></html>`;
}

async function slideHtml(setKey, s, i) {
  const set = SETS[setKey];
  const t = THEMES[s.theme];
  const wide = setKey === "ipad";
  const screen = await SCREENS[s.key]({ wide });
  const dev = deviceHtml(set.device, set.devW, screen);
  const big = setKey === "ipad";
  const devLeft = (set.w - set.devW) / 2;
  // Chips float over the device's edge, low down, alternating sides.
  const left = i % 2 === 0;
  const y = setKey === "ipad" ? set.top + 640 : setKey === "android" ? set.top + 345 : set.top + 470;
  const x = setKey === "ipad" ? devLeft - 50 : setKey === "android" ? 10 : 12;
  const chipPos = left ? `left:${x}px;top:${y}px` : `right:${x}px;top:${y}px`;
  const body = `<div class="relative h-full w-full overflow-hidden" style="${t.bg}">
    ${pitchSvg(t.lines)}
    <div class="absolute rounded-full blur-3xl" style="width:${set.w * 0.9}px;height:${set.w * 0.9}px;right:-${set.w * 0.35}px;top:-${set.w * 0.3}px;background:${t.glowB}"></div>
    <div class="absolute rounded-full blur-3xl" style="width:${set.w}px;height:${set.w}px;left:-${set.w * 0.45}px;bottom:-${set.w * 0.2}px;background:${t.glowA}"></div>
    <div class="relative text-center" style="padding:${set.eyebrowTop}px ${set.pad}px 0">
      <p class="font-bold uppercase" style="color:${t.eyebrow};font-size:${big ? 24 : setKey === "android" ? 11.5 : 13}px;letter-spacing:.18em">${s.eyebrow}</p>
      <h1 class="mt-3 font-extrabold" style="color:${t.text};font-size:${set.title}px;line-height:1.05;letter-spacing:-0.035em">${s.title}</h1>
      ${setKey === "android" ? "" : `<p class="mx-auto mt-3 font-medium" style="color:${t.sub};font-size:${big ? 26 : 15.5}px;line-height:1.45;max-width:${big ? 860 : 360}px">${s.sub}</p>`}
    </div>
    <div class="absolute" style="left:${devLeft}px;top:${set.top}px">${dev}</div>
    <div class="absolute z-10" style="${chipPos}">${chipHtml(s.chip, big, !left, setKey === "android")}</div>
  </div>`;
  return page(body, set.w, set.h);
}

async function featureHtml() {
  const home = await SCREENS.home({});
  const match = await SCREENS.match({});
  const body = `<div class="relative h-full w-full overflow-hidden" style="background:#0e1411">
    <svg class="absolute inset-0 h-full w-full" viewBox="0 0 1024 500" fill="none" stroke="white" stroke-opacity=".07" stroke-width="2"><rect x="20" y="20" width="984" height="460" rx="16"/><line x1="512" y1="20" x2="512" y2="480"/><circle cx="512" cy="250" r="80"/><rect x="20" y="150" width="110" height="200"/><rect x="894" y="150" width="110" height="200"/></svg>
    <div class="absolute -left-24 -bottom-40 h-[460px] w-[460px] rounded-full bg-[#17a65e]/35 blur-3xl"></div>
    <div class="absolute -right-20 -top-32 h-[420px] w-[420px] rounded-full bg-[#f4781f]/30 blur-3xl"></div>
    <div class="absolute left-[64px] top-[74px] w-[500px] text-white">
      <img src="logo-dark.png" class="h-[46px]">
      <h1 class="mt-7 text-[54px] font-extrabold leading-[1.02] tracking-[-0.035em]">Find your game.<br>Join your people.</h1>
      <p class="mt-4 text-[20px] font-semibold text-[#6edc9e]">Pickup games · Teams · Tournaments</p>
    </div>
    <div class="absolute right-[190px] top-[70px] rotate-[-8deg]">${deviceHtml("iphone", 220, home)}</div>
    <div class="absolute right-[24px] top-[110px] rotate-[6deg]">${deviceHtml("iphone", 220, match)}</div>
  </div>`;
  return page(body, 1024, 500);
}

// 1) write pages
const jobs = [];
for (const setKey of Object.keys(SETS)) {
  for (const [i, s] of SLIDES.entries()) {
    const file = `${setKey}-${String(i + 1).padStart(2, "0")}-${s.key}.html`;
    fs.writeFileSync(path.join(PAGES, file), await slideHtml(setKey, s, i));
    jobs.push({ file, set: SETS[setKey], out: `${setKey}/${String(i + 1).padStart(2, "0")}-${s.key}.png` });
  }
}
fs.writeFileSync(path.join(PAGES, "feature.html"), await featureHtml());
jobs.push({ file: "feature.html", set: { w: 1024, h: 500, scale: 1 }, out: "play-feature-graphic-1024x500.png" });

// 2) CSS
fs.writeFileSync(path.join(PAGES, "in.css"), `@import "tailwindcss";\n@source "./*.html";\n`);
execSync(`npx @tailwindcss/cli -i ${PAGES}/in.css -o ${PAGES}/store.css`, { stdio: "ignore" });
fs.copyFileSync(path.resolve("public/sportpadi-logo-dark.png"), path.join(PAGES, "logo-dark.png"));

// 3) render
const only = process.argv[2];
const browser = await chromium.launch();
for (const j of jobs) {
  if (only && !j.out.includes(only)) continue;
  const p = await browser.newPage({ viewport: { width: j.set.w, height: j.set.h }, deviceScaleFactor: j.set.scale });
  await p.goto("file://" + path.join(PAGES, j.file));
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(150);
  const dest = path.join(OUT, j.out);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  await p.screenshot({ path: dest, type: "png" });
  await p.close();
}
await browser.close();
console.log("done", jobs.length);

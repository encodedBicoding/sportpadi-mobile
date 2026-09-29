// SportPadi 2026 app screens, recreated in HTML for store images.
// Every screen renders at a logical 390×844 (phone) or 834×1150 (tablet)
// with the app's light palette. Sample data is fictional.
import fs from "node:fs";
import path from "node:path";
import QRCode from "qrcode";

const ICONS = path.resolve("node_modules/lucide-static/icons");
export function ic(name, cls = "h-5 w-5", sw = 2) {
  let s = fs.readFileSync(path.join(ICONS, `${name}.svg`), "utf8");
  s = s.replace(/<!--[\s\S]*?-->/g, "");
  s = s.replace(/<svg[^>]*>/, (m) =>
    m
      .replace(/\swidth="24"/, "")
      .replace(/\sheight="24"/, "")
      .replace(/class="[^"]*"/, "")
      .replace(/stroke-width="2"/, `stroke-width="${sw}"`)
      .replace("<svg", `<svg class="${cls}"`),
  );
  return s;
}

const C = {
  bg: "#f3f5f2", surface: "#ffffff", s2: "#eef2ef", ink: "#0e1411", muted: "#5e6b66",
  line: "#e3e8e5", accent: "#17a65e", deep: "#0f7a45", tint: "#e6f6ec", orange: "#f4781f",
  oTint: "#feeedf", oInk: "#9a4308", live: "#fde8e8", danger: "#e02424", mint: "#6edc9e", warm: "#ffb57d",
};

const card = "bg-white rounded-[24px] shadow-[0_1px_2px_rgba(14,20,17,.05),0_12px_28px_-18px_rgba(14,20,17,.25)]";

function pitch(color = "white", op = 0.1) {
  return `<svg class="absolute inset-0 h-full w-full" viewBox="0 0 400 240" preserveAspectRatio="xMidYMid slice" fill="none" stroke="${color}" stroke-opacity="${op}" stroke-width="2"><rect x="14" y="14" width="372" height="212" rx="10"/><line x1="200" y1="14" x2="200" y2="226"/><circle cx="200" cy="120" r="36"/><rect x="14" y="70" width="50" height="100"/><rect x="336" y="70" width="50" height="100"/></svg>`;
}

function status(dark = false) {
  const c = dark ? "text-white" : "text-[#0e1411]";
  return `<div class="flex h-[46px] items-center justify-between px-7 pt-1 text-[15px] font-semibold ${c}">
    <span>9:41</span>
    <span class="flex items-center gap-1.5">${ic("signal", "h-4 w-4", 2.4)}${ic("wifi", "h-4 w-4", 2.4)}<span class="ml-0.5 inline-block h-[11px] w-[22px] rounded-[3px] border-[1.5px] ${dark ? "border-white/80" : "border-[#0e1411]/80"} p-[1.5px]"><span class="block h-full w-[75%] rounded-[1px] ${dark ? "bg-white" : "bg-[#0e1411]"}"></span></span></span>
  </div>`;
}

function dock(active = 0) {
  const items = [["house", "Home"], ["compass", "Browse"], ["users", "Groups"], ["trophy", "Tournaments"], ["user", "Profile"]];
  return `<div class="absolute inset-x-4 bottom-6 flex h-[64px] items-center justify-between rounded-full bg-[#0e1411] px-2 shadow-[0_16px_36px_-14px_rgba(14,20,17,.6)]">
    ${items
      .map(([i, l], k) =>
        k === active
          ? `<span class="flex h-12 items-center gap-1.5 rounded-full bg-white px-4 text-[13px] font-bold text-[#0e1411]">${ic(i, "h-[22px] w-[22px] text-[#17a65e]")}${l}</span>`
          : `<span class="relative flex h-12 w-11 items-center justify-center text-white/70">${ic(i, "h-[22px] w-[22px]")}${k === 3 ? '<span class="absolute right-[9px] top-[12px] h-2 w-2 rounded-full bg-[#f4781f] ring-[1.5px] ring-[#0e1411]"></span>' : ""}</span>`,
      )
      .join("")}
  </div>`;
}

function round(icon, extra = "") {
  return `<span class="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white text-[#0e1411] shadow-[0_1px_2px_rgba(14,20,17,.05),0_12px_28px_-18px_rgba(14,20,17,.35)] ${extra}">${ic(icon, "h-5 w-5")}</span>`;
}

function avatar(init, bg, size = 40, ring = "") {
  return `<span class="flex shrink-0 items-center justify-center rounded-full font-bold text-white ${ring}" style="width:${size}px;height:${size}px;background:${bg};font-size:${Math.round(size * 0.38)}px">${init}</span>`;
}

function crest(init, a, b, size = 44, r = 14) {
  return `<span class="flex shrink-0 items-center justify-center font-extrabold text-white" style="width:${size}px;height:${size}px;border-radius:${r}px;background:linear-gradient(135deg,${a},${b});font-size:${Math.round(size * 0.32)}px">${init}</span>`;
}

function pill(text, bg, fg, dot = false, extra = "") {
  return `<span class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 text-[11.5px] font-bold ${extra}" style="background:${bg};color:${fg}">${dot ? `<span class="h-1.5 w-1.5 rounded-full" style="background:${fg}"></span>` : ""}${text}</span>`;
}

const wrapW = (wide, inner) => (wide ? `<div class="mx-auto max-w-[680px]">${inner}</div>` : inner);

// ─── Home ──────────────────────────────────────────────────────────────────
export function home({ wide = false } = {}) {
  const days = [["Sun", 4, 1], ["Mon", 5, 0], ["Tue", 6, 2], ["Wed", 7, 0], ["Thu", 8, 1], ["Fri", 9, 0], ["Sat", 10, 1]];
  const inner = `
  <div class="px-5">
    <div class="mt-2 flex items-center gap-3">
      <div class="min-w-0 flex-1">
        <p class="text-[13px] text-[#5e6b66]">Good evening</p>
        <p class="text-[27px] font-extrabold leading-tight tracking-[-0.02em]">Tunde</p>
      </div>
      ${round("bell", "")}<span class="relative -ml-1"><span class="absolute right-[3px] top-[3px] z-10 hidden"></span></span>
      <span class="relative flex h-[52px] w-[52px] items-center justify-center rounded-full" style="background:conic-gradient(#17a65e 0 68%, #e3e8e5 68% 100%)">
        <span class="flex h-[44px] w-[44px] items-center justify-center rounded-full bg-[#e6f6ec] text-[16px] font-bold text-[#0f7a45] ring-2 ring-white">TB</span>
        <span class="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-full bg-[#f4781f] px-1.5 text-[9.5px] font-extrabold text-white ring-2 ring-[#f3f5f2]">Lv 12</span>
      </span>
    </div>

    <div class="mt-4 grid grid-cols-2 gap-2.5">
      <div class="flex h-[64px] items-center gap-3 rounded-[20px] bg-white px-3 shadow-sm">
        <span class="flex h-10 w-10 items-center justify-center rounded-[13px] bg-[#e6f6ec] text-[#0f7a45]">${ic("users-round", "h-5 w-5")}</span>
        <span class="whitespace-nowrap text-[13.5px] font-bold">Create group</span>
      </div>
      <div class="flex h-[64px] items-center gap-3 rounded-[20px] bg-[#0e1411] px-3 text-white">
        <span class="flex h-10 w-10 items-center justify-center rounded-[13px] bg-white/10 text-[#17a65e]">${ic("scan-line", "h-5 w-5")}</span>
        <span class="whitespace-nowrap text-[13.5px] font-bold">Scan QR</span>
      </div>
    </div>

    <div class="mt-3 ${card} p-4">
      <div class="flex items-center gap-2.5">
        <span class="flex h-9 w-9 items-center justify-center rounded-[12px] bg-[#feeedf] text-[#f4781f]">${ic("flame", "h-5 w-5")}</span>
        <div class="flex-1"><p class="text-[15px] font-bold">Your week</p><p class="text-[12px] text-[#5e6b66]">3-week streak · keep it going</p></div>
        ${pill("+120 XP", C.tint, C.deep)}
      </div>
      <div class="mt-3 space-y-2">
        <div><div class="flex justify-between text-[12px]"><span class="font-semibold">Play 2 games</span><span class="text-[#5e6b66]">1 / 2</span></div><div class="mt-1 h-2 rounded-full bg-[#eef2ef]"><div class="h-2 w-1/2 rounded-full bg-[#17a65e]"></div></div></div>
        <div><div class="flex justify-between text-[12px]"><span class="font-semibold">Check in on time</span><span class="font-bold text-[#0f7a45]">Done</span></div><div class="mt-1 h-2 rounded-full bg-[#17a65e]"></div></div>
      </div>
    </div>

    <div class="relative mt-3 overflow-hidden rounded-[26px] bg-[#0e1411] p-4 text-white">
      <div class="absolute -right-10 -top-12 h-40 w-40 rounded-full bg-[#17a65e]/25 blur-2xl"></div>
      <div class="relative flex items-center justify-between">
        <span class="text-[10.5px] font-bold uppercase tracking-[0.16em] text-[#6edc9e]">Next up</span>
        ${pill("⚽ Football", "rgba(255,255,255,.1)", "#fff")}
      </div>
      <p class="relative mt-2 text-[20px] font-extrabold leading-tight">Sunday 5-a-side</p>
      <p class="relative mt-0.5 text-[12.5px] text-white/70">Today · 18:00 · Riverside Pitches</p>
      <div class="relative mt-3.5 flex items-center justify-between">
        <div class="flex items-center">
          ${["#17a65e", "#f4781f", "#6edc9e", "#ffb57d", "#8fb3ff"].map((c) => `<span class="-ml-1.5 h-7 w-7 rounded-full border-2 border-[#0e1411] first:ml-0" style="background:${c}"></span>`).join("")}
          <span class="ml-2 text-[12px] text-white/70">14 going</span>
        </div>
        <span class="rounded-full bg-white px-4 py-2 text-[13px] font-bold text-[#0e1411]">Check in</span>
      </div>
    </div>

    <div class="mt-3 ${card} p-4">
      <div class="flex items-center justify-between"><p class="text-[17px] font-bold">Your calendar</p><span class="text-[12px] font-semibold text-[#0f7a45]">This week</span></div>
      <div class="mt-3 grid grid-cols-7 gap-1.5">
        ${days.map(([d, n, dot], i) => `<div class="rounded-[14px] py-2 text-center ${i === 0 ? "bg-[#0e1411] text-white" : "bg-[#eef2ef]"}"><p class="text-[10px] ${i === 0 ? "text-white/70" : "text-[#5e6b66]"}">${d}</p><p class="text-[15px] font-extrabold">${n}</p><span class="mx-auto mt-0.5 block h-1.5 w-1.5 rounded-full ${dot === 2 ? "bg-[#e02424]" : dot ? (i === 0 ? "bg-[#6edc9e]" : "bg-[#17a65e]") : "bg-transparent"}"></span></div>`).join("")}
      </div>
      <div class="mt-3 space-y-2">
        <div class="flex items-center gap-3 rounded-[16px] bg-[#fde8e8] px-3 py-2.5"><span class="h-2 w-2 animate-pulse rounded-full bg-[#e02424]"></span><div class="flex-1"><p class="text-[13.5px] font-bold">Padel doubles</p><p class="text-[11.5px] text-[#5e6b66]">Court House Padel · Court 3</p></div><span class="text-[11px] font-extrabold text-[#e02424]">LIVE</span></div>
        <div class="flex items-center gap-3 rounded-[16px] bg-[#eef2ef] px-3 py-2.5"><span class="text-[12px] font-bold text-[#0f7a45]">18:00</span><div class="flex-1"><p class="text-[13.5px] font-bold">Sunday 5-a-side</p><p class="text-[11.5px] text-[#5e6b66]">East End Ballers</p></div>${pill("Going", C.tint, C.deep)}</div>
      </div>
    </div>
  </div>`;
  return `${status()}${wrapW(wide, inner)}${dock(0)}`;
}

// ─── Browse ────────────────────────────────────────────────────────────────
const TILES = [
  { t: "Sunday 5-a-side", s: "⚽ Football", w: "Today · 18:00", g: "East End Ballers", m: "0.8 mi · 14 going", bg: "linear-gradient(135deg,#0e1411,#0f7a45)", live: false },
  { t: "Padel doubles mixer", s: "🎾 Padel", w: "Now · Court 3", g: "Padel Pals", m: "1.2 mi · 8 going", bg: "linear-gradient(135deg,#123a5e,#1f7ab8)", live: true },
  { t: "Thursday night hoops", s: "🏀 Basketball", w: "Thu · 20:00", g: "Northside Hoopers", m: "2.4 mi · 11 going", bg: "linear-gradient(135deg,#3a1d0b,#c4601a)", live: false },
  { t: "Summer Cup · Semis", s: "🏆 Tournament", w: "Sat · 10:00", g: "Riverside League", m: "3.1 mi · 8 teams", bg: "linear-gradient(135deg,#0e1411,#7a3a10)", live: false },
  { t: "Beach volley social", s: "🏐 Volleyball", w: "Sun · 14:00", g: "Sand Squad", m: "4.0 mi · 10 going", bg: "linear-gradient(135deg,#5a4a17,#d9a441)", live: false },
  { t: "Run club 5k", s: "🏃 Running", w: "Wed · 07:00", g: "Dawn Runners", m: "0.5 mi · 23 going", bg: "linear-gradient(135deg,#1c2b24,#3d7a5c)", live: false },
];
function tile(x) {
  return `<div class="rounded-[22px] bg-white p-1.5 shadow-[0_1px_2px_rgba(14,20,17,.05),0_12px_28px_-18px_rgba(14,20,17,.25)]">
    <div class="relative h-[108px] overflow-hidden rounded-[17px]" style="background:${x.bg}">${pitch("white", 0.14)}
      <div class="absolute left-2 top-2">${pill(x.s, "rgba(255,255,255,.92)", "#0e1411", false, "!text-[10.5px] !px-2 !py-0.5")}</div>
      ${x.live ? `<div class="absolute right-2 top-2">${pill("LIVE", "#e02424", "#fff", true, "!text-[10px] !px-2 !py-0.5")}</div>` : ""}
    </div>
    <div class="px-1.5 pb-1.5 pt-2">
      <p class="truncate text-[13.5px] font-bold leading-tight">${x.t}</p>
      <p class="mt-0.5 truncate text-[11.5px] font-semibold ${x.live ? "text-[#e02424]" : "text-[#0f7a45]"}">${x.w}</p>
      <p class="truncate text-[11px] text-[#5e6b66]">${x.g}</p>
      <p class="mt-1 truncate text-[10.5px] text-[#5e6b66]">${ic("map-pin", "inline h-3 w-3 -mt-0.5")} ${x.m}</p>
    </div>
  </div>`;
}
export function browse({ wide = false } = {}) {
  const cols = wide ? "grid-cols-3" : "grid-cols-2";
  const tiles = wide
    ? [
        ...TILES,
        { t: "Tennis ladder night", s: "🎾 Tennis", w: "Fri · 19:00", g: "Parkside Tennis", m: "1.9 mi · 16 going", bg: "linear-gradient(135deg,#2c4a12,#7ab82f)", live: false },
        { t: "Women's 7-a-side", s: "⚽ Football", w: "Sat · 11:00", g: "Northside Ladies FC", m: "2.2 mi · 12 going", bg: "linear-gradient(135deg,#0e1411,#17a65e)", live: false },
        { t: "Badminton doubles", s: "🏸 Badminton", w: "Now · Hall B", g: "Shuttle Club", m: "3.3 mi · 9 going", bg: "linear-gradient(135deg,#3a1d5e,#7a3ab8)", live: true },
      ]
    : TILES;
  const inner = `<div class="px-5">
    <div class="mt-2 flex items-center justify-between"><p class="text-[27px] font-extrabold tracking-[-0.02em]">Browse</p>${round("map")}</div>
    <div class="mt-3 flex h-12 items-center gap-2.5 rounded-[18px] bg-white px-4 text-[#5e6b66] shadow-sm">${ic("search", "h-5 w-5")}<span class="text-[14px]">Search games, groups, players</span></div>
    <div class="mt-3 flex gap-2 overflow-hidden">
      <span class="flex shrink-0 items-center gap-1.5 rounded-full bg-[#0e1411] px-3.5 py-2 text-[13px] font-semibold text-white">${ic("navigation", "h-4 w-4")}Near me</span>
      <span class="flex shrink-0 items-center gap-1.5 rounded-full bg-white px-3.5 py-2 text-[13px] font-semibold ring-1 ring-inset ring-[#e3e8e5]"><span class="h-1.5 w-1.5 rounded-full bg-[#e02424]"></span>Live</span>
      <span class="shrink-0 rounded-full bg-white px-3.5 py-2 text-[13px] font-semibold ring-1 ring-inset ring-[#e3e8e5]">⚽ Football</span>
      <span class="shrink-0 rounded-full bg-white px-3.5 py-2 text-[13px] font-semibold ring-1 ring-inset ring-[#e3e8e5]">🎾 Padel</span>
      <span class="shrink-0 rounded-full bg-white px-3.5 py-2 text-[13px] font-semibold ring-1 ring-inset ring-[#e3e8e5]">🏀 Basketball</span>
    </div>
    <p class="mt-4 text-[13px] text-[#5e6b66]"><b class="text-[#0e1411]">42 games</b> within 5 miles of you</p>
    <div class="mt-2.5 grid ${cols} gap-2.5">${tiles.map(tile).join("")}</div>
  </div>`;
  return `${status()}${wrapW(wide, inner)}${dock(1)}`;
}

// ─── Live match ────────────────────────────────────────────────────────────
export function match({ wide = false } = {}) {
  const ev = [
    ["67'", "⚽", "Goal", "Marcus Ade", "East End", "3 – 2", true],
    ["58'", "🟨", "Yellow card", "Jide Okafor", "Northside", "", false],
    ["52'", "⚽", "Goal", "Leo Hart", "Northside", "2 – 2", false],
    ["41'", "⚽", "Goal", "Sam Reid", "East End", "2 – 1", true],
    ["23'", "🧤", "Great save", "Kofi Mensah", "East End", "", true],
  ];
  const inner = `<div class="px-5">
    <div class="mt-1 flex items-center gap-3">${round("arrow-left")}<div class="flex-1"><p class="text-[19px] font-extrabold leading-tight">Football</p><p class="text-[12.5px] text-[#5e6b66]">Summer Cup · Semi-final</p></div>${round("share-2")}</div>

    <div class="relative mt-4 overflow-hidden rounded-[28px] bg-[#0e1411] px-4 pb-4 pt-4 text-white">
      ${pitch("white", 0.07)}
      <div class="absolute -right-10 -top-10 h-40 w-40 rounded-full bg-[#f4781f]/25 blur-2xl"></div>
      <div class="relative flex justify-center">${pill("LIVE · 2nd half", "rgba(224,36,36,.18)", "#ff8a8a", true)}</div>
      <div class="relative mt-4 grid grid-cols-[1fr_auto_1fr] items-center gap-2">
        <div class="flex flex-col items-center text-center">${crest("EE", "#17a65e", "#0f7a45", 58, 20)}<p class="mt-2 text-[13px] font-bold">East End</p><p class="text-[10.5px] text-white/60">Ballers</p></div>
        <p class="text-[54px] font-extrabold leading-none tracking-[-0.04em]">3<span class="mx-2 text-white/40">–</span>2</p>
        <div class="flex flex-col items-center text-center">${crest("NS", "#f4781f", "#9a4308", 58, 20)}<p class="mt-2 text-[13px] font-bold">Northside</p><p class="text-[10.5px] text-white/60">United</p></div>
      </div>
      <div class="relative mt-4 rounded-[16px] bg-white/[0.07] px-3 py-2.5">
        <div class="flex items-center justify-between text-[12px]"><span class="font-bold text-[#6edc9e]">67'</span><span class="text-white/60">Full time 90'</span></div>
        <div class="mt-1.5 h-1.5 rounded-full bg-white/10"><div class="h-1.5 w-[74%] rounded-full bg-[#6edc9e]"></div></div>
      </div>
    </div>

    <div class="mt-3 ${card} px-2 py-1">
      <p class="px-2 pb-1 pt-3 text-[15px] font-bold">Key moments</p>
      ${ev.map(([t, e, k, n, tm, sc, home]) => `<div class="flex items-center gap-3 border-t border-[#eef2ef] px-2 py-2.5 first-of-type:border-0">
        <span class="w-8 text-[12px] font-bold text-[#5e6b66]">${t}</span>
        <span class="flex h-9 w-9 items-center justify-center rounded-[12px] ${home ? "bg-[#e6f6ec]" : "bg-[#feeedf]"} text-[16px]">${e}</span>
        <div class="min-w-0 flex-1"><p class="text-[13.5px] font-bold">${k} <span class="font-normal text-[#5e6b66]">· ${n}</span></p><p class="text-[11.5px] text-[#5e6b66]">${tm}</p></div>
        ${sc ? `<span class="rounded-full bg-[#eef2ef] px-2.5 py-1 text-[12px] font-extrabold">${sc}</span>` : ""}
      </div>`).join("")}
    </div>
  </div>`;
  return `${status()}${wrapW(wide, inner)}`;
}

// ─── Ticket / check-in ─────────────────────────────────────────────────────
export async function ticket({ wide = false } = {}) {
  const qr = await QRCode.toString("SPORTPADI-TICKET-7Q4K29", { type: "svg", margin: 0, color: { dark: "#0e1411", light: "#ffffff" } });
  const inner = `<div class="px-5">
    <div class="mx-auto mt-1 h-1 w-10 rounded-full bg-[#e3e8e5]"></div>
    <div class="mt-4 overflow-hidden rounded-[28px] bg-white shadow-[0_1px_2px_rgba(14,20,17,.05),0_12px_28px_-18px_rgba(14,20,17,.3)]">
      <div class="relative overflow-hidden bg-[#0e1411] px-5 pb-5 pt-5 text-white">
        ${pitch("white", 0.07)}
        <div class="relative flex items-center justify-between"><span class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#6edc9e]">Match ticket</span>${pill("Valid", "rgba(255,255,255,.12)", "#fff")}</div>
        <p class="relative mt-2 text-[22px] font-extrabold leading-tight">Sunday 5-a-side</p>
        <p class="relative text-[13px] text-white/75">Entry · 1 player</p>
        <div class="relative mt-4 grid grid-cols-3 gap-2">
          ${[["Date", "Sun 4 Oct"], ["Kick-off", "18:00"], ["Pitch", "No. 2"]].map(([a, b]) => `<div class="rounded-[14px] bg-white/10 px-2 py-2"><p class="text-[10.5px] text-white/60">${a}</p><p class="text-[13.5px] font-bold">${b}</p></div>`).join("")}
        </div>
      </div>
      <div class="relative h-5 bg-white"><span class="absolute -left-2.5 top-0 h-5 w-5 rounded-full bg-[#f3f5f2]"></span><span class="absolute -right-2.5 top-0 h-5 w-5 rounded-full bg-[#f3f5f2]"></span><span class="absolute inset-x-5 top-1/2 border-t-2 border-dashed border-[#e3e8e5]"></span></div>
      <div class="flex flex-col items-center px-5 pb-6 pt-2">
        <div class="w-[210px] rounded-[20px] bg-white p-3 ring-1 ring-[#e3e8e5]">${qr.replace("<svg", '<svg class="h-full w-full"')}</div>
        <p class="mt-3 font-mono text-[15px] font-bold tracking-[0.2em]">SP-7Q4K-29</p>
        <p class="mt-1 text-[12.5px] text-[#5e6b66]">Show this at the gate — it scans in a second</p>
      </div>
    </div>
    <div class="mt-3 flex items-center gap-3 rounded-[22px] bg-[#e6f6ec] px-4 py-3">
      <span class="flex h-10 w-10 items-center justify-center rounded-[13px] bg-[#0f7a45] text-white">${ic("shield-check", "h-5 w-5")}</span>
      <div class="flex-1"><p class="text-[14px] font-bold text-[#0f7a45]">Paid · £6.00</p><p class="text-[12px] text-[#5e6b66]">East End Ballers · receipt in your purchases</p></div>
    </div>
  </div>`;
  return `${status()}${wrapW(wide, inner)}`;
}

// ─── Tournament ────────────────────────────────────────────────────────────
export function tournament({ wide = false } = {}) {
  const matches = [
    ["QF", "East End", "#17a65e", "Riverside", "#1f7ab8", "4 – 1", "win"],
    ["QF", "Northside", "#f4781f", "Dockside FC", "#7a3ab8", "2 – 2 (4–3p)", "pens"],
    ["SF", "East End", "#17a65e", "Northside", "#f4781f", "3 – 2", "live"],
    ["SF", "Hilltop", "#d9a441", "Parkway", "#e02424", "Sat 12:00", "up"],
  ];
  const inner = `
  <div class="relative h-[250px] overflow-hidden rounded-b-[32px]" style="background:linear-gradient(160deg,#0e1411 30%,#7a3a10 75%,#f4781f)">
    ${pitch("white", 0.09)}
    <div class="absolute inset-x-0 top-0">${status(true)}</div>
    <div class="absolute inset-x-5 top-[54px] flex justify-between">${round("arrow-left")}${round("share-2")}</div>
    <div class="absolute bottom-16 left-0 right-0 flex justify-center text-[64px]">🏆</div>
  </div>
  <div class="relative -mt-14 px-5">
    <div class="${card} p-4">
      <div class="flex flex-wrap gap-1.5">${pill("Knockout", C.oTint, C.oInk)}${pill("⚽ Football", C.s2, C.ink)}${pill("Live", C.live, C.danger, true)}</div>
      <p class="mt-2 text-[23px] font-extrabold leading-tight tracking-[-0.02em]">Summer Cup 2026</p>
      <p class="text-[12.5px] text-[#5e6b66]">Hosted by Riverside League</p>
      <div class="mt-3 grid grid-cols-3 gap-2">
        ${[["8", "Teams"], ["14", "Matches"], ["41", "Goals"]].map(([a, b]) => `<div class="rounded-[14px] bg-[#eef2ef] py-2 text-center"><p class="text-[17px] font-extrabold">${a}</p><p class="text-[11px] text-[#5e6b66]">${b}</p></div>`).join("")}
      </div>
    </div>
    <p class="mb-2 mt-4 text-[17px] font-bold">Matches</p>
    <div class="${card} px-2 py-1">
      ${matches.map(([r, a, ca, b, cb, sc, st]) => `<div class="flex items-center gap-2.5 border-t border-[#eef2ef] px-2 py-2.5 first:border-0">
        <span class="w-7 text-[11px] font-extrabold text-[#9a4308]">${r}</span>
        <div class="min-w-0 flex-1 space-y-1">
          <p class="flex items-center gap-2 text-[13px] font-bold"><span class="h-4 w-4 rounded-[5px]" style="background:${ca}"></span>${a}</p>
          <p class="flex items-center gap-2 text-[13px] font-bold"><span class="h-4 w-4 rounded-[5px]" style="background:${cb}"></span>${b}</p>
        </div>
        ${st === "live" ? pill(sc, C.live, C.danger, true) : st === "up" ? `<span class="text-[12px] font-semibold text-[#5e6b66]">${sc}</span>` : `<span class="rounded-full bg-[#eef2ef] px-2.5 py-1 text-[11.5px] font-extrabold">${sc}</span>`}
      </div>`).join("")}
    </div>
    <p class="mb-2 mt-4 text-[17px] font-bold">Awards</p>
    <div class="grid grid-cols-2 gap-2.5">
      <div class="rounded-[20px] bg-[#0e1411] p-3 text-white"><p class="text-[20px]">🥇</p><p class="mt-1 text-[11px] text-[#6edc9e]">Golden boot</p><p class="text-[13.5px] font-bold">Marcus Ade · 7</p></div>
      <div class="rounded-[20px] bg-[#feeedf] p-3"><p class="text-[20px]">🧤</p><p class="mt-1 text-[11px] text-[#9a4308]">Best keeper</p><p class="text-[13.5px] font-bold">Kofi Mensah</p></div>
    </div>
  </div>`;
  return wrapW(wide, inner) + (wide ? "" : "");
}

// ─── Leaderboard ───────────────────────────────────────────────────────────
export function leaderboard({ wide = false } = {}) {
  const rows = [
    [4, "DO", "#8fb3ff", "Dami Ola", "18 games", 212],
    [5, "TB", "#17a65e", "You · Tunde", "16 games", 198, true],
    [6, "LH", "#d9a441", "Leo Hart", "17 games", 176],
    [7, "JO", "#7a3ab8", "Jide Okafor", "15 games", 161],
  ];
  const pod = (rank, init, col, name, pts, h, win) => `<div class="flex flex-1 flex-col items-center">
    <div class="relative">${avatar(init, col, win ? 64 : 52, win ? "ring-4 ring-[#f4781f]" : "ring-4 ring-white")}${win ? '<svg class="absolute -top-[26px] left-1/2 h-[22px] w-[30px] -translate-x-1/2" viewBox="0 0 30 22"><path d="M2.4 20.2 0.6 6.6 9 12.8 15 2.6 21 12.8 29.4 6.6 27.6 20.2Z" fill="#F0A500"/><rect x="2.4" y="17.6" width="25.2" height="4.4" rx="1.8" fill="#F0A500"/><circle cx="0.9" cy="6.6" r="2.2" fill="#F0A500"/><circle cx="15" cy="2.3" r="2.2" fill="#F0A500"/><circle cx="29.1" cy="6.6" r="2.2" fill="#F0A500"/></svg>' : ""}</div>
    <p class="mt-2 text-[13px] font-bold">${name}</p><p class="text-[11.5px] font-semibold text-[#0f7a45]">${pts} pts</p>
    <div class="mt-2 flex w-full items-start justify-center rounded-t-[18px] pt-2 ${win ? "bg-[#0e1411] text-white" : "bg-white"}" style="height:${h}px"><span class="text-[26px] font-extrabold ${win ? "text-[#6edc9e]" : "text-[#5e6b66]"}">${rank}</span></div>
  </div>`;
  const inner = `<div class="px-5">
    <div class="mt-1 flex items-center gap-3">${round("arrow-left")}<div class="flex-1"><p class="text-[19px] font-extrabold leading-tight">Leaderboard</p><p class="text-[12.5px] text-[#5e6b66]">East End Ballers · this season</p></div>${round("share-2")}</div>
    <div class="mt-4 flex gap-2 overflow-hidden">
      ${["Points", "Goals", "Assists", "MVP", "Clean sheets"].map((b, i) => `<span class="shrink-0 rounded-full px-3.5 py-2 text-[13px] font-semibold ${i === 0 ? "bg-[#0e1411] text-white" : "bg-white ring-1 ring-inset ring-[#e3e8e5]"}">${b}</span>`).join("")}
    </div>
    <div class="mt-6 flex items-end gap-2.5">
      ${pod(2, "SR", "#1f7ab8", "Sam Reid", 264, 86)}${pod(1, "MA", "#f4781f", "Marcus Ade", 301, 120, true)}${pod(3, "KM", "#7a3ab8", "Kofi Mensah", 247, 66)}
    </div>
    <div class="${card} -mt-1 px-2 py-1">
      ${rows.map(([r, i, c, n, g, p, me]) => `<div class="flex items-center gap-3 rounded-[16px] px-2 py-2.5 ${me ? "bg-[#e6f6ec]" : ""}"><span class="w-5 text-center text-[13px] font-extrabold text-[#5e6b66]">${r}</span>${avatar(i, c, 38)}<div class="flex-1"><p class="text-[14px] font-bold ${me ? "text-[#0f7a45]" : ""}">${n}</p><p class="text-[11.5px] text-[#5e6b66]">${g}</p></div><span class="text-[14px] font-extrabold">${p}</span>${me ? `<span class="flex items-center text-[#0f7a45]">${ic("trending-up", "h-4 w-4")}</span>` : ""}</div>`).join("")}
    </div>
  </div>`;
  return `${status()}${wrapW(wide, inner)}`;
}

// ─── Profile / record ──────────────────────────────────────────────────────
export function profile({ wide = false } = {}) {
  const inner = `
  <div class="relative h-[190px] overflow-hidden rounded-b-[32px]" style="background:linear-gradient(135deg,#0e1411,#0f5a36)">
    ${pitch("white", 0.08)}
    <div class="absolute -bottom-10 right-0 h-40 w-40 rounded-full bg-[#f4781f]/25 blur-2xl"></div>
    <div class="absolute inset-x-0 top-0">${status(true)}</div>
    <div class="absolute inset-x-5 top-[54px] flex items-start justify-between">${round("qr-code")}<p class="pt-2.5 text-[16px] font-extrabold text-white">Profile</p>${round("ellipsis")}</div>
  </div>
  <div class="relative -mt-[34px] px-5">
    <div class="absolute left-1/2 top-[-52px] z-10 -translate-x-1/2 rounded-full bg-white p-[3px] shadow-lg"><div class="rounded-full p-[3px] ring-[3px] ring-[#f4781f]">${avatar("TB", "linear-gradient(135deg,#17a65e,#0f7a45)", 88)}</div></div>
    <div class="${card} px-4 pb-4 pt-[62px] text-center">
      <p class="text-[23px] font-extrabold leading-tight">Tunde Bakare</p>
      <span class="mt-2 inline-flex rounded-full bg-[#eef2ef] px-3 py-1 text-[13px] font-semibold">@tunde</span>
      <div class="mt-2 flex justify-center gap-1.5">${pill("Lv 12 · Playmaker", C.oTint, C.oInk)}${pill("🔥 3-week streak", C.s2, C.ink)}</div>
      <div class="mt-4 grid grid-cols-3 gap-2">
        ${[["48", "Played"], ["29-7-12", "W-D-L"], ["60%", "Win rate", 1]].map(([a, b, g]) => `<div class="rounded-[14px] ${g ? "bg-[#e6f6ec]" : "bg-[#eef2ef]"} py-2.5"><p class="text-[17px] font-extrabold ${g ? "text-[#0f7a45]" : ""}">${a}</p><p class="text-[11px] text-[#5e6b66]">${b}</p></div>`).join("")}
      </div>
    </div>
    <div class="mt-4 flex items-center justify-between"><p class="text-[17px] font-bold">⚽ Football record</p><span class="text-[12px] font-semibold text-[#0f7a45]">All sports</span></div>
    <div class="mt-2 grid grid-cols-2 gap-2.5">
      <div class="relative overflow-hidden rounded-[22px] bg-[#0e1411] p-4 text-white">${pitch("white", 0.06)}<p class="relative text-[11px] font-bold uppercase tracking-[0.14em] text-[#6edc9e]">Goals</p><p class="relative text-[34px] font-extrabold leading-tight">31</p><p class="relative text-[11.5px] text-white/65">0.65 per game</p></div>
      <div class="rounded-[22px] bg-white p-4 shadow-sm"><p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#0f7a45]">Assists</p><p class="text-[34px] font-extrabold leading-tight">18</p><p class="text-[11.5px] text-[#5e6b66]">Top 3 in group</p></div>
      <div class="rounded-[22px] bg-white p-4 shadow-sm"><p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#9a4308]">MVP awards</p><p class="text-[34px] font-extrabold leading-tight">6</p><p class="text-[11.5px] text-[#5e6b66]">Last: 2 weeks ago</p></div>
      <div class="rounded-[22px] bg-[#e6f6ec] p-4"><p class="text-[11px] font-bold uppercase tracking-[0.14em] text-[#0f7a45]">Position</p><p class="text-[22px] font-extrabold leading-tight">Midfield</p><p class="text-[11.5px] text-[#5e6b66]">Strong foot · Right</p></div>
    </div>
  </div>`;
  return `${wrapW(wide, inner)}${dock(4)}`;
}

// ─── Group ─────────────────────────────────────────────────────────────────
export function group({ wide = false } = {}) {
  const teams = [["East End A", "#17a65e", "#0f7a45", "EA", "Football"], ["East End B", "#0e1411", "#3d7a5c", "EB", "Football"], ["Padel Pairs", "#1f7ab8", "#123a5e", "PP", "Padel"], ["Hoops Crew", "#f4781f", "#9a4308", "HC", "Basketball"]];
  const inner = `
  <div class="relative h-[210px] overflow-hidden rounded-b-[32px]" style="background:linear-gradient(140deg,#0f7a45,#17a65e 55%,#6edc9e)">
    ${pitch("white", 0.16)}
    <div class="absolute inset-x-0 top-0">${status(true)}</div>
    <div class="absolute inset-x-5 top-[54px] flex justify-between">${round("arrow-left")}<span class="flex gap-2">${round("camera")}${round("share-2")}</span></div>
  </div>
  <div class="relative -mt-14 px-5">
    <div class="${card} p-4">
      <div class="flex items-center gap-3">${crest("EB", "#0e1411", "#0f7a45", 60, 20)}<div class="flex-1"><p class="flex items-center gap-1 text-[20px] font-extrabold leading-tight">East End Ballers <svg class="h-[21px] w-[21px]" viewBox="0 0 24 24"><path d="M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z" fill="#F0A500" stroke="#F0A500" stroke-width="1.6" stroke-linejoin="round"/><path d="m9 12 2 2 4-4" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></p><p class="text-[12.5px] text-[#5e6b66]">Football · Padel · Basketball</p></div></div>
      <div class="mt-3 grid grid-cols-3 gap-2">
        ${[["142", "Members"], ["86", "Events"], ["6", "Teams"]].map(([a, b]) => `<div class="rounded-[14px] bg-[#eef2ef] py-2 text-center"><p class="text-[17px] font-extrabold">${a}</p><p class="text-[11px] text-[#5e6b66]">${b}</p></div>`).join("")}
      </div>
      <div class="mt-3 grid grid-cols-2 gap-2">
        <span class="flex h-11 items-center justify-center gap-2 rounded-full bg-[#0e1411] text-[14px] font-bold text-white">${ic("plus", "h-4 w-4")}New event</span>
        <span class="flex h-11 items-center justify-center gap-2 rounded-full bg-[#eef2ef] text-[14px] font-bold">${ic("user-plus", "h-4 w-4")}Invite</span>
      </div>
    </div>
    <div class="mt-3 grid grid-cols-3 gap-2">
      ${[["wallet", "Wallet", "£1,240", C.tint, C.deep], ["ticket", "Tickets", "38 sold", C.s2, C.ink], ["receipt", "Fines", "£45 due", C.oTint, C.oInk]].map(([i, a, b, bg, fg]) => `<div class="rounded-[18px] bg-white p-3 shadow-sm"><span class="flex h-8 w-8 items-center justify-center rounded-[10px]" style="background:${bg};color:${fg}">${ic(i, "h-4 w-4")}</span><p class="mt-2 text-[12px] text-[#5e6b66]">${a}</p><p class="text-[14px] font-extrabold">${b}</p></div>`).join("")}
    </div>
    <div class="mt-4 flex rounded-full bg-[#eef2ef] p-1">${["Events", "Teams", "Tournaments"].map((t, i) => `<span class="flex-1 rounded-full py-2 text-center text-[13px] font-semibold ${i === 1 ? "bg-white shadow-sm" : "text-[#5e6b66]"}">${t}</span>`).join("")}</div>
    <div class="mt-3 grid grid-cols-2 gap-2.5">
      ${teams.map(([n, a, b, i, s]) => `<div class="rounded-[22px] bg-white p-1.5 shadow-sm"><div class="relative h-[62px] rounded-[17px]" style="background:linear-gradient(135deg,${a},${b})"><div class="absolute -bottom-4 left-2.5 rounded-[14px] bg-white p-[3px]">${crest(i, a, b, 36, 11)}</div></div><div class="px-1.5 pb-2 pt-5"><p class="text-[13.5px] font-bold">${n}</p><p class="text-[11px] text-[#5e6b66]">${s} · 12 players</p></div></div>`).join("")}
    </div>
  </div>`;
  return `${wrapW(wide, inner)}${dock(2)}`;
}

export const SCREENS = { home, browse, match, ticket, tournament, leaderboard, profile, group };

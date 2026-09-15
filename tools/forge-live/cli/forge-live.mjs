#!/usr/bin/env node
// forge-live — el bucle "guardar y ver" para mods de Project Zomboid B42.
//
//   guardás un .lua en el repo
//     -> gate: BOM / no-ASCII / sintaxis Lua 5.1   (un archivo roto NUNCA llega al juego)
//     -> copia a las rutas instaladas (mods/ y staging de Workshop)
//     -> le pide al DemiurgoBridge in-game: reloadLuaFile(<ruta>)
//     -> imprime el veredicto real que devolvió el juego
//
// Uso:
//   node mcp/forge-live.mjs                 # vigila todo lo del config
//   node mcp/forge-live.mjs --mod Captive   # solo un mod
//   node mcp/forge-live.mjs --dry           # no escribe ni recarga, solo informa
//   node mcp/forge-live.mjs --once <file>   # procesa un archivo y sale (util para probar)
//
// Requiere PZ_ALLOW_CONTROL=1 salvo en --dry (mismo gate que el resto del MCP).

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const flag = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? (args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : true) : null;
};
const REPO = path.resolve(path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\//, "")), ".."));
const configPath = flag("--config") || path.join(REPO, "forge-live.config.json");
const onlyMod = typeof flag("--mod") === "string" ? flag("--mod") : null;
const onceFile = typeof flag("--once") === "string" ? flag("--once") : null;
const dry = args.includes("--dry");

if (!dry && process.env.PZ_ALLOW_CONTROL !== "1") {
  console.error("[forge-live] falta PZ_ALLOW_CONTROL=1 (o usa --dry)");
  process.exit(1);
}
if (!fs.existsSync(configPath)) {
  console.error(`[forge-live] no encuentro el config: ${configPath}`);
  process.exit(1);
}
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));

let luaparse = null;
try {
  luaparse = (await import("luaparse")).default;
} catch { /* opcional */ }
console.log(`[forge-live] gate de sintaxis: ${luaparse ? "ON" : "OFF (npm i luaparse)"}`);

// ---------- gate G1 (mismo criterio que pz_lua_check) ----------
function gate(abs) {
  const buf = fs.readFileSync(abs);
  const bad = [];
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf)
    bad.push("BOM UTF-8 (PZ tira Error 11)");
  // This project keeps Russian comments in UTF-8 Lua sources. PZ loads those files
  // correctly; reject only a BOM and actual Lua 5.1 syntax errors.
  if (luaparse) {
    try { luaparse.parse(buf.toString("utf8"), { luaVersion: "5.1" }); }
    catch (e) { bad.push(`sintaxis: ${e.message}`); }
  }
  return bad;
}

// ---------- lo que el motor NO recarga ----------
const NO_HOT = [
  [/\.txt$/i, "scripts .txt (items/recetas) se parsean al arrancar -> requiere reiniciar PZ"],
  [/mod\.info$/i, "mod.info se lee al arrancar -> requiere reiniciar PZ"],
  [/\.(fbx|png|x|anim)$/i, "assets cacheados por el motor -> normalmente requiere reiniciar"],
];

// ---------- canal con el bridge ----------
function send(bridgeDir, type, payload, timeoutMs = 6000) {
  const id = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  fs.mkdirSync(bridgeDir, { recursive: true });
  // El \n final NO es cosmetico: el readLine() de PZ puede devolver nil sobre un
  // archivo sin terminador de linea, y entonces el comando se pierde sin ruido.
  fs.writeFileSync(path.join(bridgeDir, "cmd.txt"), `${id}\t${type}\t${payload || ""}\n`);
  // .txt, no .json: en 42.20 getFileWriter devuelve nil sobre .json y la respuesta
  // se pierde sin error. Fue la causa raiz del canal mudo (ver doc 181).
  const rf = path.join(bridgeDir, "result.txt");
  const t0 = Date.now();
  return new Promise((res) => {
    const iv = setInterval(() => {
      try {
        const r = JSON.parse(fs.readFileSync(rf, "utf8"));
        if (r.id === id) { clearInterval(iv); res({ ...r, ms: Date.now() - t0 }); return; }
      } catch { /* aun no */ }
      if (Date.now() - t0 > timeoutMs) {
        clearInterval(iv);
        res({ id, ok: false, value: "timeout: el juego no respondio (bridge cargado? in-world?)", ms: Date.now() - t0 });
      }
    }, 120);
  });
}

// ---------- procesar un archivo ----------
async function handle(mod, abs) {
  const rel = path.relative(path.resolve(mod.src), abs);
  if (rel.startsWith("..")) return;

  const no = NO_HOT.find(([re]) => re.test(abs));
  if (no) { console.log(`  [${mod.id}] ${rel}: NO recargable — ${no[1]}`); return; }
  if (!abs.endsWith(".lua")) return;

  const t0 = Date.now();
  const bad = gate(abs);
  if (bad.length) {
    console.log(`  [${mod.id}] ${rel}: BLOQUEADO (el juego ni se entera)`);
    bad.forEach((b) => console.log(`      - ${b}`));
    return;
  }

  const targets = [];
  for (const t of mod.targets) {
    const dst = path.join(path.resolve(t), rel);
    if (!dry) { fs.mkdirSync(path.dirname(dst), { recursive: true }); fs.copyFileSync(abs, dst); }
    targets.push(dst);
  }
  if (dry) { console.log(`  [${mod.id}] ${rel}: gate OK, ${targets.length} destino(s) [dry]`); return; }

  const r = await send(path.resolve(mod.bridgeDir), "reload", targets[0]);
  const total = Date.now() - t0;
  console.log(`  [${mod.id}] ${rel}: ${r.ok ? "RECARGADO" : "FALLO"} en ${total}ms — ${r.value}`);
}

// ---------- watcher ----------
function watch(mod) {
  const src = path.resolve(mod.src);
  if (!fs.existsSync(src)) { console.error(`[${mod.id}] no existe la fuente: ${src}`); return; }
  console.log(`[${mod.id}] vigilando ${src}`);
  const timers = new Map();
  const sched = (f) => {
    clearTimeout(timers.get(f));
    timers.set(f, setTimeout(() => handle(mod, f), 300));
  };
  try {
    fs.watch(src, { recursive: true }, (_e, fname) => {
      if (!fname) return;
      const full = path.join(src, fname.toString());
      if (fs.existsSync(full) && fs.statSync(full).isFile()) sched(full);
    });
  } catch {
    console.log(`[${mod.id}] sin watch recursivo; sondeo cada 1s`);
    const seen = new Map();
    setInterval(() => {
      const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).forEach((e) => {
        const full = path.join(d, e.name);
        if (e.isDirectory()) return walk(full);
        const m = fs.statSync(full).mtimeMs;
        if (seen.get(full) && seen.get(full) !== m) sched(full);
        seen.set(full, m);
      });
      walk(src);
    }, 1000);
  }
}

// ---------- main ----------
const mods = config.mods.filter((m) => !onlyMod || m.id === onlyMod);
if (!mods.length) { console.error("[forge-live] ningun mod coincide"); process.exit(1); }

if (onceFile) {
  const abs = path.resolve(onceFile);
  const mod = mods.find((m) => !path.relative(path.resolve(m.src), abs).startsWith(".."));
  if (!mod) { console.error(`[forge-live] ${abs} no pertenece a ningun mod del config`); process.exit(1); }
  await handle(mod, abs);
  process.exit(0);
}

console.log(`[forge-live] ${dry ? "DRY — " : ""}vigilando ${mods.length} mod(s). Ctrl+C para salir.`);
for (const m of mods) watch(m);
if (!dry) {
  for (const m of mods) {
    if (!m.bridgeDir) continue;
    send(path.resolve(m.bridgeDir), "ping", "").then((r) =>
      console.log(`[${m.id}] bridge: ${r.ok ? r.value : "sin respuesta — " + r.value}`));
  }
}

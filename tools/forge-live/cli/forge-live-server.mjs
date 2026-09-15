#!/usr/bin/env node
// forge-live-server -- hot-reload a mod file on a DEDICATED Project Zomboid server,
// with no restart, driven over RCON.
//
//   you edit a .lua in your repo
//     -> syntax gate (BOM / non-ASCII / Lua 5.1 parse)   -- broken files never ship
//     -> copy into the server's mod folder (local path or over ssh)
//     -> RCON: reloadlua "<filename>"
//     -> print what the server actually answered
//
// Verified on Build 42.20: `reloadlua` is a real server admin command and it works
// over RCON, so no admin has to be logged into the game to type it in chat. That is
// what makes this scriptable.
//
// Usage:
//   node cli/forge-live-server.mjs --host 1.2.3.4 --port 27015 --password X \
//        --file path/to/MyMod_Server.lua --dest /path/on/server/.../MyMod_Server.lua
//   node cli/forge-live-server.mjs ... --watch      # keep watching and reload on save
//   node cli/forge-live-server.mjs ... --command 'players'   # just run a command
//
// If --dest is an ssh target (user@host:/path) the copy goes through `scp`.
//
// SAFETY: point this at a DEV/LAB server. Reloading server Lua under live players
// is not something this tool can make safe for you.

import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2);
const opt = (n, d = null) => {
  const i = args.indexOf(`--${n}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : d;
};
const has = (n) => args.includes(`--${n}`);

const host = opt("host", "127.0.0.1");
const port = parseInt(opt("port", "27015"), 10);
const password = opt("password") || process.env.PZ_RCON_PASSWORD;
const file = opt("file");
const dest = opt("dest");
const rawCommand = opt("command");

if (!password) {
  console.error("[forge-live-server] missing --password (or PZ_RCON_PASSWORD)");
  process.exit(1);
}

// ---------- Source RCON protocol ----------
const T_AUTH = 3, T_EXEC = 2;
function encode(id, type, body) {
  const b = Buffer.from(body, "utf8");
  const buf = Buffer.alloc(14 + b.length);
  buf.writeInt32LE(10 + b.length, 0);
  buf.writeInt32LE(id, 4);
  buf.writeInt32LE(type, 8);
  b.copy(buf, 12);
  return buf;
}

function rcon(cmd, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection({ host, port });
    let buf = Buffer.alloc(0);
    let authed = false;
    const chunks = [];
    let settle;

    const done = (err, val) => {
      clearTimeout(settle);
      sock.destroy();
      err ? reject(err) : resolve(val);
    };
    settle = setTimeout(() => done(null, chunks.join("").trim()), timeoutMs);

    sock.on("error", (e) => done(e));
    sock.on("connect", () => sock.write(encode(1, T_AUTH, password)));
    sock.on("data", (d) => {
      buf = Buffer.concat([buf, d]);
      // packets can arrive split or coalesced; drain whatever is complete
      while (buf.length >= 4) {
        const len = buf.readInt32LE(0);
        if (buf.length < 4 + len) break;
        const id = buf.readInt32LE(4);
        const body = buf.subarray(12, 4 + len).toString("utf8").replace(/\0+$/, "");
        buf = buf.subarray(4 + len);

        if (!authed) {
          if (id === -1) return done(new Error("RCON auth failed (wrong password?)"));
          authed = true;
          sock.write(encode(2, T_EXEC, cmd));
          // the reply may span several packets; the timer above closes the window
          clearTimeout(settle);
          settle = setTimeout(() => done(null, chunks.join("").trim()), 1500);
        } else if (body) {
          chunks.push(body);
          clearTimeout(settle);
          settle = setTimeout(() => done(null, chunks.join("").trim()), 600);
        }
      }
    });
  });
}

// ---------- syntax gate (same criteria as the client-side CLI) ----------
let luaparse = null;
try { luaparse = (await import("luaparse")).default; } catch { /* optional */ }

function gate(abs) {
  const buf = fs.readFileSync(abs);
  const bad = [];
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf)
    bad.push("UTF-8 BOM (PZ's parser chokes on it)");
  let n = 0;
  for (const b of buf) if (b > 127) n++;
  if (n) bad.push(`${n} non-ASCII byte(s) (accents break Kahlua)`);
  if (luaparse) {
    try { luaparse.parse(buf.toString("utf8"), { luaVersion: "5.1" }); }
    catch (e) { bad.push(`syntax: ${e.message}`); }
  }
  return bad;
}

// ---------- push one file and reload it ----------
async function pushAndReload(abs) {
  const t0 = Date.now();
  const bad = gate(abs);
  if (bad.length) {
    console.log(`  BLOCKED -- the server never sees this file`);
    bad.forEach((b) => console.log(`      - ${b}`));
    return;
  }
  if (dest) {
    if (dest.includes(":")) execFileSync("scp", ["-q", abs, dest], { stdio: "inherit" });
    else { fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.copyFileSync(abs, dest); }
  }
  // PZ's reloadlua takes the FILE NAME, not a full path -- it resolves it itself.
  const name = path.basename(abs);
  const answer = await rcon(`reloadlua "${name}"`);
  console.log(`  ${name}: ${answer || "(no reply)"}  [${Date.now() - t0}ms]`);
}

// ---------- main ----------
if (rawCommand) {
  console.log(await rcon(rawCommand));
  process.exit(0);
}
if (!file) {
  console.error("[forge-live-server] need --file <path.lua> (or --command '<rcon cmd>')");
  process.exit(1);
}

const abs = path.resolve(file);
console.log(`[forge-live-server] ${host}:${port} | syntax gate: ${luaparse ? "ON" : "OFF (npm i luaparse)"}`);
await pushAndReload(abs);

if (has("watch")) {
  console.log(`[forge-live-server] watching ${abs} -- Ctrl+C to stop`);
  let timer = null;
  fs.watch(abs, () => {
    clearTimeout(timer);
    timer = setTimeout(() => pushAndReload(abs).catch((e) => console.error("  " + e.message)), 300);
  });
}

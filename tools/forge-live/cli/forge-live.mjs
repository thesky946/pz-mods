#!/usr/bin/env node
// Validated batches, dependency ordering and one outstanding bridge request.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import lua from "luaparse";
import { snapshot, planReload, serialQueue, batchScheduler, acquireBridgeLock } from "./reload-core.mjs";
import { createStatusStore } from "./status-store.mjs";

const args = process.argv.slice(2);
const flag = name => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configPath = flag("--config") || path.join(repo, "forge-live.config.json");
const onlyMod = flag("--mod");
const onceFile = flag("--once");
const dry = args.includes("--dry");
if (!dry && process.env.PZ_ALLOW_CONTROL !== "1") {
  console.error("[forge-live] Set PZ_ALLOW_CONTROL=1 or use --dry.");
  process.exit(1);
}
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const mods = config.mods.filter(mod => !onlyMod || mod.id === onlyMod);
if (!mods.length) throw new Error("No matching mod.");
const unlock = [];
const statuses = new Map();
let stopReason = "process exit";
process.on("exit", () => {
  for (const status of statuses.values()) status.stop(stopReason);
  for (const release of unlock) release();
});
process.on("SIGINT", () => { stopReason = "SIGINT"; process.exit(0); });
process.on("SIGTERM", () => { stopReason = "SIGTERM"; process.exit(0); });
if (!dry) {
  for (const dir of new Set(mods.map(mod => path.resolve(mod.bridgeDir)))) unlock.push(acquireBridgeLock(dir));
  for (const bridgeDir of new Set(mods.map(mod => path.resolve(mod.bridgeDir)))) {
    const bridgeMods = mods.filter(mod => path.resolve(mod.bridgeDir) === bridgeDir).map(mod => mod.id);
    const configuredConsole = mods.find(mod => path.resolve(mod.bridgeDir) === bridgeDir)?.consolePath ?? config.consolePath;
    const consolePath = configuredConsole || path.resolve(bridgeDir, "..", "..", "console.txt");
    statuses.set(bridgeDir, createStatusStore({ bridgeDir, mods: bridgeMods, consolePath }));
  }
}
console.log("[forge-live] Lua 5.1 syntax gate ON; dependency batches; serialized mailbox.");

const mailboxes = new Map();
function send(bridgeDir, type, payload, timeout = 6000) {
  bridgeDir = path.resolve(bridgeDir);
  if (!mailboxes.has(bridgeDir)) mailboxes.set(bridgeDir, serialQueue());
  return mailboxes.get(bridgeDir)(() => {
    const id = Date.now() + "-" + Math.floor(Math.random() * 1e9);
    fs.mkdirSync(bridgeDir, { recursive: true });
    fs.writeFileSync(path.join(bridgeDir, "cmd.txt"), id + "\t" + type + "\t" + (payload || "") + "\n");
    const start = Date.now();
    return new Promise(resolve => {
      const timer = setInterval(() => {
        try {
          const reply = JSON.parse(fs.readFileSync(path.join(bridgeDir, "result.txt"), "utf8"));
          if (reply.id === id) {
            clearInterval(timer);
            resolve(reply);
            return;
          }
        } catch { /* reply not ready */ }
        if (Date.now() - start >= timeout) {
          clearInterval(timer);
          resolve({ ok: false, value: "timeout: game did not acknowledge the command" });
        }
      }, 120);
    });
  });
}

function inside(root, file) {
  const relative = path.relative(root, file);
  return relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
}

function createRunner(mod, previous) {
  const root = path.resolve(mod.src);
  const status = statuses.get(path.resolve(mod.bridgeDir));
  let blocked = false;
  return async function run(forceFile) {
    const current = snapshot(root, lua.parse);
    let baseline = previous;
    if (forceFile && current.has(forceFile)) {
      baseline = new Map(previous);
      // Keep a new file new, so --once cannot bypass the restart requirement.
      if (baseline.has(forceFile)) baseline.set(forceFile, { ...baseline.get(forceFile), hash: "force-reload" });
    }
    const plan = planReload(baseline, current, mod.modulePrefix || mod.id + "_");
    if (!plan.order.length && !plan.removed.length) return true;
    console.log("[" + mod.id + "] batch: " + plan.order.join(", "));
    if (dry) {
      console.log(plan.restart ? "RESTART REQUIRED: module set changed [dry]" : "Validation OK [dry]");
      previous = current;
      return true;
    }
    status.transition("reloading", {
      batch: {
        at: new Date().toISOString(), mod: mod.id, files: plan.order,
        added: plan.added, removed: plan.removed, result: "staging",
      },
    });
    // Validate ALL sources before copying ANY of them, then copy ALL before reload.
    for (const relative of plan.order) {
      for (const target of mod.targets) {
        const destination = path.join(path.resolve(target), relative);
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.writeFileSync(destination, current.get(relative).bytes);
      }
    }
    previous = current;
    if (plan.restart || blocked) {
      blocked = true;
      const reason = plan.restart ? "module set changed" : "automatic reload already blocked";
      status.transition(plan.restart ? "restart-required" : "blocked", {
        reason,
        batch: { result: plan.restart ? "restart-required" : "blocked" },
      });
      console.error("[" + mod.id + "] RESTART REQUIRED: staged files only; automatic reload paused.");
      if (plan.added.length) console.error("Added: " + plan.added.join(", "));
      if (plan.removed.length) console.error("Removed: " + plan.removed.join(", "));
      console.error("Stop this watcher, restart PZ after syncing with tools/dev.ps1, then start tools/dev.cmd.");
      return false;
    }
    for (const relative of plan.order) {
      // require() caches the resolved absolute path in LuaManager.loadedReturn.
      // Reloading a relative alias leaves that absolute-path cache stale.
      const reloadPath = path.join(path.resolve(mod.targets[0]), relative).split(path.sep).join("/");
      let result;
      try {
        result = await send(mod.bridgeDir, "reload", reloadPath);
      } catch (error) {
        blocked = true;
        status.transition("blocked", {
          reason: "Bridge I/O failed: " + error.message,
          batch: { result: "bridge-error" },
        });
        throw new Error("Bridge I/O failed; restart PZ and watcher: " + error.message);
      }
      if (!result.ok) {
        blocked = true;
        status.transition("blocked", {
          reason: relative + ": " + result.value,
          batch: { result: "reload-rejected" },
        });
        console.error("[" + mod.id + "] FAILED: " + relative + ": " + result.value);
        console.error("Batch stopped; restart PZ and this watcher before continuing.");
        return false;
      }
      status.update({
        reload: { at: new Date().toISOString(), mod: mod.id, file: relative, ok: true, value: result.value },
      });
      // pcall(reloadLuaFile) is an acknowledgement, not proof of correct runtime behavior.
      console.log("[" + mod.id + "] RELOAD ACK: " + relative);
    }
    status.transition("ready", { reason: null, batch: { result: "ok" } });
    return true;
  };
}

if (onceFile) {
  const absolute = path.resolve(onceFile);
  const mod = mods.find(candidate => inside(path.resolve(candidate.src), absolute));
  if (!mod) throw new Error("File is outside configured mod sources.");
  const target = path.resolve(mod.targets[0]);
  const baseline = fs.existsSync(target) ? snapshot(target, lua.parse) : new Map();
  const run = createRunner(mod, baseline);
  const relative = path.relative(path.resolve(mod.src), absolute).split(path.sep).join("/");
  if (!absolute.endsWith(".lua")) throw new Error("--once requires a Lua source.");
  if (!(await run(relative))) process.exitCode = 1;
} else {
  for (const mod of mods) {
    const root = path.resolve(mod.src);
    const run = createRunner(mod, snapshot(root, lua.parse));
    const schedule = batchScheduler(run, error => {
      statuses.get(path.resolve(mod.bridgeDir))?.update({
        batch: { at: new Date().toISOString(), mod: mod.id, result: "validation-error", error: error.message },
      });
      console.error("[" + mod.id + "] BLOCKED: " + error.message + ". Fix sources and save again.");
    });
    console.log("[" + mod.id + "] watching " + root);
    if (!dry) {
      // Queue before watcher requests so startup ping cannot overwrite a reload.
      send(mod.bridgeDir, "ping", "").then(reply => {
        const status = statuses.get(path.resolve(mod.bridgeDir));
        status.transition(reply.ok ? "ready" : "blocked", {
          bridge: { at: new Date().toISOString(), ok: Boolean(reply.ok), value: reply.value },
          ...(reply.ok ? { reason: null } : { reason: "Bridge ping failed: " + reply.value }),
        });
        console.log("[" + mod.id + "] bridge: " + reply.value);
      }).catch(error => {
        statuses.get(path.resolve(mod.bridgeDir))?.transition("blocked", {
          bridge: { at: new Date().toISOString(), ok: false, value: error.message },
          reason: "Bridge ping failed: " + error.message,
        });
        console.error(error.message);
      });
    }
    try {
      fs.watch(root, { recursive: true }, (_event, filename) => {
        if (!filename) { schedule(); return; }
        const file = filename.toString();
        if (/\.(txt|json|png|fbx|anim)$/i.test(file) || /mod\.info$/i.test(file)) {
          statuses.get(path.resolve(mod.bridgeDir))?.transition("restart-required", {
            reason: file + ": non-Lua asset changed",
          });
          console.log("[" + mod.id + "] " + file + ": sync and restart PZ required.");
          return;
        }
        // Deletions and directory renames must also trigger a new snapshot.
        schedule();
      });
    } catch {
      console.log("[" + mod.id + "] recursive watcher unavailable; polling every second.");
      setInterval(schedule, 1000);
    }
  }
}

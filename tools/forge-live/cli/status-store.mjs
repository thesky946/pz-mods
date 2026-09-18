import fs from "node:fs";
import path from "node:path";

const terminalStates = new Set(["blocked", "restart-required"]);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function merge(target, patch) {
  for (const [key, value] of Object.entries(patch)) {
    if (value && typeof value === "object" && !Array.isArray(value) &&
        target[key] && typeof target[key] === "object" && !Array.isArray(target[key])) {
      merge(target[key], value);
    } else {
      target[key] = value;
    }
  }
  return target;
}

export function createStatusStore({ bridgeDir, mods, consolePath, pid = process.pid, now = () => new Date() }) {
  const root = path.resolve(bridgeDir);
  const output = path.join(root, "status.json");
  const temporary = output + "." + pid + ".tmp";
  const timestamp = () => {
    const value = now();
    return (value instanceof Date ? value : new Date(value)).toISOString();
  };
  const consoleOffset = consolePath && fs.existsSync(consolePath) ? fs.statSync(consolePath).size : 0;
  let status = {
    schema: 1,
    state: "starting",
    updatedAt: timestamp(),
    watcher: {
      pid,
      mods: [...mods],
      startedAt: timestamp(),
    },
    console: {
      path: consolePath ? path.resolve(consolePath) : null,
      offset: consoleOffset,
    },
  };

  function persist() {
    fs.mkdirSync(root, { recursive: true });
    fs.writeFileSync(temporary, JSON.stringify(status, null, 2) + "\n", "utf8");
    fs.renameSync(temporary, output);
  }

  function update(patch) {
    merge(status, clone(patch));
    status.updatedAt = timestamp();
    persist();
    return clone(status);
  }

  function transition(state, patch = {}) {
    if (!terminalStates.has(status.state) || state === "stopped") status.state = state;
    return update(patch);
  }

  function stop(reason = "process exit") {
    if (status.state === "stopped") return clone(status);
    status.state = "stopped";
    status.stoppedAt = timestamp();
    return update({ reason });
  }

  persist();
  return { update, transition, stop, snapshot: () => clone(status) };
}

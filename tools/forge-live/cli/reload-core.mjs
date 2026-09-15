import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

// Cross-process ownership, including --once. A second CLI must never touch cmd.txt.
export function acquireBridgeLock(bridgeDir) {
  fs.mkdirSync(bridgeDir, { recursive: true });
  const lock = path.join(bridgeDir, "watcher.lock");
  const token = crypto.randomUUID();
  try {
    const fd = fs.openSync(lock, "wx");
    try { fs.writeFileSync(fd, JSON.stringify({ pid: process.pid, token })); }
    finally { fs.closeSync(fd); }
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    let owner;
    try { owner = JSON.parse(fs.readFileSync(lock, "utf8")); } catch { /* incomplete owner write */ }
    if (owner?.pid) {
      try { process.kill(owner.pid, 0); }
      catch (e) {
        if (e.code === "ESRCH") {
          // Serialize stale recovery too; concurrent recoverers must not remove a new owner.
          const recovery = lock + ".recovery";
          let fd;
          try { fd = fs.openSync(recovery, "wx"); } catch { throw new Error("Bridge lock recovery in progress: " + bridgeDir); }
          try {
            if (fs.readFileSync(lock, "utf8") === JSON.stringify(owner)) {
              fs.unlinkSync(lock);
              return acquireBridgeLock(bridgeDir);
            }
          } finally { fs.closeSync(fd); fs.unlinkSync(recovery); }
        }
      }
    }
    throw new Error("Bridge already owned by watcher PID " + (owner?.pid ?? "initializing") + ": " + bridgeDir);
  }
  return () => {
    try {
      if (JSON.parse(fs.readFileSync(lock, "utf8")).token === token) fs.unlinkSync(lock);
    } catch { /* another owner or already released */ }
  };
}

export function snapshot(root, parse) {
  const files = new Map();
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const absolute = path.join(dir, entry.name);
      if (entry.isDirectory()) { walk(absolute); continue; }
      if (!entry.name.endsWith(".lua")) continue;
      const relative = path.relative(root, absolute).split(path.sep).join("/");
      const bytes = fs.readFileSync(absolute);
      if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
        throw new Error(relative + ": UTF-8 BOM");
      }
      const ast = parse(bytes.toString("utf8"), { luaVersion: "5.1", encodingMode: "x-user-defined" });
      const requires = new Set();
      function visit(node) {
        if (!node || typeof node !== "object") return;
        if (["CallExpression", "StringCallExpression"].includes(node.type)
          && node.base?.type === "Identifier" && node.base.name === "require") {
          const argument = node.arguments?.[0] ?? node.argument;
          if (argument?.type === "StringLiteral") requires.add(argument.value);
        }
        for (const value of Object.values(node)) {
          if (Array.isArray(value)) value.forEach(visit);
          else if (value && typeof value === "object") visit(value);
        }
      }
      visit(ast);
      const moduleName = relative.replace(/^media\/lua\/(client|shared|server)\//, "").replace(/\.lua$/, "");
      files.set(relative, {
        bytes, requires, moduleName,
        hash: crypto.createHash("sha256").update(bytes).digest("hex"),
      });
    }
  }
  walk(root);
  return files;
}

export function planReload(previous, current, modulePrefix) {
  const added = [...current.keys()].filter(file => !previous.has(file));
  const removed = [...previous.keys()].filter(file => !current.has(file));
  const changed = new Set([...current.keys()].filter(file => previous.get(file)?.hash !== current.get(file).hash));
  const modules = new Map();
  for (const [file, record] of current) {
    if (modules.has(record.moduleName)) throw new Error("Ambiguous Lua module: " + record.moduleName);
    modules.set(record.moduleName, file);
  }
  for (const [file, record] of current) {
    for (const name of record.requires) {
      if (modulePrefix && name.startsWith(modulePrefix) && !modules.has(name)) {
        throw new Error(file + ": missing local module " + name);
      }
    }
  }
  const dependencies = new Map([...current].map(([file, record]) => [
    file, [...record.requires].map(name => modules.get(name)).filter(Boolean),
  ]));
  // Reload importers too: they may retain a local reference to a returned table.
  let expanded = true;
  while (expanded) {
    expanded = false;
    for (const [file, deps] of dependencies) {
      if (!changed.has(file) && deps.some(dep => changed.has(dep))) {
        changed.add(file);
        expanded = true;
      }
    }
  }
  const order = [], visiting = new Set(), visited = new Set();
  function visit(file) {
    if (visited.has(file)) return;
    if (visiting.has(file)) throw new Error("Cyclic Lua dependency: " + file);
    visiting.add(file);
    for (const dep of dependencies.get(file)) if (changed.has(dep)) visit(dep);
    visiting.delete(file);
    visited.add(file);
    order.push(file);
  }
  [...changed].sort().forEach(visit);
  return { added, removed, order, restart: added.length > 0 || removed.length > 0 };
}

// One mailbox must have one outstanding request, including ping.
export function serialQueue() {
  let tail = Promise.resolve();
  return task => {
    const result = tail.then(task);
    tail = result.catch(() => {});
    return result;
  };
}

// No filesystem event can start a second operation while a batch is in flight.
export function batchScheduler(run, onError, delay = 500) {
  let timer, running = false, dirty = false;
  async function flush() {
    timer = undefined;
    if (running) return;
    running = true;
    dirty = false;
    try { await run(); } catch (error) { onError(error); }
    finally {
      running = false;
      if (dirty) timer = setTimeout(flush, delay);
    }
  }
  return () => {
    dirty = true;
    if (timer) clearTimeout(timer);
    if (!running) timer = setTimeout(flush, delay);
  };
}

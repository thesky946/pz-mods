import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createStatusStore } from "./status-store.mjs";

function fixture() {
  const bridgeDir = fs.mkdtempSync(path.join(os.tmpdir(), "forge-status-"));
  const consolePath = path.join(bridgeDir, "console.txt");
  fs.writeFileSync(consolePath, "old log\n", "utf8");
  let tick = Date.parse("2026-09-19T10:00:00.000Z");
  const store = createStatusStore({
    bridgeDir,
    mods: ["CookItForMe"],
    consolePath,
    pid: 123,
    now: () => new Date(tick++),
  });
  const read = () => JSON.parse(fs.readFileSync(path.join(bridgeDir, "status.json"), "utf8"));
  return { bridgeDir, store, read };
}

test("records startup metadata and writes atomically", t => {
  const { bridgeDir, store, read } = fixture();
  t.after(() => fs.rmSync(bridgeDir, { recursive: true, force: true }));

  const status = read();
  assert.equal(status.schema, 1);
  assert.equal(status.state, "starting");
  assert.deepEqual(status.watcher.mods, ["CookItForMe"]);
  assert.equal(status.watcher.pid, 123);
  assert.equal(status.console.offset, Buffer.byteLength("old log\n"));
  assert.equal(fs.readdirSync(bridgeDir).some(file => file.endsWith(".tmp")), false);
  assert.deepEqual(store.snapshot(), status);
});

test("transitions preserve fields and terminal states", t => {
  const { bridgeDir, store, read } = fixture();
  t.after(() => fs.rmSync(bridgeDir, { recursive: true, force: true }));

  store.transition("ready", { bridge: { ok: true, value: "pong v0.2.0" } });
  store.update({ batch: { files: ["client/Main.lua"], result: "pending" } });
  assert.equal(read().bridge.value, "pong v0.2.0");
  assert.deepEqual(read().batch.files, ["client/Main.lua"]);

  store.transition("blocked", { reason: "reload rejected" });
  store.transition("reloading", { batch: { files: ["shared/New.lua"] } });
  assert.equal(read().state, "blocked");
  assert.equal(read().reason, "reload rejected");

  store.stop("SIGTERM");
  assert.equal(read().state, "stopped");
  assert.equal(read().reason, "SIGTERM");
  assert.ok(read().stoppedAt);
});

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import lua from "luaparse";
import { spawnSync } from "node:child_process";
import { acquireBridgeLock } from "./reload-core.mjs";
import { snapshot, planReload, serialQueue, batchScheduler } from "./reload-core.mjs";

const record = (moduleName, hash, requires = []) => ({ moduleName, hash, requires: new Set(requires) });
test("bridge lock rejects a second owner and releases cleanly", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "forge-lock-"));
  try {
    const release = acquireBridgeLock(dir);
    assert.throws(() => acquireBridgeLock(dir), /already owned/);
    release();
    const second = acquireBridgeLock(dir);
    release(); // old release cannot remove the new owner's lock
    assert.throws(() => acquireBridgeLock(dir), /already owned/);
    second();
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test("bridge lock recovers an exited process", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "forge-lock-dead-"));
  try {
    const child = spawnSync(process.execPath, ["-e", "process.stdout.write(String(process.pid))"], { encoding: "utf8", windowsHide: true });
    assert.equal(child.status, 0);
    fs.writeFileSync(path.join(dir, "watcher.lock"), JSON.stringify({ pid: Number(child.stdout), token: "dead" }));
    acquireBridgeLock(dir)();
    assert.equal(fs.existsSync(path.join(dir, "watcher.lock")), false);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test("dependencies before consumers, including unchanged consumers", () => {
  const before = new Map([
    ["Cook.lua", record("Cook", "1", ["Planner", "Actions"])],
    ["Planner.lua", record("Planner", "1", ["Food"])],
    ["Actions.lua", record("Actions", "1")],
    ["Food.lua", record("Food", "1")],
  ]);
  const after = new Map(before);
  after.set("Food.lua", record("Food", "2"));
  assert.deepEqual(planReload(before, after).order, ["Food.lua", "Planner.lua", "Cook.lua"]);
  assert.equal(planReload(before, after).restart, false);
  assert.deepEqual(planReload(after, after).order, []);
});

test("new and removed modules require restart; cycles are rejected", () => {
  const before = new Map([["A.lua", record("A", "1")]]);
  const after = new Map([...before, ["B.lua", record("B", "1", ["A"])]]);
  assert.deepEqual(planReload(before, after).added, ["B.lua"]);
  assert.equal(planReload(before, after).restart, true);
  assert.deepEqual(planReload(after, before).removed, ["B.lua"]);
  after.set("A.lua", record("A", "2", ["B"]));
  assert.throws(() => planReload(before, after), /Cyclic/);
});

test("a consumer saved before its new dependency never reaches the game", () => {
  const current = new Map([["A.lua", record("Mod_A", "1", ["Mod_Missing", "ISUI/ISButton"])]]);
  assert.throws(() => planReload(new Map(), current, "Mod_"), /missing local module Mod_Missing/);
});

test("Lua parser recognizes imports, ignores comments, validates whole snapshot", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "forge-reload-test-"));
  try {
    fs.mkdirSync(path.join(dir, "media/lua/shared"), { recursive: true });
    const file = path.join(dir, "media/lua/shared/A.lua");
    fs.writeFileSync(file, '-- require "Fake"\nlocal b = require "B"\nlocal c = require("C")\nreturn {}');
    const data = snapshot(dir, lua.parse).get("media/lua/shared/A.lua");
    assert.equal(data.moduleName, "A");
    assert.deepEqual([...data.requires], ["B", "C"]);
    fs.writeFileSync(file, "local =");
    assert.throws(() => snapshot(dir, lua.parse));
  } finally {
    // Only the exact directory returned by mkdtemp belongs to this test.
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("mailbox never overlaps requests and recovers after rejection", async () => {
  const enqueue = serialQueue(), trace = [];
  const first = enqueue(async () => {
    trace.push("first");
    await new Promise(resolve => setTimeout(resolve, 10));
    trace.push("done");
    throw new Error("failure");
  });
  const second = enqueue(async () => { trace.push("second"); return 2; });
  await assert.rejects(first);
  assert.equal(await second, 2);
  assert.deepEqual(trace, ["first", "done", "second"]);
});

test("events during an active batch produce one later batch", async () => {
  let runs = 0, active = 0, maxActive = 0, finish;
  const completed = new Promise(resolve => { finish = resolve; });
  const schedule = batchScheduler(async () => {
    runs++;
    active++;
    maxActive = Math.max(maxActive, active);
    if (runs === 1) {
      schedule(); schedule();
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    active--;
    if (runs === 2) finish();
  }, error => { throw error; }, 1);
  schedule(); schedule(); schedule();
  await completed;
  assert.equal(runs, 2);
  assert.equal(maxActive, 1);
});

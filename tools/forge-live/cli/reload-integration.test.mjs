import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const cli = fileURLToPath(new URL("./forge-live.mjs", import.meta.url));
function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "forge-integration-"));
  const source = path.join(dir, "source"), target = path.join(dir, "target"), bridge = path.join(dir, "bridge");
  for (const root of [source, target]) fs.mkdirSync(path.join(root, "media/lua/shared"), { recursive: true });
  fs.mkdirSync(bridge);
  const config = path.join(dir, "config.json");
  fs.writeFileSync(config, JSON.stringify({ mods: [{ id: "Mod", src: source, targets: [target], bridgeDir: bridge }] }));
  const write = (root, name, code) => fs.writeFileSync(path.join(root, "media/lua/shared", name + ".lua"), code);
  for (const root of [source, target]) {
    write(root, "Mod_A", "return { version = 1 }");
    write(root, "Mod_B", 'local a = require "Mod_A"; return a');
  }
  return { dir, source, target, bridge, config, write };
}
function launch(f) {
  const process = spawn(globalThis.process.execPath, [
    cli, "--config", f.config, "--once", path.join(f.source, "media/lua/shared/Mod_A.lua"),
  ], { env: { ...globalThis.process.env, PZ_ALLOW_CONTROL: "1" }, windowsHide: true });
  let output = "";
  process.stdout.on("data", chunk => { output += chunk; });
  process.stderr.on("data", chunk => { output += chunk; });
  return new Promise((resolve, reject) => {
    process.on("error", reject);
    process.on("close", code => resolve({ code, output }));
  });
}

function launchTranslations(f, modId = "Mod", config = f.config) {
  const process = spawn(globalThis.process.execPath, [
    cli, "--config", config, "--mod", modId, "--translations",
  ], { env: { ...globalThis.process.env, PZ_ALLOW_CONTROL: "1" }, windowsHide: true });
  let output = "";
  process.stdout.on("data", chunk => { output += chunk; });
  process.stderr.on("data", chunk => { output += chunk; });
  const guard = setTimeout(() => process.kill(), 1000);
  return new Promise((resolve, reject) => {
    process.on("error", reject);
    process.on("close", code => { clearTimeout(guard); resolve({ code, output }); });
  });
}

function startWatcher(f) {
  const child = spawn(globalThis.process.execPath, [
    cli, "--config", f.config, "--mod", "Mod",
  ], { env: { ...globalThis.process.env, PZ_ALLOW_CONTROL: "1" }, windowsHide: true });
  let output = "";
  child.stdout.on("data", chunk => { output += chunk; });
  child.stderr.on("data", chunk => { output += chunk; });
  const commands = [];
  let lastId, readyResolve, readyReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const timer = setInterval(() => {
    const file = path.join(f.bridge, "cmd.txt");
    if (!fs.existsSync(file)) return;
    const [id, kind, payload] = fs.readFileSync(file, "utf8").replace(/\r?\n$/, "").split("\t");
    if (!id || id === lastId) return;
    lastId = id;
    commands.push({ kind, payload });
    fs.writeFileSync(path.join(f.bridge, "result.txt"), JSON.stringify({ id, ok: true, value: kind === "ping" ? "pong test" : "translations reloaded" }));
    if (kind === "ping") readyResolve();
  }, 5);
  const guard = setTimeout(() => readyReject(new Error("watcher did not ping")), 2000);
  const closed = new Promise(resolve => child.on("close", resolve));
  return {
    child,
    commands,
    get output() { return output; },
    ready: ready.finally(() => clearTimeout(guard)),
    stop: async () => { clearInterval(timer); child.kill(); await closed; },
  };
}

test("translations command sends only the allowlisted reload and reports its acknowledgement", async () => {
  for (const ok of [true, false]) {
    const f = fixture();
    let lastId, command, fixtureError;
    const timer = setInterval(() => {
      const file = path.join(f.bridge, "cmd.txt");
      if (!fs.existsSync(file)) return;
      const [id, kind, payload] = fs.readFileSync(file, "utf8").replace(/\r?\n$/, "").split("\t");
      if (!id || id === lastId) return;
      lastId = id;
      try {
        command = { kind, payload };
        assert.equal(kind, "translations");
        assert.equal(payload, "");
      } catch (error) { fixtureError = error; }
      fs.writeFileSync(path.join(f.bridge, "result.txt"), JSON.stringify({ id, ok, value: ok ? "translations reloaded" : "translation reload error" }));
    }, 5);
    try {
      const result = await launchTranslations(f);
      if (fixtureError) throw fixtureError;
      assert.deepEqual(command, { kind: "translations", payload: "" });
      assert.equal(result.code, ok ? 0 : 1, result.output);
      assert.match(result.output, ok ? /translations reloaded/ : /translation reload error/);
    } finally {
      clearInterval(timer);
      fs.rmSync(f.dir, { recursive: true, force: true });
    }
  }
});

test("translations command queues through an already running watcher", async () => {
  const f = fixture();
  const alternateConfig = path.join(f.dir, "alternate-config.json");
  fs.writeFileSync(alternateConfig, JSON.stringify({ mods: [{
    id: "AnotherMod", src: f.source, targets: [f.target], bridgeDir: f.bridge,
  }] }));
  const watcher = startWatcher(f);
  try {
    await watcher.ready;
    const result = await launchTranslations(f, "AnotherMod", alternateConfig);
    assert.equal(result.code, 0, `${result.output}\nwatcher=${watcher.output}\ncommands=${JSON.stringify(watcher.commands)}\nfiles=${fs.readdirSync(f.bridge)}`);
    assert.deepEqual(watcher.commands.map(command => command.kind), ["ping", "translations"]);
    assert.match(result.output, /translations reloaded/);
  } finally {
    await watcher.stop();
    fs.rmSync(f.dir, { recursive: true, force: true });
  }
});

test("CLI stages complete batch before ordered requests; stops on negative ack", async () => {
  for (const fail of [false, true]) {
    const f = fixture(), commands = [];
    let lastId, fixtureError;
    f.write(f.source, "Mod_A", "return { version = 2 }");
    f.write(f.source, "Mod_B", 'local a = require "Mod_A"; return { a, version = 2 }');
    const timer = setInterval(() => {
      const command = path.join(f.bridge, "cmd.txt");
      if (!fs.existsSync(command)) return;
      const [id, kind, payload] = fs.readFileSync(command, "utf8").trim().split("\t");
      if (!id || id === lastId) return;
      lastId = id;
      try {
        assert.equal(kind, "reload");
        for (const name of ["Mod_A", "Mod_B"]) {
          assert.match(fs.readFileSync(path.join(f.target, "media/lua/shared", name + ".lua"), "utf8"), /version = 2/);
        }
        commands.push(payload);
      } catch (error) { fixtureError = error; }
      fs.writeFileSync(path.join(f.bridge, "result.txt"), JSON.stringify({ id, ok: !fail, value: fail ? "test rejection" : "ack" }));
    }, 5);
    try {
      const result = await launch(f);
      if (fixtureError) throw fixtureError;
      assert.equal(result.code, fail ? 1 : 0, result.output);
      const expected = (fail ? ["Mod_A.lua"] : ["Mod_A.lua", "Mod_B.lua"])
        .map(name => path.join(f.target, "media/lua/shared", name).split(path.sep).join("/"));
      assert.deepEqual(commands, expected, "reload must invalidate the absolute-path require cache");
      const status = JSON.parse(fs.readFileSync(path.join(f.bridge, "status.json"), "utf8"));
      assert.equal(status.schema, 1);
      assert.equal(status.state, "stopped");
      assert.equal(status.batch.result, fail ? "reload-rejected" : "ok");
      if (fail) assert.equal(status.reload, undefined);
      else assert.equal(status.reload.file, "media/lua/shared/Mod_B.lua");
    } finally {
      clearInterval(timer);
      fs.rmSync(f.dir, { recursive: true, force: true });
    }
  }
});

test("new module stages without reload; syntax errors stage nothing", async () => {
  for (const invalid of [false, true]) {
    const f = fixture();
    f.write(f.source, "Mod_A", "return { version = 2 }");
    f.write(f.source, "Mod_C", invalid ? "local =" : "return {}");
    try {
      const result = await launch(f);
      assert.equal(result.code, 1);
      assert.equal(fs.existsSync(path.join(f.bridge, "cmd.txt")), false);
      assert.equal(fs.readFileSync(path.join(f.target, "media/lua/shared/Mod_A.lua"), "utf8"), invalid ? "return { version = 1 }" : "return { version = 2 }");
      const status = JSON.parse(fs.readFileSync(path.join(f.bridge, "status.json"), "utf8"));
      assert.equal(status.state, "stopped");
      if (!invalid) {
        assert.match(result.output, /RESTART REQUIRED/);
        assert.equal(status.batch.result, "restart-required");
      }
    } finally {
      fs.rmSync(f.dir, { recursive: true, force: true });
    }
  }
});

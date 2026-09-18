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

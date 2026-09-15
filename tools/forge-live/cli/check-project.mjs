import fs from "node:fs";
import path from "node:path";
import lua from "luaparse";
import { snapshot, planReload } from "./reload-core.mjs";
const root = path.resolve(process.argv[2]);
const files = snapshot(path.join(root, "42"), lua.parse);
planReload(files, files, "CookItForMe_");
snapshot(path.join(root, "tests"), lua.parse);
const translate = path.join(root, "common/media/lua/shared/Translate");
for (const category of ["UI", "Sandbox"]) {
  const reference = JSON.parse(fs.readFileSync(path.join(translate, "EN", category + ".json"), "utf8"));
  for (const lang of fs.readdirSync(translate)) {
    const data = JSON.parse(fs.readFileSync(path.join(translate, lang, category + ".json"), "utf8"));
    if (JSON.stringify(Object.keys(data).sort()) !== JSON.stringify(Object.keys(reference).sort())) throw new Error("Translation keys differ: " + lang);
    for (const [key, value] of Object.entries(data)) {
      if (typeof value !== "string" || !value.trim() || /\?{3,}/.test(value)) throw new Error("Invalid translation: " + lang + "/" + key);
      if (JSON.stringify((value.match(/%\d+/g) || []).sort()) !== JSON.stringify((reference[key].match(/%\d+/g) || []).sort())) throw new Error("Translation placeholders differ: " + lang + "/" + key);
    }
  }
}
console.log("Lua 5.1 syntax, dependencies and translations OK");

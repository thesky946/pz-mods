# pz-mods

Общая инфраструктура находится в `tools/`; каждый мод — в `mods/<slug>/`.

Перед синхронизацией или публикацией выполнять:

```powershell
.\tools\check.ps1 -Mod <slug>
```

`42/`, `common/`, `tests/`, `workshop/`, `mod-manifest.json` и документация принадлежат конкретному моду и не должны быть общими.

Для `cook-it-for-me` см. [`mods/cook-it-for-me/CODEX.md`](mods/cook-it-for-me/CODEX.md) и [`mods/cook-it-for-me/DEVELOPMENT.md`](mods/cook-it-for-me/DEVELOPMENT.md).

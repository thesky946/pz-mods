# pz-mods

Монорепозиторий модов для Project Zomboid.

```text
mods/
  cook-it-for-me/      один самостоятельный мод: исходники, тесты, Workshop-метаданные и документация
tools/                 общая инфраструктура: проверки, staging, Workshop-сборка, публикация, Forge Live
```

Для существующего мода:

```powershell
.\tools\check.ps1 -Mod cook-it-for-me
.\tools\watch.cmd cook-it-for-me
.\tools\build_workshop.ps1 -Mod cook-it-for-me
.\tools\publish_workshop.ps1 -Mod cook-it-for-me
```

Новый мод добавляется в `mods/<slug>/` и содержит `42/mod.info`; для Workshop-команд также нужен `mod-manifest.json` рядом с ним.

Создать заготовку:

```powershell
.\tools\new-mod.ps1 -Slug my-mod -Id MyMod -Name 'My Mod'
```

Запуск hot reload двойным кликом: `tools\watch.cmd` предложит выбрать мод. Выбор можно передать сразу: `tools\watch.cmd my-mod`.

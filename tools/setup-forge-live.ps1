# Installs the local-only Forge Live bridge and watcher used by tools\dev.cmd.
# Nothing from this script is included in the Workshop upload.

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ForgeRoot = Join-Path $PSScriptRoot 'forge-live'
$BridgeTarget = Join-Path $env:USERPROFILE 'Zomboid\mods\ForgeLiveBridge'
$WorkshopTarget = Join-Path $env:USERPROFILE 'Zomboid\Workshop\CookItForMe\Contents\mods\CookItForMe\42'
$BridgeDir = Join-Path $env:USERPROFILE 'Zomboid\Lua\forgelive'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required for Forge Live.' }
if (-not (Test-Path -LiteralPath $ForgeRoot)) {
    & git clone --depth 1 https://github.com/Twynzen/pz-forge-live.git $ForgeRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone pz-forge-live.' }
}

$cli = Join-Path $ForgeRoot 'cli\forge-live.mjs'
if (-not (Test-Path -LiteralPath $cli)) { throw "Forge Live CLI missing: $cli" }

# Forge Live rejects all non-ASCII Lua, but this mod has UTF-8 Russian comments.
$cliText = [IO.File]::ReadAllText($cli)
$asciiGate = @'
  let n = 0;
  for (const b of buf) if (b > 127) n++;
  if (n) bad.push(`${n} byte(s) no-ASCII (tildes/enie rompen Kahlua)`);
'@
$asciiGate = $asciiGate.Replace("`r`n", "`n") + "`n"
if ($cliText.Contains($asciiGate)) {
    $cliText = $cliText.Replace($asciiGate, '')
    [IO.File]::WriteAllText($cli, $cliText, [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath (Join-Path $ForgeRoot 'node_modules\luaparse'))) {
    Push-Location $ForgeRoot
    try {
        & npm install luaparse
        if ($LASTEXITCODE -ne 0) { throw 'Could not install luaparse.' }
    } finally { Pop-Location }
}

$bridgeSource = Join-Path $ForgeRoot 'mod\ForgeLiveBridge'
if (-not (Test-Path -LiteralPath $bridgeSource)) { throw "Forge Live bridge missing: $bridgeSource" }
New-Item -ItemType Directory -Path $BridgeTarget -Force | Out-Null
Get-ChildItem -LiteralPath $bridgeSource -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $BridgeTarget -Recurse -Force
}

$json = @{
    mods = @(@{
        id = 'CookItForMe'
        # Watch only the Build 42 source tree. Watching the repository root also
        # receives transient .git object events while commits are being written.
        src = (Join-Path $ProjectRoot '42').Replace('\', '/')
        targets = @($WorkshopTarget.Replace('\', '/'))
        bridgeDir = $BridgeDir.Replace('\', '/')
        reloadFrom = 'target'
    })
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $ForgeRoot 'forge-live.config.json'), $json, [Text.UTF8Encoding]::new($false))

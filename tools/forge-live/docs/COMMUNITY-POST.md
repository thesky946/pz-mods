# Posts para la comunidad / Community posts

Dos versiones del mismo mensaje, listas para copiar. Tono: humilde, concreto, pidiendo
feedback. Al final hay una variante corta para Discord (límite 2000 caracteres).

---
---

# 🇬🇧 ENGLISH — for the PZ modding Discord / theindiestone forums / r/projectzomboid

**Title:** We measured a few things about hot-reloading Lua in B42 (42.20) and some of it
surprised us — sharing the tool + asking for corrections

---

Hi everyone. We run a small RP server (Dystopia RP) with a custom NPC mod, and the part
that was killing us was multiplayer testing: edit → zip → upload → restart → everyone logs
back in. Eight minutes to see a one-line change, several times a day.

So we spent a while poking at `reloadLuaFile()` and the `reloadlua` server command, wrapped
a dev loop around them, and wrote down everything we measured — including the parts where
we turned out to be wrong.

**Repo:** https://github.com/Twynzen/pz-forge-live (MIT)

## First: we are not first

[**PZModReload**](https://github.com/deckard93/PZModReload) by deckard93 and
[**pz_lua_hmr**](https://github.com/escapepz/pz_lua_hmr) by escapepz both did automatic
hot-reload before us. deckard93 also documented the "your event handlers duplicate on
reload" pattern before we wrote ours. If you just want reloading and nothing else, go look
at theirs first — they may suit you better.

## What we measured on 42.20 (not assumed — observed in a log)

| | |
|---|---|
| `reloadLuaFile()` re-executes a file | ✅ relative **and** absolute paths |
| ...including files that did **not** exist at boot | ✅ |
| Server `reloadlua "<file>"` **over RCON**, no restart | ✅ |
| Edit → reload → see it **while connected to a dedicated server** | ✅ |
| `DoLuaChecksum` checks at **login**, not continuously | ✅ |

Client loop measured at ~150 ms from save to applied.

## Three things that cost us a night, so they don't cost you one

**1. `getFileWriter` returns `nil` for `.json` files on 42.20.** No error. No log line. It
just doesn't write. If you maintain any file-based bridge that answers in `.json`, it is
dying silently right now. Use `.txt`.

**2. Connecting to a server drops your dev mods.** PZ rebuilds the Lua state from the
**server's** mod list. Anything you have that the server doesn't list is silently discarded
for that session — the connection is still accepted, you just don't get your mod. We spent
hours convinced our bridge was broken. It wasn't there.

**3. `DoLuaChecksum=true` is not the wall it looks like.** It checks when your client
*connects*, not continuously. We changed a mod's client `.lua` mid-session and stayed
connected for minutes with no complaint. Reconnect out of sync and you *do* get
`user X will be kicked in 8000ms because Lua/script checksums do not match` — but during a
session you can iterate freely.

## Where we were wrong, publicly

Our own README used to say "reloading duplicates your event handlers". We built a test that
couldn't be fooled — each reload counting into its own slot — and got:

```
reloads=3   handlers ALIVE=0    (g1=0 g2=0 g3=0)
control handler registered from the in-game console: n=623
```

So on 42.20, `reloadLuaFile` seems **not to re-register events at all**. Good news: no
duplication. Bad news: **it doesn't install new handlers either** — if your edit adds an
`Events.X.Add`, expect it to need a restart.

We don't know the mechanism, and we only tested this in a multiplayer session.
PZModReload, which reloads via `loadstring` instead, *does* report duplication — so the two
approaches may simply behave differently and we may both be right about our own.

**If you can reproduce or contradict any of this, please do.** A log excerpt is worth more
than an opinion, and being corrected in public beats confidently misinforming people.

## What the tool adds on top of the reload itself

Honestly, the reload call isn't the hard part — the engine has had it for ages. What we
built around it:

- **A validation gate before the file reaches the game** — UTF-8 BOM, non-ASCII bytes, Lua
  5.1 parse. A broken file never gets synced. In PZ a bad `.lua` can take down your whole
  Lua state, so catching it in ~5 seconds instead of after a 3-minute restart is the part
  we care about most. We couldn't find another tool that does this.
- **The game's real answer, printed back in the terminal you saved from.**
- **A dedicated-server path over RCON** — no admin needs to be logged in to type a chat
  command, so it's scriptable. We couldn't find anything doing this either.

## Status: alpha, and honest about it

Verified on 42.20 only. `docs/KNOWN-LIMITS.md` splits proven from unproven and does not
blur the line. Things it can't do (`.txt` scripts, `mod.info`, new models are all read once
at boot) are listed rather than pretended away — the CLI tells you "requires a restart"
instead of reporting a success that didn't happen.

If it saves you a restart, great. If you find we got something wrong, that's genuinely more
useful to us — issues welcome.

---
---

# 🇪🇸 ESPAÑOL — para Discord de modding de PZ / foros / r/projectzomboid

**Título:** Medimos algunas cosas sobre hot-reload de Lua en B42 (42.20) y varias nos
sorprendieron — comparto la herramienta y pido correcciones

---

Hola a todos. Llevamos un servidor de rol chico (Dystopia RP) con un mod de NPCs propio, y
lo que nos estaba matando era testear en multijugador: editar → zip → subir → reiniciar →
que todos vuelvan a entrar. Ocho minutos para ver un cambio de una línea, varias veces
por día.

Así que estuvimos un buen rato hurgando en `reloadLuaFile()` y en el comando de servidor
`reloadlua`, armamos un ciclo de desarrollo alrededor, y anotamos todo lo que medimos —
incluidas las partes donde resultamos estar equivocados.

**Repo:** https://github.com/Twynzen/pz-forge-live (MIT)

## Primero: no somos los primeros

[**PZModReload**](https://github.com/deckard93/PZModReload) de deckard93 y
[**pz_lua_hmr**](https://github.com/escapepz/pz_lua_hmr) de escapepz ya hacían hot-reload
automático antes que nosotros. deckard93 además documentó antes que nosotros el patrón de
"al recargar se te duplican los handlers de eventos". Si solo querés recargar y nada más,
mirá los de ellos primero — puede que te sirvan mejor.

## Lo que medimos en 42.20 (no supuesto — observado en un log)

| | |
|---|---|
| `reloadLuaFile()` re-ejecuta un archivo | ✅ con ruta relativa **y** absoluta |
| ...incluso archivos que **no existían** al arrancar | ✅ |
| `reloadlua "<archivo>"` en servidor **por RCON**, sin reiniciar | ✅ |
| Editar → recargar → verlo **estando conectado a un servidor** | ✅ |
| `DoLuaChecksum` verifica al **entrar**, no en continuo | ✅ |

El ciclo en cliente da ~150 ms desde que guardás hasta que se aplica.

## Tres cosas que nos costaron una noche, para que no te cuesten una a vos

**1. `getFileWriter` devuelve `nil` con archivos `.json` en 42.20.** Sin error. Sin línea
en el log. Simplemente no escribe. Si mantenés algún puente por archivos que responde en
`.json`, está muriendo en silencio ahora mismo. Usá `.txt`.

**2. Conectarte a un servidor descarta tus mods de desarrollo.** PZ reconstruye el estado
Lua con la lista de mods **del servidor**. Todo lo que vos tengas y él no liste se descarta
en silencio en esa sesión — la conexión igual se acepta, simplemente no tenés tu mod.
Perdimos horas convencidos de que nuestro puente estaba roto. No estaba: no existía.

**3. `DoLuaChecksum=true` no es el muro que parece.** Verifica cuando tu cliente *entra*,
no en continuo. Cambiamos el `.lua` de cliente de un mod a mitad de sesión y seguimos
conectados varios minutos sin una queja. Si te reconectás desincronizado sí te echa —
`user X will be kicked in 8000ms because Lua/script checksums do not match` — pero durante
la sesión podés iterar libremente.

## Dónde nos equivocamos, en público

Nuestro propio README decía "recargar duplica tus handlers de eventos". Armamos un test que
no se podía engañar —cada recarga contando en su propio casillero— y salió esto:

```
recargas=3   handlers VIVOS=0    (g1=0 g2=0 g3=0)
handler de control registrado desde la consola del juego: n=623
```

O sea que en 42.20 `reloadLuaFile` parece **no re-registrar eventos en absoluto**. La buena:
no duplica. La mala: **tampoco instala handlers nuevos** — si tu edición agrega un
`Events.X.Add`, contá con que va a necesitar reiniciar.

No sabemos el mecanismo, y esto lo probamos solo en una sesión de multijugador.
PZModReload, que recarga con `loadstring` en vez de `reloadLuaFile`, *sí* reporta
duplicación — así que puede que los dos enfoques simplemente se comporten distinto y que
ambos tengamos razón sobre el nuestro.

**Si podés reproducir o contradecir cualquiera de estos puntos, hacelo.** Un fragmento de
log vale más que una opinión, y que te corrijan en público es mejor que desinformar a la
gente con seguridad.

## Qué agrega la herramienta por encima del reload en sí

Con honestidad: la llamada de recarga no es la parte difícil, el motor la tiene hace años.
Lo que construimos alrededor:

- **Un filtro de validación antes de que el archivo llegue al juego** — BOM UTF-8, bytes
  no-ASCII, parseo Lua 5.1. Un archivo roto nunca se sincroniza. En PZ un `.lua` malo te
  puede tumbar el estado Lua entero, así que atraparlo en ~5 segundos en vez de después de
  un reinicio de 3 minutos es la parte que más nos importa. No encontramos otra herramienta
  que lo haga.
- **La respuesta real del juego, impresa en la misma terminal donde guardaste.**
- **Un camino para servidor dedicado por RCON** — ningún admin necesita estar logueado para
  tipear un comando en el chat, así que es automatizable. Tampoco encontramos nada que
  hiciera esto.

## Estado: alpha, y lo decimos

Verificado solo en 42.20. El archivo `docs/KNOWN-LIMITS.md` separa lo probado de lo no
probado y no difumina la línea. Lo que no puede hacer (los scripts `.txt`, `mod.info` y los
modelos nuevos se leen una sola vez al arrancar) está listado en vez de disimulado — el CLI
te dice "requiere reiniciar" en lugar de reportar un éxito que no pasó.

Si te ahorra un reinicio, buenísimo. Si encontrás que nos equivocamos en algo, eso nos
sirve todavía más — los issues son bienvenidos.

---
---

# 📱 VERSIÓN CORTA (Discord, < 2000 caracteres)

**ES:**

> Hola 👋 Llevamos un server de rol chico y lo que nos mataba era testear mods en MP:
> editar → zip → subir → reiniciar → que todos vuelvan a entrar. 8 minutos por cada cambio
> de una línea.
>
> Armamos un ciclo de hot-reload alrededor de `reloadLuaFile()` y del comando `reloadlua`
> del servidor, y documentamos todo lo que medimos en 42.20:
> **https://github.com/Twynzen/pz-forge-live** (MIT, alpha)
>
> No somos los primeros — PZModReload (deckard93) y pz_lua_hmr (escapepz) ya lo hacían, y
> están acreditados en el repo.
>
> Tres cosas que quizás te sirvan aunque no uses la herramienta:
> • `getFileWriter` devuelve **nil** con archivos `.json` en 42.20. Sin error, sin log. Si
> tenés un puente por archivos que responde en `.json`, está muerto en silencio. Usá `.txt`.
> • Al conectarte a un server, PZ **descarta** los mods que el server no lista. La conexión
> se acepta igual, pero tu mod de desarrollo no está. Perdimos horas con esto.
> • `DoLuaChecksum=true` verifica **al entrar**, no en continuo → podés editar durante la
> sesión sin que te echen.
>
> Y donde nos equivocamos: creíamos que recargar duplicaba los handlers de eventos. Lo
> medimos y **no los duplica… pero tampoco instala handlers nuevos**. Corregimos el README.
>
> Si podés reproducir o contradecir algo de esto, por favor decilo 🙏

**EN:**

> Hi 👋 We run a small RP server and MP mod testing was killing us: edit → zip → upload →
> restart → everyone logs back in. 8 minutes per one-line change.
>
> We built a hot-reload loop around `reloadLuaFile()` and the server's `reloadlua` command,
> and wrote down everything we measured on 42.20:
> **https://github.com/Twynzen/pz-forge-live** (MIT, alpha)
>
> We're not first — PZModReload (deckard93) and pz_lua_hmr (escapepz) got there before us,
> both credited in the repo.
>
> Three things that might help you even if you never use the tool:
> • `getFileWriter` returns **nil** for `.json` files on 42.20. No error, no log. If you
> have a file bridge answering in `.json`, it's dying silently. Use `.txt`.
> • Connecting to a server makes PZ **drop** mods the server doesn't list. The connection is
> still accepted, you just don't have your dev mod. This cost us hours.
> • `DoLuaChecksum=true` checks **at login**, not continuously → you can edit mid-session
> without getting kicked.
>
> And where we were wrong: we thought reloading duplicated event handlers. We measured it —
> it **doesn't duplicate… but it doesn't install new handlers either**. README corrected.
>
> If you can reproduce or contradict any of this, please do 🙏

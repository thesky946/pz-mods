-- ForgeHandlerTest.lua -- mide si recargar DUPLICA handlers. Version honesta.
--
-- El intento anterior fallo por una razon tonta: el contador vivia en una tabla
-- global compartida, asi que no se podia distinguir "un handler contando 60
-- veces" de "tres handlers contando 20 cada uno". Ahora cada generacion cuenta
-- en SU PROPIO casillero, y al final se listan todos los que siguen vivos.
-- Si tras N recargas hay N casilleros sumando, se duplicaron. Si hay 1, no.

FHT = FHT or { gen = 0, hits = {} }   -- hits[gen] = cuantas veces conto ESA generacion
FHT.gen = FHT.gen + 1
local miGen = FHT.gen
FHT.hits[miGen] = 0

local function contar()
    FHT.hits[miGen] = (FHT.hits[miGen] or 0) + 1
end

-- Dos modos, elegidos por una global que se setea ANTES de recargar:
--   FHT_USE_DYSLIVE = true  -> registra via DysLive (deberia quedar 1 vivo)
--   FHT_USE_DYSLIVE = false -> registra a pelo    (deberian quedar N vivos)
if FHT_USE_DYSLIVE and DysLive and DysLive.on then
    DysLive.on(Events.OnRenderTick, "fht_counter", contar)
    print("[FHT] gen=" .. miGen .. " registrado VIA DysLive")
else
    Events.OnRenderTick.Add(contar)
    print("[FHT] gen=" .. miGen .. " registrado A PELO")
end

-- Informe: cuantas generaciones siguen contando de verdad.
function FHT.report()
    local vivos, detalle = 0, {}
    for g = 1, FHT.gen do
        local n = FHT.hits[g] or 0
        FHT.hits[g] = 0                       -- reset para medir de nuevo
        if n > 0 then vivos = vivos + 1 end
        table.insert(detalle, "g" .. g .. "=" .. n)
    end
    print("[FHT] RESULTADO -> recargas=" .. FHT.gen .. " handlers VIVOS=" .. vivos ..
          "  detalle: " .. table.concat(detalle, " "))
    print("[FHT] (vivos=1 -> no se duplica | vivos=" .. FHT.gen .. " -> se duplica)")
end

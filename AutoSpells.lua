-- ClaudeMaster: kouzla, ktera rotace nezna (nove ranky / levely / talenty).
-- Pri nauceni se precte popis kouzla a podle klicovych slov se zaradi:
--   attack  = poskozeni (s cooldownem -> na cooldown, bez nej -> jen kdyz rotace ceka)
--   aoe     = plosne poskozeni (2+ moby)
--   heal    = leceni (sebe / umirajiciho spoluhrace, kdyz neni lecitel)
--   buff    = dlouhy buff (drzet mimo boj)
--   stop    = preruseni / stun (na kouzlici moby)
--   defense = stit / mene damage (pri malo HP)
--   ignore  = neumim pouzit (teleport, forma, vyvolani...)
-- Vysledek se ulozi do ClaudeMasterDB.autoSpells a jednou se oznami do chatu.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool
local E = ns.Engine

local AS = {}
ns.AutoSpells = AS
AS.list = {}   -- jmena auto kouzel, ktera prave mam ve spellbooku

local LABEL = {
  attack = 'utok', aoe = 'plosny utok (2+ moby)', heal = 'leceni', buff = 'buff (drzim ho mimo boj)',
  stop = 'preruseni / stun', defense = 'obrana pri malo HP', ignore = 'nepouzivam (neznam ucel)',
}

local function lower(s) return type(s) == 'string' and s:lower() or '' end
local function has(d, ...)
  for _, w in ipairs({ ... }) do if d:find(w, 1, true) then return true end end
  return false
end

-- trvani v popisu ("for 30 min", "lasts 1 hour") v sekundach
local function longest(d)
  local best = 0
  for n, u in d:gmatch('(%d+%.?%d*)%s*(%a+)') do
    local v = tonumber(n) or 0
    if u == 'min' or u == 'mins' or u == 'minute' or u == 'minutes' then v = v * 60
    elseif u == 'hour' or u == 'hours' or u == 'hr' or u == 'hrs' then v = v * 3600
    elseif u == 'sec' or u == 'secs' or u == 'second' or u == 'seconds' then v = v
    else v = 0 end
    if v > best then best = v end
  end
  return best
end

function AS.classify(desc)
  local d = lower(desc)
  if d == '' then return nil end
  if has(d, 'teleport', 'portal', 'summon', 'resurrect', 'return to life', 'returns the spirit', 'shapeshift',
    'transforms the caster', 'track ', 'tracking', 'conjure', 'creates a', 'hearth', 'taunt',
    'polymorph', 'banish', 'fishing', 'disenchant', 'detect', 'soulstone') then
    return 'ignore'
  end
  local dmg = has(d, 'damage') and not has(d, 'damage taken', 'reduces damage', 'reducing damage', 'absorbs',
    'absorbing', 'damage done to', 'prevents all damage')
  local enemy = has(d, 'enemy', 'enemies', 'target', 'nearby')
  if has(d, 'interrupt', 'stuns ', 'stunning', 'stun the', 'stuns the', 'silence', 'incapacitat', 'knock') then return 'stop' end
  if dmg and enemy then
    if has(d, 'all enemies', 'nearby enemies', 'enemies within', 'enemies in', 'up to ', 'surrounding') then return 'aoe' end
    return 'attack'
  end
  if longest(d) >= 300 and has(d, 'increas', 'grant', 'improv', 'bonus', 'chance', 'armor', 'resistance', 'stamina',
    'intellect', 'spirit', 'strength', 'agility', 'attack power', 'regenerat') then
    return 'buff'
  end
  if longest(d) >= 300 then return 'buff' end   -- dlouhe trvani bez poskozeni = buff
  if has(d, 'heals ', 'heal ', 'healing', 'restores', 'restoring') and not dmg then return 'heal' end
  if has(d, 'absorb', 'damage taken', 'reduces damage', 'reducing damage', 'immune', 'invulnerab', 'prevents all damage') then
    return 'defense'
  end
  return 'ignore'
end

local function describe(id)
  local d = C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
  if (type(d) ~= 'string' or d == '') and GetSpellDescription then d = safe(pc(GetSpellDescription, id)) end
  if type(d) ~= 'string' or d == '' then
    if C_Spell and C_Spell.RequestLoadSpellData then pc(C_Spell.RequestLoadSpellData, id) end
    return nil
  end
  return d
end

-- zakladni cooldown: API, jinak radek "X sec cooldown" v tooltipu
local function baseCd(id)
  if GetSpellBaseCooldown then
    local ms = safeNum(pc(GetSpellBaseCooldown, id))
    if ms and ms > 0 then return ms / 1000 end
  end
  local td = C_TooltipInfo and C_TooltipInfo.GetSpellByID and pc(C_TooltipInfo.GetSpellByID, id)
  if type(td) == 'table' and type(td.lines) == 'table' then
    for _, l in ipairs(td.lines) do
      for _, txt in ipairs({ safe(l.leftText), safe(l.rightText) }) do
        if type(txt) == 'string' then
          local n, u = txt:match('(%d+%.?%d*)%s*(%a+) [Cc]ooldown')
          if n then return (tonumber(n) or 0) * ((u == 'min' or u == 'minutes') and 60 or 1) end
        end
      end
    end
  end
  return 0
end

local retried = false
-- volano ze ns.scanSpells (Core.lua) se seznamem spellbooku: name -> id
function AS.scan(book)
  local db = ns.db
  if not db then return end
  db.autoSpells = db.autoSpells or {}
  local known, inList = {}, {}   -- known = kouzla rotace (bez drive pridanych auto kouzel)
  AS.base = AS.base or #ns.SPELLS   -- kolik kouzel ma rotace sama (auto se pridavaji za ne)
  for i, n in ipairs(ns.SPELLS) do
    inList[n] = true
    if i <= AS.base then known[n] = true end
  end
  local pending, list = false, {}
  for name, id in pairs(book) do
    local base = name:match('^(.-) %(') or name
    local line = ns.bookLine and ns.bookLine[name]
    if line and not known[name] and not known[base] then
      local rec = db.autoSpells[name]
      if not rec or rec.id ~= id then
        local d = describe(id)
        local kind = d and AS.classify(d)
        if kind then
          local isNew = rec == nil
          rec = { kind = (rec and rec.manual) and rec.kind or kind, manual = rec and rec.manual, id = id, cd = baseCd(id) }
          db.autoSpells[name] = rec
          if isNew then
            ns.say(('Novy spell |cffffd200%s|r: %s'):format(name, LABEL[rec.kind] or rec.kind))
          end
        else
          pending = true
        end
      end
      if rec and rec.kind ~= 'ignore' then
        list[#list + 1] = name
        if rec.cd and rec.cd > 1.5 and not ns.BASE_CD[name] then ns.BASE_CD[name] = rec.cd end
      end
    end
  end
  table.sort(list)
  AS.list = list
  -- pridat do ns.SPELLS, at je Core sleduje (id, ikona, cena, cooldown, klavesa)
  for _, n in ipairs(list) do
    if not inList[n] then ns.SPELLS[#ns.SPELLS + 1] = n inList[n] = true end
  end
  -- popis jeste neni nacteny: zkusit znovu za chvili
  if pending and not retried and C_Timer then
    retried = true
    C_Timer.After(4, function() retried = false if ns.scanSpells then pcall(ns.scanSpells) end end)
  end
end

-- buffy hrace mimo boj (podle indexu)
local function myBuffs()
  if ns.inCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local t = {}
  for i = 1, 60 do
    local a = pc(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HELPFUL')
    if type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) == 'string' then t[n] = true end
  end
  return t
end

local function usable(n, c)
  if not ns.known(n) then return false end
  local id = ns.id(n)
  if ns.cdLeft(n) > (c.gcd or 0) + (c.lead or 0) + 0.1 then return false end
  if ns.cost(n) > 0 and c.manaKnown and (c.mana or 1) * ns.manaMax() < ns.cost(n) then return false end
  if id and C_Spell and C_Spell.IsSpellUsable then
    local ok = safeBool(pc(C_Spell.IsSpellUsable, id))
    if ok == false then return false end
  end
  return true
end
local function inRange(n, unit)
  local id = ns.id(n)
  if not id or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
  return safeBool(pc(C_Spell.IsSpellInRange, id, unit or 'target'))
end

-- jedna akce z auto kouzel (nebo nil)
function AS.pick(c, first)
  local db = ns.db
  if not db or not db.autoSpells or #AS.list == 0 or db.autoOff then return nil end
  local php = c.php or 100
  local healerUp = false
  for _, m in ipairs((c.party and c.party.members) or {}) do
    if m.healer and m.alive and not m.unit:find('pet') then healerUp = true end
  end
  local danger = c.aggro or ((c.enemies and c.enemies.onMe) or 0) > 0
  local aoe = (c.enemies and (c.enemies.cluster or c.enemies.combat)) or 0
  local idle = not first or first.kind == 'wait'
  local urgentFirst = first and first.urgent
  local buffs

  for _, n in ipairs(AS.list) do
    local rec = db.autoSpells[n]
    local k = rec and rec.kind
    if k and usable(n, c) then
      if not c.inCombat then
        if k == 'buff' and idle and not c.hostile and not c.resting then
          buffs = buffs or myBuffs()
          if buffs and not buffs[n] then
            return { name = n, reason = 'Chybi buff: ' .. n, kind = 'spell', unit = 'player', auto = true }
          end
        end
      else
        if k == 'stop' and c.hostile and c.tCasting and c.interruptible and inRange(n) ~= false and not urgentFirst then
          return { name = n, reason = 'Mob kouzli: ' .. n .. ' (preruseni)', kind = 'spell', urgent = true, auto = true }
        end
        if k == 'defense' and danger and php < 35 and not urgentFirst then
          return { name = n, reason = 'Malo HP: ' .. n, kind = 'spell', urgent = true, auto = true }
        end
        if k == 'heal' and not healerUp and not urgentFirst then
          if php < 40 then
            return { name = n, reason = ('HP ~%d%%: %s'):format(math.floor(php), n), kind = 'spell', unit = 'player',
              urgent = php < 25, auto = true }
          end
          for _, m in ipairs((c.party and c.party.members) or {}) do
            if m.alive and m.veryLow and not m.unit:find('pet') and inRange(n, m.unit) ~= false then
              return { name = n, reason = ('%s umira: %s'):format(m.name or '?', n), kind = 'spell', unit = m.unit,
                urgent = true, auto = true }
            end
          end
        end
        if (k == 'attack' or (k == 'aoe' and aoe >= 2)) and c.hostile and inRange(n) ~= false and not urgentFirst then
          -- s cooldownem: na cooldown; bez cooldownu jen do mezery, kdy rotace ceka
          local cd = ns.cdFor(n)
          if cd >= 4 or idle then
            return { name = n, reason = (k == 'aoe' and ('%d moby: '):format(aoe) or '') .. n .. (cd >= 4 and ' (na cooldown)' or ''),
              kind = 'spell', auto = true }
          end
        end
      end
    end
  end
  return nil
end

-- obal E.plan (tento soubor se nacita po class modulech)
local basePlan = E.plan
if basePlan then
  E.plan = function(c, ...)
    local plan, util = basePlan(c, ...)
    plan = plan or {}
    local ok, a = pcall(AS.pick, c, plan[1])
    if ok and a then
      local first = plan[1]
      if first then
        a.at, a.wait = first.at, first.wait
        if first.kind == 'wait' then plan[1] = a
        else table.insert(plan, 1, a) end
        while #plan > 3 do table.remove(plan) end
      else
        a.at, a.wait = 0, c.gcd or 0
        plan[1] = a
      end
    end
    return plan, util
  end
end

-- /cm auto: seznam;  /cm auto <jmeno> <druh>: rucni zmena;  /cm auto off|on
function AS.cmd(arg)
  local db = ns.db
  db.autoSpells = db.autoSpells or {}
  arg = arg or ''
  if arg == 'off' then db.autoOff = true ns.say('Auto kouzla vypnuta') return end
  if arg == 'on' then db.autoOff = nil ns.say('Auto kouzla zapnuta') return end
  local name, kind = arg:match('^(.-)%s+(%a+)$')
  if name then   -- prikaz je malymi pismeny: najit jmeno bez ohledu na velikost
    for nm in pairs(db.autoSpells) do if nm:lower() == name:lower() then name = nm end end
  end
  if name and LABEL[kind] and db.autoSpells[name] then
    db.autoSpells[name].kind, db.autoSpells[name].manual = kind, true
    ns.say(('%s: %s'):format(name, LABEL[kind]))
    if ns.scanSpells then pcall(ns.scanSpells) end
    return
  end
  local n = 0
  for nm, r in pairs(db.autoSpells) do
    n = n + 1
    ns.say(('%s: %s%s'):format(nm, LABEL[r.kind] or r.kind, r.manual and ' (rucne)' or ''))
  end
  if n == 0 then ns.say('Zadna nova kouzla - vsechna zna rotace') end
  ns.say('Zmena: /cm auto <jmeno> attack|aoe|heal|buff|stop|defense|ignore')
end

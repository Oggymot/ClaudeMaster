-- ClaudeMaster: vlastnosti nepritele a imunity.
-- 1) Pevna pravidla podle typu tvora (Polymorph jen na Beast/Humanoid/Critter, vodni/ledovi
--    elementalove odolavaji mrazu, ohnivi ohni).
-- 2) Uceni: kdyz hra ukaze "Immune", zapamatuje si to podle jmena moba (ulozeno pro postavu).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local I = {}
ns.Immune = I

-- skola kazdeho kouzla
I.SCHOOL = {
  Frostbolt = 'frost', ['Ice Lance'] = 'frost', ['Cone of Cold'] = 'frost', Blizzard = 'frost', ['Frost Nova'] = 'frost',
  Cryoblast = 'frost', ['Scroll of Cryoblast'] = 'frost',
  Pyroblast = 'fire', ['Blast Wave'] = 'fire', ['Arcane Blast'] = 'arcane', ['Arcane Wrath'] = 'arcane',
  ['Shadow Bolt'] = 'shadow', Corruption = 'shadow', ['Curse of Agony'] = 'shadow', ['Bane of Agony'] = 'shadow',
  ['Bane of Havoc'] = 'shadow', ['Bane of Doom'] = 'shadow', Wrack = 'shadow', Incinerate = 'fire', ['Drain Life'] = 'shadow',
  ['Drain Soul'] = 'shadow', ['Death Coil'] = 'shadow', Shadowburn = 'shadow', ['Siphon Life'] = 'shadow',
  Immolate = 'fire', Conflagrate = 'fire', ['Searing Pain'] = 'fire', ['Soul Fire'] = 'fire', ['Rain of Fire'] = 'fire',
  Hellfire = 'fire',
  ['Fire Blast'] = 'fire', Fireball = 'fire', Scorch = 'fire', Flamestrike = 'fire',
  ['Frostfire Bolt'] = 'frostfire',
  ['Arcane Explosion'] = 'arcane', ['Arcane Missiles'] = 'arcane', Polymorph = 'arcane',
}
local MASK = { [16] = 'frost', [4] = 'fire', [64] = 'arcane', [32] = 'shadow' }
local SCHOOL_CZ = { frost = 'mraz', fire = 'ohen', arcane = 'arcane', shadow = 'stin' }
I.SCHOOL_CZ = SCHOOL_CZ

local POLY_OK = { Beast = true, Humanoid = true, Critter = true }
local WATERY = { 'water', 'frost', 'ice', 'glacial', 'snow', 'tidal', 'wave', 'sea ', 'brine', 'spray', 'cryo', 'winter', 'chill' }
local FIERY = { 'fire', 'flame', 'blaze', 'inferno', 'lava', 'magma', 'ember', 'scorch', 'burning', 'molten', 'pyro', 'cinder' }
local function nameHas(name, list)
  local n = name:lower()
  for _, w in ipairs(list) do if n:find(w, 1, true) then return true end end
  return false
end

local function db()
  ns.db.immune = ns.db.immune or {}
  return ns.db.immune
end

-- Jmeno cile: v boji muze byt skryte, proto si ho drzime z chvile, kdy slo precist
I.tname, I.ttype = nil, nil
function I.refreshTarget()
  local n = safe(pc(UnitName, 'target'))
  if type(n) == 'string' then I.tname = n end
  local t = safe(pc(UnitCreatureType, 'target'))
  if type(t) == 'string' then I.ttype = t end
end
function I.targetChanged()
  I.tname, I.ttype = nil, nil
  I.refreshTarget()
end

-- Zapamatovat imunitu
local function learn(mob, spell, school, how)
  if type(mob) ~= 'string' or mob == '' then return end
  local d = db()
  local e = d[mob] or { schools = {}, spells = {} }
  d[mob] = e
  local isNew = false
  if spell and not e.spells[spell] then e.spells[spell] = true isNew = true end
  -- skola se uci jen u kouzel, ktera nejsou jen o efektu (root/Polymorph)
  if school and spell ~= 'Frost Nova' and spell ~= 'Polymorph' and not e.schools[school] then
    e.schools[school] = true isNew = true
  end
  if spell == 'Frost Nova' and mob == I.tname and ns.T then ns.T.frozenUntil = 0 end   -- root nechytil
  if isNew then
    ns.say(('%s je imunni na %s%s'):format(mob, spell or '?', school and (' (' .. (SCHOOL_CZ[school] or school) .. ')') or '')
      .. (how and (' |cff888888[' .. how .. ']|r') or ''))
  end
end
I.learn = learn

-- Vlastnosti aktualniho cile
function I.info()
  local r = { name = I.tname, ctype = I.ttype, schools = {}, spells = {}, staticNote = nil }
  local name, ctype = I.tname, I.ttype
  if ctype == 'Elemental' and name then
    if nameHas(name, WATERY) then r.schools.frost = 'typ' r.staticNote = 'vodni/ledovy elemental' end
    if nameHas(name, FIERY) then r.schools.fire = 'typ' r.staticNote = 'ohnivy elemental' end
  end
  if ctype and not POLY_OK[ctype] then r.spells.Polymorph = 'typ' end
  -- Banish jen na demony a elementaly, Enslave jen na demony
  if ctype and ctype ~= 'Demon' and ctype ~= 'Elemental' then r.spells.Banish = 'typ' end
  if ctype and ctype ~= 'Demon' then r.spells['Enslave Demon'] = 'typ' end
  local e = name and db()[name]
  if e then
    for s in pairs(e.schools) do r.schools[s] = 'nauceno' end
    for s in pairs(e.spells) do r.spells[s] = 'nauceno' end
  end
  return r
end
-- Muzu tohle kouzlo na cil pouzit?
function I.bad(info, spell)
  if not info then return false end
  if info.spells[spell] then return true end
  local sc = I.SCHOOL[spell]
  -- Frostfire: pocita se s nizsim odporem, takze vadi jen imunita na mraz i ohen
  if sc == 'frostfire' then return info.schools.frost and info.schools.fire or false end
  if sc and info.schools[sc] then return true end
  return false
end
-- Odhad skoly podle jmena (moba nebo kouzla): 'fire' / 'frost' / nil
local SPELL_FIRE = { 'immolat', 'burn', 'fireball', 'flame', 'fire', 'scorch', 'lava', 'magma', 'pyro', 'ember', 'inferno', 'blaze' }
local SPELL_FROST = { 'frost', 'ice', 'chill', 'cold', 'blizzard', 'glacial', 'snow', 'freez', 'winter' }
function I.guessSchool(str)
  if type(str) ~= 'string' then return nil end
  if nameHas(str, SPELL_FROST) then return 'frost' end
  if nameHas(str, SPELL_FIRE) then return 'fire' end
  return nil
end
-- "imunni: mraz, Frost Nova"
function I.describe(info)
  local parts = {}
  for _, sc in ipairs({ 'frost', 'fire', 'arcane', 'shadow' }) do
    if info.schools[sc] then parts[#parts + 1] = SCHOOL_CZ[sc] end
  end
  for sp, how in pairs(info.spells) do
    -- jen kouzla, ktera mam (magovi nepsat Banish apod.)
    if not (sp == 'Polymorph' and how == 'typ') and ns.known(sp) then parts[#parts + 1] = sp end
  end
  table.sort(parts)
  return parts
end

------------------------------------------------------------------------------------------
-- Detekce "Immune"
------------------------------------------------------------------------------------------
-- Posledni vlastni kouzla (kvuli prirazeni, kdyz hra prozradi jen skolu)
local recent = {}
function I.onCast(name)
  if not I.SCHOOL[name] then return end
  table.insert(recent, 1, { name = name, at = GetTime(), mob = I.tname })
  if #recent > 6 then table.remove(recent) end
end
local function lastOfSchool(school, window)
  local now = GetTime()
  for _, r in ipairs(recent) do
    if now - r.at <= window and I.SCHOOL[r.name] == school then return r end
  end
end

local f = CreateFrame('Frame')
-- Combat log: Forever (pravidla Midnight) addonum registraci zakazuje - hra by vyhodila popup
-- "blocked from an action only available to the Blizzard UI". Spolehame se na UNIT_COMBAT.
I.cleuOK = false
pcall(f.RegisterEvent, f, 'UNIT_COMBAT')
I.cleuWorks, I.unitCombatWorks = false, false
-- pocitadla pro diagnostiku: kolik zprav prislo a kolik z nich bylo skrytych
I.stat = { cleu = 0, cleuSecret = 0, uc = 0, ucSecret = 0 }

f:SetScript('OnEvent', function(_, event, ...)
  if not ns.db then return end
  if event == 'COMBAT_LOG_EVENT_UNFILTERED' then
    if not CombatLogGetCurrentEventInfo then return end
    local _, sub, _, srcGUID, _, _, _, _, destName, _, _, _, spellName, school, missType = CombatLogGetCurrentEventInfo()
    I.stat.cleu = I.stat.cleu + 1
    if ns.issecret(sub) then I.stat.cleuSecret = I.stat.cleuSecret + 1 end
    sub, srcGUID, destName, spellName, missType = safe(sub), safe(srcGUID), safe(destName), safe(spellName), safe(missType)
    if not sub then return end
    I.cleuWorks = true
    if (sub == 'SPELL_MISSED' or sub == 'RANGE_MISSED') and missType == 'IMMUNE' then
      local me = safe(pc(UnitGUID, 'player'))
      if me and srcGUID == me then
        local sc = MASK[safeNum(school) or 0] or I.SCHOOL[spellName or '']
        learn(destName, spellName, sc, 'log')
      end
    end
  elseif event == 'UNIT_COMBAT' then
    local unit, action, _, _, schoolMask = ...
    if safe(unit) ~= 'target' then return end
    I.stat.uc = I.stat.uc + 1
    if ns.issecret(action) then I.stat.ucSecret = I.stat.ucSecret + 1 end
    action = safe(action)
    if action then I.unitCombatWorks = true end
    if action == 'IMMUNE' and not I.cleuWorks then
      -- portret ukazuje i kouzla ostatnich: ucime jen kdyz skola sedi s mym kouzlem z posledni chvile
      local sc = MASK[safeNum(schoolMask) or 0]
      local r = sc and lastOfSchool(sc, 2.5)
      if r then learn(r.mob or I.tname, r.name, sc, 'portret') end
    end
  end
end)

-- ClaudeMaster: rozhodovaci logika pro Destruction Warlocka (40+).
-- Pouziva stejny kontext jako mag (Frost.lua: cil, moby, parta, mana, pamet mobu...) a pridava
-- warlocke veci: soul shardy, peta, DoTy a curse (sledovane z vlastnich castu, protoze
-- debuffy cile Forever v boji skryva), Life Tap, healthstone/soulstone.
local ADDON, ns = ...
if not ns.enabled or ns.class ~= 'WARLOCK' then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = ns.Engine
local W = {}
ns.Warlock = W

-- Soulstone: na kom je. Aury jdou cist mimo boj, v boji drzime posledni zjisteny stav.
-- W.ssOn = jmeno (nebo nil), W.ssKnown = jestli sken fungoval
W.ssOn, W.ssKnown, W.ssAt = nil, false, 0
local function auraSS(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, 'HELPFUL')
    if not ok or type(a) ~= 'table' then return false end
    local n = safe(a.name)
    if type(n) ~= 'string' then return nil end      -- skryte
    if n == 'Soulstone Resurrection' or n == 'Soulstone' then return true end
  end
  return false
end
function W.ssScan(c)
  if c.inCombat or GetTime() - W.ssAt < 2 then return end
  W.ssAt = GetTime()
  local units = { 'player', 'party1', 'party2', 'party3', 'party4' }
  local on, known = nil, false
  for _, u in ipairs(units) do
    if UnitExists(u) then
      local r = auraSS(u)
      if r ~= nil then known = true end
      if r then on = (u == 'player') and 'ty' or safe(pc(UnitName, u)) break end
    end
  end
  W.ssOn, W.ssKnown = on, known
end

-- DoTy a jejich delka (s)
local DOT = { Immolate = 15, Corruption = 18, ['Siphon Life'] = 30, ['Curse of Agony'] = 24,
  ['Curse of the Elements'] = 300, ['Curse of Shadow'] = 300, ['Curse of Weakness'] = 120, ['Curse of Tongues'] = 30,
  ['Curse of Recklessness'] = 120, ['Curse of Doom'] = 60, ['Curse of Exhaustion'] = 12,
  ['Bane of Agony'] = 24, ['Bane of Havoc'] = 300, ['Bane of Doom'] = 60 }
-- WoW Forever: Agony/Doom/Havoc jsou "Bane" - jeden Bane + jedna Curse od kazdeho warlocka na cili
local BANE = { ['Bane of Agony'] = true, ['Bane of Havoc'] = true, ['Bane of Doom'] = true }
local CURSE = { ['Curse of Agony'] = true, ['Curse of the Elements'] = true, ['Curse of Shadow'] = true,
  ['Curse of Weakness'] = true, ['Curse of Tongues'] = true, ['Curse of Recklessness'] = true, ['Curse of Doom'] = true,
  ['Curse of Exhaustion'] = true }
local PETS = { 'Summon Imp', 'Summon Voidwalker', 'Summon Succubus', 'Summon Felhunter' }

-- DoTy podle cile (GUID, aby se neztratily pri prepinani cilu): W.dots[cil][jmeno] = { untilT, other }
W.dots = {}
W.armorUntil = 0
-- curse, ktere jsou na cili jen jednou (od jakehokoli warlocka); Agony/Doom ma kazdy warlock svou
local UNIQUE = { ['Curse of the Elements'] = true, ['Curse of Shadow'] = true, ['Curse of Weakness'] = true,
  ['Curse of Tongues'] = true, ['Curse of Recklessness'] = true }

local function keyOf(unit)
  local g = safe(pc(UnitGUID, unit))
  if type(g) == 'string' then return g end
  if unit == 'target' then return 't' .. ns.T.token end
end
-- U cile ukladame pod GUID i pod "token" vyberu cile: mimo boj je GUID citelne, v boji ho Forever
-- skryje - DoT seslany na pull (mimo boj) by se jinak v boji "ztratil" a addon by ho radil znovu.
local function keysOf(key)
  if type(key) == 'table' then return key end
  return { key }
end
-- Jmenovka cile: token 'nameplateN' patri jednomu mobovi, dokud je jeho jmenovka videt.
-- V boji je GUID skryte a 't<token>' se meni s kazdym prepnutim cile - bez tohohle by addon
-- po tabnuti zpet na moba "zapomnel" jeho Immolate a radil ho znovu.
local function plateKey()
  for u in pairs(ns.Plates and ns.Plates.units or {}) do
    if safeBool(pc(UnitIsUnit, 'target', u)) == true then return 'p' .. u end
  end
end
local function targetKeys()
  local k = {}
  local g = safe(pc(UnitGUID, 'target'))
  if type(g) == 'string' then k[#k + 1] = g end
  k[#k + 1] = 't' .. ns.T.token
  local p = plateKey()
  if p then k[#k + 1] = p end
  return k
end
local function mark(key, name, dur, other)
  if not key then return end
  for _, kk in ipairs(keysOf(key)) do
    local d = W.dots[kk] or {}
    W.dots[kk] = d
    d[name] = { untilT = GetTime() + dur, other = other }
  end
end
local function cleanup()
  local now = GetTime()
  for k, d in pairs(W.dots) do
    local any = false
    for n, e in pairs(d) do if e.untilT <= now then d[n] = nil else any = true end end
    if not any then W.dots[k] = nil end
  end
end

------------------------------------------------------------------------------------------
-- Sledovani castu (svych i warlocku v parte) a hlasky "uz tam je silnejsi kouzlo"
------------------------------------------------------------------------------------------
local lastFail, lastBounce = { t = 0 }, 0
local function bounced(name)
  -- cil uz ma tuto curse (nebo silnejsi) od nekoho jineho
  if name and DOT[name] then mark(targetKeys(), name, (CURSE[name] or BANE[name]) and math.min(DOT[name], 120) or 10, true) end
end
local ev = CreateFrame('Frame')
for _, e in ipairs({ 'UNIT_SPELLCAST_SUCCEEDED', 'UNIT_SPELLCAST_FAILED', 'UI_ERROR_MESSAGE', 'PLAYER_TARGET_CHANGED',
  'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED' }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript('OnEvent', function(_, event, unit, arg2, spellID)
  if not ns.db then return end
  local now = GetTime()
  if event == 'UI_ERROR_MESSAGE' then
    local msg = safe(arg2)
    if type(msg) == 'string' and (msg == SPELL_FAILED_AURA_BOUNCED or msg:find('more powerful')) then
      lastBounce = now
      if now - lastFail.t < 1 then bounced(lastFail.name) end
    end
    return
  end
  if event == 'NAME_PLATE_UNIT_ADDED' or event == 'NAME_PLATE_UNIT_REMOVED' then
    -- jmenovka zmizela / patri novemu mobovi: jeji DoTy zahodit
    local u = safe(unit)
    if type(u) == 'string' then W.dots['p' .. u] = nil end
    return
  end
  if event == 'PLAYER_TARGET_CHANGED' then
    -- mimo boj jdou debuffy cile precist: co uz na nem je, si zapamatuj
    if not ns.inCombat() then
      for n in pairs(DOT) do if (CURSE[n] or BANE[n]) and ns.targetDebuff(n) then mark(targetKeys(), n, math.min(DOT[n], 120), true) end end
    end
    cleanup()
    return
  end
  unit = safe(unit)
  local name = ns.nameOf(safeNum(spellID))
  if not name or type(unit) ~= 'string' then return end
  if event == 'UNIT_SPELLCAST_FAILED' then
    if unit == 'player' then
      lastFail = { name = name, t = now }
      if now - lastBounce < 1 then bounced(name) end
    end
    return
  end
  -- UNIT_SPELLCAST_SUCCEEDED
  if unit == 'player' then
    local key = targetKeys()
    if DOT[name] then
      -- jeden warlock = jedna vlastni curse na cili
      local slot = (CURSE[name] and CURSE) or (BANE[name] and BANE)
      if slot then
        for _, kk in ipairs(key) do
          local d = W.dots[kk]
          if d then for n in pairs(slot) do local e = d[n] if e and not e.other then d[n] = nil end end end
        end
      end
      mark(key, name, DOT[name], false)
      if name == 'Bane of Havoc' then W.havocAt = now end
    elseif name == 'Conflagrate' then
      -- Conflagrate spotrebuje Immolate - na Foreveru ale talent Shadow and Flame dava sanci
      -- (5/5 = vzdy), ze Immolate zustane. Pri 5/5 nic nemazat, jinak si ho schovat: kdyz
      -- Conflagrate zustane pouzitelny (vyzaduje Immolate na cili), Immolate tam porad je.
      if (ns.talent('Shadow and Flame') or 0) < 5 then
        W.immSaved = W.immSaved or {}
        for _, kk in ipairs(key) do
          local d = W.dots[kk]
          if d and d.Immolate then W.immSaved[kk] = d.Immolate d.Immolate = nil end
        end
      end
    elseif name == 'Demon Armor' or name == 'Demon Skin' then
      W.armorUntil = now + 1800
    elseif name == 'Soulstone Resurrection' then
      ns.db.ssAt = time and time() or 0
    end
  elseif unit:find('^party%d$') and UNIQUE[name] then
    -- jiny warlock v parte dal curse na svuj cil
    mark(keyOf(unit .. 'target'), name, DOT[name], true)
  end
end)

local function dotEntry(name)
  for _, kk in ipairs(targetKeys()) do
    local d = W.dots[kk]
    local e = d and d[name]
    if e and e.untilT > GetTime() then return e end
  end
end
local function immolateKept()
  if not W.immSaved then return nil end
  local now = GetTime()
  for _, kk in ipairs(targetKeys()) do
    local e = W.immSaved[kk]
    if e and e.untilT > now then
      local f = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
      local id = ns.id('Conflagrate')
      if f and id and safeBool(pc(f, id)) == true then return e end
    end
  end
end
local function dotLeft(name)
  local e = dotEntry(name)
  if not e and name == 'Immolate' then e = immolateKept() end
  local left = e and (e.untilT - GetTime()) or 0
  if left <= 0 and (ns.targetDebuff(name) or ns.cdm('target', name)) then left = 3 end
  return left
end
-- kolik ruznych cilu ma ode mne DoT (multi-DoT). Klice 't<token>' = cil v dobe castu.
function W.dottedCount()
  local now, n = GetTime(), 0
  for k, d in pairs(W.dots) do
    if type(k) == 'string' and k:sub(1, 1) == 't' and type(d) == 'table' then
      for _, nm in ipairs({ 'Corruption', 'Bane of Agony', 'Immolate', 'Curse of Agony', 'Siphon Life' }) do
        local e = d[nm]
        if e and not e.other and e.untilT > now + 2 then n = n + 1 break end
      end
    end
  end
  return n
end
-- ma tuto curse cil od nekoho jineho?
function W.otherHas(name)
  local e = dotEntry(name)
  return e and e.other or false
end

local function hasBuff(names, trackedUntil)
  local unknown = false
  for _, n in ipairs(names) do
    local a = ns.playerAura(n)
    if a == nil then unknown = true elseif a then return true end
  end
  if unknown then return GetTime() < (trackedUntil or 0) end
  return false
end

------------------------------------------------------------------------------------------
-- Kontext: k magovskemu pridame warlocke veci
------------------------------------------------------------------------------------------
local baseContext = E.context
E.context = function()
  local c = baseContext()
  c.shards = ns.Bags.count('shard')
  c.pet = UnitExists('pet') and safeBool(pc(UnitIsDeadOrGhost, 'pet')) ~= true
  c.petFamily = c.pet and safe(pc(UnitCreatureFamily, 'pet')) or nil
  c.petLow = c.pet and ns.hpBelow('pet', 30) == true
  c.lockArmor = hasBuff({ 'Demon Armor', 'Demon Skin' }, W.armorUntil)
  c.dots = {}
  for n in pairs(DOT) do c.dots[n] = dotLeft(n) end
  -- kdo je v parte (curse podle toho, kdo bude bit)
  c.classes = {}
  for _, m in ipairs((c.party and c.party.members) or {}) do
    local cls = select(2, UnitClass(m.unit))
    if cls then c.classes[cls] = true end
    if m.healer and m.alive then c.healer = m end
  end
  W.ssScan(c)
  c.ssOn, c.ssKnown = W.ssOn, W.ssKnown
  if not c.healer then
    for _, m in ipairs((c.party and c.party.members) or {}) do
      local cls = select(2, UnitClass(m.unit))
      if m.alive and (cls == 'PRIEST' or cls == 'DRUID' or cls == 'SHAMAN' or cls == 'PALADIN') then c.healer = m break end
    end
  end
  return c
end

-- Ktery pet
local function wantPet(c)
  local pref = c.db.lockPet
  if pref and pref ~= 'auto' and ns.known('Summon ' .. pref) then return 'Summon ' .. pref end
  if c.group or c.instance then
    if ns.known('Summon Imp') then return 'Summon Imp' end       -- Blood Pact (vic HP pro celou partu)
  elseif ns.known('Summon Voidwalker') and c.shards >= 1 then
    return 'Summon Voidwalker'                                    -- solo tank
  end
  return ns.known('Summon Imp') and 'Summon Imp' or nil
end

-- Ktera curse
local function longFight(c)
  local ttd = c.ttd or c.ttdMem
  return c.boss or c.tough or (ttd and ttd > 20) or false
end
-- Bane (Forever): Agony na kazdy cil, ktery chvili vydrzi
local function chooseBane(c)
  if c.db.lockCurse and BANE[c.db.lockCurse] and ns.known(c.db.lockCurse) then return c.db.lockCurse end
  if ns.known('Bane of Agony') then return 'Bane of Agony' end
end
local function chooseCurse(c)
  local pref = c.db.lockCurse
  if pref == 'none' then return nil end
  if pref and pref ~= 'auto' and not BANE[pref] and ns.known(pref) then return pref end
  if ns.known('Bane of Agony') then
    -- Forever: Agony je Bane, curse je navic. Curse of the Elements (+8 % magie pro tebe i maga) jen na delsi boj
    -- Vyplati se, kdyz +8 % ze vsech magickych dmg za zbytek boje > 1 GCD tveho dmg.
    -- Solo ~19 s, s magem v parte ~9 s (zvedne dmg vam obema). Neznamy cas boje = pocitej 20 s.
    if ns.known('Curse of the Elements') then
      local casters = 1 + ((c.classes and c.classes.MAGE) and 1 or 0) + ((c.classes and c.classes.WARLOCK) and 1 or 0)
      local need = 1.5 / (0.08 * casters)
      local ttd = c.ttd or c.ttdMem or 20
      if c.boss or c.tough or ttd > need + 1 then return 'Curse of the Elements' end
    end
    return nil
  end
  if c.group then
    -- mag v parte: Curse of the Elements (ohen + mraz); jinak Curse of Shadow (tvuj Shadow Bolt)
    if c.classes.MAGE and ns.known('Curse of the Elements') then return 'Curse of the Elements' end
    if ns.known('Curse of Shadow') and (c.tough or c.boss) then return 'Curse of Shadow' end
  else
    if (c.boss or (c.tough and (c.ttd or c.ttdMem or 0) > 40)) and ns.known('Curse of Shadow') then return 'Curse of Shadow' end
  end
  if ns.known('Curse of Agony') then return 'Curse of Agony' end
end

------------------------------------------------------------------------------------------
-- Talenty a vyber filleru: ktere kouzlo da nejvic poskozeni za sekundu castu
-- (poskozeni z popisu kouzla, cas castu ze hry - uz s talenty jako Bane - a bonusy z talentu)
------------------------------------------------------------------------------------------
W.talents, W.scores, W.order = {}, {}, { 'Shadow Bolt', 'Searing Pain' }
local FILLERS = { 'Shadow Bolt', 'Searing Pain', 'Incinerate' }

function W.scanTalents()
  ns.scanTalents()
  W.talents, W.talentsRead = ns.talents, ns.talentsRead
end
local function tal(name) return W.talents[name] or 0 end

local function spellDamage(name)
  local id = ns.id(name)
  if not id or not (C_Spell and C_Spell.GetSpellDescription) then return nil end
  local d = safe(pc(C_Spell.GetSpellDescription, id))
  if type(d) ~= 'string' then return nil end
  d = d:gsub(',', '')
  local lo, hi = d:match('(%d+) to (%d+)')
  if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
  local x = d:match('causing (%d+)') or d:match('for (%d+)')
  return x and tonumber(x) or nil
end

function W.refresh()
  W.scanTalents()
  local scores = {}
  -- mana warlocka = HP pres Life Tap: drahe kouzlo stoji navic cas na Life Tap (a HP)
  local tap = 300
  local tid = ns.id('Life Tap')
  local td = tid and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, tid))
  if type(td) == 'string' then tap = tonumber(td:gsub(',', ''):match('Converts (%d+)')) or tap end
  for _, n in ipairs(FILLERS) do
    if ns.known(n) then
      local dmg = spellDamage(n)
      local BASECT = { ['Shadow Bolt'] = 3, ['Searing Pain'] = 1.5, Incinerate = 2.5 }
      local ct = math.max(1.5, ns.castTime(n))   -- cas castu ze hry uz je s talentem Bane
      local fire = n ~= 'Shadow Bolt'
      -- bonus ze spell poweru (koeficienty z MythicSim enginu pro Forever)
      local COEF = { ['Shadow Bolt'] = 0.857, ['Searing Pain'] = 0.429, Incinerate = 0.714 }
      local sp = safeNum(pc(GetSpellBonusDamage, fire and 3 or 6)) or 0
      if dmg then dmg = dmg + sp * (COEF[n] or math.min(1, (BASECT[n] or ct) / 3.5)) end
      local mult = 1
      local critBonus = 0.5 + 0.1 * tal('Ruin')     -- crit 1.5x, Ruin +0.1 za bod (5/5 = 2x)
      -- Agonizing Flames (Forever): +10 % Destruction dmg, Searing Pain +10 % crit
      mult = mult * (1 + 0.1 * tal('Agonizing Flames') / 3)
      if fire then
        mult = mult * (1 + 0.02 * tal('Emberstorm'))
        if n == 'Searing Pain' then
          mult = mult * (1 + 0.02 * tal('Improved Searing Pain') * critBonus)
          mult = mult * (1 + (0.1 * tal('Agonizing Flames') / 3) * critBonus)
        end
      else
        mult = mult * (1 + 0.02 * tal('Shadow Mastery')) * (1 + 0.025 * tal('Improved Shadow Bolt'))
      end
      -- Devastation (+crit) a Ruin (crit x2) plati na Destruction kouzla
      mult = mult * (1 + 0.01 * tal('Devastation') * critBonus)
      -- Incinerate (Forever): +25 % na cil s Immolate - addon Immolate drzi porad
      if n == 'Incinerate' then mult = mult * 1.25 end
      local cost = ns.cost(n)
      local ctEff = ct + (cost > 0 and (cost / math.max(50, tap)) * 1.5 or 0)   -- + podil Life Tapu (1.5 s GCD)
      scores[n] = { dmg = dmg, ct = ct, ctEff = ctEff, cost = cost, dps = dmg and (dmg * mult / ctEff) or nil, mult = mult }
    end
  end
  W.scores = scores
  -- DoTy: celkove poskozeni a delka z popisu (+ spell power), at jde porovnat s fillerem
  W.dotInfo = {}
  for _, n in ipairs({ 'Corruption', 'Bane of Agony', 'Curse of Agony', 'Siphon Life', 'Immolate' }) do
    local id = ns.known(n) and ns.id(n)
    local d = id and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
    if type(d) == 'string' then
      d = d:gsub(',', '')
      local dmg, dur = d:match('(%d+) %a+ damage over (%d+) sec')
      if not dmg then dmg, dur = d:match('(%d+) health from the target to the caster every %d+ sec%.%s+Lasts (%d+) sec') end
      dmg, dur = tonumber(dmg), tonumber(dur)
      if dmg and dur and dur > 0 then
        local sp = safeNum(pc(GetSpellBonusDamage, n == 'Immolate' and 3 or 6)) or 0
        local mult = 1
        if n == 'Corruption' then mult = 1 + 0.02 * tal('Improved Corruption') end
        -- celkovy koeficient DoTu (engine): Corruption 6x0.2, Agony 12x0.133, Immolate 5x0.13
        local DOTCOEF = { Corruption = 1.2, ['Bane of Agony'] = 1.6, ['Curse of Agony'] = 1.6, Immolate = 0.65 }
        W.dotInfo[n] = { dmg = (dmg + sp * (DOTCOEF[n] or math.min(1, dur / 15))) * mult, dur = dur, ramp = (n == 'Bane of Agony' or n == 'Curse of Agony') }
      end
    end
  end
  local order = {}
  for n in pairs(scores) do order[#order + 1] = n end
  table.sort(order, function(a, b)
    local x, y = scores[a].dps or 0, scores[b].dps or 0
    if math.abs(x - y) > 0.03 * math.max(x, y) then return x > y end
    return (scores[a].ct or 9) < (scores[b].ct or 9)   -- skoro stejne: kratsi cast (min pushbacku, mene overkillu)
  end)
  if #order > 0 then W.order = order end
end
local origScan = ns.scanSpells
ns.scanSpells = function(...)
  origScan(...)
  pcall(W.refresh)
end
local tev = CreateFrame('Frame')
for _, e in ipairs({ 'CHARACTER_POINTS_CHANGED', 'PLAYER_TALENT_UPDATE', 'SPELLS_CHANGED' }) do pcall(tev.RegisterEvent, tev, e) end
tev:SetScript('OnEvent', function() if ns.db and not InCombatLockdown() and C_Timer then C_Timer.After(1, function() pcall(W.refresh) end) end end)

function W.report()
  ns.talentReport()
  if not W.talentsRead then ns.say('Filler vybiram jen podle poskozeni a casu castu.') end
  for _, n in ipairs(W.order) do
    local s = W.scores[n]
    if s then ns.say(('  %s: %s dmg x%.2f, cast %.1fs + Life Tap za %d many = %.1fs -> %s za sekundu'):format(n,
      s.dmg and math.floor(s.dmg) or '?', s.mult, s.ct, s.cost or 0, s.ctEff or s.ct, s.dps and math.floor(s.dps) or '?')) end
  end
  local pref = ns.db.lockFiller
  ns.say('Filler: ' .. ((pref and pref ~= 'auto') and (pref .. ' (nastaveno rucne)') or (W.order[1] or '?')) .. '   (/cm filler auto/shadowbolt/searing)')
end

-- curse do makra (bez kontextu boje): nastavena, jinak CoE kdyz je v parte mag, jinak Agony
function W.macroCurse()
  local pref = ns.db.lockCurse
  if pref and pref ~= 'auto' and ns.known(pref) then return pref end
  if IsInGroup and IsInGroup() and ns.known('Curse of the Elements') then
    for i = 1, 4 do if select(2, UnitClass('party' .. i)) == 'MAGE' then return 'Curse of the Elements' end end
  end
  if ns.known('Bane of Agony') then return nil end   -- Bane jde v makru zvlast
  return ns.known('Curse of Agony') and 'Curse of Agony' or nil
end

------------------------------------------------------------------------------------------
-- Rozhodnuti pro jeden krok
------------------------------------------------------------------------------------------
local function A(name, reason, kind, extra)
  local a = { name = name, reason = reason, kind = kind or 'spell' }
  if extra then for k, v in pairs(extra) do a[k] = v end end
  return a
end

local function decide(c, s)
  local db = c.db
  local function bad(n) return c.imm ~= nil and ns.Immune.bad(c.imm, n) end
  local function can(n) return ns.known(n) and not bad(n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if ns.cost(n) > 0 and s.mana * ns.manaMax() < ns.cost(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  local function dot(n) return math.max(0, (s.dots[n] or 0) - s.t) end
  local filler = 'Shoot'
  local pref = db.lockFiller
  if pref and pref ~= 'auto' and can(pref) then filler = pref
  else for _, n in ipairs(W.order) do if can(n) then filler = n break end end end
  -- v parte s tankem ma Searing Pain obri threat (bez Demonic Brand): radsi Shadow Bolt / Incinerate
  local spThreat = c.tankUp and (ns.talent('Demonic Brand') or 0) == 0
  if filler == 'Searing Pain' and spThreat then
    for _, n in ipairs({ 'Shadow Bolt', 'Incinerate' }) do if can(n) then filler = n break end end
  end
  -- Shadow Bolt ma navrch jen v dlouhem klidnem boji. Kratky boj (overkill), mob te bije (pushback 2.5s castu)
  -- nebo malo many (Life Tap = HP) -> rychly a levny Searing Pain
  local fillerWhy
  local locked = pref and pref ~= 'auto'
  if not locked and filler == 'Shadow Bolt' and can('Searing Pain') and not spThreat then
    local ttdF = c.ttd or c.ttdMem
    if not c.instance and not c.boss and not c.tough then
      fillerWhy = 'mimo dungeon - rychly a levny (Shadow Bolt az v dungeonu a na silne moby)'
    elseif ttdF and ttdF < 15 then fillerWhy = 'kratky boj - rychlejsi cast, mene overkillu'
    elseif c.aggro and c.enemies.onMe > 0 and not c.group then fillerWhy = 'mob te bije - dlouhy cast by se posouval'
    elseif c.manaKnown and c.mana < 0.4 then fillerWhy = 'malo many - levnejsi (Life Tap bere HP)' end
    if fillerWhy then filler = 'Searing Pain' end
  end
  local aoeN = c.enemies.cluster or c.enemies.combat
  local ttd = c.ttd or c.ttdMem
  local keep = db.shardKeep or 3
  local curse = chooseCurse(c)
  if curse and UNIQUE[curse] and W.otherHas(curse) then
    curse = (not ns.known('Bane of Agony') and ns.known('Curse of Agony')) and 'Curse of Agony' or nil   -- tu uz drzi jiny warlock
  end
  local bane = chooseBane(c)
  local tDying = c.tLow20 or (ttd and ttd < 5)
  local tapOK = not c.hpLow50 and (c.php == nil or c.php > 50)   -- Life Tap bere HP

  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end

  -- pod vodou: Unending Breath (10 min dychani) - sobe, pak parte
  local askBreath = c.party and c.party.needBreath and c.party.needBreath.asked
  if s.step == 1 and ns.known('Unending Breath') and (ns.underwater() or askBreath) and not s.used.breath then
    -- buff uz mam? (dvema zpusoby; navic s nim nebezi ukazatel dechu)
    local mine = ns.playerAura('Unending Breath')
    if not mine then mine = ns.playerHasBuff('Unending Breath') end
    local recent = GetTime() - (ns.castAt['Unending Breath'] or -999) < 540
    local losing = ns.breathRunning()
    if ns.underwater() and not mine and not recent and losing ~= false then
      s.used.breath = true
      return A('Unending Breath', 'Pod vodou: Unending Breath (dychani na 10 min)', 'spell', { unit = 'player' })
    end
    local nb = c.party and c.party.needBreath
    if nb then
      s.used.breath = true
      return A('Unending Breath', (nb.asked and '%s se topi: Unending Breath' or 'Pod vodou: Unending Breath na %s'):format(nb.name),
        'spell', { unit = nb.unit, urgent = nb.asked or nil })
    end
  end

  -- tagovani: sedy (cizi) mob / nekdo ho vzal behem castu / instant otvirak v plne oblasti
  if ns.Tactics and ns.Tactics.tagHint then
    local tg = ns.Tactics.tagHint(c, s, A, ready) or ns.Tactics.tagOpener(c, s, A, ready)
    if tg then return tg end
  end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    local town = c.resting and not c.hostile   -- ve meste: zadne buffy ani pet (az venku)
    local armor = ns.known('Demon Armor') and 'Demon Armor' or (ns.known('Demon Skin') and 'Demon Skin' or nil)
    if armor and not c.lockArmor and not s.used.armor and not town then s.used.armor = true return A(armor, 'Chybi ti ' .. armor) end
    if not c.pet and not s.used.pet and not town then
      local p = wantPet(c)
      if p then
        s.used.pet = true
        return A(p, (p == 'Summon Imp' and (c.group or c.instance)) and 'Bez peta: Imp (Blood Pact pro partu)'
          or ('Bez peta: ' .. p:gsub('Summon ', '')))
      end
    end
    -- healthstone/soulstone stoji shard: nabizet az kdyz jich je dost (aspon 3, nebo kolik si chces drzet)
    local spare = math.max(3, db.shardKeep or 3)
    if ns.known('Create Healthstone') and ns.Bags.count('stone') == 0 and c.shards >= spare and not s.used.hs then
      s.used.hs = true
      return A('Create Healthstone', 'Nemas Healthstone - vyrob si ho (1 shard)')
    end
    if c.petFamily == 'Imp' and c.group and s.step == 1 and ns.auraHas and ns.auraHas('pet', { 'Phase Shift' }) == true then
      return A('PET', 'Imp ma Phase Shift: v parte ho vypni, at bije a dava Blood Pact', 'hint',
        { icon = 'Interface\\Icons\\Spell_Shadow_ImpPhaseShift' })
    end
    if c.instance and c.healer and ns.known('Create Soulstone') and ns.Bags.count('soulstone') == 0 and c.shards >= spare
      and not s.used.ss then
      s.used.ss = true
      return A('Create Soulstone', 'V parte: vyrob Soulstone')
    end
    -- soulstone: jen na healera (kdyz ho nikdo v parte nema a kamen je ready)
    local ssItem = ns.Bags.best('soulstone')
    local ssAgo = (time and time() or 0) - (db.ssAt or 0)
    local nobodyHas = c.ssKnown and not c.ssOn or (not c.ssKnown and ssAgo > 1800)
    if ssItem and c.instance and c.group and nobodyHas and s.step == 1 and ns.itemReady(ssItem, 'soulstone', 1800) then
      if c.healer and c.healer.alive ~= false then
        return A('item:' .. ssItem, ('Nikdo nema Soulstone: dej ho healerovi (%s)'):format(c.healer.name), 'item',
          { item = ssItem, unit = c.healer.unit })
      end
    end
    local sc = not town and ns.Bags.missingScroll()
    if sc and not s.used['item:' .. sc.id] then
      return A('item:' .. sc.id, ('Chybi buff: %s'):format(sc.name), 'item', { item = sc.id })
    end
    if c.party and c.party.magic and s.step == 1 then
      return A('PET', ('Magicky debuff na %s: Felhunter - Devour Magic'):format(c.party.magic.name), 'hint',
        { icon = 'Interface\\Icons\\Spell_Nature_Purge' })
    end
    -- Firestone na zbran (+1 % crit a ohen; s Ruin crity boli dvojnasob)
    local im = not town and ns.Bags.missingImbue()
    if im and not s.used['item:' .. im.id] then
      s.used['item:' .. im.id] = true
      return A('item:' .. im.id, ('Zbran bez kamene: %s'):format(im.name), 'item', { item = im.id, slot = 16 })
    end
    if not im and #ns.Bags.list('imbue') == 0 and not s.used.mkstone and s.step == 1 and not c.hostile then
      local has = GetWeaponEnchantInfo and pc(GetWeaponEnchantInfo)
      if has == false and c.manaKnown and c.mana > 0.5 then
        local mk = ns.known('Create Firestone') and 'Create Firestone' or (ns.known('Create Spellstone') and 'Create Spellstone' or nil)
        if mk then s.used.mkstone = true return A(mk, mk == 'Create Firestone' and 'Vyrob Firestone na zbran (+crit, +ohen)' or 'Vyrob Spellstone na zbran') end
      end
    end
    if c.hostile then
      if s.step == 1 and (c.tough or c.instance) then
        local ex = ns.Bags.missingElixir()
        if ex then return A('item:' .. ex.id, ('Pred tezkym bojem: %s'):format(ex.name), 'item', { item = ex.id }) end
      end
      -- mana pred pullem: Life Tap (levnejsi nez piti), kdyz je dost HP
      local need = ns.Mem and ns.Mem.needMana(ns.Immune.tname, c.group)
      local thresh = need and math.min(0.9, need * 1.15 + 0.05) or 0.4
      if c.manaKnown and c.mana < thresh and ready('Life Tap') and c.php and c.php > 70 and not s.used.tap then
        s.used.tap = true
        return A('Life Tap', ('Mana %d%% na pull malo: Life Tap'):format(math.floor(c.mana * 100)))
      end
      if s.step == 1 and c.mob and c.mob.caster and c.mob.school == 'shadow' and not c.shadowWardUp and ready('Shadow Ward') then
        s.used['Shadow Ward'] = true
        return A('Shadow Ward', 'Mob kouzli stinem (pamet): Shadow Ward pred pullem')
      end
      -- znacka mesic = tvuj CC: Banish (demon/elemental), jinak Seduction od Succuby
      if s.step == 1 and c.mark == 5 and c.group then
        local ct = safe(pc(UnitCreatureType, 'target'))
        if (ct == 'Demon' or ct == 'Elemental') and ready('Banish') then
          s.used.Banish = true
          return A('Banish', 'Mesic = tvuj CC: Banish, pak teprve tank pulluje')
        end
        if c.petFamily == 'Succubus' or c.petFamily == 'Incubus' then
          return A('PET', 'Mesic = tvuj CC: posli ' .. c.petFamily .. ' na Seduction (pet bar), pak pull', 'hint',
            { icon = 'Interface\\Icons\\Spell_Shadow_MindSteal' })
        end
      end
      local adds = (c.enemies.idle or 0) > 0 and (' |cffffcc00(+%d blizko)|r'):format(c.enemies.idle) or ''
      local sendPet = (c.pet and not c.group) and ' (nejdriv posli peta)' or ''
      if s.step == 1 and c.tough and ready('Soul Fire') and c.shards > keep and not c.moving then
        return A('Soul Fire', 'Silny cil: otevri Soul Fire z max. dosahu' .. adds)
      end
      if ready('Immolate') and not bad('Immolate') then
        return A('Immolate', (c.inRange == false and 'Pull: dojdi na dosah (30 yd)' or 'Pull: Immolate') .. sendPet .. adds)
      end
      return A(filler, 'Pull: ' .. filler .. sendPet .. adds)
    end
    if c.drinking or c.eating then return nil end
    -- regenerace: Life Tap + jidlo je levnejsi nez piti
    if s.step == 1 and c.manaKnown and c.mana < db.drinkMana then
      if ready('Life Tap') and c.php and c.php > 70 then return A('Life Tap', 'Mana dole, HP dost: Life Tap (pak se najez)') end
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
    end
    if s.step == 1 and c.php and c.php < 60 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(c.php)), 'item', { item = fd }) end
    end
    return nil
  end

  if not c.hostile then
    if s.step == 1 and c.enemies.combat > 0 then
      return A('TARGET', c.target and 'Cil je mrtvy - vyber dalsiho moba' or 'Vyber dalsiho moba', 'hint',
        { icon = 'Interface\\Icons\\Ability_Hunter_SniperShot', key = GetBindingKey and GetBindingKey('TARGETNEARESTENEMY') })
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  -- Hellfire bezi a threat na nekterem mobovi roste k tankovu: zrus ho
  if s.step == 1 and c.channel and c.castName == 'Hellfire' and c.tankUp and (c.enemies.thrMax or 0) >= 80 then
    return A('Hellfire', ('ZRUS Hellfire (pohni se)! threat %d%% - strhnes aggro'):format(math.floor(c.enemies.thrMax)),
      'wait', { dur = 0.5, urgent = true })
  end
  -- probihajici channel nech dobehnout
  if s.step == 1 and c.channel and (c.castName == 'Drain Soul' or c.castName == 'Rain of Fire' or c.castName == 'Hellfire'
    or c.castName == 'Health Funnel' or c.castName == 'Drain Life') and not c.hpLow35 then
    return A(c.castName, ('Nech %s dobehnout (%.1fs)'):format(c.castName, c.castLeft), 'wait', { dur = c.castLeft })
  end
  -- 1) nouze
  if c.aggro and c.hpLow35 and ready('Death Coil') then
    return A('Death Coil', 'HP dole: Death Coil (vystrasi moba a vyleci te)', 'spell', { urgent = true })
  end
  if c.aggro and c.hpLow20 and tDying then
    -- mob je skoro mrtvy: Fear by ho jen poslal pro kamarady, radsi ho dorazit
    if ready('Shadowburn') and c.shards > 0 then return A('Shadowburn', 'Ty i mob malo HP: dorazit Shadowburn', 'spell', { urgent = true }) end
    if ready('Conflagrate') and dot('Immolate') > 0 then return A('Conflagrate', 'Ty i mob malo HP: dorazit Conflagrate', 'spell', { urgent = true }) end
    if ready('Searing Pain') then return A('Searing Pain', 'Ty i mob malo HP: dorazit Searing Pain', 'spell', { urgent = true }) end
  end
  if c.aggro and c.hpLow20 and not c.group and not tDying and ready('Fear') then
    return A('Fear', 'HP pod 20 %: Fear a pak se dej dohromady', 'spell', { urgent = true })
  end
  -- threat: v parte jsi blizko pretazeni aggra
  if s.step == 1 and c.tankUp and not c.aggro and c.threatPct and c.threatPct >= 85 then
    return A(ns.known('Shoot') and 'Shoot' or filler, ('Threat %d%%: chvili uber (wand), at nestrhnes aggro'):format(math.floor(c.threatPct)),
      'wait', { dur = 1.5, urgent = c.threatPct >= 95 })
  end
  -- 1a) Drain Life jako zachrana (solo, jeden mob, ktery hned nepadne)
  -- (jen opravdova nouze; pri 35-50 % HP nejdriv rotace, Drain Life prijde az po DoTech)
  if c.aggro and c.hpLow35 and not c.healer and not tDying and c.enemies.onMe <= 1 and can('Drain Life')
    and not ready('Death Coil') and not c.moving and not (c.channel and c.castName == 'Drain Life') then
    return A('Drain Life', 'HP pod 35 %: Drain Life (leci te a bije)', 'spell', { urgent = true })
  end
  -- 1a2) Shadow Ward proti stinu
  if c.aggro and c.wardSchool == 'shadow' and not c.shadowWardUp and ready('Shadow Ward') then
    s.used['Shadow Ward'] = true
    return A('Shadow Ward', 'Cil bije stinem: Shadow Ward')
  end
  -- 1b) ovce/CC v cili
  if s.step == 1 and c.targetCC then
    return A('TARGET', 'Cil je ovce/CC - nebij ho, vyber jiny cil', 'hint',
      { icon = 'Interface\\Icons\\Spell_Nature_Polymorph', key = GetBindingKey and GetBindingKey('TARGETNEARESTENEMY') })
  end
  -- 1c) mob utika
  if s.step == 1 and c.mob and c.mob.fleeingNow then
    if ready('Shadowburn') and c.shards > 0 then return A('Shadowburn', 'Mob utika: Shadowburn', 'spell', { urgent = true }) end
    if ready('Conflagrate') and dot('Immolate') > 0 then return A('Conflagrate', 'Mob utika: Conflagrate', 'spell', { urgent = true }) end
    if ready('Curse of Exhaustion') and dot('Curse of Exhaustion') <= 0 then
      return A('Curse of Exhaustion', 'Mob utika: Curse of Exhaustion (-30 % rychlost)', 'spell', { urgent = true })
    end
    if ready('Death Coil') then return A('Death Coil', 'Mob utika: Death Coil ho zastavi', 'spell', { urgent = true }) end
    if ready('Searing Pain') and not spThreat then return A('Searing Pain', 'Mob utika: rychly Searing Pain', 'spell', { urgent = true }) end
  end
  -- 1d) parta: mob bije healera nebo nekoho slabeho (ty nemas aggro)
  local pt = c.party or {}
  local d = pt.danger
  if s.step == 1 and d and not c.aggro and (d.low or d.healer or d.mobs >= 2) then
    if c.petFamily == 'Voidwalker' then
      return A('PET', ('Mob bije %s: Voidwalker - Torment na neho'):format(d.name), 'hint',
        { icon = 'Interface\\Icons\\Spell_Shadow_GatherShadows', urgent = d.low })
    end
    if (c.petFamily == 'Succubus' or c.petFamily == 'Incubus') and d.mobs == 1 then
      return A('PET', ('Mob bije %s: zamer ho, Seduction od %s'):format(d.name, c.petFamily), 'hint',
        { icon = 'Interface\\Icons\\Spell_Shadow_MindSteal', urgent = d.low })
    end
    if ready('Death Coil') and (d.low or d.healer) then
      return A('Death Coil', ('Mob bije %s: zamer ho a Death Coil (3 s strach)'):format(d.name), 'spell', { urgent = d.low })
    end
  end
  -- 1e) solo: mob u tebe bez Voidwalkera / utikajici mob -> Curse of Exhaustion (kiting)
  if not c.group and c.aggro and ready('Curse of Exhaustion') and dot('Curse of Exhaustion') <= 0 and not tDying
    and ((c.near and c.petFamily ~= 'Voidwalker') or (c.mob and c.mob.flees and c.tLow35)) then
    return A('Curse of Exhaustion', c.near and 'Mob u tebe: Curse of Exhaustion a odstup (kiting)'
      or 'Mob bude utikat: Curse of Exhaustion predem')
  end
  -- 2) parta: strhl jsi aggro
  if s.step == 1 and c.tankUp and c.aggro then
    if c.hpLow50 and ready('Death Coil') then return A('Death Coil', 'Strhl jsi aggro a HP dole: Death Coil', 'spell', { urgent = true }) end
    return A(ns.known('Shoot') and 'Shoot' or filler, 'Strhl jsi aggro: uber (wand), jdi k tankovi, at si ho vezme', 'wait', { urgent = true })
  end
  -- 2b) dungeon: na zacatku pullu nech tanka nabrat aggro
  local tw = db.tankWait or 1.5
  if s.step == 1 and c.tankUp and not c.aggro and c.enemies.onMe == 0 and c.pullAge < tw then
    local left = tw - c.pullAge
    local early = (curse and dot(curse) <= 0 and ready(curse) and curse) or (bane and dot(bane) <= 0 and ready(bane) and bane)
    return A(early or filler,
      ('Nech tanka nabrat aggro (%.1fs)'):format(left), 'wait', { dur = left })
  end
  -- 3) solo: vic mobu u tebe
  if not c.group and c.enemies.near >= 2 and c.enemies.onMe >= 2 and ready('Howl of Terror') and not c.enemies.ccNear then
    return A('Howl of Terror', ('%d mobu u tebe: Howl of Terror'):format(c.enemies.near))
  end
  -- 4) pet umira (solo)
  if not c.group and c.petLow and c.enemies.onMe == 0 and not c.hpLow50 and ready('Health Funnel') and not c.moving then
    return A('Health Funnel', 'Pet umira: Health Funnel (ty mas HP dost)')
  end
  -- 5) mana
  if c.manaKnown and c.mana < 0.2 and tapOK and ready('Life Tap') and not s.used.tap then
    s.used.tap = true
    return A('Life Tap', ('Mana %d%%: Life Tap'):format(math.floor(c.mana * 100)))
  end
  -- 6) AoE (v parte az kdyz tank moby drzi)
  local aoeHold
  if c.tankUp and aoeN >= db.aoe then
    local wait = (db.aoeDelay or 3) - c.pullAge
    if wait > 0 then aoeHold = ('AoE az za %ds (tank sbira aggro)'):format(math.ceil(wait))
    elseif c.enemies.victimKnown and (c.tankMobs or 0) < db.aoe then
      aoeHold = ('AoE az budou moby na tankovi (ma %d)'):format(c.tankMobs or 0)
    end
  end
  if aoeN >= db.aoe and not aoeHold and c.mana > 0.25 then
    -- Hellfire: solo nebo parta BEZ tanka (duo), a jen kdyz neudela vic skody nez uzitku:
    -- dost HP (bez healera vic), moby u tebe a nepadnou hned, zadny CC ani necinny mob v okoli (nepritahne dalsi)
    -- dungeon s tankem: Hellfire jen kdyz vidime threat na VSECH mobech v boji a je nizky,
    -- tank je drzi (zadny na tobe) a pull uz chvili bezi. Kdyz threat vyroste, addon rekne "zrus".
    local e = c.enemies
    if c.tankUp and not aoeHold and e.near >= db.aoe and (e.onMe or 0) == 0 and e.thrKnown > 0
      and e.thrKnown >= e.combat and e.thrMax < 30 and c.php and c.php > 60 and not e.ccNear and (e.cc or 0) == 0
      and (ttd == nil or ttd > 8) and ready('Hellfire') and not s.used.Hellfire then
      s.used.Hellfire = true
      return A('Hellfire', ('Tank drzi %d mobu, tvuj threat max %d%%: Hellfire (pri 80 %% ho addon zrusi)'):format(e.near,
        math.floor(e.thrMax)))
    end
    local hfHP = c.healer and 60 or 70
    if not c.tankUp and c.enemies.near >= 3 and (c.enemies.onMe or 0) >= 2 and c.php and c.php > hfHP
      and not c.enemies.ccNear and (c.enemies.cc or 0) == 0 and (c.enemies.idle or 0) == 0
      and (ttd == nil or ttd > 6) and ready('Hellfire') and not s.used.Hellfire then
      s.used.Hellfire = true
      return A('Hellfire', ('%d mobu u tebe: Hellfire (pali i tebe - pod 35 %% HP ho zrus)'):format(c.enemies.near))
    end
    if can('Rain of Fire') and c.enemies.near == 0 and not c.moving and not s.used['Rain of Fire']
      and (ttd == nil or ttd > 5) then
      s.used['Rain of Fire'] = true
      return A('Rain of Fire', ('%d mobu pohromade: Rain of Fire%s'):format(aoeN, (c.enemies.cc or 0) > 0 and ' - mir mimo ovci!' or ''))
    end
  end
  -- 7) dorazeni
  local dying = c.tLow10 or (c.tLow20 and (ttd == nil or ttd < 4)) or (ttd and ttd < 3)
  if c.tLow20 and c.shards < math.min(db.shardWant or 6, db.shardTrim ~= false and (db.shardMax or 10) or 99) and can('Drain Soul') and not c.moving and not c.boss
    and not c.tPlayer and (ttd == nil or ttd < 15) then
    return A('Drain Soul', ('Dorazit Drain Soulem: shard navic (mas %d)'):format(c.shards))
  end
  if dying then
    if ready('Shadowburn') and c.shards > keep then return A('Shadowburn', 'Dorazit: Shadowburn (instant)') end
    if ready('Conflagrate') and dot('Immolate') > 0 then return A('Conflagrate', 'Dorazit: Conflagrate') end
    if ns.known('Shoot') and c.manaKnown and c.mana < 0.5 and not c.tough then return A('Shoot', 'Skoro mrtvy: wand, setri manu') end
    if ready('Searing Pain') then return A('Searing Pain', 'Dorazit rychlym Searing Pain') end
  end
  -- 8) zaklad: Immolate -> Conflagrate -> znovu Immolate (Conflagrate Immolate spotrebuje)
  if dot('Immolate') <= 1 and ready('Immolate') and not c.moving and (ttd == nil or ttd > 4) then
    return A('Immolate', 'Immolate (pak Conflagrate)')
  end
  if ready('Conflagrate') and dot('Immolate') > 0 then return A('Conflagrate', 'Conflagrate') end
  -- 8b) Shadow and Flame 5/5: Shadowburn vraci shard vzdy a dava +10 % ohen na 20 s -> na cooldown,
  --     ale az po Immolate + Conflagrate a jen na moba, ktery jeste chvili zije. Pod 5/5 shard nevraci
  --     jiste -> Shadowburn jen na dorazeni (viz 7).
  if (ns.talent('Shadow and Flame') or 0) >= 5 and ready('Shadowburn') and c.shards > 0 and not c.tPlayer
    and dot('Immolate') > 0 and ttd and ttd > 6 then
    return A('Shadowburn', 'Shadowburn: +10 % ohen na 20 s a shard zpet (Shadow and Flame 5/5)')
  end
  -- 9) pak DoTy podle toho, kolik stihnou udelat, nez mob padne (vs. filler za stejny cas)
  local fsc = W.scores[filler]
  local fdps = (fsc and fsc.dps) or 90
  local ttdD = ttd or (c.boss and 60) or (c.tough and 40) or 20
  local function dotWorth(n)
    local di = W.dotInfo and W.dotInfo[n]
    if not di then return (ttd == nil or ttd > 12), nil end
    local frac = math.min(1, ttdD / di.dur)
    if di.ramp then frac = frac ^ 1.6 end          -- Agony bije ze zacatku slabe
    local per = di.dmg * frac / math.max(1.5, ns.castTime(n))
    return per >= fdps * 0.9, per
  end
  local corrCT = ns.castTime('Corruption')
  if dot('Corruption') <= 0.5 and ready('Corruption') and not dying and not (c.moving and corrCT > 0.1) then
    local ok, per = dotWorth('Corruption')
    if ok then return A('Corruption', ('Corruption (%s za GCD, filler %d)'):format(per and math.floor(per) or '?', math.floor(fdps))) end
  end
  if bane and dot(bane) <= 0.5 and ready(bane) and not dying then
    local ok, per = dotWorth(bane)
    if ok then return A(bane, ('%s (%s za GCD, filler %d)'):format(bane, per and math.floor(per) or '?', math.floor(fdps))) end
  end
  if dot('Siphon Life') <= 0.5 and ready('Siphon Life') and not dying and select(1, dotWorth('Siphon Life')) then
    return A('Siphon Life', 'Siphon Life')
  end
  -- 10) curse (az po DoTech)
  if curse and dot(curse) <= 0.5 and ready(curse) and not dying
    and (ttd == nil or ttd > (curse == 'Curse of Agony' and 10 or 6)) then
    return A(curse, curse == 'Curse of the Elements' and (c.classes.MAGE and 'Curse of the Elements (+8 % magie, mag v parte bije vic)'
      or 'Curse of the Elements (+8 % magie, delsi boj)') or curse)
  end
  -- 11) Soul Fire na silny cil
  if c.tough and ready('Soul Fire') and c.shards > keep and not c.moving and not c.aggro and (ttd == nil or ttd > 9) then
    return A('Soul Fire', ('Silny cil: Soul Fire (shardu %d)'):format(c.shards))
  end
  -- 12) pohyb: jen instanty
  if c.moving then
    if ready('Conflagrate') and dot('Immolate') > 0 then return A('Conflagrate', 'V pohybu: Conflagrate') end
    if ready('Shadowburn') and c.shards > keep + 1 then return A('Shadowburn', 'V pohybu: Shadowburn') end
    if bane and dot(bane) <= 0.5 and ready(bane) then return A(bane, 'V pohybu: ' .. bane) end
    if dot('Corruption') <= 0.5 and ready('Corruption') and ns.castTime('Corruption') < 0.1 then return A('Corruption', 'V pohybu: Corruption') end
    if c.manaKnown and c.mana < 0.7 and tapOK and ready('Life Tap') and not s.used.tap then
      s.used.tap = true return A('Life Tap', 'V pohybu: Life Tap')
    end
  end
  -- 13) mana
  if c.manaKnown and c.mana < db.wandMana and ns.known('Shoot') then return A('Shoot', ('Mana %d%%: wand'):format(math.floor(c.mana * 100))) end
  if c.manaKnown and c.mana < 0.35 and tapOK and ready('Life Tap') and not s.used.tap then
    s.used.tap = true return A('Life Tap', ('Mana %d%%: Life Tap'):format(math.floor(c.mana * 100)))
  end
  -- 13b) Drain Life na udrzeni HP (bez healera): leci tolik, kolik bije - mene jidla a Life Tap se vyplati
  if not c.healer and not c.instance and c.php and c.php < 55 and not tDying and (ttd == nil or ttd > 5)
    and (dot('Immolate') > 0 or dot('Corruption') > 0)
    and can('Drain Life') and not c.moving and c.inRange ~= false and c.manaKnown and c.mana > 0.15
    and not (c.channel and c.castName == 'Drain Life') then
    return A('Drain Life', ('HP ~%d%%: Drain Life (leci te, usetris jidlo)'):format(math.floor(c.php)))
  end
  -- 14) wand misto filleru: DoTy moba dobiji / hned padne / chybi mana i HP (setri manu, HP a jidlo)
  if ns.known('Shoot') and not c.tough and not c.boss and not c.moving and c.inRange ~= false then
    local dotsUp = dot('Corruption') > 2 or (bane and dot(bane) > 2) or dot('Immolate') > 2
    if dotsUp and (c.tLow35 or (ttd and ttd < 8)) then
      return A('Shoot', 'DoTy ho dobiji - wand (setris manu i HP)')
    end
    if ttd and ttd < 5 then return A('Shoot', 'Mob hned padne - wand, dalsi cast by dopadl na mrtvolu') end
    if c.manaKnown and c.mana < (db.conserveMana or 0.3) and not tapOK then
      return A('Shoot', 'Malo many a HP na Life Tap nestaci - wand')
    end
  end
  if c.inRange == false then return A(filler, 'Cil je mimo dosah - priblizit se') end
  if aoeHold then return A(filler, aoeHold .. ' - zatim ' .. filler) end
  if filler == 'Searing Pain' and c.imm and c.imm.schools.shadow then return A(filler, 'Cil je imunni na stin: Searing Pain') end
  if fillerWhy then return A(filler, filler .. ': ' .. fillerWhy) end
  local sc = W.scores[filler]
  return A(filler, (sc and sc.dps) and ('%s (dlouhy boj: nejvic dmg za sekundu vc. many)'):format(filler) or filler)
end

local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  s.mana = math.max(0, s.mana - ns.cost(n) / ns.manaMax())
  if n == 'Life Tap' then s.mana = math.min(1, s.mana + 0.12) end
  local cd, ct = ns.cdFor(n), ns.castTime(n)
  local dur
  if a.kind == 'wait' then dur = a.dur or 1.5
  elseif ns.CHANNEL[n] then dur = ns.CHANNEL[n]
  elseif ns.OFF_GCD[n] then dur = 0
  else dur = math.max(1.5, ct) end
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  if not c.inCombat then s.used[n] = true end
  if DOT[n] then
    if CURSE[n] then for k in pairs(CURSE) do s.dots[k] = 0 end end
    if BANE[n] then for k in pairs(BANE) do s.dots[k] = 0 end end
    s.dots[n] = s.t + ct + DOT[n]
  end
  if n == 'Conflagrate' and (ns.talent('Shadow and Flame') or 0) < 5 then s.dots.Immolate = 0 end
  s.t = s.t + dur
end

local TRACK = { 'Conflagrate', 'Shadowburn', 'Death Coil', 'Howl of Terror', 'Soul Fire', 'Shadow Ward', 'Amplify Curse',
  'Fel Domination', 'Curse of Doom' }

function E.plan(c)
  local s = { t = 0, mana = c.mana, cd = {}, used = {}, step = 1, dots = {} }
  for _, n in ipairs(TRACK) do if ns.known(n) then s.cd[n] = ns.cdLeft(n) end end
  for n, left in pairs(c.dots or {}) do if left > 0 then s.dots[n] = left end end
  if c.castName and not c.channel then
    s.t = c.castLeft
    if DOT[c.castName] then s.dots[c.castName] = c.castLeft + DOT[c.castName] end
  end
  s.t = math.max(s.t, c.gcd)
  local startT = s.t
  local plan = {}
  for step = 1, 3 do
    s.step = step
    local a = decide(c, s)
    if not a then break end
    a.at = s.t
    plan[#plan + 1] = a
    apply(c, s, a)
  end
  if plan[1] and ns.Mem then plan[1] = ns.Mem.swap(c, plan[1]) end
  if plan[1] then plan[1].wait = startT end

  ---------------- mimo GCD / predmety / tipy
  local util
  if c.inCombat and c.hostile then
    -- v nebezpeci = mob na tobe (i kdyz neni tvuj cil), nebo HP uz hodne dole (DoT, AoE)
    local danger = c.aggro or (c.enemies.onMe or 0) > 0 or ns.hpBelow('player', 25) == true
    local lowHP = danger and ns.hpBelow('player', c.db.potionHP)
    -- Healthstone je zdarma a ma vlastni cooldown: pouzij ho driv nez potion (do 40 % HP)
    local lowStone = danger and ns.hpBelow('player', math.max(40, c.db.potionHP or 30))
    local hs = ns.Bags.best('stone')
    if hs and lowStone and ns.itemReady(hs, 'stone', 120) then util = A('item:' .. hs, 'Healthstone! (zdarma, pred potionem)', 'item', { item = hs, urgent = true }) end
    local hp = ns.Bags.best('hpot')
    if not util and hp and lowHP and ns.itemReady(hp, 'potion', 120) then
      util = A('item:' .. hp, 'Healing Potion!', 'item', { item = hp, urgent = true })
    end
    local ag = ns.Bags.best('defense')
    if not util and ag and lowHP and ns.itemReady(ag, 'defense', 60) then
      util = A('item:' .. ag, 'Nouzova obrana', 'item', { item = ag, urgent = true })
    end
    -- pet umrel v boji: Fel Domination = rychle vyvolani
    if not util and not c.pet and ns.known('Fel Domination') and ns.cdLeft('Fel Domination') <= 0 then
      util = A('Fel Domination', 'Pet padl: Fel Domination a hned novy pet')
    end
    -- pet: preruseni / tank
    local kw, kwhy = 'yes', nil
    if c.tCasting and ns.kickWorth then kw, kwhy = ns.kickWorth(c) end
    if not util and c.petFamily == 'Felhunter' and c.tCasting and c.interruptible and kw ~= 'save' then
      local ks = c.group and ns.Party and ns.Party.kickState() or nil
      local myK
      if ks then for _, k in ipairs(ks.list) do if k.me then myK = k end end end
      if ks and ks.justKicked then
        -- nekdo prave prerusil
      elseif myK and not myK.ready then
        -- Spell Lock je na cooldownu
      elseif ks and ks.claimedBy and c.tCastAge < 1.5 then
        util = A('PET', ('Interrupt: %s prave prerusuje, Spell Lock si drz'):format(ks.claimedBy), 'hint',
          { icon = 'Interface\\Icons\\Spell_Shadow_MindRot' })
      elseif ks and ks.others and ks.nextUp and not ks.nextUp.me and c.tCastAge < (kw == 'urgent' and 0.4 or 0.8) then
        util = A('PET', ('Interrupt: na rade je %s (%s), Spell Lock si drz'):format(ks.nextUp.name, ks.nextUp.spell), 'hint',
          { icon = 'Interface\\Icons\\Spell_Shadow_MindRot' })
      else
        if ks and ks.others and ns.Duo then ns.Duo.claimKick() end
        util = A('PET', ((ks and ks.others) and 'Interrupt: TED TY - Felhunter Spell Lock!' or 'Felhunter: Spell Lock - preruse kouzlo!')
          .. (kwhy and (' ' .. kwhy) or ''), 'hint', { icon = 'Interface\\Icons\\Spell_Shadow_MindRot', urgent = true })
      end
    end
    -- pet: nebije (nema cil), Voidwalker Sacrifice v nouzi
    if not util and c.pet and c.inCombat and c.hostile and (c.pullAge or 0) > 2.5 and not c.targetCC
      and safeBool(pc(UnitExists, 'pettarget')) == false then
      util = A('PET', 'Pet nebije: posli ho na cil (pet Attack)', 'hint', { icon = 'Interface\\Icons\\Ability_GhoulFrenzy' })
    end
    if not util and c.petFamily == 'Voidwalker' and c.aggro and c.php and c.php < 25 and not c.healer then
      util = A('PET', 'Mas malo HP: Voidwalker - Sacrifice (stit, pet zmizi)', 'hint',
        { icon = 'Interface\\Icons\\Spell_Shadow_SacrificialShield', urgent = true })
    end
    if not util and c.petFamily == 'Voidwalker' and not c.group and c.aggro and c.near then
      util = A('PET', 'Voidwalker: Torment - at si moba vezme', 'hint', { icon = 'Interface\\Icons\\Spell_Shadow_GatherShadows' })
    end
    if not util and plan[1] and (plan[1].name == 'Curse of Agony' or plan[1].name == 'Bane of Agony')
      and ns.known('Amplify Curse') and ns.cdLeft('Amplify Curse') <= 0 then
      util = A('Amplify Curse', 'Amplify Curse pred ' .. plan[1].name)
    end
    -- Bane of Havoc: 15 % tveho dmg na druheho moba (vydrzi 5 min) - na delsi boj s vic moby
    if not util and ns.known('Bane of Havoc') and c.enemies.combat >= 2 and longFight(c)
      and GetTime() - (W.havocAt or -999) > 60 and not c.enemies.ccNear then
      util = A('Bane of Havoc', 'Vic mobu: Bane of Havoc na DRUHEHO moba (focus/mouseover), pak bij hlavni', 'hint')
    end
    if not util and c.enemies.moonLoose then
      if c.petFamily == 'Succubus' or c.petFamily == 'Incubus' then
        util = A('PET', 'Mesic se probral: zamer ho, Seduction znovu', 'hint', { icon = 'Interface\\Icons\\Spell_Shadow_MindSteal' })
      elseif ns.known('Banish') and ns.cdLeft('Banish') <= 0 then
        util = A('Banish', 'Mesic se probral: zamer ho a Banish (jen demon/elemental)', 'hint')
      end
    end
    local pt = c.party or {}
    if not util and pt.magic and not c.aggro then
      util = A('PET', ('Magicky debuff na %s: Felhunter - Devour Magic (cil: %s)'):format(pt.magic.name, pt.magic.name), 'hint',
        { icon = 'Interface\\Icons\\Spell_Nature_Purge' })
    end
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
    if not util and c.offTank and not c.aggro then
      util = A('TARGET', ('Tank (%s) bije jiny cil - prepni na jeho cil'):format(c.tankName or 'tank'), 'hint',
        { icon = 'Interface\\Icons\\Ability_Warrior_DefensiveStance' })
    end
    local mp = ns.Bags.best('mpot')
    if not util and mp and c.manaKnown and c.mana < 0.2 and c.hpLow50 and (c.tough or c.instance) and ns.itemReady(mp, 'potion', 120) then
      util = A('item:' .. mp, 'Mana potion (na Life Tap uz nemas HP)', 'item', { item = mp })
    end
  end
  return plan, util
end

-- Radek do panelu: shardy, pet, DoTy
function E.infoLine(c)
  local p = {}
  local keep = c.db.shardKeep or 3
  p[#p + 1] = ((c.shards or 0) <= keep and '|cffffcc00' or '|cffc080ff') .. 'Shardy ' .. (c.shards or 0) .. '|r'
  if c.pet then
    p[#p + 1] = (c.petLow and '|cffff7070' or '|cff9aa6b8') .. (c.petFamily or 'pet') .. (c.petLow and ' umira' or '') .. '|r'
  else
    p[#p + 1] = '|cffff7070bez peta|r'
  end
  if c.hostile then
    local d = {}
    local SHORT = { Immolate = 'Imm', Corruption = 'Corr', ['Siphon Life'] = 'SL', ['Bane of Agony'] = 'BoA', ['Bane of Doom'] = 'BoD',
      ['Bane of Havoc'] = 'Havoc' }
    for _, n in ipairs({ 'Immolate', 'Bane of Agony', 'Bane of Doom', 'Bane of Havoc', 'Corruption', 'Siphon Life' }) do
      local l = c.dots[n] or 0
      if l > 0 then d[#d + 1] = ('%s %ds'):format(SHORT[n], math.ceil(l)) end
    end
    for n in pairs(CURSE) do
      local l = c.dots[n] or 0
      if l > 0 then d[#d + 1] = ('%s %ds'):format(n:gsub('Curse of ', 'Co'):gsub('the ', ''):sub(1, 6), math.ceil(l)) end
    end
    if #d > 0 then p[#p + 1] = '|cff7fd8ff' .. table.concat(d, ' ') .. '|r' end
  end
  if ns.Bags.count('stone') == 0 then p[#p + 1] = '|cffffcc00bez Healthstone|r' end
  return table.concat(p, '  |cff556070-|r  ')
end


------------------------------------------------------------------------------------------
-- Soul shardy nad maximum: mimo boj zahodit (nastaveni: shardTrim, shardMax; vychozi 10)
------------------------------------------------------------------------------------------
local trimQueued, trimWarned = false, false
local function shardSlots()
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local out, total = {}, 0
  if not (getNum and getInfo) then return out, 0 end
  for bag = 0, 5 do
    for slot = 1, safeNum(pc(getNum, bag)) or 0 do
      local info = pc(getInfo, bag, slot)
      local link = type(info) == 'table' and safe(info.hyperlink)
      if type(link) == 'string' and (safeNum(info.itemID) == 6265 or link:find('%[Soul Shard%]')) then
        local n = safeNum(info.stackCount) or 1
        out[#out + 1] = { bag = bag, slot = slot, n = n }
        total = total + n
      end
    end
  end
  return out, total
end
function W.trimShards()
  local db = ns.db
  if not db or db.shardTrim == false then return end
  if InCombatLockdown() or ns.inCombat() or (CursorHasItem and CursorHasItem()) then return end
  local max = db.shardMax or 10
  local slots, total = shardSlots()
  local excess = total - max
  if excess <= 0 then return end
  local s = slots[#slots]   -- od posledniho slotu (nejspis v Soul Bagu az na konci)
  local pick = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  local split = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
  local ok
  if s.n > excess and split then ok = pcall(split, s.bag, s.slot, excess)
  else ok = pcall(pick, s.bag, s.slot) end
  if ok and CursorHasItem and CursorHasItem() then ok = pcall(DeleteCursorItem) end
  if CursorHasItem and CursorHasItem() then   -- hra mazani nedovolila: vratit a rict hraci
    if ClearCursor then ClearCursor() end
    if not trimWarned then
      trimWarned = true
      ns.say(('Mas %d soul shardu (max %d) - zahodit je automaticky hra nedovolila, zahod je rucne.'):format(total, max))
    end
    return
  end
  if ok then
    ns.say(('Soul shardy: zahozeno %d (mas %d, max %d - zmenis v /cm config)'):format(math.min(excess, s.n), total - math.min(excess, s.n), max))
    if C_Timer then C_Timer.After(0.6, function() pcall(W.trimShards) end) end
  end
end
local tq = CreateFrame('Frame')
for _, e in ipairs({ 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED', 'PLAYER_ENTERING_WORLD' }) do pcall(tq.RegisterEvent, tq, e) end
tq:SetScript('OnEvent', function()
  if trimQueued or not C_Timer then return end
  trimQueued = true
  C_Timer.After(1.5, function() trimQueued = false pcall(W.trimShards) end)
end)

-- ClaudeMaster: rozhodovaci logika pro Druida (univerzalni: caster / lecitel / medved / kocka).
-- Pouziva spolecny kontext (Frost.lua: cil, moby, parta, mana...) a pridava druidske veci:
-- forma (medved / kocka / caster), Moonfire a Insect Swarm na cili (z vlastnich castu, aury jsou
-- v boji skryte), Mark of the Wild / Thorns na sobe i na parte (mimo boj), leceni sebe a party.
local ADDON, ns = ...
if not ns.enabled or ns.class ~= 'DRUID' then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = ns.Engine
local DR = {}
ns.Druid = DR

local FORMS = { ['Bear Form'] = 'bear', ['Dire Bear Form'] = 'bear', ['Cat Form'] = 'cat', ['Travel Form'] = 'travel',
  ['Aquatic Form'] = 'aquatic', ['Moonkin Form'] = 'moonkin', ['Flight Form'] = 'travel', ['Swift Flight Form'] = 'travel' }
local DOTS = { Moonfire = 12, ['Insect Swarm'] = 12, Rake = 9, Rip = 12, ['Faerie Fire'] = 40, ['Faerie Fire (Feral)'] = 40,
  ['Demoralizing Roar'] = 30, ['Entangling Roots'] = 12, Lacerate = 15 }
local HOTS = { Rejuvenation = 12, Regrowth = 21 }

-- Aktualni forma: 'bear' / 'cat' / 'travel' / 'aquatic' / 'moonkin' / nil (caster)
local function form()
  local n = safeNum(pc(GetShapeshiftForm)) or 0
  if n == 0 then return nil end
  local _, active, _, id = pc(GetShapeshiftFormInfo, n)
  id = safeNum(id)
  local name = id and C_Spell and C_Spell.GetSpellName and safe(pc(C_Spell.GetSpellName, id))
  if type(name) == 'string' and FORMS[name] then return FORMS[name] end
  -- nezname jmeno: medved je na Foreveru obvykle prvni forma
  return n == 1 and 'bear' or 'other'
end
DR.form = form

-- DoTy a debuffy na cili z vlastnich castu (podle tokenu cile: po prepnuti cile neplati)
DR.onTarget = {}   -- name -> { tok, untilT }
DR.hotOn = {}      -- name -> { unit, untilT }
local f = CreateFrame('Frame')
pcall(f.RegisterUnitEvent, f, 'UNIT_SPELLCAST_SUCCEEDED', 'player')
pcall(f.RegisterUnitEvent, f, 'UNIT_SPELLCAST_SENT', 'player')
-- na koho sel heal (SENT nese jmeno cile) -> jednotka party
local function unitByName(name)
  if type(name) ~= 'string' or name == '' or name == safe(pc(UnitName, 'player')) then return 'player' end
  for i = 1, 4 do
    local u = 'party' .. i
    if safe(pc(UnitName, u)) == name then return u end
  end
  return 'player'
end
f:SetScript('OnEvent', function(_, ev, _, a2, a3, a4)
  if ev == 'UNIT_SPELLCAST_SENT' then
    -- (unit, targetName, castGUID, spellID)
    DR.lastHealUnit = unitByName(safe(a2))
    return
  end
  local spellID = a3   -- SUCCEEDED: (unit, castGUID, spellID)
  local n = ns.nameOf and ns.nameOf(safeNum(spellID) or 0)
  if not n then return end
  local now = GetTime()
  if DOTS[n] then DR.onTarget[n] = { tok = ns.T and ns.T.token, untilT = now + DOTS[n] } end
  if HOTS[n] then DR.hotOn[n .. ':' .. (DR.lastHealUnit or 'player')] = now + HOTS[n] end
  -- Swiftmend spotrebuje HoT
  if n == 'Swiftmend' then
    local u = DR.lastHealUnit or 'player'
    if (DR.hotOn['Rejuvenation:' .. u] or 0) > now then DR.hotOn['Rejuvenation:' .. u] = nil
    else DR.hotOn['Regrowth:' .. u] = nil end
  end
end)
local function dotLeft(n)
  local e = DR.onTarget[n]
  if not e or e.tok ~= (ns.T and ns.T.token) then return 0 end
  return math.max(0, e.untilT - GetTime())
end
local function hotLeft(n, unit)
  return math.max(0, (DR.hotOn[n .. ':' .. (unit or 'player')] or 0) - GetTime())
end

-- Specializace podle talentu (strom = sloupec v talentech Foreveru), /cm druid resto|balance|feral|auto
local TREE = {
  resto = { 'Improved Tranquility', 'Wild Growth', 'Living Spirit', 'Swiftmend', 'Improved Regrowth', 'Improved Rejuvenation',
    'Tranquil Spirit', 'Gift of Nature', 'Subtlety', 'Bloom', 'Natural Shapeshifter', 'Reflection', "Nature's Swiftness",
    'Naturalist', "Nature's Focus", 'Heart of the Wild' },
  balance = { 'Improved Wrath', 'Genesis', 'Moonglow', 'Improved Entangling Roots', "Nature's Majesty", "Nature's Splendor",
    "Nature's Reach", 'Insect Swarm', 'Improved Moonfire', 'Vengeance', 'Improved Starfire', "Nature's Grace", 'Eclipse',
    'Moonfury', 'Moonkin Form', 'Overgrowth' },
  feral = { 'Ferocity', 'Furor', 'Feral Instinct', 'Brutal Impact', 'Thick Hide', 'Feral Swiftness', 'Feral Charge',
    'Shredding Attacks', 'Sharpened Claws', 'Blood Frenzy', 'Savage Fury', 'Lacerate', 'Natural Instinct',
    'Predatory Discipline', 'Predatory Strikes', 'Rend and Tear', 'Natural Reaction', 'Leader of the Pack', 'Primal Bite',
    'Shifting Power' },
}
function DR.spec()
  local pref = ns.db and ns.db.druidSpec
  if pref and TREE[pref] then return pref end
  local best, bestN = nil, 0
  for k, list in pairs(TREE) do
    local n = 0
    for _, t in ipairs(list) do n = n + (ns.talent and ns.talent(t) or 0) end
    if n > bestN then best, bestN = k, n end
  end
  return best   -- nil = zatim zadne talenty
end

-- Buff na jednotce mimo boj (index scan): true / false / nil (v boji nebo nejde cist)
local function unitBuff(u, names)
  if ns.inCombat() then return nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get or not UnitExists(u) then return nil end
  for i = 1, 40 do
    local ok, a = pcall(get, u, i, 'HELPFUL')
    if not ok then return nil end
    if type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) == 'string' then
      for _, w in ipairs(names) do if n == w then return true end end
    end
  end
  return false
end
-- ma unit neco, co umim odstranit (filtr RAID = jen co ja dispellnu)?
local function dispellable(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, 1, 'HARMFUL|RAID')
  if not ok then return nil end
  if a ~= nil then return true end
  return not ns.inCombat() and false or nil
end
local function cureSpell()
  for _, n in ipairs({ 'Abolish Poison', 'Cure Poison', 'Remove Curse' }) do if ns.known(n) then return n end end
end
local function rage()
  return safeNum(pc(UnitPower, 'player', 1))
end
local function energy()
  return safeNum(pc(UnitPower, 'player', 3))
end
local function combo()
  local c = safeNum(pc(UnitPower, 'player', 4))
  if c == nil and GetComboPoints then c = safeNum(pc(GetComboPoints, 'player', 'target')) end
  return c
end
local function bestHeal(urgent, php)
  -- nouze: Regrowth (velky okamzity heal + HoT), jinak Healing Touch; Rejuvenation na pomale doleceni
  if urgent and ns.known('Regrowth') then return 'Regrowth' end
  if ns.known('Healing Touch') then return 'Healing Touch' end
  return ns.known('Regrowth') and 'Regrowth' or nil
end

------------------------------------------------------------------------------------------
-- Kontext
------------------------------------------------------------------------------------------
local baseContext = E.context
E.context = function()
  local c = baseContext()
  c.form = form()
  c.rage, c.energy, c.combo = rage(), energy(), combo()
  c.healerUp = false
  for _, m in ipairs((c.party and c.party.members) or {}) do
    if m.healer and m.alive and not m.unit:find('pet') then c.healerUp = true end
  end
  c.spec = DR.spec()
  c.resto = c.spec == 'resto'
  c.mf = dotLeft('Moonfire')
  c.is = dotLeft('Insect Swarm')
  local function inR(n)
    local id = ns.id(n)
    if not id or not c.hostile or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    return safeBool(pc(C_Spell.IsSpellInRange, id, 'target'))
  end
  c.castR = inR('Wrath')
  if c.castR == nil then c.castR = inR('Moonfire') end
  local m = inR('Maul')
  if m == nil then m = inR('Claw') end
  if m ~= nil and (c.form == 'bear' or c.form == 'cat') then c.near = m end
  -- buffy (mimo boj): Mark of the Wild, Thorns
  c.motw = unitBuff('player', { 'Mark of the Wild', 'Gift of the Wild' })
  c.thorns = unitBuff('player', { 'Thorns' })
  return c
end

------------------------------------------------------------------------------------------
-- Rozhodnuti pro jeden krok
------------------------------------------------------------------------------------------
local function A(name, reason, kind, extra)
  local a = { name = name, reason = reason, kind = kind or 'spell' }
  if extra then for k, v in pairs(extra) do a[k] = v end end
  return a
end

-- Resto: koho lecit. Ty + parta (bez petu). HP pres hpBelow (v boji odhad), partak s addonem posila presne.
local function below(u, x)
  if u ~= 'player' and ns.Duo and ns.Duo.hpOf then
    local h = ns.Duo.hpOf(u)
    if h then return h < x end
  end
  return ns.hpBelow(u, x) == true
end
local function healTargets(c)
  local t = { { unit = 'player', name = 'ty', mobs = (c.enemies and c.enemies.onMe) or 0 } }
  local tank = c.party and c.party.tank
  for _, m in ipairs((c.party and c.party.members) or {}) do
    if m.alive and not m.unit:find('pet') and safeBool(pc(UnitIsConnected, m.unit)) ~= false then
      t[#t + 1] = { unit = m.unit, name = m.name or '?', mobs = m.mobs or 0, tank = m == tank }
    end
  end
  return t
end
-- jeden krok leceni pro resto (nil = nikoho neni treba lecit)
local function restoHeal(c, s, ready)
  local list = healTargets(c)
  local function inRange(u)
    if u == 'player' then return true end
    local id = ns.id('Rejuvenation')
    local r = id and C_Spell and C_Spell.IsSpellInRange and safeBool(pc(C_Spell.IsSpellInRange, id, u))
    return r ~= false
  end
  local function who(m) return m.unit == 'player' and 'sebe' or m.name end
  -- 1) nekdo umira
  for _, m in ipairs(list) do
    if below(m.unit, 35) and inRange(m.unit) then
      local hot = hotLeft('Rejuvenation', m.unit) > s.t or hotLeft('Regrowth', m.unit) > s.t
      if hot and ready('Swiftmend') then
        s.used.Swiftmend = true
        return A('Swiftmend', ('%s umira: Swiftmend (spotrebuje HoT)'):format(m.name), 'spell', { unit = m.unit, urgent = true })
      end
      if below(m.unit, 25) and ready("Nature's Swiftness") then
        return A("Nature's Swiftness", ("%s umira: Nature's Swiftness + Healing Touch"):format(m.name), 'spell', { urgent = true })
      end
      local h = (hotLeft('Regrowth', m.unit) <= s.t and ready('Regrowth')) and 'Regrowth' or (ready('Healing Touch') and 'Healing Touch')
      if h then
        s.used[h .. m.unit] = true
        return A(h, ('%s ma malo HP: %s na %s'):format(m.name, h, who(m)), 'spell', { unit = m.unit, urgent = true })
      end
    end
  end
  -- 2) vic lidi zranenych: Wild Growth / Tranquility
  local hurt = 0
  for _, m in ipairs(list) do if below(m.unit, 75) then hurt = hurt + 1 end end
  if hurt >= 3 and ready('Wild Growth') then return A('Wild Growth', ('%d zranenych: Wild Growth'):format(hurt)) end
  if hurt >= 3 and c.inCombat and ready('Tranquility') and #list >= 4 then
    local bad = 0
    for _, m in ipairs(list) do if below(m.unit, 45) then bad = bad + 1 end end
    if bad >= 3 then return A('Tranquility', ('%d lidi pod 45 %%: Tranquility'):format(bad), 'spell', { urgent = true }) end
  end
  -- 3) stredne zraneny: Regrowth (velky heal + HoT), pod 50 % i bez HoTu Healing Touch
  for _, m in ipairs(list) do
    if below(m.unit, 60) and inRange(m.unit) and not s.used['Regrowth' .. m.unit] then
      if hotLeft('Regrowth', m.unit) <= s.t and ready('Regrowth') then
        s.used['Regrowth' .. m.unit] = true
        return A('Regrowth', ('%s pod 60 %%: Regrowth'):format(m.name), 'spell', { unit = m.unit })
      end
      if below(m.unit, 50) and ready('Healing Touch') and not s.used['Healing Touch' .. m.unit] then
        s.used['Healing Touch' .. m.unit] = true
        return A('Healing Touch', ('%s pod 50 %%: Healing Touch'):format(m.name), 'spell', { unit = m.unit })
      end
    end
  end
  -- 4) Rejuvenation: tank / kdo dostava rany, a kdo je pod 85 %
  for pass = 1, 2 do
    for _, m in ipairs(list) do
      local want = (pass == 1 and c.inCombat and (m.tank or m.mobs > 0) and below(m.unit, 95)) or (pass == 2 and below(m.unit, 85))
      if want and inRange(m.unit) and hotLeft('Rejuvenation', m.unit) <= s.t and ready('Rejuvenation') and not s.used['Rejuvenation' .. m.unit] then
        s.used['Rejuvenation' .. m.unit] = true
        return A('Rejuvenation', ('%s: Rejuvenation (HoT)'):format(m.name), 'spell', { unit = m.unit })
      end
    end
  end
  return nil
end

local function decide(c, s)
  local db = c.db
  local function bad(n) return c.imm ~= nil and ns.Immune.bad(c.imm, n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if ns.cost(n) > 0 and (c.form == nil or c.form == 'moonkin') and s.mana * ns.manaMax() < ns.cost(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  local php = c.php or 100
  local town = c.resting and not c.hostile
  local fm = s.form
  local caster = fm == nil or fm == 'moonkin'

  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end
  -- cestovni / vodni forma: nic neradit
  if fm == 'travel' or fm == 'aquatic' then return nil end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    if caster and c.resto and c.group and not c.drinking and not c.eating and (not c.manaKnown or c.mana > 0.25) then
      local h = restoHeal(c, s, ready)
      if h then return h end
    end
    if caster then
      -- Mark of the Wild / Thorns na sobe
      if c.motw == false and not s.used.motw and ready('Mark of the Wild') then
        s.used.motw = true
        return A('Mark of the Wild', 'Chybi Mark of the Wild', 'spell', { unit = 'player' })
      end
      -- ... a na parte (buffy spoluhracu jdou mimo boj cist)
      if not town and not s.used.motwP and ready('Mark of the Wild') then
        for _, m in ipairs((c.party and c.party.members) or {}) do
          if m.alive and not m.unit:find('pet') and safeBool(pc(UnitIsConnected, m.unit)) ~= false
            and unitBuff(m.unit, { 'Mark of the Wild', 'Gift of the Wild' }) == false then
            s.used.motwP = true
            return A('Mark of the Wild', ('%s nema Mark of the Wild'):format(m.name or '?'), 'spell', { unit = m.unit })
          end
        end
      end
      if c.thorns == false and not town and not s.used.thorns and ready('Thorns') then
        s.used.thorns = true
        return A('Thorns', 'Chybi Thorns (melee moby se zrani samy)', 'spell', { unit = 'player' })
      end
      -- jed / prokleti: Cure Poison / Remove Curse
      local cure = cureSpell()
      if cure and ready(cure) then
        if dispellable('player') then return A(cure, 'Mas na sobe jed/prokleti: ' .. cure, 'spell', { unit = 'player' }) end
        for _, m in ipairs((c.party and c.party.members) or {}) do
          if m.alive and not m.unit:find('pet') and dispellable(m.unit) then
            return A(cure, ('%s ma jed/prokleti: %s'):format(m.name or '?', cure), 'spell', { unit = m.unit })
          end
        end
      end
      -- leceni party (nikdo jiny neleci)
      for _, m in ipairs((c.party and c.party.members) or {}) do
        if m.alive and m.low and not m.unit:find('pet') and not c.healerUp and not s.used.heal then
          local h = (hotLeft('Rejuvenation', m.unit) <= 0 and ready('Rejuvenation')) and 'Rejuvenation' or bestHeal(false)
          if h and ready(h) then
            s.used.heal = true
            return A(h, ('%s ma malo HP - %s'):format(m.name or '?', h), 'spell', { unit = m.unit })
          end
        end
      end
      -- vlastni HP: kouzlo je levnejsi nez cekat na jidlo, kdyz je many dost
      if s.step == 1 and php < 70 and not c.eating and not c.drinking and (not c.manaKnown or c.mana > 0.45) then
        local h = (php > 50 and hotLeft('Rejuvenation', 'player') <= 0 and ready('Rejuvenation')) and 'Rejuvenation' or bestHeal(false)
        if h and ready(h) then
          s.used.heal = true
          return A(h, ('HP ~%d%%: %s (mana se doplni pitim)'):format(math.floor(php), h), 'spell', { unit = 'player' })
        end
      end
    end
    if s.step == 1 and not c.eating and php < 50 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(php)), 'item', { item = fd }) end
    end
    if s.step == 1 and c.manaKnown and c.mana < (db.drinkMana or 0.55) and not c.drinking and not c.hostile and caster then
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
    end
    if c.drinking or c.eating then return nil end
    if c.hostile then
      if fm == 'bear' then return A('Attack', c.near and 'Utoc (medved)' or 'Pull: dojdi k cili', 'wait') end
      if fm == 'cat' then
        if ready('Prowl') and not s.used.prowl then s.used.prowl = true return A('Prowl', 'Pred pullem: Prowl (plizeni)') end
        if c.near and ready('Ravage') then return A('Ravage', 'Opener: Ravage') end
        if c.near and ready('Pounce') then return A('Pounce', 'Opener: Pounce (stun)') end
        return A('Attack', c.near and 'Utoc (kocka)' or 'Pull: dojdi k cili', 'wait')
      end
      -- caster: pull dlouhym kouzlem (castujes jeste mimo boj), pak Moonfire
      if c.castR ~= false then
        if ready('Starfire') and not s.used.pull then s.used.pull = true return A('Starfire', 'Pull: Starfire') end
        if ready('Wrath') and not s.used.pull then s.used.pull = true return A('Wrath', 'Pull: Wrath') end
        if ready('Moonfire') then return A('Moonfire', 'Pull: Moonfire') end
      end
      return A('Attack', 'Pull: dojdi na dosah kouzel', 'wait')
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  local danger = c.aggro or (c.enemies.onMe or 0) > 0
  local aoe = c.enemies.cluster or c.enemies.combat or 0

  ---------------- medved
  if fm == 'bear' then
    -- malo HP a nikdo neleci: vyjdi z formy a vylec se
    if s.step == 1 and php < 30 and not c.healerUp and c.manaKnown and c.mana > 0.25 and ready('Bear Form') and bestHeal(true) then
      s.form = nil
      return A('Bear Form', 'Malo HP: vyjdi z medveda (klik) a vylec se', 'spell', { urgent = true })
    end
    if php < 40 and ready('Frenzied Regeneration') then
      return A('Frenzied Regeneration', 'Malo HP: Frenzied Regeneration', 'spell', { urgent = true })
    end
    if not c.hostile then return nil end
    if c.tCasting and c.interruptible and c.near and ready('Bash') then
      s.used.Bash = true
      return A('Bash', 'Mob kouzli: Bash (stun = preruseni)', 'spell', { urgent = true })
    end
    -- v parte: mob nebije tebe -> Growl
    if c.group and not c.aggro and not c.tankUp and ready('Growl') then return A('Growl', 'Mob nebije tebe: Growl') end
    if (c.rage or 0) < 10 and ready('Enrage') and c.near then return A('Enrage', 'Malo rage: Enrage') end
    if dotLeft('Demoralizing Roar') <= s.t + 2 and ready('Demoralizing Roar') and c.near and (danger or aoe >= 2)
      and not s.used.demo and (c.rage == nil or c.rage >= 10) then
      s.used.demo = true
      return A('Demoralizing Roar', 'Demoralizing Roar (moby bijou slabeji)')
    end
    if aoe >= 2 and c.near and ready('Swipe') and (c.rage == nil or c.rage >= 20) then
      return A('Swipe', ('%d moby: Swipe'):format(aoe))
    end
    if c.near and ready('Lacerate') and dotLeft('Lacerate') <= s.t + 3 and (c.rage == nil or c.rage >= 15) and not s.used.Lacerate then
      s.used.Lacerate = true
      return A('Lacerate', 'Lacerate (krvaceni)')
    end
    if c.near and ready('Maul') and not s.used.Maul and (c.rage == nil or c.rage >= 15) then
      s.used.Maul = true
      return A('Maul', 'Maul (silnejsi pristi uder)')
    end
    if not c.near then return A('Attack', 'Dojdi k cili (medved)', 'wait', { dur = 1.5 }) end
    return A('Attack', 'Auto attack, sbirej rage', 'wait', { dur = 1.5 })
  end

  ---------------- kocka
  if fm == 'cat' then
    if not c.hostile then return nil end
    if php < 30 and not c.healerUp and c.manaKnown and c.mana > 0.25 and ready('Cat Form') and bestHeal(true) then
      s.form = nil
      return A('Cat Form', 'Malo HP: vyjdi z kocky (klik) a vylec se', 'spell', { urgent = true })
    end
    if not c.near then return A('Attack', 'Dojdi k cili (kocka)', 'wait', { dur = 1.5 }) end
    local cp = (c.combo or 0) + (s.cp or 0)
    local en = c.energy
    if cp >= 5 or (cp >= 3 and c.tLow20) then
      if ready('Rip') and not c.tLow20 and (c.ttd == nil or c.ttd > 10) and dotLeft('Rip') <= s.t then
        s.cp = -(c.combo or 0) return A('Rip', ('%d combo: Rip'):format(cp))
      end
      if ready('Ferocious Bite') then s.cp = -(c.combo or 0) return A('Ferocious Bite', ('%d combo: Ferocious Bite'):format(cp)) end
    end
    if ready("Tiger's Fury") and (en == nil or en >= 60) and not s.used.tf then s.used.tf = true return A("Tiger's Fury", "Tiger's Fury") end
    if ready('Rake') and dotLeft('Rake') <= s.t and (c.ttd == nil or c.ttd > 6) and not s.used.Rake then
      s.used.Rake = true s.cp = (s.cp or 0) + 1
      return A('Rake', 'Rake (krvaceni)')
    end
    if ready('Shred') and not c.aggro and c.group then s.cp = (s.cp or 0) + 1 return A('Shred', 'Shred (jsi za zady)') end
    if ready('Claw') then s.cp = (s.cp or 0) + 1 return A('Claw', 'Claw (combo body)') end
    return A('Attack', 'Auto attack, cekej na energii', 'wait', { dur = 1 })
  end

  ---------------- caster (vcetne moonkina)
  -- resto v parte: nejdriv leceni (ty i parta), DPS jen kdyz je vsichni v poradku a many dost
  if c.resto and c.group then
    local h = restoHeal(c, s, ready)
    if h then return h end
    if php < 35 and danger and ready('Barkskin') then
      return A('Barkskin', 'Malo HP: Barkskin (mene damage, cast se neprerusuje)', 'spell', { urgent = true })
    end
    if c.manaKnown and s.mana < 0.5 then
      return A('Attack', 'Setri manu na leceni (vsichni v poradku)', 'wait', { dur = 1.5 })
    end
  end
  -- nouze
  if php < 35 and not c.healerUp then
    if php < 25 and danger and ready('Barkskin') then
      return A('Barkskin', 'Malo HP: Barkskin (mene damage, cast se neprerusuje)', 'spell', { urgent = true })
    end
    if ready("Nature's Swiftness") and php < 25 then
      return A("Nature's Swiftness", "Umiras: Nature's Swiftness + Healing Touch", 'spell', { urgent = true })
    end
    local h = (hotLeft('Regrowth', 'player') <= s.t and ready('Regrowth')) and 'Regrowth' or bestHeal(false)
    if h and ready(h) then
      s.used[h] = true
      return A(h, ('HP ~%d%%: %s'):format(math.floor(php), h), 'spell', { unit = 'player', urgent = php < 25 })
    end
  end
  -- mob te bije: Nature's Grasp (prvni uder ho zakoreni)
  if danger and ready("Nature's Grasp") and not s.used.grasp then
    s.used.grasp = true
    return A("Nature's Grasp", 'Mob te bije: Nature\'s Grasp (zakoreni ho, ustup a castuj)')
  end
  -- pomale doleceni HoTem, dokud je many dost
  if php < 70 and danger and hotLeft('Rejuvenation', 'player') <= s.t and ready('Rejuvenation')
    and (not c.manaKnown or s.mana > 0.3) and not c.healerUp then
    s.used.Rejuvenation = true
    return A('Rejuvenation', ('HP ~%d%%: Rejuvenation'):format(math.floor(php)), 'spell', { unit = 'player' })
  end
  -- parta bez lecitele: zachran spoluhrace
  if c.group and not c.healerUp then
    for _, m in ipairs((c.party and c.party.members) or {}) do
      if m.alive and m.veryLow then
        local h = bestHeal(true)
        if h and ready(h) then
          s.used[h] = true
          return A(h, ('%s umira - %s na nej'):format(m.name or '?', h), 'spell', { unit = m.unit, urgent = true })
        end
      elseif m.alive and m.low and not m.unit:find('pet') and hotLeft('Rejuvenation', m.unit) <= 0 and ready('Rejuvenation') then
        s.used.Rejuvenation = true
        return A('Rejuvenation', ('%s ma malo HP: Rejuvenation'):format(m.name or '?'), 'spell', { unit = m.unit })
      end
    end
  end
  local cure = cureSpell()
  if s.step == 1 and cure and ready(cure) and dispellable('player') == true and php < 70 then
    return A(cure, 'Jed/prokleti na tobe: ' .. cure, 'spell', { unit = 'player' })
  end
  if not c.hostile then return nil end
  -- dosah
  if c.castR == false then return A('Attack', 'Dojdi na dosah kouzel', 'wait', { dur = 1.5 }) end
  -- malo many, mob ma jeste hodne HP: medved (rage misto many)
  if c.manaKnown and s.mana < 0.12 and ready('Bear Form') and not c.tLow35 and php > 40 and not c.group then
    s.form = 'bear'
    return A('Bear Form', 'Dochazi mana: do medveda, dobij to rage')
  end
  -- debuffy / DoTy
  if c.group and ready('Faerie Fire') and dotLeft('Faerie Fire') <= s.t and (c.ttd == nil or c.ttd > 10) and not s.used.ff
    and (c.tough or c.elite) then
    s.used.ff = true
    return A('Faerie Fire', 'Faerie Fire (mene brneni pro melee)')
  end
  if ready('Insect Swarm') and dotLeft('Insect Swarm') <= s.t and (c.ttd == nil or c.ttd > 8) and not s.used.is then
    s.used.is = true
    return A('Insect Swarm', 'Insect Swarm (DoT)')
  end
  if ready('Moonfire') and dotLeft('Moonfire') <= s.t and (c.ttd == nil or c.ttd > 6) and not s.used.mf then
    s.used.mf = true
    return A('Moonfire', 'Moonfire (DoT + instant)')
  end
  if aoe >= 3 and ready('Hurricane') and not c.group then
    return A('Hurricane', ('%d moby: Hurricane'):format(aoe))
  end
  -- mob je blizko a dorazit: instantni Moonfire misto castu
  if c.tLow10 and ready('Moonfire') then return A('Moonfire', 'Dorazit: Moonfire (instant)') end
  if ready('Starfire') and not danger and (c.ttd == nil or c.ttd > 4) then return A('Starfire', 'Starfire') end
  if ready('Wrath') then return A('Wrath', 'Wrath') end
  if c.near then return A('Attack', 'Bez many: bij holi', 'wait', { dur = 1.5 }) end
  return A('Attack', 'Neni co castit', 'wait', { dur = 1.5 })
end

local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  if a.kind == 'wait' then s.used[n] = true s.t = s.t + (a.dur or 1.5) return end
  if s.form == nil or s.form == 'moonkin' then s.mana = math.max(0, s.mana - ns.cost(n) / ns.manaMax()) end
  local cd, ct = ns.cdFor(n), ns.castTime(n)
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  if FORMS[n] then s.used[n] = true end
  if not c.inCombat then s.used[n] = true end
  s.t = s.t + (ns.OFF_GCD[n] and 0 or math.max(1.5, ct))
end

local TRACK = { "Nature's Grasp", 'Enrage', 'Growl', 'Bash', 'Barkskin', 'Innervate', 'Swiftmend', "Nature's Swiftness",
  'Hurricane', 'Frenzied Regeneration', 'Challenging Roar', 'Dash', 'Feral Charge', 'Rebirth', 'Tranquility', "Tiger's Fury",
  'Faerie Fire (Feral)' }

function E.plan(c)
  local s = { t = 0, mana = c.mana or 1, cd = {}, used = {}, step = 1, form = c.form }
  for _, n in ipairs(TRACK) do if ns.known(n) then s.cd[n] = ns.cdLeft(n) end end
  if c.castName and not c.channel then s.t = c.castLeft end
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
    if a.name == 'Attack' and step == 1 and not c.inCombat then break end
  end
  if plan[1] and ns.Mem then plan[1] = ns.Mem.swap(c, plan[1]) end
  if plan[1] then plan[1].wait = startT end

  local util
  if c.inCombat and c.hostile then
    local danger = c.aggro or (c.enemies.onMe or 0) > 0 or ns.hpBelow('player', 25) == true
    local lowHP = danger and ns.hpBelow('player', c.db.potionHP)
    local hp = ns.Bags.best('hpot')
    if hp and lowHP and ns.itemReady(hp, 'potion', 120) then
      util = A('item:' .. hp, 'Healing Potion!', 'item', { item = hp, urgent = true })
    end
    local mp = ns.Bags.best('mpot')
    if not util and mp and c.manaKnown and c.mana < 0.15 and (c.tough or c.instance) and ns.itemReady(mp, 'potion', 120) then
      util = A('item:' .. mp, 'Mana potion', 'item', { item = mp })
    end
    -- Innervate: sobe pri malo many v dlouhem boji
    if not util and c.manaKnown and c.mana < 0.25 and ns.known('Innervate') and ns.cdLeft('Innervate') <= 0 and (c.tough or c.group) then
      util = A('Innervate', 'Malo many: Innervate', 'spell', { unit = 'player' })
    end
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
  end
  return plan, util
end

-- Radek do panelu: forma, Moonfire na cili, MotW / Thorns
function E.infoLine(c)
  local p = {}
  local fn = { bear = 'Medved', cat = 'Kocka', moonkin = 'Moonkin', travel = 'Cestovni', aquatic = 'Vodni', other = 'Forma' }
  p[#p + 1] = '|cffffb070' .. (c.form and fn[c.form] or 'Caster') .. '|r'
  if c.form == 'bear' and c.rage then p[#p + 1] = '|cffff6060rage ' .. c.rage .. '|r' end
  if c.form == 'cat' and c.combo then p[#p + 1] = '|cffffe060combo ' .. c.combo .. '|r' end
  if c.hostile and ns.known('Moonfire') and (c.form == nil or c.form == 'moonkin') then
    p[#p + 1] = (c.mf or 0) > 0 and ('|cff9aa6b8Moonfire ' .. math.ceil(c.mf) .. 's|r') or '|cffffcc00bez Moonfire|r'
  end
  if c.motw == false then p[#p + 1] = '|cffffcc00bez MotW|r' end
  if c.thorns == false then p[#p + 1] = '|cffffcc00bez Thorns|r' end
  return table.concat(p, '  |cff556070-|r  ')
end

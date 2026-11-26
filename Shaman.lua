-- ClaudeMaster: rozhodovaci logika pro Shamana (univerzalni: melee / kouzla / leceni / totemy).
-- Myslene hlavne pro hrace, kteri v shamanovi "plavou": rada je vzdy jen jedna vec, s duvodem,
-- a addon hlida manu - drzi REZERVU NA LECENI (solo se shaman leci sam), takze damage kouzla
-- radi jen kdyz na to mana je, jinak "bij zbrani".
--  * spec podle talentu (resto / elemental / enhancement), bez talentu = hybrid (melee + leceni)
--  * Lightning / Water Shield a imbue zbrane (Rockbiter / Flametongue / Windfury) vzdy nahozene
--  * totemy jen kdyz maji smysl (tezky boj, vic mobu, parta), at to neni zmatek
--  * resto v parte: nejdriv leceni (Healing Wave / Lesser / Chain Heal / Riptide), damage jen s plnou manou
local ADDON, ns = ...
if not ns.enabled or ns.class ~= 'SHAMAN' then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = ns.Engine
local SH = {}
ns.Shaman = SH

------------------------------------------------------------------------------------------
-- Spec podle talentu (Forever: Elemental / Enhancement / Restoration), /cm shaman resto|ele|enh|auto
------------------------------------------------------------------------------------------
local TREE = {
  ele = { 'Convection', 'Concussion', 'Call of Flame', 'Elemental Alacrity', 'Elemental Devastation', 'Reverberation',
    'Elemental Focus', 'Elemental Warding', 'Trial by Fire', 'Eye of the Storm', 'Earthbound', 'Elemental Reach',
    'Call of Thunder', 'Lightning Overload', 'Elemental Fury', 'Lightning Mastery' },
  enh = { 'Ancestral Knowledge', 'Thundering Strikes', "Earth's Grasp", 'Mental Dexterity', 'Guardian Totems',
    'Improved Lightning Shield', 'Elemental Weapons', 'Shamanistic Focus', 'Anticipation', 'Flurry', 'Toughness',
    'Improved Ghost Wolf', 'Stormstrike', 'Spirit Weapons', 'Mental Quickness', 'Improved Stormstrike', 'Maelstrom Weapon',
    'Rage of the Farseer' },
  resto = { 'Improved Healing Wave', 'Tidal Focus', 'Natural Grace', 'Mindfulness', 'Totemic Focus', 'Improved Reincarnation',
    'Ancestral Healing', 'Healing Focus', 'Water Shield', 'Restorative Totems', 'Tidal Mastery', 'Mana Tide Totem',
    'Healing Way', "Nature's Swiftness", 'Purification', 'Riptide' },
}
function SH.spec()
  local pref = ns.db and ns.db.shamanSpec
  if pref and TREE[pref] then return pref end
  local n = {}
  for k, list in pairs(TREE) do
    n[k] = 0
    for _, t in ipairs(list) do n[k] = n[k] + (ns.talent and ns.talent(t) or 0) end
  end
  -- hybrid: resto + elemental, kdyz ani jeden strom vyrazne nevede (leveling "napul heal, napul damage")
  local best, bn = nil, 0
  for k, v in pairs(n) do if v > bn then best, bn = k, v end end
  if not best then return 'hybrid' end
  if best ~= 'enh' and n.resto > 0 and n.ele > 0 and math.abs(n.resto - n.ele) <= 5 then return 'hybrid' end
  return best
end
local SPEC_CZ = { resto = 'Resto (lecitel)', ele = 'Elemental (kouzla)', enh = 'Enhancement (melee)', hybrid = 'Hybrid (melee + leceni)' }
SH.SPEC_CZ = SPEC_CZ

------------------------------------------------------------------------------------------
-- Sledovani: Flame Shock na cili, Riptide (HoT) na lidech, stit a imbue z vlastnich castu
------------------------------------------------------------------------------------------
SH.onTarget, SH.hotOn, SH.castAt = {}, {}, {}
local DOTS = { ['Flame Shock'] = 12, ['Frost Shock'] = 8 }
local HOTS = { Riptide = 15 }
local f = CreateFrame('Frame')
pcall(f.RegisterUnitEvent, f, 'UNIT_SPELLCAST_SUCCEEDED', 'player')
pcall(f.RegisterUnitEvent, f, 'UNIT_SPELLCAST_SENT', 'player')
local function unitByName(name)
  if type(name) ~= 'string' or name == '' or name == safe(pc(UnitName, 'player')) then return 'player' end
  for i = 1, 4 do
    local u = 'party' .. i
    if safe(pc(UnitName, u)) == name then return u end
  end
  return 'player'
end
f:SetScript('OnEvent', function(_, ev, _, a2, a3)
  if ev == 'UNIT_SPELLCAST_SENT' then SH.lastUnit = unitByName(safe(a2)) return end
  local n = ns.nameOf and ns.nameOf(safeNum(a3) or 0)
  if not n then return end
  local now = GetTime()
  SH.castAt[n] = now
  if DOTS[n] then SH.onTarget[n] = { tok = ns.T and ns.T.token, untilT = now + DOTS[n] } end
  if HOTS[n] then SH.hotOn[n .. ':' .. (SH.lastUnit or 'player')] = now + HOTS[n] end
end)
local function dotLeft(n)
  local e = SH.onTarget[n]
  if not e or e.tok ~= (ns.T and ns.T.token) then return 0 end
  return math.max(0, e.untilT - GetTime())
end
local function hotLeft(n, u) return math.max(0, (SH.hotOn[n .. ':' .. (u or 'player')] or 0) - GetTime()) end

-- buff mimo boj (index scan): true / false / nil (v boji / nejde cist)
local function unitBuff(u, names)
  if ns.inCombat() then return nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get or not UnitExists(u) then return nil end
  for i = 1, 40 do
    local ok, a = pcall(get, u, i, 'HELPFUL')
    if not ok then return nil end
    if type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) == 'string' then for _, w in ipairs(names) do if n == w then return true end end end
  end
  return false
end
local function dispellable(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, 1, 'HARMFUL|RAID')
  if not ok then return nil end
  if a ~= nil then return true end
  return not ns.inCombat() and false or nil
end

-- totemy: slot 1 ohen, 2 zeme, 3 voda, 4 vzduch -> zbyva sekund (0 = neni)
local function totemLeft(slot)
  if not GetTotemInfo then return nil end
  local have, name, start, dur = pc(GetTotemInfo, slot)
  have, start, dur = safeBool(have), safeNum(start), safeNum(dur)
  if have == nil then return nil end
  if not have or not start or not dur or dur == 0 then return 0 end
  return math.max(0, start + dur - GetTime()), safe(name)
end
-- imbue zbrane: true / false / nil
local function imbueUp()
  if not GetWeaponEnchantInfo then return nil end
  local mh = safeBool((pc(GetWeaponEnchantInfo)))
  return mh
end
local function hasMH()
  return GetInventoryItemLink and safe(pc(GetInventoryItemLink, 'player', 16)) ~= nil
end

-- nejlepsi stit / imbue podle specu
local function bestShield(spec)
  if ns.known('Water Shield') and spec ~= 'enh' then return 'Water Shield', 'mana pri kazdem zasahu' end
  if ns.known('Lightning Shield') then return 'Lightning Shield', 'kdo te bije, dostane blesk' end
  if ns.known('Water Shield') then return 'Water Shield', 'mana pri kazdem zasahu' end
end
local function bestImbue(spec)
  local list = (spec == 'enh' or spec == 'hybrid') and { 'Windfury Weapon', 'Flametongue Weapon', 'Rockbiter Weapon' }
    or { 'Flametongue Weapon', 'Rockbiter Weapon' }
  for _, n in ipairs(list) do if ns.known(n) then return n end end
end
-- leceni: rychle (Lesser) v nouzi, jinak Healing Wave
local function bestHeal(urgent)
  if urgent and ns.known('Lesser Healing Wave') then return 'Lesser Healing Wave' end
  if ns.known('Healing Wave') then return 'Healing Wave' end
  return ns.known('Lesser Healing Wave') and 'Lesser Healing Wave' or nil
end

------------------------------------------------------------------------------------------
-- Kontext
------------------------------------------------------------------------------------------
local baseContext = E.context
E.context = function()
  local c = baseContext()
  c.spec = SH.spec()
  c.healerUp = false
  for _, m in ipairs((c.party and c.party.members) or {}) do
    if m.healer and m.alive and not m.unit:find('pet') then c.healerUp = true end
  end
  local function inR(n)
    local id = ns.id(n)
    if not id or not c.hostile or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    return safeBool(pc(C_Spell.IsSpellInRange, id, 'target'))
  end
  c.castR = inR('Lightning Bolt')
  c.shockR = inR('Earth Shock')
  if c.hostile and ns.known('Stormstrike') then
    local m = inR('Stormstrike')
    if m ~= nil then c.near = m end
  end
  c.shield = unitBuff('player', { 'Lightning Shield', 'Water Shield' })
  if c.shield == nil then
    -- v boji: z casu castu (10 min), stit muze spadnout driv (naboje) - neradime ho v boji znovu kazdou chvili
    local t = math.max(SH.castAt['Lightning Shield'] or -999, SH.castAt['Water Shield'] or -999)
    c.shield = GetTime() - t < 600
  end
  c.imbue = imbueUp()
  c.hasMH = hasMH()
  c.fire, c.fireName = totemLeft(1)
  c.earth = totemLeft(2)
  c.water = totemLeft(3)
  c.air = totemLeft(4)
  c.fs = dotLeft('Flame Shock')
  -- rezerva many na leceni: solo bez healera 35 %, resto v parte 30 %, s healerem 10 %
  c.reserve = c.healerUp and 0.10 or ((c.spec == 'resto' and c.group) and 0.30 or 0.35)
  return c
end

------------------------------------------------------------------------------------------
-- Rozhodnuti
------------------------------------------------------------------------------------------
local function A(name, reason, kind, extra)
  local a = { name = name, reason = reason, kind = kind or 'spell' }
  if extra then for k, v in pairs(extra) do a[k] = v end end
  return a
end
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
-- leceni party (resto / kdo nema lecitele): nil = vsichni v poradku
local function partyHeal(c, s, ready)
  local list = healTargets(c)
  local function inRange(u)
    if u == 'player' then return true end
    local id = ns.id('Healing Wave')
    local r = id and C_Spell and C_Spell.IsSpellInRange and safeBool(pc(C_Spell.IsSpellInRange, id, u))
    return r ~= false
  end
  local function who(m) return m.unit == 'player' and 'sebe' or m.name end
  for _, m in ipairs(list) do
    if below(m.unit, 35) and inRange(m.unit) then
      if below(m.unit, 25) and ready("Nature's Swiftness") then
        return A("Nature's Swiftness", ("%s umira: Nature's Swiftness, pak Healing Wave (hned)"):format(m.name), 'spell', { urgent = true })
      end
      if ready('Riptide') and hotLeft('Riptide', m.unit) <= s.t then
        s.used['Riptide' .. m.unit] = true
        return A('Riptide', ('%s umira: Riptide (instant)'):format(m.name), 'spell', { unit = m.unit, urgent = true })
      end
      local h = bestHeal(true)
      if h and ready(h) and not s.used[h .. m.unit] then
        s.used[h .. m.unit] = true
        return A(h, ('%s ma malo HP: %s na %s'):format(m.name, h, who(m)), 'spell', { unit = m.unit, urgent = true })
      end
    end
  end
  local hurt = 0
  for _, m in ipairs(list) do if below(m.unit, 75) then hurt = hurt + 1 end end
  if hurt >= 3 and ready('Chain Heal') and not s.used.ch then
    s.used.ch = true
    return A('Chain Heal', ('%d zranenych: Chain Heal (skace na dalsi)'):format(hurt))
  end
  for _, m in ipairs(list) do
    if below(m.unit, 60) and inRange(m.unit) then
      if ready('Riptide') and hotLeft('Riptide', m.unit) <= s.t and not s.used['Riptide' .. m.unit] then
        s.used['Riptide' .. m.unit] = true
        return A('Riptide', ('%s pod 60 %%: Riptide'):format(m.name), 'spell', { unit = m.unit })
      end
      if ready('Healing Wave') and not s.used['Healing Wave' .. m.unit] then
        s.used['Healing Wave' .. m.unit] = true
        return A('Healing Wave', ('%s pod 60 %%: Healing Wave'):format(m.name), 'spell', { unit = m.unit })
      end
    end
  end
  -- tank dostava rany: Riptide predem
  for _, m in ipairs(list) do
    if c.inCombat and m.tank and m.mobs > 0 and below(m.unit, 90) and ready('Riptide') and hotLeft('Riptide', m.unit) <= s.t
      and not s.used['Riptide' .. m.unit] then
      s.used['Riptide' .. m.unit] = true
      return A('Riptide', ('%s tankuje: Riptide predem'):format(m.name), 'spell', { unit = m.unit })
    end
  end
end

local function decide(c, s)
  local db = c.db
  local function bad(n) return c.imm ~= nil and ns.Immune.bad(c.imm, n) end
  local function manaFor(n) return ns.cost(n) <= 0 or s.mana * ns.manaMax() >= ns.cost(n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if not manaFor(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  -- damage kouzlo jen nad rezervou na leceni
  local function spare(n, extra) return ready(n) and (not c.manaKnown or s.mana - ns.cost(n) / ns.manaMax() > c.reserve + (extra or 0)) end
  local php = c.php or 100
  local town = c.resting and not c.hostile
  local spec = c.spec

  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    if c.drinking or c.eating then return nil end
    -- leceni party / sebe (kouzlo je levnejsi nez cekat na jidlo, kdyz je many dost)
    if c.group and (not c.manaKnown or c.mana > 0.3) then
      local h = partyHeal(c, s, ready)
      if h then return h end
    end
    -- troll: Rapid Regeneration = 50 % HP za 6 s zadarmo (nesmis se hybat) - lepsi nez kouzlo i jidlo
    if s.step == 1 and php < 70 and not c.hostile and ready('Rapid Regeneration') then
      return A('Rapid Regeneration', ('HP ~%d%%: Rapid Regeneration - 6 s stuj na miste, vyleci pulku HP zadarmo'):format(math.floor(php)),
        'spell', { unit = 'player' })
    end
    if s.step == 1 and php < 70 and (not c.manaKnown or c.mana > 0.45) then
      local h = bestHeal(false)
      if h and ready(h) then
        s.used.heal = true
        return A(h, ('HP ~%d%%: %s - mana se doplni pitim, je to rychlejsi nez jidlo'):format(math.floor(php), h), 'spell', { unit = 'player' })
      end
    end
    if s.step == 1 and php < 50 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(php)), 'item', { item = fd }) end
    end
    if s.step == 1 and c.manaKnown and c.mana < (db.drinkMana or 0.55) and not c.hostile then
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se (shaman bez many se nevyleci)'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
    end
    if not town then
      -- stit
      local sh, why = bestShield(spec)
      if sh and c.shield == false and ready(sh) and not s.used.shield then
        s.used.shield = true
        return A(sh, ('Nahod %s (%s)'):format(sh, why), 'spell', { unit = 'player' })
      end
      -- imbue zbrane
      local im = bestImbue(spec)
      if im and c.hasMH and c.imbue == false and ready(im) and not s.used.imbue then
        s.used.imbue = true
        return A(im, ('Zbran bez imbue: %s'):format(im))
      end
      -- jed / nemoc
      for _, cure in ipairs({ 'Cure Poison', 'Cure Disease' }) do
        if ready(cure) then
          if dispellable('player') then return A(cure, 'Mas na sobe jed/nemoc: ' .. cure, 'spell', { unit = 'player' }) end
          for _, m in ipairs((c.party and c.party.members) or {}) do
            if m.alive and not m.unit:find('pet') and dispellable(m.unit) then
              return A(cure, ('%s ma jed/nemoc: %s'):format(m.name or '?', cure), 'spell', { unit = m.unit })
            end
          end
        end
      end
    end
    if c.hostile then
      -- pull: z dalky Lightning Bolt (kdyz je many dost), jinak dojdi a bij
      if c.castR ~= false and spare('Lightning Bolt', 0.15) and spec ~= 'enh' and not s.used.pull then
        s.used.pull = true
        return A('Lightning Bolt', 'Pull: Lightning Bolt z dalky (mob k tobe dobehne)')
      end
      if c.shockR and spare('Flame Shock', 0.1) and spec ~= 'resto' and not s.used.pull then
        s.used.pull = true
        return A('Flame Shock', 'Pull: Flame Shock (instant, pali dal)')
      end
      return A('Attack', c.near and 'Utoc zbrani' or 'Pull: dojdi k mobovi a bij zbrani (setris manu na leceni)', 'wait')
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  local danger = c.aggro or (c.enemies.onMe or 0) > 0
  local aoe = c.enemies.cluster or c.enemies.combat or 0

  -- resto v parte: leceni ma prednost
  if spec == 'resto' and c.group then
    local h = partyHeal(c, s, ready)
    if h then return h end
  end
  -- vlastni nouze (solo / nikdo neleci)
  if php < 40 and not c.healerUp then
    if php < 25 and ready("Nature's Swiftness") then
      return A("Nature's Swiftness", "Umiras: Nature's Swiftness, pak Healing Wave (hned)", 'spell', { urgent = true })
    end
    if php < 30 and danger and (c.enemies.onMe or 0) >= 2 and c.near and ready('War Stomp') then
      return A('War Stomp', 'Vic mobu u tebe a malo HP: War Stomp (omraci je na 2 s) a pak se vylec', 'spell', { urgent = true })
    end
    local h = bestHeal(true)
    if h and ready(h) then
      s.used[h] = true
      return A(h, ('HP ~%d%%: %s na sebe'):format(math.floor(php), h), 'spell', { unit = 'player', urgent = php < 30 })
    end
  end
  -- parta bez lecitele: zachran spoluhrace
  if c.group and not c.healerUp and spec ~= 'resto' then
    for _, m in ipairs((c.party and c.party.members) or {}) do
      if m.alive and m.veryLow and not m.unit:find('pet') then
        local h = bestHeal(true)
        if h and ready(h) then
          s.used[h] = true
          return A(h, ('%s umira - %s na nej'):format(m.name or '?', h), 'spell', { unit = m.unit, urgent = true })
        end
      end
    end
  end
  if not c.hostile then return nil end
  -- preruseni kouzla: Earth Shock
  if s.step == 1 and c.tCasting and c.interruptible and ready('Earth Shock') and c.shockR ~= false then
    s.used['Earth Shock'] = true
    return A('Earth Shock', 'Mob kouzli: Earth Shock ho prerusi', 'spell', { urgent = true })
  end
  -- mob utika: Frost Shock (zpomali)
  if s.step == 1 and c.mob and c.mob.fleeingNow and ready('Frost Shock') then
    return A('Frost Shock', 'Mob utika: Frost Shock ho zpomali', 'spell', { urgent = true })
  end
  -- vic mobu na tobe: Stoneclaw Totem (bere jejich pozornost), War Stomp
  if (c.enemies.onMe or 0) >= 2 and not c.group and ready('Stoneclaw Totem') and (c.earth or 0) <= s.t and not s.used.stoneclaw then
    s.used.stoneclaw = true
    return A('Stoneclaw Totem', ('%d moby na tobe: Stoneclaw Totem (chvili bijou jeho)'):format(c.enemies.onMe))
  end
  -- AoE: 3+ moby u tebe
  if aoe >= 3 and c.near then
    if ready('Magma Totem') and (c.fire or 0) <= s.t and spare('Magma Totem') and not s.used.fireT then
      s.used.fireT = true
      return A('Magma Totem', ('%d moby u tebe: Magma Totem'):format(aoe))
    end
    if ready('Fire Nova Totem') and (c.fire or 0) <= s.t and spare('Fire Nova Totem') and not s.used.fireT then
      s.used.fireT = true
      return A('Fire Nova Totem', ('%d moby u tebe: Fire Nova Totem'):format(aoe))
    end
    if ready('Fire Nova') and spare('Fire Nova') then return A('Fire Nova', ('%d moby u tebe: Fire Nova'):format(aoe)) end
  end
  if aoe >= 3 and spare('Chain Lightning', 0.1) and c.castR ~= false then
    return A('Chain Lightning', ('%d moby: Chain Lightning'):format(aoe))
  end
  -- parta: totem many pro lecitele / resto
  if c.group and (spec == 'resto' or spec == 'hybrid') and ready('Mana Spring Totem') and (c.water or 0) <= s.t and not s.used.waterT then
    s.used.waterT = true
    return A('Mana Spring Totem', 'Parta: Mana Spring Totem (mana pro tebe i ostatni)')
  end
  -- tezky boj: Searing Totem (bije sam)
  local long = c.tough or c.elite or (c.ttd and c.ttd > 15)
  if long and c.near and ready('Searing Totem') and (c.fire or 0) <= s.t and spare('Searing Totem') and not s.used.fireT then
    s.used.fireT = true
    return A('Searing Totem', 'Delsi boj: Searing Totem (bije cil s tebou)')
  end
  if ready('Elemental Mastery') and spec == 'ele' and (c.tough or c.elite) then return A('Elemental Mastery', 'Elemental Mastery') end
  -- resto v parte: damage jen s plnou manou
  if spec == 'resto' and c.group then
    if c.manaKnown and s.mana < 0.8 then return A('Attack', 'Setri manu na leceni (vsichni v poradku)', 'wait', { dur = 1.5 }) end
  end
  -- Stormstrike (enhancement)
  if c.near and ready('Stormstrike') then return A('Stormstrike', 'Stormstrike') end
  -- Flame Shock na delsi boj (DoT)
  if c.fs <= s.t and (c.ttd == nil or c.ttd > 9) and spare('Flame Shock', 0.05) and c.shockR ~= false and not s.used.fs then
    s.used.fs = true
    return A('Flame Shock', 'Flame Shock (pali cil dal, instant)')
  end
  -- dorazit: Earth Shock
  if c.tLow20 and spare('Earth Shock') and c.shockR ~= false then return A('Earth Shock', 'Dorazit: Earth Shock (instant)') end
  -- elemental / hybrid na dalku: Lightning Bolt nad rezervou
  if spec == 'ele' or (not c.near and spec ~= 'enh') then
    if c.castR ~= false and spare('Lightning Bolt') and not c.moving then return A('Lightning Bolt', 'Lightning Bolt') end
  end
  -- melee: Earth Shock jen s hodne manou, jinak zbran
  if c.near then
    if spare('Earth Shock', 0.35) and spec ~= 'resto' then return A('Earth Shock', 'Earth Shock (many je dost)') end
    local why = (c.manaKnown and s.mana <= c.reserve + 0.1) and ('Bij zbrani - mana %d %%, drz ji na leceni'):format(math.floor(s.mana * 100))
      or 'Bij zbrani'
    return A('Attack', why, 'wait', { dur = 1.5 })
  end
  if c.castR ~= false and spare('Lightning Bolt') then return A('Lightning Bolt', 'Lightning Bolt') end
  return A('Attack', 'Dojdi k mobovi a bij zbrani', 'wait', { dur = 1.5 })
end

local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  if a.kind == 'wait' then s.used[n] = true s.t = s.t + (a.dur or 1.5) return end
  s.mana = math.max(0, s.mana - ns.cost(n) / ns.manaMax())
  local cd, ct = ns.cdFor(n), ns.castTime(n)
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  -- shocky sdili cooldown
  if n == 'Earth Shock' or n == 'Flame Shock' or n == 'Frost Shock' then
    for _, x in ipairs({ 'Earth Shock', 'Flame Shock', 'Frost Shock' }) do s.cd[x] = s.t + math.max(cd, 6) end
  end
  if not c.inCombat then s.used[n] = true end
  s.t = s.t + (ns.OFF_GCD[n] and 0 or math.max(1.5, ct))
end

local TRACK = { 'Berserking', 'Rapid Regeneration', 'Earth Shock', 'Flame Shock', 'Frost Shock', 'Stormstrike', 'Chain Lightning', "Nature's Swiftness",
  'Mana Tide Totem', 'Stoneclaw Totem', 'Fire Nova Totem', 'Earthbind Totem', 'Grounding Totem', 'War Stomp',
  'Elemental Mastery', 'Riptide', 'Fire Nova', 'Reincarnation' }

function E.plan(c)
  local s = { t = 0, mana = c.mana or 1, cd = {}, used = {}, step = 1 }
  for _, n in ipairs(TRACK) do if ns.known(n) then s.cd[n] = ns.cdLeft(n) end end
  for _, n in ipairs(ns.SPELLS) do if not s.cd[n] and ns.known(n) and ns.cdFor(n) > 1.5 then s.cd[n] = ns.cdLeft(n) end end
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
    if not util and c.manaKnown and c.mana < 0.3 and ns.known('Mana Tide Totem') and ns.cdLeft('Mana Tide Totem') <= 0 then
      util = A('Mana Tide Totem', 'Malo many: Mana Tide Totem', 'spell')
    end
    -- troll: Berserking na tezky boj nebo vic mobu (rychlejsi kouzla i leceni)
    if not util and ns.known('Berserking') and ns.cdLeft('Berserking') <= 0
      and (c.tough or c.elite or (c.enemies.onMe or 0) >= 2 or ns.hpBelow('player', 40) == true) then
      util = A('Berserking', 'Tezky boj: Berserking (+10 % rychlost castu a utoku na 15 s)', 'spell')
    end
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
  end
  return plan, util
end

-- Radek do panelu: spec, stit, imbue, totemy, rezerva many
function E.infoLine(c)
  local p = {}
  p[#p + 1] = '|cff4da6ff' .. (SPEC_CZ[c.spec] or 'Shaman') .. '|r'
  if c.shield == false then p[#p + 1] = '|cffffcc00bez stitu|r' end
  if c.imbue == false and c.hasMH then p[#p + 1] = '|cffffcc00zbran bez imbue|r' end
  local t = {}
  if (c.fire or 0) > 0 then t[#t + 1] = 'ohen' end
  if (c.earth or 0) > 0 then t[#t + 1] = 'zeme' end
  if (c.water or 0) > 0 then t[#t + 1] = 'voda' end
  if (c.air or 0) > 0 then t[#t + 1] = 'vzduch' end
  if #t > 0 then p[#p + 1] = '|cff9aa6b8totemy: ' .. table.concat(t, ', ') .. '|r' end
  if c.inCombat and c.manaKnown and c.mana <= (c.reserve or 0.35) + 0.05 then
    p[#p + 1] = '|cff7fd8ffmana jen na leceni|r'
  end
  return table.concat(p, '  |cff556070-|r  ')
end

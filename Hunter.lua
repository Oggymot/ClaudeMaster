-- ClaudeMaster: rozhodovaci logika pro Huntera (univerzalni, hlavne Beast Mastery).
-- Hlavni myslenka: tankuje PET. Addon proto hlida, aby pet mel moba (pull petem a chvili pockat),
-- kdyz mob bezi k tobe, vrati ho petovi (Intimidation, Growl, Concussive Shot, Wing Clip + odstup,
-- Feign Death), hlida HP peta (Mend Pet), oziveni, nakrmeni a Growl autocast. Strelba na dalku
-- (8+ yardu) dela dvakrat vic nez melee.
local ADDON, ns = ...
if not ns.enabled or ns.class ~= 'HUNTER' then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = ns.Engine
local HU = {}
ns.Hunter = HU

local TREE = {
  bm = { 'Deadly Aspects', 'Endurance Training', 'Focused Fire', 'Improved Aspect of the Monkey', 'Improved Revive Pet',
    'Pathfinding', 'Bestial Swiftness', 'Unleashed Fury', 'Improved Mend Pet', 'Ferocity', 'Summon Hawk', 'Spirit Bond',
    'Intimidation', 'Bestial Discipline', 'Frenzy', 'Bestial Wrath' },
  mm = { 'Hawk Eye', 'Improved Concussive Shot', 'Lethal Attacks', 'Efficiency', 'Careful Aim', 'Improved Stings',
    'Improved Arcane Shot', 'Rapid Killing', 'Lone Wolf', 'Trueshot Aura', 'Mortal Shots', 'Improved Serpent Sting',
    'Rapid Recuperation', 'Barrage', 'Scatter Shot', 'Ranged Weapon Specialization', 'Sniper Shot' },
  sv = { 'Improved Tracking', 'Deflection', 'Entrapment', 'Savage Strikes', 'Survivalist', 'Improved Wing Clip',
    'Clever Traps', 'Surefooted', 'Deterrence', 'Survival Tactics', 'Counterattack', "Predator's Edge",
    'Resourcefulness', 'Expose Prey', "Survivalist's Discipline", 'Strider Kick', 'Lightning Reflexes', 'Lacerating Strikes' },
}
function HU.spec()
  local pref = ns.db and ns.db.hunterSpec
  if pref and TREE[pref] then return pref end
  local best, bn = nil, 0
  for k, list in pairs(TREE) do
    local n = 0
    for _, t in ipairs(list) do n = n + (ns.talent and ns.talent(t) or 0) end
    if n > bn then best, bn = k, n end
  end
  return best or 'bm'
end
local SPEC_CZ = { bm = 'Beast Mastery (pet)', mm = 'Marksmanship (strelba)', sv = 'Survival' }

-- Serpent Sting / Hunter's Mark na cili z vlastnich castu
HU.onTarget, HU.castAt = {}, {}
local DOTS = { ['Serpent Sting'] = 15, ["Hunter's Mark"] = 120, ['Concussive Shot'] = 4, ['Wing Clip'] = 10 }
local f = CreateFrame('Frame')
pcall(f.RegisterUnitEvent, f, 'UNIT_SPELLCAST_SUCCEEDED', 'player')
f:SetScript('OnEvent', function(_, _, _, _, spellID)
  local n = ns.nameOf and ns.nameOf(safeNum(spellID) or 0)
  if not n then return end
  HU.castAt[n] = GetTime()
  if DOTS[n] then HU.onTarget[n] = { tok = ns.T and ns.T.token, untilT = GetTime() + DOTS[n] } end
end)
local function dotLeft(n)
  local e = HU.onTarget[n]
  if not e or e.tok ~= (ns.T and ns.T.token) then return 0 end
  return math.max(0, e.untilT - GetTime())
end
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
local ASPECTS = { 'Aspect of the Hawk', 'Aspect of the Monkey', 'Aspect of the Cheetah', 'Aspect of the Pack',
  'Aspect of the Viper', 'Aspect of the Wild', 'Aspect of the Beast' }

------------------------------------------------------------------------------------------
-- Kontext
------------------------------------------------------------------------------------------
local baseContext = E.context
E.context = function()
  local c = baseContext()
  c.spec = HU.spec()
  c.pet = UnitExists('pet') and true or false
  c.petDead = c.pet and safeBool(pc(UnitIsDead, 'pet')) == true
  c.petHP = c.pet and not c.petDead and ns.healthPct('pet') or nil
  c.petOnTarget = c.pet and c.hostile and safeBool(pc(UnitIsUnit, 'pettarget', 'target')) == true
  c.happy = GetPetHappiness and safeNum((pc(GetPetHappiness))) or nil   -- 1 nestastny, 2 ok, 3 stastny
  if GetSpellAutocast and c.pet then
    local can, on = pc(GetSpellAutocast, 'Growl', 'pet')
    c.growlAuto = safeBool(on)
  end
  local function inR(n)
    local id = ns.id(n)
    if not id or not c.hostile or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    return safeBool(pc(C_Spell.IsSpellInRange, id, 'target'))
  end
  c.shootR = inR('Auto Shot')
  if c.shootR == nil then c.shootR = inR('Arcane Shot') end
  local m = inR('Raptor Strike')
  if m ~= nil then c.near = m end
  -- aspekt (mimo boj aura, v boji podle castu)
  c.aspect = nil
  if not ns.inCombat() then
    for _, a in ipairs(ASPECTS) do if unitBuff('player', { a }) then c.aspect = a break end end
  else
    local best, bt = nil, -1
    for _, a in ipairs(ASPECTS) do local t = HU.castAt[a] or -1 if t > bt then best, bt = a, t end end
    c.aspect = bt > 0 and best or nil
  end
  -- munice (slot 0)
  c.ammo = GetInventoryItemCount and safeNum(pc(GetInventoryItemCount, 'player', 0)) or nil
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
local PET_ICON = 'Interface\\Icons\\Ability_Hunter_BeastCall'
local function petAttack(reason)
  return A('TARGET', reason, 'hint', { icon = 'Interface\\Icons\\Ability_GhoulFrenzy', macro = '/petattack', macroLabel = 'pet: utok' })
end

local function decide(c, s)
  local db = c.db
  local function bad(n) return c.imm ~= nil and ns.Immune.bad(c.imm, n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if ns.cost(n) > 0 and c.manaKnown and s.mana * ns.manaMax() < ns.cost(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  local php = c.php or 100
  local town = c.resting and not c.hostile
  local petOk = c.pet and not c.petDead

  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    if c.drinking or c.eating then return nil end
    -- pet
    if not town then
      if c.petDead and ready('Revive Pet') then return A('Revive Pet', 'Pet je mrtvy: Revive Pet') end
      if not c.pet and ready('Call Pet') and not s.used.callpet then
        s.used.callpet = true
        return A('Call Pet', 'Bez peta: Call Pet (pet tankuje za tebe)')
      end
      if petOk and c.petHP and c.petHP < 70 and ready('Mend Pet') and not s.used.mend then
        s.used.mend = true
        return A('Mend Pet', ('Pet ma ~%d %% HP: Mend Pet pred dalsim pullem'):format(math.floor(c.petHP)))
      end
      if petOk and c.happy and c.happy < 3 and ready('Feed Pet') and not s.used.feed then
        s.used.feed = true
        return A('Feed Pet', 'Pet neni spokojeny: Feed Pet (nakrm ho) - stastny pet bije vic', 'spell')
      end
      if petOk and c.growlAuto == false and not c.group and s.step == 1 then
        return A('TARGET', 'Zapni petovi Growl autocast (pravy klik na Growl na liste peta) - jinak moba neudrzi',
          'hint', { icon = 'Interface\\Icons\\Ability_Physical_Taunt' })
      end
    end
    if s.step == 1 and php < 50 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(php)), 'item', { item = fd }) end
    end
    if s.step == 1 and c.manaKnown and c.mana < (db.drinkMana or 0.55) and not c.hostile then
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
    end
    if not town then
      -- aspekt: Hawk (vic damage na dalku); Viper pri malo many, kdyz existuje
      local want = (c.manaKnown and c.mana < 0.3 and ns.known('Aspect of the Viper')) and 'Aspect of the Viper'
        or (ns.known('Aspect of the Hawk') and 'Aspect of the Hawk') or (ns.known('Aspect of the Monkey') and 'Aspect of the Monkey')
      if want and c.aspect ~= want and c.aspect ~= 'Aspect of the Cheetah' and c.aspect ~= 'Aspect of the Pack'
        and ready(want) and not s.used.aspect then
        s.used.aspect = true
        return A(want, ('Aspekt: %s'):format(want), 'spell', { unit = 'player' })
      end
      if s.step == 1 and c.ammo and c.ammo < 100 then
        return A('TARGET', ('Dochazi munice (%d) - kup u vendora'):format(c.ammo), 'hint', { icon = 'Interface\\Icons\\INV_Ammo_Bullet_02' })
      end
    end
    if c.hostile then
      -- pull: nejdriv pet, pak strelba (pet si moba "nabije", nepobezi k tobe)
      if petOk and not c.petOnTarget and not s.used.petattack then
        s.used.petattack = true
        return petAttack("Pull: posli peta na moba (klik) a pockej ~2 s, az ho pet bije - pak strilej")
      end
      if ready("Hunter's Mark") and dotLeft("Hunter's Mark") <= 0 and not s.used.mark then
        s.used.mark = true
        return A("Hunter's Mark", "Hunter's Mark (vic damage pro tebe i peta)")
      end
      if c.shootR ~= false and ready('Auto Shot') then return A('Auto Shot', petOk and 'Az pet moba bije: strilej' or 'Pull: Auto Shot') end
      return A('Attack', 'Dojdi na dosah strelby (8-35 yd)', 'wait')
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  local danger = c.aggro or (c.enemies.onMe or 0) > 0
  local aoe = c.enemies.cluster or c.enemies.combat or 0
  -- pet: ziv a bije muj cil?
  if petOk and c.hostile and not c.petOnTarget and s.step == 1 then
    return petAttack('Pet nebije tvuj cil: posli ho na nej (klik)')
  end
  -- mob jde po tobe (pet ho neudrzel): vratit ho petovi
  if danger and petOk and c.hostile then
    if ready('Intimidation') then
      s.used.Intimidation = true
      return A('Intimidation', 'Mob jde po tobe: Intimidation (pet ho omraci a vezme si ho)', 'spell', { urgent = true })
    end
    if s.step == 1 and not s.used.growl then
      s.used.growl = true
      return A('TARGET', 'Mob jde po tobe: Growl od peta (klik) - pet si ho vezme zpet', 'hint',
        { icon = 'Interface\\Icons\\Ability_Physical_Taunt', macro = '/cast Growl', macroLabel = 'pet: Growl', urgent = true })
    end
    if php < 40 and ready('Feign Death') then
      return A('Feign Death', 'Malo HP: Feign Death - moby prejdou na peta', 'spell', { urgent = true })
    end
    if c.near then
      if ready('Wing Clip') and dotLeft('Wing Clip') <= s.t then
        return A('Wing Clip', 'Mob u tebe: Wing Clip (zpomali ho), odstup 8+ yd a strilej', 'spell', { urgent = true })
      end
    elseif ready('Concussive Shot') and dotLeft('Concussive Shot') <= s.t then
      return A('Concussive Shot', 'Mob bezi k tobe: Concussive Shot (zpomali ho, pet ho dobehne)', 'spell', { urgent = true })
    end
  end
  -- pet umira
  if petOk and c.petHP and c.petHP < 35 and ready('Mend Pet') and not s.used.mend then
    s.used.mend = true
    return A('Mend Pet', ('Pet ma ~%d %% HP: Mend Pet'):format(math.floor(c.petHP)), 'spell', { urgent = true })
  end
  -- ja umiram bez peta
  if php < 30 and not petOk and ready('Feign Death') then
    return A('Feign Death', 'Malo HP: Feign Death (moby te pusti)', 'spell', { urgent = true })
  end
  if not c.hostile then return nil end
  if c.mob and c.mob.fleeingNow and ready('Concussive Shot') then
    return A('Concussive Shot', 'Mob utika: Concussive Shot', 'spell', { urgent = true })
  end
  if c.tough or c.elite then
    if ready('Bestial Wrath') and petOk then return A('Bestial Wrath', 'Tezky boj: Bestial Wrath (pet bije mnohem vic)') end
    if ready('Rapid Fire') and not c.near then return A('Rapid Fire', 'Tezky boj: Rapid Fire') end
  end
  -- melee (mob u tebe): bez peta nebo kdyz neodstoupis
  if c.near then
    if ready('Mongoose Bite') then return A('Mongoose Bite', 'Mongoose Bite') end
    if ready('Raptor Strike') and not s.used.raptor then
      s.used.raptor = true
      return A('Raptor Strike', petOk and 'Mob u tebe: Raptor Strike - ale radsi odstup, strelba dava 2x vic' or 'Raptor Strike')
    end
    return A('Attack', petOk and 'Odstup od moba (8+ yd) - na dalku das 2x vic' or 'Bij zbrani', 'wait', { dur = 1.5 })
  end
  if c.shootR == false then return A('Attack', 'Dojdi na dosah strelby', 'wait', { dur = 1.5 }) end
  -- na dalku
  if ready("Hunter's Mark") and dotLeft("Hunter's Mark") <= s.t and (c.ttd == nil or c.ttd > 8) and not s.used.mark then
    s.used.mark = true
    return A("Hunter's Mark", "Hunter's Mark")
  end
  if aoe >= 3 and ready('Multi-Shot') and (not c.manaKnown or s.mana > 0.3) then return A('Multi-Shot', ('%d moby: Multi-Shot'):format(aoe)) end
  if ready('Serpent Sting') and dotLeft('Serpent Sting') <= s.t and (c.ttd == nil or c.ttd > 10)
    and (not c.manaKnown or s.mana > 0.25) and not s.used.ss then
    s.used.ss = true
    return A('Serpent Sting', 'Serpent Sting (jed, bije dal)')
  end
  if ready('Kill Command') and petOk then return A('Kill Command', 'Kill Command (pet)') end
  if ready('Arcane Shot') and (not c.manaKnown or s.mana > 0.4) then return A('Arcane Shot', 'Arcane Shot (instant)') end
  if ready('Steady Shot') and (not c.manaKnown or s.mana > 0.25) then return A('Steady Shot', 'Steady Shot') end
  return A('Auto Shot', 'Auto Shot strili sam - setris manu', 'wait', { dur = 1.5 })
end

local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  if a.kind == 'wait' or a.kind == 'hint' then s.used[n] = true s.t = s.t + (a.dur or 1) return end
  s.mana = math.max(0, s.mana - ns.cost(n) / math.max(1, ns.manaMax()))
  local cd, ct = ns.cdFor(n), ns.castTime(n)
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  if not c.inCombat then s.used[n] = true end
  s.t = s.t + (ns.OFF_GCD[n] and 0 or math.max(1.5, ct))
end

local TRACK = { 'Intimidation', 'Bestial Wrath', 'Rapid Fire', 'Feign Death', 'Concussive Shot', 'Arcane Shot',
  'Multi-Shot', 'Raptor Strike', 'Mongoose Bite', 'Wing Clip', 'Kill Command', 'Disengage', 'War Stomp', 'Scatter Shot',
  'Freezing Trap', 'Frost Trap', 'Immolation Trap', 'Explosive Trap', 'Deterrence', 'Counterattack' }

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
    if (a.name == 'Attack' or a.kind == 'hint') and step == 1 and not c.inCombat then break end
  end
  if plan[1] and ns.Mem then plan[1] = ns.Mem.swap(c, plan[1]) end
  if plan[1] then plan[1].wait = startT end
  local util
  if c.inCombat and c.hostile then
    local danger = c.aggro or (c.enemies.onMe or 0) > 0 or ns.hpBelow('player', 25) == true
    local hp = ns.Bags.best('hpot')
    if hp and danger and ns.hpBelow('player', c.db.potionHP) and ns.itemReady(hp, 'potion', 120) then
      util = A('item:' .. hp, 'Healing Potion!', 'item', { item = hp, urgent = true })
    end
    if not util and ns.known('War Stomp') and ns.cdLeft('War Stomp') <= 0 and c.near and (c.enemies.onMe or 0) >= 2 then
      util = A('War Stomp', 'Vic mobu u tebe: War Stomp (omraci je), odstup a strilej', 'spell')
    end
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
  end
  return plan, util
end

function E.infoLine(c)
  local p = { '|cffabd473' .. (SPEC_CZ[c.spec] or 'Hunter') .. '|r' }
  if not c.pet then p[#p + 1] = '|cffffcc00bez peta|r'
  elseif c.petDead then p[#p + 1] = '|cffff6060pet mrtvy|r'
  elseif c.petHP then p[#p + 1] = ('pet %d %%'):format(math.floor(c.petHP)) end
  if c.pet and c.happy and c.happy < 3 then p[#p + 1] = '|cffffcc00pet hladovy|r' end
  if c.aspect then p[#p + 1] = '|cff9aa6b8' .. c.aspect:gsub('Aspect of the ', '') .. '|r' end
  if c.ammo and c.ammo < 200 then p[#p + 1] = ('|cffffcc00munice %d|r'):format(c.ammo) end
  return table.concat(p, '  |cff556070-|r  ')
end

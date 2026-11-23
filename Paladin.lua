-- ClaudeMaster: rozhodovaci logika pro Paladina (univerzalni, bez ohledu na specializaci).
-- Pouziva spolecny kontext (Frost.lua: cil, moby, parta, mana...) a pridava paladinske veci:
-- seal (sledovany z vlastnich castu, protoze aury jsou v boji skryte), aura, blessing,
-- Judgement / Strike na cooldown, leceni sebe a party, nouzove stity (Divine Protection / Shield).
local ADDON, ns = ...
if not ns.enabled or ns.class ~= 'PALADIN' then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = ns.Engine
local PA = {}
ns.Paladin = PA

local SEALS = { 'Seal of Righteousness', 'Seal of Command', 'Seal of the Crusader', 'Seal of Wisdom', 'Seal of Light',
  'Seal of Justice', 'Seal of Vengeance', 'Seal of Blood', 'Seal of Martyrdom', 'Seal of Fury' }
local AURAS = { 'Devotion Aura', 'Retribution Aura', 'Concentration Aura', 'Sanctity Aura', 'Crusader Aura',
  'Shadow Resistance Aura', 'Frost Resistance Aura', 'Fire Resistance Aura' }
local BLESS = { 'Blessing of Might', 'Blessing of Wisdom', 'Blessing of Kings', 'Blessing of Sanctuary',
  'Blessing of Light', 'Blessing of Salvation', 'Greater Blessing of Might', 'Greater Blessing of Wisdom',
  'Greater Blessing of Kings', 'Greater Blessing of Sanctuary' }
local SEAL_SET = {} for _, n in ipairs(SEALS) do SEAL_SET[n] = true end
local SEAL_DUR, BLESS_DUR = 30, 600
local STRIKES = { 'Crusader Strike', 'Holy Strike', 'Hammer of the Righteous' }
-- Cleanse (42) umi i magii, Purify jen jed/nemoc
local function cure() return ns.known('Cleanse') and 'Cleanse' or 'Purify' end

-- Buffy hrace mimo boj: projit vsechny podle indexu (hledani podle jmena na Foreveru
-- sealy nenachazelo). Vysledek: jmeno -> expirationTime (0 = bez konce). V boji nil.
local buffCache, buffAt = nil, -1
local function myBuffs()
  if ns.inCombat() then return nil end
  if buffAt == GetTime() then return buffCache end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return nil end
  local t, seen = {}, {}
  for i = 1, 40 do
    local ok, a = pcall(get, 'player', i, 'HELPFUL')
    if not ok then return nil end
    if type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) == 'string' then
      t[n] = safeNum(a.expirationTime) or 0
      seen[#seen + 1] = n
    end
  end
  buffCache, buffAt = t, GetTime()
  if ns.db then ns.db.palBuffs = seen end   -- diagnostika: co hra opravdu ukazuje
  return t
end

-- Buff ze skupiny: jmeno (aktivni) / false (neni) / nil (nevime). V boji podle posledniho castu.
local function activeOf(list, dur, pat)
  local b = myBuffs()
  if b then
    for _, n in ipairs(list) do
      if b[n] then
        -- naucit cas nahozeni, at sledovani pokracuje i v boji (seal nahozeny pred /reload)
        if dur and b[n] > 0 then ns.castAt[n] = b[n] - dur end
        if not ns.castAt[n] then ns.castAt[n] = GetTime() end
        return n
      end
    end
    if pat then
      for n, exp in pairs(b) do
        if n:find(pat) then
          if dur and exp > 0 then ns.castAt[n] = exp - dur elseif not ns.castAt[n] then ns.castAt[n] = GetTime() end
          return n
        end
      end
    end
    return false
  end
  -- v boji hra o buffech lze ("neni"), takze jen podle castu / toho, co jsme videli mimo boj
  if not ns.inCombat() then
    local unknown = false
    for _, n in ipairs(list) do
      local a = ns.playerAura(n)
      if a == nil then unknown = true elseif a then return n end
    end
    if not unknown then return false end
  end
  local best, at = nil, -1
  local function consider(n, t)
    if t and t > at and (not dur or GetTime() - t < dur) then best, at = n, t end
  end
  for _, n in ipairs(list) do consider(n, ns.castAt[n]) end
  if pat then for n, t in pairs(ns.castAt) do if type(n) == 'string' and n:find(pat) then consider(n, t) end end end
  return best
end
local function forbearance()
  local f = ns.playerAura('Forbearance')
  if f then return true end
  for _, n in ipairs({ 'Divine Protection', 'Divine Shield', 'Blessing of Protection', 'Lay on Hands' }) do
    if GetTime() - (ns.castAt[n] or -999) < 60 then return true end
  end
  return false
end
local function shielded()
  return GetTime() - (ns.castAt['Divine Shield'] or -999) < 10 or GetTime() - (ns.castAt['Divine Protection'] or -999) < 6
end

-- Ktery seal: nastaveny rucne > malo many (Wisdom) > Command (talent) > Righteousness > Crusader
-- mas stit v ruce? (Seal of Fury dava se stitem absorb, Righteous Fury jen pro tanka)
local function hasShield()
  local id = safeNum(pc(GetInventoryItemID, 'player', 17))
  if not id then return false end
  local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local _, _, _, loc = pc(f, id)
  return safe(loc) == 'INVTYPE_SHIELD'
end
-- ma unit neco, co umim odstranit (filtr RAID = jen co ja dispellnu)? true / false / nil (v boji)
local function dispellable(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, 1, 'HARMFUL|RAID')
  if not ok then return nil end
  if a ~= nil then return true end
  return not ns.inCombat() and false or nil
end
local function wantSeal(c)
  local pref = c.db.palSeal
  if pref and pref ~= 'auto' and ns.known(pref) then return pref end
  if c.manaKnown and c.mana < 0.2 and ns.known('Seal of Wisdom') and not c.tough then return 'Seal of Wisdom', 'malo many' end
  -- se stitem: Seal of Fury (Holy dmg + absorb stit z kazdeho uderu)
  if c.shield and ns.known('Seal of Fury') then return 'Seal of Fury' end
  -- engine: ret i prot drzi Righteousness (nemuze minout, skaluje se spell power i rychlosti zbrane)
  if ns.known('Seal of Righteousness') then return 'Seal of Righteousness' end
  if ns.known('Seal of Command') then return 'Seal of Command' end
  return ns.known('Seal of the Crusader') and 'Seal of the Crusader' or nil
end
local function wantAura(c)
  if c.group and ns.known('Retribution Aura') and c.tankUp then return 'Retribution Aura' end
  return ns.known('Devotion Aura') and 'Devotion Aura' or nil
end
local function wantBless(c)
  local pref = c.db.palBless
  if pref and pref ~= 'auto' and ns.known(pref) then return pref end
  return ns.known('Blessing of Might') and 'Blessing of Might' or nil
end
local function bestHeal(urgent)
  if urgent and ns.known('Flash of Light') then return 'Flash of Light' end
  if ns.known('Holy Light') then return 'Holy Light' end
  return ns.known('Flash of Light') and 'Flash of Light' or nil
end

------------------------------------------------------------------------------------------
-- Kontext
------------------------------------------------------------------------------------------
local baseContext = E.context
E.context = function()
  local c = baseContext()
  c.seal = activeOf(SEALS, SEAL_DUR, '^Seal of')
  c.sealLeft = nil   -- nil = seal je (aura), ale nevime kolik zbyva
  if c.seal and ns.castAt[c.seal] and GetTime() - ns.castAt[c.seal] < SEAL_DUR then
    c.sealLeft = SEAL_DUR - (GetTime() - ns.castAt[c.seal])
  end
  c.palAura = activeOf(AURAS, nil, ' Aura$')
  c.bless = activeOf(BLESS, nil, 'Blessing of')
  c.forb = forbearance()
  c.healerUp = false
  for _, m in ipairs((c.party and c.party.members) or {}) do
    if m.healer and m.alive and not m.unit:find('pet') then c.healerUp = true end
  end
  c.undead = c.ctype == 'Undead' or c.ctype == 'Demon'
  c.shield = hasShield()
  c.rf = ns.known('Righteous Fury') and activeOf({ 'Righteous Fury' }) or nil
  -- dosah: Attack (6603) nema dosah, takze melee merime pres Strike, Judgement ma 10 yd
  local function inR(n)
    local id = ns.id(n)
    if not id or not c.hostile or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    return safeBool(pc(C_Spell.IsSpellInRange, id, 'target'))
  end
  local m = inR('Crusader Strike')
  if m == nil then m = inR('Holy Strike') end
  if m ~= nil then c.near = m end
  c.judgeR = inR('Judgement')
  if c.judgeR == nil then c.judgeR = c.near end
  c.hojR = inR('Hammer of Justice')
  if c.hojR == nil then c.hojR = c.near end
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

local function decide(c, s)
  local db = c.db
  local function bad(n) return c.imm ~= nil and ns.Immune.bad(c.imm, n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if ns.cost(n) > 0 and s.mana * ns.manaMax() < ns.cost(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  local php = c.php or 100
  local town = c.resting and not c.hostile

  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    local aura = wantAura(c)
    if c.palAura == false and aura and not s.used.aura then
      s.used.aura = true
      return A(aura, 'Chybi aura')
    end
    -- tank se stitem ve skupine: Righteous Fury (vic threatu)
    if c.rf == false and c.shield and c.group and not town and ready('Righteous Fury') then
      return A('Righteous Fury', 'Tankujes se stitem: Righteous Fury (vic aggra)')
    end
    -- jed / nemoc (Cleanse i magie) na tobe nebo na partakovi
    local cu = cure()
    if ready(cu) then
      if dispellable('player') then return A(cu, 'Mas na sobe debuff: ' .. cu, 'spell', { unit = 'player' }) end
      for _, m in ipairs((c.party and c.party.members) or {}) do
        if m.alive and not m.unit:find('pet') and dispellable(m.unit) then
          return A(cu, ('%s ma debuff: %s'):format(m.name or '?', cu), 'spell', { unit = m.unit })
        end
      end
    end
    local bl = wantBless(c)
    if c.bless == false and bl and not town and not s.used.bless and ready(bl) then
      s.used.bless = true
      return A(bl, 'Chybi Blessing', 'spell', { unit = 'player' })
    end
    -- leceni party (mimo boj, nikdo jiny neleci)
    local pt = c.party or {}
    for _, m in ipairs(pt.members or {}) do
      if m.alive and m.low and not m.unit:find('pet') and not c.healerUp then
        local h = bestHeal(false)
        if h and ready(h) and not s.used.heal then
          s.used.heal = true
          return A(h, ('%s ma malo HP - vylec ho'):format(m.name or '?'), 'spell', { unit = m.unit })
        end
      end
    end
    -- vlastni HP: kouzlo je levnejsi nez cekat na jidlo, kdyz je many dost
    if s.step == 1 and php < 70 and not c.eating and not c.drinking and (not c.manaKnown or c.mana > 0.45) then
      local h = bestHeal(false)
      if h and ready(h) then
        s.used.heal = true
        return A(h, ('HP ~%d%%: %s (mana se doplni pitim)'):format(math.floor(php), h), 'spell', { unit = 'player' })
      end
    end
    if s.step == 1 and not c.eating and php < 50 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(php)), 'item', { item = fd }) end
    end
    if s.step == 1 and c.manaKnown and c.mana < (db.drinkMana or 0.55) and not c.drinking and not c.hostile then
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
    end
    if c.drinking or c.eating then return nil end
    if c.hostile then
      local seal = wantSeal(c)
      if not c.seal and seal and ready(seal) and not s.seal then
        return A(seal, 'Pred pullem: ' .. seal)
      end
      if c.judgeR and ready('Judgement') and (c.seal or s.seal) then return A('Judgement', 'Pull: Judgement') end
      if ready('Exorcism') and c.undead then return A('Exorcism', 'Pull: Exorcism (undead/demon)') end
      return A('Attack', c.near and 'Utoc (auto attack)' or 'Pull: dojdi k cili', 'wait')
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  -- nouze
  local danger = c.aggro or (c.enemies.onMe or 0) > 0
  if s.step == 1 and php < 15 and ready('Lay on Hands') then
    return A('Lay on Hands', 'Umiras: Lay on Hands!', 'spell', { urgent = true, unit = 'player' })
  end
  if s.step == 1 and danger and php < 20 and not c.forb and ready('Divine Shield') then
    s.shield = true
    return A('Divine Shield', 'Umiras: Divine Shield, pak se vylec', 'spell', { urgent = true })
  end
  if s.step == 1 and danger and php < 30 and not c.forb and ready('Divine Protection') and not c.healerUp then
    s.shield = true
    return A('Divine Protection', 'Malo HP: Divine Protection, pak se vylec', 'spell', { urgent = true })
  end
  -- Templar's Bulwark (talent): absorb stit na 8 s, take dava Forbearance
  if s.step == 1 and danger and php < 40 and not c.forb and ready("Templar's Bulwark") then
    s.shield = true
    return A("Templar's Bulwark", "Malo HP: Templar's Bulwark (stit)", 'spell', { urgent = true })
  end
  -- malo HP a mob te bije: omrac ho Hammer of Justice a vylec se (stun = 3+ s klidu na Holy Light)
  if s.step == 1 and danger and php < 40 and not c.healerUp and c.hostile and c.hojR and ready('Hammer of Justice')
    and not shielded() and bestHeal(false) then
    s.used['Hammer of Justice'] = true
    s.stunned = true
    return A('Hammer of Justice', 'Malo HP: omrac moba (Hammer of Justice) a hned se vylec', 'spell', { urgent = true })
  end
  if s.stunned and php < 80 then
    local h = bestHeal(false)
    if h and ready(h) then
      s.used[h] = true
      return A(h, 'Mob je omraceny: ' .. h .. ' na sebe', 'spell', { unit = 'player' })
    end
  end
  -- pod stitem: lec se (nic te neprerusi)
  if (shielded() or s.shield) and php < 80 then
    local h = bestHeal(false)
    if h and ready(h) then
      s.used[h] = true
      return A(h, 'Jsi chraneny: ' .. h .. ' na sebe', 'spell', { unit = 'player' })
    end
  end
  if php < 35 and not c.healerUp then
    local h = bestHeal(php < 25)
    if h and ready(h) then
      s.used[h] = true
      return A(h, ('HP ~%d%%: %s'):format(math.floor(php), h), 'spell', { unit = 'player', urgent = php < 25 })
    end
  end
  -- spoluhrac (ne tank) umira a bije ho mob: Blessing of Protection (fyzicke utoky mu neublizi)
  if c.group then
    local tank = c.party and c.party.tank
    for _, m in ipairs((c.party and c.party.members) or {}) do
      if m.alive and m.veryLow and (m.mobs or 0) > 0 and m ~= tank and not m.unit:find('pet') and ready('Blessing of Protection') then
        s.used['Blessing of Protection'] = true
        return A('Blessing of Protection', ('%s umira a mob ho bije: Blessing of Protection'):format(m.name or '?'), 'spell',
          { unit = m.unit, urgent = true })
      end
    end
  end
  -- party bez lecitele: zachran spoluhrace
  if c.group and not c.healerUp then
    for _, m in ipairs((c.party and c.party.members) or {}) do
      if m.alive and m.veryLow then
        local h = bestHeal(true)
        if h and ready(h) then
          s.used[h] = true
          return A(h, ('%s umira - %s na nej'):format(m.name or '?', h), 'spell', { unit = m.unit, urgent = true })
        end
      end
    end
  end
  -- jed / nemoc v boji (kdyz to hra prozradi)
  if s.step == 1 and ready(cure()) and dispellable('player') == true and php < 70 then
    return A(cure(), 'Debuff na tobe: ' .. cure(), 'spell', { unit = 'player' })
  end
  if not c.hostile then return nil end
  -- preruseni / stun kouzlici mobky
  if c.tCasting and c.interruptible and c.hojR and ready('Hammer of Justice') then
    s.used['Hammer of Justice'] = true
    return A('Hammer of Justice', 'Mob kouzli: Hammer of Justice (stun = preruseni)', 'spell', { urgent = true })
  end
  -- Repentance (talent): HoJ je na cooldownu, mob kouzli -> uspi ho
  if c.tCasting and c.interruptible and c.near and ready('Repentance') and not ready('Hammer of Justice') then
    s.used.Repentance = true
    return A('Repentance', 'Mob kouzli: Repentance (preruseni)', 'spell', { urgent = true })
  end
  -- mob, ktery pri malo HP utika (humanoid / vime z minula): omracit tesne pred utekem, at nepritahne dalsi
  local mob = c.mob
  if mob and mob.flees and c.hojR and ready('Hammer of Justice') and not c.targetCC
    and (mob.fleeingNow or (not c.tLow10 and ((c.thp and c.thp < 30) or c.tLow20))) and not (c.ttd and c.ttd < 2) then
    s.used['Hammer of Justice'] = true
    return A('Hammer of Justice', mob.fleeingNow and 'Mob utika: Hammer of Justice, at nepritahne dalsi'
      or 'Mob pri malo HP utika: omrac ho (Hammer of Justice) a dobij', 'spell', { urgent = mob.fleeingNow })
  end
  -- seal
  local seal = wantSeal(c)
  local sealOn = s.seal or (c.seal and (c.sealLeft == nil or c.sealLeft > s.t + 1))
  if not sealOn and seal and ready(seal) then
    s.seal = seal
    return A(seal, c.seal and 'Seal dobiha - obnov ho' or 'Chybi seal: ' .. seal)
  end
  local aoe = c.enemies.cluster or c.enemies.combat or 0
  -- Holy Shield: se stitem, kdyz te moby bijou (blok + holy damage)
  if c.shield and danger and ready('Holy Shield') and not s.used['Holy Shield'] then
    s.used['Holy Shield'] = true
    return A('Holy Shield', 'Moby te bijou: Holy Shield')
  end
  if c.tLow20 and ready('Hammer of Wrath') then return A('Hammer of Wrath', 'Cil pod 20 %: Hammer of Wrath') end
  -- Holy Wrath: undead/demon kolem tebe
  if c.undead and c.near and ready('Holy Wrath') and (aoe >= 2 or not c.manaKnown or s.mana > 0.5) then
    return A('Holy Wrath', 'Undead/demon: Holy Wrath')
  end
  if aoe >= 2 and c.near and ready('Hammer of the Righteous') then
    return A('Hammer of the Righteous', ('%d moby: Hammer of the Righteous'):format(aoe))
  end
  if c.judgeR and ready('Judgement') then return A('Judgement', 'Judgement (seal zustava)') end
  -- Swift Judgement (ret talent): druhy Judgement s vlastnim cooldownem
  if c.judgeR and ready('Swift Judgement') then return A('Swift Judgement', 'Swift Judgement (vlastni cooldown)') end
  if c.undead and ready('Exorcism') then return A('Exorcism', 'Undead/demon: Exorcism') end
  if c.near then
    for _, n in ipairs(STRIKES) do
      if ready(n) then return A(n, n) end
    end
  end
  if aoe >= 2 and c.near and ready('Consecration') and (not c.manaKnown or s.mana > 0.3) then
    return A('Consecration', ('%d moby kolem: Consecration'):format(aoe))
  end
  -- jeden cil: Consecration jen kdyz je many dost (engine: od 70 %)
  if c.near and ready('Consecration') and c.manaKnown and s.mana >= 0.7 and not c.tLow20 then
    return A('Consecration', 'Hodne many: Consecration i na jeden cil')
  end
  if not c.near and ready('Holy Shock') and (not c.manaKnown or s.mana > 0.4) then
    return A('Holy Shock', 'Cil je daleko: Holy Shock')
  end
  if not c.near then return A('Attack', 'Dojdi k cili (melee)', 'wait', { dur = 1.5 }) end
  -- nic neni ready: kdy bude neco
  local nxt
  for _, n in ipairs({ 'Judgement', 'Crusader Strike', 'Holy Strike', 'Hammer of Justice' }) do
    if ns.known(n) and not bad(n) then
      local t = (s.cd[n] or 0) - s.t
      if t > 0 and (not nxt or t < nxt) then nxt = t end
    end
  end
  local dur = math.max(0.5, math.min(nxt or 1.5, 3))
  return A('Attack', 'Auto attack, dalsi schopnost za chvili', 'wait', { dur = dur })
end

local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  if a.kind == 'wait' then s.used[n] = true s.t = s.t + (a.dur or 1.5) return end
  s.mana = math.max(0, s.mana - ns.cost(n) / ns.manaMax())
  local cd, ct = ns.cdFor(n), ns.castTime(n)
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  if SEAL_SET[n] then s.seal = n end
  if not c.inCombat then s.used[n] = true end
  s.t = s.t + (ns.OFF_GCD[n] and 0 or math.max(1.5, ct))
end

function E.plan(c)
  local s = { t = 0, mana = c.mana, cd = {}, used = {}, step = 1 }
  -- cooldowny vsech znamych kouzel (i tech, ktera prijdou s levelem)
  for _, n in ipairs(ns.SPELLS) do if ns.known(n) and ns.cdFor(n) > 1.5 then s.cd[n] = ns.cdLeft(n) end end
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
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
  end
  return plan, util
end

-- Radek do panelu: seal, aura, blessing
function E.infoLine(c)
  local p = {}
  local function short(n) return (n or ''):gsub('^Seal of ', ''):gsub('^the ', ''):gsub(' Aura$', ''):gsub('^Greater ', 'G.'):gsub('^Blessing of ', '') end
  if c.seal then
    local l = c.sealLeft or 0
    p[#p + 1] = (l > 0 and l < 6 and '|cffffcc00' or '|cffffe08a') .. 'Seal ' .. short(c.seal) .. (l > 0 and (' ' .. math.ceil(l) .. 's') or '') .. '|r'
  else
    p[#p + 1] = '|cffff7070bez sealu|r'
  end
  if c.palAura then p[#p + 1] = '|cff9aa6b8' .. short(c.palAura) .. '|r'
  elseif c.palAura == false then p[#p + 1] = '|cffffcc00bez aury|r' end
  if c.bless then p[#p + 1] = '|cff9aa6b8' .. short(c.bless) .. '|r'
  elseif c.bless == false then p[#p + 1] = '|cffffcc00bez Blessing|r' end
  if c.forb then p[#p + 1] = '|cffff9060Forbearance|r' end
  return table.concat(p, '  |cff556070-|r  ')
end

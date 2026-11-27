-- ClaudeMaster: rozhodovaci logika pro Frost Mage.
-- Kazdy krok se rozhoduje nad "simulovanym" stavem, takze druhe a treti doporuceni
-- uz pocitaji s tim, co udela to prvni (Frost Nova -> cil zmrazen -> Ice Lance, atd.).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local E = {}
ns.Engine = E

local ARMORS = { 'Ice Armor', 'Frost Armor', 'Mage Armor', 'Molten Armor' }
local GEMS = { 'Conjure Mana Ruby', 'Conjure Mana Citrine', 'Conjure Mana Jade', 'Conjure Mana Agate' }

local function hasBuff(names, trackedUntil)
  local unknown = false
  for _, n in ipairs(names) do
    local a = ns.playerAura(n)
    if a == nil then unknown = true elseif a then return true end
  end
  if unknown then return GetTime() < (trackedUntil or 0) end
  return false
end
-- Armor podle situace:
--  tank drzi moby (parta s tankem / dungeon ve skupine) -> Mage Armor (mana i pri kouzleni; na tebe nikdo nebije)
--  solo proti kouzlici mobce -> Mage Armor (+odolnost, zpomaleni by stejne nebylo k nicemu)
--  jinak (solo, parta bez tanku) -> Ice/Frost Armor (armor + zpomali kazdeho, kdo te bije)
local function armorSitu(c)
  return (c.tankUp or (c.instance and c.group)) and 'tank' or 'solo'
end
local function bestArmor(c)
  local ice = (ns.known('Ice Armor') and 'Ice Armor') or (ns.known('Frost Armor') and 'Frost Armor') or nil
  local mage = ns.known('Mage Armor') and 'Mage Armor' or nil
  if not c then return ice or mage end
  if mage and armorSitu(c) == 'tank' then return mage, 'tank drzi moby, mana pri kouzleni' end
  if mage and not c.group and c.hostile and c.mob and c.mob.caster then return mage, 'cil kouzli: +odolnost, mana' end
  if ice then return ice, 'moby te bijou: zpomali je' end
  return mage
end
local function currentArmor()
  for _, n in ipairs(ARMORS) do
    if ns.playerAura(n) then return n end
  end
  if GetTime() < (ns.armorUntil or 0) then return ns.armorName end
end

------------------------------------------------------------------------------------------
-- Kontext: vse, co o situaci vime
------------------------------------------------------------------------------------------
local fallStart
function E.context()
  local c = { now = GetTime() }
  c.db = ns.db
  c.inCombat = ns.inCombat()
  c.lead = ns.queueLead()
  c.group = IsInGroup and IsInGroup() or false
  -- mesto / hostinec (rested zona): buffy tu nedavaji smysl, vyprsi nez vyrazis
  c.resting = IsResting and safeBool(pc(IsResting)) == true or false
  c.moving = (safeNum(pc(GetUnitSpeed, 'player')) or 0) > 0

  c.mana, c.manaExact, c.manaLo, c.manaHi = ns.mana()
  c.manaKnown = c.mana ~= nil
  if not c.manaKnown then c.mana = 0.6 end   -- nevime: neutralni hodnota, rozhodnuti podle many se vypnou
  c.php = ns.healthPct('player')
  c.hpLow20 = ns.hpBelow('player', 20) == true
  c.hpLow35 = ns.hpBelow('player', 35) == true
  c.hpSure35 = ns.hpBelowSure and ns.hpBelowSure(35) or false
  c.hpSure50 = ns.hpBelowSure and ns.hpBelowSure(50) or false
  c.hpLow50 = ns.hpBelow('player', 50) == true
  c.hpLow75 = ns.hpBelow('player', 75) == true

  c.target = UnitExists('target')
  c.hostile = c.target and safeBool(pc(UnitCanAttack, 'player', 'target')) == true
    and safeBool(pc(UnitIsDeadOrGhost, 'target')) ~= true
  if c.hostile then
    c.tPlayer = safeBool(pc(UnitIsPlayer, 'target')) == true
    if ns.Immune then
      ns.Immune.refreshTarget()
      c.imm = ns.Immune.info()
      c.ctype = c.imm.ctype
    end
    local cls = safe(pc(UnitClassification, 'target'))
    local lv, my = safeNum(pc(UnitLevel, 'target')), safeNum(pc(UnitLevel, 'player')) or 1
    c.elite = cls == 'elite' or cls == 'rareelite' or cls == 'worldboss' or lv == -1
    c.boss = cls == 'worldboss' or lv == -1
    c.levelDiff = lv and lv > 0 and (lv - my) or (lv == -1 and 10) or 0
    c.tough = c.elite or c.tPlayer or c.levelDiff >= 3
    c.thp, c.thpExact, c.thpLo, c.thpHi = ns.healthPct('target')
    c.tLow10 = ns.hpBelow('target', 10) == true
    c.tLow20 = ns.hpBelow('target', 20) == true
    c.tLow35 = ns.hpBelow('target', 35) == true
    c.ttd = ns.ttd()
    c.near = ns.near('target') == true
    local fb = ns.id('Frostbolt') or ns.id('Fireball')
    c.inRange = fb and C_Spell and safeBool(pc(C_Spell.IsSpellInRange, fb, 'target'))
    ns.T.near = c.near
    -- kouzli cil? (jmeno muze byt skryte, ale "neco" tam je)
    local r = { pc(UnitCastingInfo, 'target') }
    local casting = ns.isSet(r[1])
    local notInt = r[8]
    local sid = r[9]
    if not casting then
      r = { pc(UnitChannelInfo, 'target') }
      casting = ns.isSet(r[1])
      notInt = r[7]
      sid = r[8]
    end
    -- co kouzli a jak moc stoji za preruseni
    c.tCastName, c.tCastPrio, c.tCastWhy, c.tCastKind = nil, nil, nil, nil
    if casting and ns.castPrio then
      local nm = safe(r[1])
      local st, en = safeNum(r[4]), safeNum(r[5])
      c.tCastName = type(nm) == 'string' and nm or nil
      c.tCastPrio, c.tCastWhy, c.tCastKind = ns.castPrio(c.tCastName, safeNum(sid), (st and en) and (en - st) or nil)
    end
    ns.lastTCast = casting and c.tCastName or nil
    c.tCasting = casting
    c.interruptible = casting and safeBool(notInt) ~= true
    -- Forever muze "nejde prerusit" skryvat: zkusit stit na cast baru (sedy bar) a co jsme se naucili
    if c.interruptible and ns.castShielded and ns.castShielded() then c.interruptible = false end
    if c.interruptible and c.tCastName and ns.db.noKick and ns.db.noKick[c.tCastName] then c.interruptible = false end
    -- jak dlouho uz cil kouzli (kvuli interrupt rotaci v parte)
    if casting and not ns.tCastWas then ns.tCastStart = GetTime() end
    ns.tCastWas = casting
    c.tCastAge = casting and (GetTime() - (ns.tCastStart or GetTime())) or 0
    -- agro
    local tt = safeBool(pc(UnitIsUnit, 'targettarget', 'player'))
    -- isTanking, status (0-3), scaledPercent (100 = strhnes aggro), rawPercent
    local tanking, status, scaled = pc(UnitDetailedThreatSituation, 'player', 'target')
    c.threat = safeNum(scaled)
    c.threatStatus = safeNum(status)
    if c.threatStatus == nil then c.threatStatus = safeNum(pc(UnitThreatSituation, 'player', 'target')) end
    c.tt, c.tanking = tt, safeBool(tanking)
    c.aggro = tt == true or c.tanking == true or (not c.group and c.inCombat and tt == nil)
  end

  ns.phase = 'enemies' c.enemies = ns.scanEnemies() ns.phase = 'context'
  if c.hostile then
    if not c.near and c.enemies.targetNear then c.near = true ns.T.near = true end
    -- mob u tebe v boji skoro jiste jde po tobe (Forever cil cile casto skryva)
    if not c.aggro and c.near and c.inCombat and c.tanking ~= false and c.tt ~= false then c.aggro = true end
  end
  if c.hostile and c.inCombat and c.enemies.combat < 1 then c.enemies.combat = 1 end
  if c.enemies.onMe == 0 and c.aggro then c.enemies.onMe = 1 end
  c.dangerAdds = (not c.group) and c.enemies.onMe >= 3
  ns.phase = 'party' c.party = ns.Party and ns.Party.scan(c) or {} ns.phase = 'context'

  c.fof = ns.fofStacks()
  c.frozen = ns.frozenLeft()
  c.barrierUp = ns.cdm('player', 'Ice Barrier') or (ns.playerAura('Ice Barrier') and true) or GetTime() < ns.barrierUntil
  c.armor = hasBuff(ARMORS, ns.armorUntil)
  c.ai = hasBuff({ 'Arcane Intellect', 'Arcane Brilliance' }, ns.aiUntil)
  c.drinking = (ns.playerAura('Drink') or ns.playerAura('Refreshment')) and true or false
  c.eating = (ns.playerAura('Food') or ns.playerAura('Refreshment')) and true or false
  c.instance = IsInInstance and select(1, IsInInstance()) or false

  c.castName, c.castLeft, c.channel = ns.casting()
  c.gcd = ns.gcdLeft()
  -- padani (Slow Fall)
  local falling = IsFalling and IsFalling()
  if falling then fallStart = fallStart or GetTime() else fallStart = nil end
  c.fallTime = fallStart and (GetTime() - fallStart) or 0
  -- ztrata kontroly (stun / fear) - Will to Survive
  if C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount then
    c.loc = (safeNum(pc(C_LossOfControl.GetActiveLossOfControlDataCount)) or 0) > 0
  end
  -- jakou skolou nas cil bije: podle kouzla, ktere prave sesila, jinak podle jmena (Fire Elemental...)
  if c.hostile then
    c.tCaster = safeNum(pc(UnitPowerType, 'target')) == 0 and safeNum(pc(UnitPowerMax, 'target')) ~= nil
      and (safeNum(pc(UnitPowerMax, 'target')) or 0) > 0
    local spellName = c.tCasting and safe((pc(UnitCastingInfo, 'target'))) or nil
    if type(spellName) ~= 'string' and c.tCasting then spellName = safe((pc(UnitChannelInfo, 'target'))) end
    c.tCastSchool = ns.Immune.guessSchool(type(spellName) == 'string' and spellName or nil)
    -- pamet: co vime o tomto druhu moba z minulych boju
    c.mob = ns.Mem and ns.Mem.info(ns.Immune.tname, c.ctype, c.group)
    -- "utika" je podle jmena: po tabu na jineho moba se stejnym jmenem to neplati,
    -- pokud to neni ten samy cil (token) nebo nema opravdu malo HP
    if c.mob and c.mob.fleeingNow then
      local tok = ns.Mem.fleeTok and ns.Mem.fleeTok[ns.Immune.tname]
      if tok ~= ns.T.token and not c.tLow35 then c.mob.fleeingNow = nil end
    end
    c.wardSchool = c.tCastSchool or (c.mob and c.mob.school) or ns.Immune.guessSchool(ns.Immune.tname)
    if c.mob and c.mob.nb >= 2 and c.mob.ttd and c.mob.ttd > 35 then c.tough = true c.memTough = true end
    if not c.ttd and c.mob and c.mob.ttd and c.mob.nb >= 2 and ns.T.engagedAt then
      c.ttdMem = math.max(1, c.mob.ttd - (GetTime() - ns.T.engagedAt))
    end
    -- cil je ovce / jiny CC: nebit
    if c.inCombat and ns.isCC then c.targetCC = ns.isCC('target') == true end
    -- parta: bije tank stejny cil?
    local tank = c.party and c.party.tank
    if tank and c.inCombat then
      local tt = tank.unit .. 'target'
      if UnitExists(tt) and safeBool(pc(UnitCanAttack, 'player', tt)) and safeBool(pc(UnitIsDeadOrGhost, tt)) ~= true then
        c.offTank = safeBool(pc(UnitIsUnit, 'target', tt)) == false
        c.tankName = tank.name
      end
    end
  end
  c.novaAgo = GetTime() - (ns.castAt['Frost Nova'] or -99)
  -- dungeon / parta s tankem
  c.pullAge = ns.T.engagedAt and (GetTime() - ns.T.engagedAt) or 0
  local tk = c.party and c.party.tank
  c.tankUp = c.group and tk ~= nil
  ns.armorSituNow = armorSitu(c)
  if tk then c.tankMobs = c.enemies.on[tk.unit] or 0 c.tankName = c.tankName or tk.name end
  if c.hostile then c.mark = safeNum(pc(GetRaidTargetIndex, 'target')) end
  -- skutecny threat (kdyz ho Forever neskryva): % k pretazeni aggra od tanka
  c.threatPct, c.threatStatus = nil, nil
  if c.hostile and c.inCombat and UnitDetailedThreatSituation then
    local tanking, status, scaled = pc(UnitDetailedThreatSituation, 'player', 'target')
    c.threatPct, c.threatStatus = safeNum(scaled), safeNum(status)
    if safeBool(tanking) then c.aggro = true end
  end
  c.shadowWardUp = (ns.playerAura('Shadow Ward') and true) or GetTime() - (ns.castAt['Shadow Ward'] or -99) < 30
  c.manaShieldUp = (ns.playerAura('Mana Shield') and true) or GetTime() - (ns.castAt['Mana Shield'] or -99) < 60
  c.wardUp = (ns.playerAura('Fire Ward') or ns.playerAura('Frost Ward')) and true
    or GetTime() - math.max(ns.castAt['Fire Ward'] or -99, ns.castAt['Frost Ward'] or -99) < 30
  c.flamestrikeLeft = 8 - (GetTime() - (ns.castAt['Flamestrike'] or -99))
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
  local function can(n) return ns.known(n) and not bad(n) end
  local function ready(n)
    if not ns.known(n) or s.used[n] or bad(n) then return false end
    if ns.cost(n) > 0 and s.mana * ns.manaMax() < ns.cost(n) then return false end
    return (s.cd[n] or 0) <= s.t + c.lead
  end
  local frozenLeft = s.frozenUntil - s.t
  local fbCast = ns.castTime('Frostbolt')
  -- filler: prvni kouzlo, na ktere cil neni imunni
  local filler = 'Shoot'
  for _, n in ipairs({ 'Frostbolt', 'Fireball', 'Frostfire Bolt', 'Arcane Missiles', 'Scorch' }) do
    if can(n) then filler = n break end
  end
  local nEnemies = c.enemies.combat
  -- AoE jen na moby, ktere stoji pohromade (bijou stejneho cloveka); ovce se nepocitaji
  local aoeN = c.enemies.cluster or nEnemies
  local sheep = (c.enemies.cc or 0) > 0

  -- padas uz pres 2 s (ne obycejny skok): Slow Fall
  if s.step == 1 and c.fallTime > 2 and ready('Slow Fall') then
    s.used['Slow Fall'] = true
    return A('Slow Fall', 'Padas: Slow Fall!', 'spell', { urgent = true, unit = 'player' })
  end
  -- omraceny / vystraseny v boji: lidsky racial
  if s.step == 1 and c.loc and c.inCombat and ready('Will to Survive') then
    s.used['Will to Survive'] = true
    return A('Will to Survive', 'Jsi pod kontrolou (stun/fear): Will to Survive', 'spell', { urgent = true })
  end

  -- tagovani: sedy (cizi) mob / nekdo ho vzal behem castu / instant otvirak v plne oblasti
  if ns.Tactics and ns.Tactics.tagHint then
    local tg = ns.Tactics.tagHint(c, s, A, ready) or ns.Tactics.tagOpener(c, s, A, ready)
    if tg then return tg end
  end

  ---------------------------------------------------------------- mimo boj
  if not c.inCombat then
    local want, why = bestArmor(c)
    local town = c.resting and not c.hostile   -- ve meste: zadne buffy (az venku)
    if not c.armor and want and not s.used.armor and not town then
      s.used.armor = true
      return A(want, 'Chybi ti armor' .. (why and (' (' .. why .. ')') or ''))
    end
    -- situace se od nahozeni zmenila (pripojil se tank / parta se rozpadla): vymenit.
    -- Kdyz si jinou armor das sam ve stejne situaci, addon to respektuje.
    local cur = currentArmor()
    if c.armor and want and cur and cur ~= want and ns.armorSitu and ns.armorSitu ~= armorSitu(c) and not town
      and not c.drinking and not c.eating and (not c.manaKnown or c.mana >= 0.4) and not s.used.armor then
      s.used.armor = true
      return A(want, ('Vymen %s za %s (%s)'):format(cur, want, why or ''))
    end
    if not c.ai and ns.known('Arcane Intellect') and not s.used['Arcane Intellect'] and not town then
      return A('Arcane Intellect', 'Chybi Arcane Intellect', 'spell', { unit = 'player' }) end
    -- parta: Arcane Intellect a curse
    local pt = c.party
    if pt.needAI and not s.used['Arcane Intellect'] and ready('Arcane Intellect') and not town then
      return A('Arcane Intellect', ('Arcane Intellect na %s'):format(pt.needAI.name), 'spell', { unit = pt.needAI.unit })
    end
    local decurse = ns.known('Remove Curse') and 'Remove Curse' or 'Remove Lesser Curse'
    if pt.curse and ns.known(decurse) and not s.used[decurse] then
      return A(decurse, ('Curse na %s - odstran ho'):format(pt.curse.name), 'spell', { unit = pt.curse.unit })
    end
    -- pred pullem i bez cile: scrolly z inventare (chybejici buff)
    local sc = not town and ns.Bags.missingScroll()
    if sc and not s.used['item:' .. sc.id] then
      return A('item:' .. sc.id, ('Chybi buff: %s'):format(sc.name), 'item', { item = sc.id })
    end
    local fam = not town and ns.Bags.missingFamiliar()
    if fam and not s.used['item:' .. fam.id] then
      return A('item:' .. fam.id, ('Bez familiara: %s (+Intellect na 1 h)'):format(fam.name), 'item', { item = fam.id })
    end
    -- docasne vylepseni zbrane (slot 16 = hlavni ruka)
    local im = not town and ns.Bags.missingImbue()
    if im and not s.used['item:' .. im.id] then
      return A('item:' .. im.id, ('Zbran bez vylepseni: %s'):format(im.name), 'item', { item = im.id, slot = 16 })
    end
    if c.hostile then
      -- elixir pred tezkym bojem
      if s.step == 1 and (c.tough or c.instance) then
        local ex = ns.Bags.missingElixir()
        if ex then return A('item:' .. ex.id, ('Pred tezkym bojem: %s'):format(ex.name), 'item', { item = ex.id }) end
      end
      -- staci mana na tohoto moba? (pamet: kolik many obvykle stoji)
      local need = ns.Mem and ns.Mem.needMana(ns.Immune.tname, c.group)
      local thresh = need and math.min(0.9, need * 1.15 + 0.05) or (c.tough and 0 or 0.35)
      if s.step == 1 and c.manaKnown and c.mana < thresh then
        local w = ns.Bags.best('water')
        if w and not c.drinking then
          return A('item:' .. w, need and ('Na tohoto moba obvykle padne ~%d%% many, mas %d%% - napij se')
            :format(math.floor(need * 100 + 0.5), math.floor(c.mana * 100)) or 'Malo many na pull - napij se', 'item', { item = w })
        end
      end
      -- znacka mesic = tvoje ovce: otevri pull Polymorphem
      if s.step == 1 and c.mark == 5 and c.group and ready('Polymorph') then
        s.used.Polymorph = true
        return A('Polymorph', 'Mesic = tvoje ovce: Polymorph, pak teprve tank pulluje')
      end
      -- mob z pameti kouzli ohnem/mrazem: ward jeste pred pullem
      if s.step == 1 and c.mob and c.mob.caster and (c.mob.school == 'fire' or c.mob.school == 'frost') and not c.wardUp then
        local ward = c.mob.school == 'fire' and 'Fire Ward' or 'Frost Ward'
        if ready(ward) then
          s.used[ward] = true
          return A(ward, ('Tento mob kouzli %s: %s pred pullem'):format(c.mob.school == 'fire' and 'ohnem' or 'mrazem', ward))
        end
      end
      if not c.group and c.tCaster and ready('Dampen Magic') and not ns.playerAura('Dampen Magic')
        and GetTime() - (ns.castAt['Dampen Magic'] or -999) > 600 then
        s.used['Dampen Magic'] = true
        return A('Dampen Magic', 'Cil je caster: Dampen Magic (mene dmg z kouzel)', 'spell', { unit = 'player' })
      end
      if db.prebarrier and ready('Ice Barrier') and not c.barrierUp and not s.barrier then
        s.barrier = true return A('Ice Barrier', 'Stit pred pullem') end
      if ready('Cryoblast') and c.tough and s.step == 1 then
        return A('Cryoblast', 'Otevri silnym kouzlem') end
      if can('Pyroblast') and not c.group and s.step == 1 and c.inRange ~= false then
        return A('Pyroblast', 'Pull: Pyroblast z max. dosahu (mob k tobe dojde az po dopadu)') end
      local adds = (c.enemies.idle or 0) > 0 and (' |cffffcc00(+%d blizko)|r'):format(c.enemies.idle) or ''
      return A(filler, (c.inRange == false and 'Pull: dojdi na dosah (30 yd)' or 'Pull: ' .. filler .. ' z max. dosahu') .. adds)
    end
    -- HP: najist se
    if s.step == 1 and not c.eating and c.php and c.php < 60 then
      local fd = ns.Bags.best('food')
      if fd then return A('item:' .. fd, ('HP ~%d%% - najez se'):format(math.floor(c.php)), 'item', { item = fd }) end
    end
    if c.manaKnown and c.mana < db.drinkMana and not c.drinking and s.step == 1 then
      if ready('Evocation') and c.mana < 0.4 and not c.hostile and c.enemies.combat == 0 then
        return A('Evocation', ('Mana %d%%, Evocation je ready: misto piti (8 min CD, pak zase voda)'):format(math.floor(c.mana * 100)))
      end
      local w = ns.Bags.best('water')
      if w then return A('item:' .. w, ('Mana %d%% - napij se'):format(math.floor(c.mana * 100)), 'item', { item = w }) end
      if ns.known('Conjure Water') then return A('Conjure Water', 'Nemas vodu - vyrob si ji') end
      if ready('Evocation') and c.manaKnown and c.mana < 0.3 then return A('Evocation', 'Bez vody: Evocation') end
    end
    if c.drinking or c.eating then return nil end
    -- buffovaci jidlo jen ve skupine / dungeonu
    if (c.group or c.instance) and s.step == 1 and not town then
      local wf = ns.Bags.missingWellFed()
      if wf then return A('item:' .. wf.id, ('Chybi Well Fed: %s'):format(wf.name), 'item', { item = wf.id }) end
    end
    for _, g in ipairs(GEMS) do
      if ns.known(g) then
        if ns.Bags.count('gem') == 0 and not s.used[g] and c.mana > 0.5 then return A(g, 'Nemas mana gem') end
        break
      end
    end
    if ns.known('Conjure Food') and ns.Bags.count('food') < 4 and c.mana > 0.6 and not s.used['Conjure Food'] then
      return A('Conjure Food', 'Doplnit jidlo (mas min nez 4)') end
    if ns.known('Conjure Water') and ns.Bags.count('water') < 6 and c.mana > 0.6 and not s.used['Conjure Water'] then
      return A('Conjure Water', 'Doplnit vodu (mas min nez 6)') end
    -- duo: partak s addonem nema vodu
    local peer = ns.Duo and ns.Duo.neediest and ns.Duo.neediest('water')
    -- vycarovana voda/jidlo stoji jen manu: parťák nemusi kupovat (pocita se jen vycarovane, kdyz to posila)
    local pw = peer and (peer.cw or peer.water)
    if peer and peer.cls ~= 'WARRIOR' and peer.cls ~= 'ROGUE' and peer.cls ~= 'MAGE' and pw < 5 and not peer.combat and s.step == 1 then
      if ns.Bags.countConj('water') >= 10 then
        local w = ns.Bags.best('water')
        return A('TARGET', ('%s ma jen %d vycarovane vody: posli ji svou (trade, zadarmo)'):format(peer.name, pw), 'hint',
          { icon = w and ns.itemIcon(w) or 'Interface\\Icons\\INV_Drink_18',
            trade = peer.unit and { unit = peer.unit, name = peer.name, item = w, what = 'vodu' } or nil })
      elseif ns.known('Conjure Water') and c.mana > 0.4 and not s.used['Conjure Water'] then
        return A('Conjure Water', ('%s ma jen %d vycarovane vody: vyrob a posli (trade)'):format(peer.name, pw))
      end
    end
    peer = ns.Duo and ns.Duo.neediest and ns.Duo.neediest('food')
    local pf = peer and (peer.cf or peer.food)
    if peer and peer.cls ~= 'MAGE' and pf and pf < 4 and not peer.combat and s.step == 1 then
      if ns.Bags.countConj('food') >= 10 then
        local fd = ns.Bags.best('food')
        return A('TARGET', ('%s ma jen %d vycarovaneho jidla: posli mu sve (trade, zadarmo)'):format(peer.name, pf), 'hint',
          { icon = fd and ns.itemIcon(fd) or 'Interface\\Icons\\INV_Misc_Food_10',
            trade = peer.unit and { unit = peer.unit, name = peer.name, item = fd, what = 'jidlo' } or nil })
      elseif ns.known('Conjure Food') and c.mana > 0.4 and not s.used['Conjure Food'] then
        return A('Conjure Food', ('%s ma jen %d vycarovaneho jidla: vyrob a posli (trade)'):format(peer.name, pf))
      end
    end
    return nil
  end

  if not c.hostile then
    -- cil padl / zadny cil, ale boj bezi dal
    if s.step == 1 and c.enemies.combat > 0 then
      local key = GetBindingKey and GetBindingKey('TARGETNEARESTENEMY')
      return A('TARGET', c.target and 'Cil je mrtvy - vyber dalsiho moba' or 'Vyber dalsiho moba', 'hint',
        { icon = 'Interface\\Icons\\Ability_Hunter_SniperShot', key = key })
    end
    return nil
  end

  ---------------------------------------------------------------- v boji
  -- Blizzard prave bezi: nech ho dobehnout, pokud nehori
  if s.step == 1 and c.channel and c.castName == 'Blizzard' and not c.hpLow35 then
    return A('Blizzard', ('Nech Blizzard dobehnout (%.1fs)'):format(c.castLeft), 'wait', { dur = c.castLeft })
  end

  -- 1) Nouze
  if c.aggro and c.hpLow20 then
    if ready('Ice Block') then return A('Ice Block', 'HP pod 20 % - Ice Block!', 'spell', { urgent = true }) end
  end
  -- 1b) cil je ovce / CC: nebit ho
  if s.step == 1 and c.targetCC then
    return A('TARGET', 'Cil je ovce/CC - nebij ho, vyber jiny cil', 'hint',
      { icon = 'Interface\\Icons\\Spell_Nature_Polymorph', key = GetBindingKey and GetBindingKey('TARGETNEARESTENEMY') })
  end
  -- 1c) mob utika (privede dalsi): zastavit nebo dorazit
  local mob = c.mob
  if s.step == 1 and mob and mob.fleeingNow then
    if c.near and ready('Frost Nova') then return A('Frost Nova', 'Mob utika! Frost Nova ho zastavi', 'spell', { urgent = true }) end
    if ready('Fire Blast') and c.inRange ~= false then return A('Fire Blast', 'Mob utika: dorazit Fire Blastem', 'spell', { urgent = true }) end
    if ready('Ice Lance') then return A('Ice Lance', 'Mob utika: Ice Lance', 'spell', { urgent = true }) end
    if c.near and ready('Cone of Cold') then return A('Cone of Cold', 'Mob utika: Cone of Cold ho zpomali', 'spell', { urgent = true }) end
    if can('Frostbolt') then return A('Frostbolt', 'Mob utika: Frostbolt ho zpomali', 'spell', { urgent = true }) end
  end
  if mob and mob.flees and c.tLow20 and not mob.fleeingNow and c.near and not c.group and frozenLeft <= 0 and ready('Frost Nova') then
    return A('Frost Nova', 'Mob brzy utece (malo HP): Frost Nova ho udrzi na miste')
  end
  -- 2) Preruseni
  local kw, kwhy = 'yes', nil
  if c.tCasting and ns.kickWorth then kw, kwhy = ns.kickWorth(c) end
  if s.step == 1 and c.tCasting and c.interruptible and c.inRange ~= false and ready('Counterspell') and kw ~= 'save' then
    local ks = c.group and ns.Party and ns.Party.kickState() or nil
    if ks and ks.justKicked then
      -- nekdo prave prerusil: neplytvat
    elseif ks and ks.claimedBy and c.tCastAge < 1.5 then
      return A('Counterspell', ('Interrupt: %s prave prerusuje - ty ne'):format(ks.claimedBy), 'wait', { dur = 0.5 })
    elseif ks and ks.others and ks.nextUp and not ks.nextUp.me and c.tCastAge < (kw == 'urgent' and 0.4 or 0.8) then
      -- na rade je nekdo jiny: chvili pockej, kdyby to nestihl, je to na tobe
      return A('Counterspell', ('Interrupt: na rade je %s (%s) - ty jen kdyz to nestihne'):format(ks.nextUp.name, ks.nextUp.spell),
        'wait', { dur = 0.8 })
    else
      if ks and ks.others and ns.Duo then ns.Duo.claimKick() end
      local why = (ks and ks.others) and ((ks.nextUp and ks.nextUp.me) and 'Interrupt: TED TY - Counterspell!'
        or 'Nikdo nepreusil - Counterspell ted!') or 'Cil kouzli - preruse ho!'
      if kwhy then why = why .. ' ' .. kwhy end
      return A('Counterspell', why, 'spell', { urgent = true })
    end
  end
  -- 2b) Parta: mob bije spoluhrace / pet umira
  local pt = c.party
  if s.step == 1 and pt then
    local d = pt.danger
    if d and (d.low or d.healer or d.mobs >= 2) and d.near and ready('Frost Nova') then
      return A('Frost Nova', ('Mob bije %s: Frost Nova u nej, pak odstup'):format(d.name), 'spell', { urgent = d.low })
    end
    if pt.petLow and not c.aggro and ready('Ice Barrier') and not c.barrierUp then
      return A('Ice Barrier', ('%s ma malo HP: Ice Barrier, budes brat aggro'):format(pt.petLow.name))
    end
  end
  -- 2c) dungeon: na zacatku pullu nech tanka nabrat aggro
  local tw = db.tankWait or 1.5
  if s.step == 1 and c.tankUp and not c.aggro and c.enemies.onMe == 0 and c.pullAge < tw and not c.tPlayer then
    local left = tw - c.pullAge
    return A(filler, ('Nech tanka nabrat aggro (%.1fs)'):format(left), 'wait', { dur = left })
  end
  -- 3) Threat ve skupine
  -- status 1 = mas vic threatu nez tank (mob se chysta prejit na tebe)
  if s.step == 1 and c.group and not c.aggro and ((c.threat and c.threat >= 90) or c.threatStatus == 1) then
    local t = c.threat and ('Threat %d%%'):format(math.floor(c.threat)) or 'Threat nad tankem'
    return A(ns.known('Shoot') and 'Shoot' or filler, t .. ' - uber (wand), jinak strhnes aggro', 'wait', { urgent = true })
  end
  -- root / stun u moba: Blink te vysvobodi
  if s.step == 1 and c.loc and c.inCombat and c.aggro and (c.near or c.enemies.onMe > 0) and ready('Blink') then
    s.used.Blink = true
    return A('Blink', 'Root/stun u moba: Blink pryc (sundava root i stun)', 'spell', { urgent = true })
  end
  -- threat: v parte jsi blizko pretazeni aggra
  if s.step == 1 and c.tankUp and not c.aggro and c.threatPct and c.threatPct >= 85 then
    return A(ns.known('Shoot') and 'Shoot' or 'Frostbolt', ('Threat %d%%: chvili uber (wand), at nestrhnes aggro'):format(math.floor(c.threatPct)),
      'wait', { dur = 1.5, urgent = c.threatPct >= 95 })
  end
  -- 4) Ice Barrier (absorbuje a bez preruseni castu)
  if ready('Ice Barrier') and not c.barrierUp and s.barrierUntil <= s.t and (c.aggro or c.enemies.onMe > 0) then
    local why = c.hpLow50 and 'HP pod 50 % - Ice Barrier' or (c.enemies.onMe >= 2 and 'Vic mobu na tobe - stit' or 'Udrzuj Ice Barrier (bez pushbacku)')
    if c.hpLow75 or c.enemies.onMe >= 2 or c.tough or not c.group then return A('Ice Barrier', why) end
  end
  -- Forever Ice Barrier dava i +15-20 % mrazive poskozeni: drz ho porad, kdyz bojujes
  if ns.barrierBuff and ready('Ice Barrier') and not c.barrierUp and s.barrierUntil <= s.t and c.hostile then
    return A('Ice Barrier', 'Ice Barrier: +5 % mraziveho dmg (s Frigid Power +20 %), bez pushbacku - drz ho porad')
  end
  -- 4a) procy z Forever talentu (hra rozsviti tlacitko)
  if (ns.talent('Missile Barrage') or 0) > 0 and ns.glowing('Arcane Missiles') and ready('Arcane Missiles') and not c.moving then
    return A('Arcane Missiles', 'Missile Barrage proc: rychle Arcane Missiles zdarma')
  end
  if ns.glowing('Pyroblast') and ready('Pyroblast') then
    return A('Pyroblast', 'Heating Up: zrychleny Pyroblast')
  end
  -- 4b) Fire / Frost Ward proti mobovi, ktery bije ohnem nebo mrazem
  if c.aggro and (c.wardSchool == 'fire' or c.wardSchool == 'frost') and not c.wardUp then
    local ward = c.wardSchool == 'fire' and 'Fire Ward' or 'Frost Ward'
    if ready(ward) then
      s.used[ward] = true
      return A(ward, ('Cil bije %s: %s'):format(c.wardSchool == 'fire' and 'ohnem' or 'mrazem', ward))
    end
  end
  -- 4c) Mana Shield, kdyz Ice Barrier neni a HP jde dolu
  if c.aggro and c.hpLow50 and not c.barrierUp and not ready('Ice Barrier') and not c.manaShieldUp
    and c.manaKnown and c.mana > 0.4 and ready('Mana Shield') then
    s.used['Mana Shield'] = true
    return A('Mana Shield', 'HP pod 50 %, Barrier na CD: Mana Shield')
  end
  -- 5) Mob na tobe v melee
  if c.near and c.aggro and frozenLeft <= 0 and not c.tPlayer and not c.enemies.ccNear then
    if mob and mob.flees and c.tLow35 and not c.tLow20 and not c.hpLow50 and ready('Cone of Cold') then
      return A('Cone of Cold', 'Mob bude utikat: Cone of Cold, Novu si nech na utek')
    end
    if ready('Frost Nova') then
      return A('Frost Nova', c.group and 'Strhl jsi aggro: Frost Nova a odstup, at si ho tank/pet vezme zpet'
        or 'Mob je u tebe: Frost Nova, odstup a Ice Lance na zmrazeneho (4x dmg)')
    end
    if ready('Cone of Cold') then return A('Cone of Cold', 'Mob u tebe, Nova na CD: zpomal ho a odejdi') end
    if c.hpLow35 and ready('Blink') then return A('Blink', 'Mob u tebe a HP dole: Blink pryc') end
  end
  if c.tPlayer and c.near and ready('Frost Nova') and frozenLeft <= 0 then
    return A('Frost Nova', 'Hrac u tebe: Nova a kite')
  end
  -- 6) AoE (v parte s tankem az kdyz si tank moby drzi)
  local aoeHold
  if c.tankUp and aoeN >= db.aoe then
    local wait = (db.aoeDelay or 3) - c.pullAge
    if wait > 0 then aoeHold = ('AoE az za %ds (tank sbira aggro)'):format(math.ceil(wait))
    elseif c.enemies.onMe > 0 then aoeHold = 'Mob je na tobe - AoE az ho tank prebere'
    elseif c.enemies.victimKnown and (c.tankMobs or 0) < db.aoe then
      aoeHold = ('AoE az budou moby na tankovi (ma %d)'):format(c.tankMobs or 0)
    end
  end
  if aoeN >= db.aoe and c.mana > 0.12 and not aoeHold then
    if c.enemies.near >= 2 and ready('Frost Nova') and frozenLeft <= 0 and c.aggro and not c.enemies.ccNear then
      return A('Frost Nova', ('%d mobu u tebe: zmraz je, odstup, pak Blizzard'):format(c.enemies.near))
    end
    if c.enemies.near >= 2 and frozenLeft > 0 and ready('Cone of Cold') then
      return A('Cone of Cold', 'Zmrazena skupina: Cone of Cold')
    end
    if c.enemies.near >= 2 and ready('Blast Wave') and not c.enemies.ccNear then
      return A('Blast Wave', ('%d mobu u tebe: Blast Wave (zpomali je)'):format(c.enemies.near))
    end
    local care = sheep and ' - mir mimo ovci!' or ''
    if can('Flamestrike') and c.enemies.near == 0 and not c.moving and c.flamestrikeLeft <= 0
      and not s.used.Flamestrike and c.mana > 0.3 and (c.ttd == nil or c.ttd > 6) then
      s.used.Flamestrike = true
      return A('Flamestrike', ('%d mobu pohromade: Flamestrike%s'):format(aoeN, care))
    end
    if can('Blizzard') and not c.moving and (c.ttd == nil or c.ttd > 4 or c.tough) then
      if c.enemies.near >= 3 and frozenLeft <= 0 and not ready('Frost Nova') and c.aggro and ready('Cone of Cold') then
        return A('Cone of Cold', 'Moby u tebe bez Novy: Cone of Cold a odejdi')
      end
      if not s.used.Blizzard then
        s.used.Blizzard = true
        return A('Blizzard', ('%d mobu pohromade: Blizzard%s'):format(aoeN, care ~= '' and care or ' (stuj mimo jejich dosah)'))
      end
    end
    if c.enemies.near >= 3 and ready('Arcane Explosion') and c.mana > 0.2 and not sheep then
      return A('Arcane Explosion', 'Moby kolem tebe: Arcane Explosion')
    end
  end
  -- 7) Dorazeni (neplytvat dlouhym castem na skoro mrtveho)
  local dying = (c.tLow10 or (c.tLow20 and (c.ttd == nil or c.ttd < 4)) or (c.ttd and c.ttd < fbCast + s.t))
  if dying and not c.boss and aoeN < db.aoe then
    if frozenLeft > 0 and ready('Ice Lance') then return A('Ice Lance', 'Dorazit: Ice Lance na zmrazeny cil') end
    if ready('Fire Blast') then return A('Fire Blast', 'Dorazit instantem (Fire Blast)') end
    if ready('Ice Lance') then return A('Ice Lance', 'Dorazit instantem (Ice Lance)') end
    if ns.known('Shoot') and c.manaKnown and c.mana < 0.6 and not c.tough then return A('Shoot', 'Skoro mrtvy: dorazit wandem, setri manu') end
    local nr = ns.rankCount('Frostbolt')
    if can('Frostbolt') and nr > 3 and c.manaKnown and c.mana < db.conserveMana and not c.moving then
      local r = math.max(1, nr - 3)
      return A('Frostbolt', ('Dorazit levnym rankem: Frostbolt rank %d'):format(r), 'spell', { rank = r })
    end
  end
  -- 8) Zmrazeny cil (Frost Nova / Frostbite) = Shatter
  if frozenLeft > 0 then
    if ready('Ice Lance') then return A('Ice Lance', ('Zmrazeny cil (%.1fs): Ice Lance 4x dmg'):format(frozenLeft)) end
    -- Forever: Shatter dava jen par % critu, hlavni bonus na zmrazeny cil je Ice Lance (3x dmg).
    -- Frostbolt jen kdyz Ice Lance nejde (mana) a zmrazeni vydrzi cely cast.
    if can('Frostbolt') and frozenLeft > fbCast + 0.2 and not c.moving then
      return A('Frostbolt', ('Zmrazeny cil (%.1fs): Frostbolt'):format(frozenLeft))
    end
    if c.near and ready('Cone of Cold') then return A('Cone of Cold', 'Zmrazeny cil u tebe: Cone of Cold') end
  end
  -- 9) Fingers of Frost
  if s.fofBatch and s.casting == 'Frostbolt' and ready('Ice Lance') then
    return A('Ice Lance', 'FoF: Ice Lance tesne pred dopadem Frostboltu (batch - oba dostanou bonus)', 'spell', { batch = true })
  end
  if s.fof >= 1 then
    if s.fof >= 2 and ready('Ice Lance') then return A('Ice Lance', 'FoF 2 stacky: Ice Lance') end
    if can('Frostbolt') and not c.moving then return A('Frostbolt', 'FoF: Frostbolt a tesne pred dopadem Ice Lance') end
    if ready('Ice Lance') then return A('Ice Lance', 'FoF v pohybu: Ice Lance') end
  end
  -- 9a) Fire Blast na cooldown: instant ~385 dmg za GCD (~1.8x vic za sekundu nez Frostbolt).
  --     Sdili 8s cooldown s Ice Lance -> ne, kdyz cekame FoF / zmrazeni (tam ma Ice Lance 4x dmg),
  --     a jen kdyz je dost many (je drazsi na manu nez Frostbolt).
  local novaSoon = c.near and c.aggro and ready('Frost Nova')
  if ready('Fire Blast') and s.fof == 0 and frozenLeft <= 0 and not novaSoon and c.manaKnown
    and s.mana > math.max(db.conserveMana or 0.3, 0.35) and c.inRange ~= false
    and (C_Spell and C_Spell.IsSpellInRange and ns.id('Fire Blast')
      and safeBool(pc(C_Spell.IsSpellInRange, ns.id('Fire Blast'), 'target'))) ~= false then   -- Fire Blast ma kratsi dosah
    return A('Fire Blast', 'Fire Blast: instant mezi Frostbolty (sdili CD s Ice Lance)')
  end
  -- 9b) kiting solo: Nova dobehla a mob se zase blizi -> rychly Frostbolt rank 1 (zpomali) a ustupovat
  if s.step == 1 and not c.group and c.aggro and not c.near and frozenLeft <= 0 and c.novaAgo < 12
    and not (c.mob and c.mob.caster) and not c.tCasting
    and can('Frostbolt') and ns.rankCount('Frostbolt') >= 2 and not c.tLow20 then
    return A('Frostbolt', 'Kite: Frostbolt rank 1 (rychly cast, zpomali) a ustupuj', 'spell', { rank = 1 })
  end
  -- 10) Velka kouzla na CD
  if ready('Cryoblast') and not c.moving and (c.ttd == nil or c.ttd > 4) then
    return A('Cryoblast', 'Cryoblast je pripraveny')
  end
  -- 11) Pohyb: jen instanty
  if c.moving then
    if ready('Fire Blast') and c.mana > db.conserveMana then return A('Fire Blast', 'V pohybu: Fire Blast') end
    if ready('Ice Lance') then return A('Ice Lance', 'V pohybu: Ice Lance') end
    if c.near and ready('Cone of Cold') then return A('Cone of Cold', 'V pohybu u moba: Cone of Cold') end
    if c.near and ready('Frost Nova') and c.aggro then return A('Frost Nova', 'V pohybu u moba: Frost Nova') end
  end
  -- 12) Mana
  if c.manaKnown and c.mana < db.wandMana and ns.known('Shoot') then
    if ready('Evocation') and c.enemies.onMe == 0 then return A('Evocation', 'Zadna mana a nikdo na tobe: Evocation') end
    return A('Shoot', ('Mana %d%%: wand'):format(math.floor(c.mana * 100)))
  end
  if c.manaKnown and c.mana < db.conserveMana and ns.known('Shoot') and not c.tough and c.ttd and c.ttd < 6 then
    return A('Shoot', 'Setri manu: mob brzy padne, wand')
  end
  if c.manaKnown and c.mana < 0.15 and ready('Evocation') and c.enemies.onMe == 0 then
    return A('Evocation', 'Malo many a nikdo na tobe: Evocation')
  end
  if c.inRange == false then return A(filler, 'Cil je mimo dosah - priblizit se') end
  -- 13) Filler
  if aoeHold then return A(filler, aoeHold .. ' - zatim ' .. filler) end
  if filler == 'Frostbolt' then
    if pt and pt.petLow and not c.aggro then
      return A('Frostbolt', ('%s umira: ber aggro - Frostbolt, pak Frost Nova a kite'):format(pt.petLow.name))
    end
    if c.near and not c.aggro and c.tt == false then
      return A('Frostbolt', 'Mob je u tebe, ale bije nekoho jineho: Frostbolt')
    end
    if c.near then
      local nova = s.cd['Frost Nova']
      local why = (nova and nova > s.t) and ('Mob u tebe (Nova za %ds): Frostbolt ho zpomali, odstup'):format(math.ceil(nova - s.t))
        or 'Mob u tebe: Frostbolt (zpomali), odstup'
      return A('Frostbolt', why)
    end
    return A('Frostbolt', 'Frostbolt')
  end
  if c.imm and c.imm.schools.frost then
    return A(filler, ('Cil je imunni na mraz: %s'):format(filler))
  end
  return A(filler, filler)
end

------------------------------------------------------------------------------------------
-- Dopad akce na simulovany stav
------------------------------------------------------------------------------------------
local function apply(c, s, a)
  local n = a.name
  if a.kind == 'item' then s.used[n] = true s.t = s.t + 1.5 return end
  local cost = ns.cost(n)
  s.mana = math.max(0, s.mana - cost / ns.manaMax())
  local cd = ns.cdFor(n)
  local ct = ns.castTime(n)
  local dur
  if a.kind == 'wait' then dur = a.dur or 1.5
  elseif ns.CHANNEL[n] then dur = ns.CHANNEL[n]
  elseif ns.OFF_GCD[n] then dur = 0
  else dur = math.max(1.5, ct) end
  if cd > 1.5 then s.cd[n] = s.t + ct + cd end
  -- Forever: Ice Lance a Fire Blast sdili cooldown (kategorie 8 s)
  if cd > 1.5 and (n == 'Ice Lance' or n == 'Fire Blast') then
    local other = n == 'Ice Lance' and 'Fire Blast' or 'Ice Lance'
    s.cd[other] = math.max(s.cd[other] or 0, s.t + ct + cd)
  end
  if not c.inCombat then s.used[n] = true end   -- buffy/conjure jen jednou
  if n == 'Frost Nova' and (c.near or c.enemies.near > 0) then s.frozenUntil = s.t + 8 s.frozenHits = 0 end
  if n == 'Ice Barrier' then s.barrierUntil = s.t + 60 end
  if n == 'Counterspell' or n == 'Ice Block' or n == 'Evocation' then s.used[n] = true end
  if n == 'Frostbolt' or n == 'Ice Lance' or n == 'Fire Blast' or n == 'Cone of Cold' then
    if s.frozenUntil > s.t then
      s.frozenHits = s.frozenHits + 1
      if s.frozenHits >= 3 then s.frozenUntil = s.t end
    end
  end
  if n == 'Ice Lance' or n == 'Cone of Cold' then s.fof = math.max(0, s.fof - 1) end
  if n == 'Frostbolt' then
    -- dalsi krok je "tesne pred dopadem Frostboltu": tam se hodi batch Ice Lance
    s.fofBatch = s.fof >= 1
    s.fof = math.max(0, s.fof - 1)
    s.casting = 'Frostbolt'
    s.t = s.t + dur
    return
  end
  s.casting, s.fofBatch = nil, nil
  s.t = s.t + dur
end

------------------------------------------------------------------------------------------
-- Plan: az 3 kroky + mimo-GCD/predmet
------------------------------------------------------------------------------------------
local TRACK = { 'Frost Nova', 'Cone of Cold', 'Fire Blast', 'Counterspell', 'Ice Barrier', 'Ice Block', 'Cold Snap',
  'Icy Veins', 'Evocation', 'Blink', 'Ice Lance', 'Cryoblast' }

function E.plan(c)
  local s = { t = 0, mana = c.mana, cd = {}, used = {}, step = 1, fof = c.fof or 0,
    frozenUntil = c.frozen or 0, frozenHits = ns.T.frozenHits or 0,
    barrierUntil = c.barrierUp and 60 or 0 }
  for _, n in ipairs(TRACK) do if ns.known(n) then s.cd[n] = ns.cdLeft(n) end end
  -- kdy muzu dalsi kouzlo: po castu (ne channel) a po GCD
  if c.castName and not c.channel then
    s.t = c.castLeft
    if c.castName == 'Frostbolt' then
      s.casting = 'Frostbolt'
      if s.fof >= 1 then s.fofBatch = true s.fof = s.fof - 1 end
    end
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

  ---------------- mimo GCD / predmety
  local util
  local pt = c.party or {}
  if c.inCombat and c.hostile then
    -- v nebezpeci = mob na tobe (i kdyz neni tvuj cil), nebo HP uz hodne dole (DoT, AoE)
    local danger = c.aggro or (c.enemies.onMe or 0) > 0 or ns.hpBelow('player', 25) == true
    local lowHP = danger and ns.hpBelow('player', c.db.potionHP)
    -- Healthstone je zdarma a ma vlastni cooldown: pouzij ho driv nez potion (do 40 % HP)
    local lowStone = danger and ns.hpBelow('player', math.max(40, c.db.potionHP or 30))
    local hs = ns.Bags.best('stone')
    if not util and hs and lowStone and ns.itemReady(hs, 'stone', 120) then
      util = A('item:' .. hs, 'Healthstone!', 'item', { item = hs, urgent = true })
    end
    local hp = ns.Bags.best('hpot')
    if not util and hp and lowHP and ns.itemReady(hp, 'potion', 120) then
      util = A('item:' .. hp, 'Healing Potion!', 'item', { item = hp, urgent = true })
    end
    local ag = ns.Bags.best('defense')
    if not util and ag and lowHP and ns.itemReady(ag, 'defense', 60) then
      util = A('item:' .. ag, 'Nouzova obrana: ' .. (ns.Bags.items[ag] and ns.Bags.items[ag].name or ''), 'item', { item = ag, urgent = true })
    end
    local cryo = ns.Bags.best('nuke')
    if not util and cryo and (c.tough or c.boss) and not c.moving and ns.itemReady(cryo, 'nuke', 30)
      and not (c.imm and ns.Immune.bad(c.imm, 'Scroll of Cryoblast')) then
      util = A('item:' .. cryo, 'Silny cil: Scroll of Cryoblast', 'item', { item = cryo })
    end
    local rb = ns.Bags.best('antiElem')
    if not util and rb and safe(pc(UnitCreatureType, 'target')) == 'Elemental' and ns.itemReady(rb, 'antiElem', 30) then
      util = A('item:' .. rb, 'Elemental: Scroll of Rebuke Elemental', 'item', { item = rb })
    end
    if not util and c.group and c.enemies.skull and c.mark ~= 8 then
      util = A('TARGET', 'Bij lebku - tank na ni jde prvni', 'hint', { icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' })
    end
    -- ovce brzy skonci: prodlouzit (Polymorph ma 1.5 s cast, proto uz od 5 s)
    local sl = ns.sheepLeft and ns.sheepLeft()
    if not util and sl and sl <= 5 and ((c.enemies.cc or 0) > 0 or ns.sheep.guid) and ns.cdLeft('Polymorph') <= 0
      and (c.enemies.combat or 0) > 0 then
      local mac = (safeNum(pc(GetMacroIndexByName, 'CM Ovce')) or 0) > 0
      util = A('Polymorph', ('Ovce konci za %.0f s: %s'):format(sl, mac and 'zmackni CM Ovce (prodlouzi i bez zmeny cile)'
        or 'zamer ji a Polymorph znovu (/cm makro udela CM Ovce)'), 'hint',
        { urgent = sl <= 3 })
    end
    if not util and c.enemies.moonLoose and ns.known('Polymorph') and ns.cdLeft('Polymorph') <= 0 then
      util = A('Polymorph', 'Mesic se probral: zamer ho a Polymorph znovu', 'hint')
    end
    if not util and c.offTank and not c.aggro then
      util = A('TARGET', ('Tank (%s) bije jiny cil - prepni na jeho cil'):format(c.tankName or 'tank'), 'hint',
        { icon = 'Interface\\Icons\\Ability_Warrior_DefensiveStance' })
    end
    local d = pt.danger
    if not util and d and (d.low or d.healer or d.mobs >= 2) then
      util = A(ns.known('Polymorph') and 'Polymorph' or 'Frost Nova',
        ('Mob bije %s: zamer ho a zpomal/zmraz (Polymorph, Frostbolt, Nova u nej)'):format(d.name), 'hint')
    end
    if not util and pt.petDead then
      util = A('Frost Nova', ('Pet padl, moby jdou po %s: Frost Nova u nej, Ice Barrier'):format(pt.petDead.name), 'hint')
    end
    local decurse = ns.known('Remove Curse') and 'Remove Curse' or 'Remove Lesser Curse'
    if not util and pt.curse and ns.known(decurse) and not c.aggro then
      util = A(decurse, ('Curse na %s (mouseover/target)'):format(pt.curse.name), 'hint', { unit = pt.curse.unit })
    end
    if not util and c.aggro and c.hpLow35 and ns.known('Cold Snap') and ns.cdLeft('Cold Snap') <= 0
      and ns.cdLeft('Ice Block') > 0 and ns.cdLeft('Ice Barrier') > 0 then
      util = A('Cold Snap', 'Cold Snap: reset Ice Block / Barrier / Novy')
    end
    local gem = ns.Bags.best('gem')
    if not util and gem and c.manaKnown and c.mana < c.db.gemMana and ns.itemReady(gem, 'gem', 120) then
      util = A('item:' .. gem, ('Mana %d%%: pouzij mana gem'):format(math.floor(c.mana * 100)), 'item', { item = gem })
    end
    -- v dungeonu setrit velke cooldowny na bosse (nebo velky pull)
    local bigFight = c.instance and (c.boss or c.enemies.combat >= c.db.aoe + 1)
      or (not c.instance and (c.tough or c.enemies.combat >= c.db.aoe or (c.ttd and c.ttd > 20)))
    if not util and ns.known('Icy Veins') and ns.cdLeft('Icy Veins') <= 0 and bigFight then
      util = A('Icy Veins', c.boss and 'Boss: Icy Veins' or 'Tvrdy boj: Icy Veins')
    end
    -- talentove cooldowny: pouziji se, az je mag vezme
    if not util and ns.known('Arcane Power') and ns.cdLeft('Arcane Power') <= 0 and bigFight and c.mana > 0.3 then
      util = A('Arcane Power', 'Tvrdy boj: Arcane Power (+dmg, vic many)')
    end
    if not util and ns.known('Combustion') and ns.cdLeft('Combustion') <= 0 and bigFight then
      util = A('Combustion', 'Tvrdy boj: Combustion (ohniva kouzla crit)')
    end
    if not util and ns.known('Presence of Mind') and ns.cdLeft('Presence of Mind') <= 0 and not c.moving
      and (bigFight or (c.aggro and c.hpLow50)) then
      local nxt = ns.known('Pyroblast') and 'Pyroblast' or 'Frostbolt'
      util = A('Presence of Mind', 'Presence of Mind: dalsi ' .. nxt .. ' bude instantni')
    end
    local mp = ns.Bags.best('mpot')
    if not util and mp and c.manaKnown and c.mana < 0.2 and (c.tough or c.instance) and ns.itemReady(mp, 'potion', 120) then
      util = A('item:' .. mp, 'Mana potion', 'item', { item = mp })
    end
    if not util and not c.group and c.enemies.onMe == 2 and ns.known('Polymorph') and not c.tough
      and not (c.imm and ns.Immune.bad(c.imm, 'Polymorph')) then
      util = A('Polymorph', '2 moby na tobe: Polymorph na druheho (CM Ovce si ho zapamatuje)', 'hint')
    end
  end
  return plan, util
end

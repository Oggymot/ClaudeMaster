-- ClaudeMaster: takticke rady pro duo / partu
--  * multi-DoT (warlock): kdyz je vic mobu, DoTy i na dalsi (lze vypnout v nastaveni)
--  * hodnoceni pullu: kolik mobu je ve skupine (pack, odhad), elite, level, mana obou -> jak tezke to bude
--  * rozdeleny cil: kazdy bijete jineho moba -> zamer cil parťáka
--  * domluva CC: mag ovce, warlock Seduction / Fear / Banish na dalsiho (pres duo zpravy)
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local TA = { splitSince = nil, packAt = 0, pack = nil, ccWaitFrom = nil }
ns.Tactics = TA

local function hint(reason, icon, urgent)
  return { name = 'TARGET', kind = 'hint', reason = reason, icon = icon, urgent = urgent,
    key = GetBindingKey and GetBindingKey('TARGETNEARESTENEMY') }
end

------------------------------------------------------------------------------------------
-- Pack: nepratele u cile (mimo boj). Pozice ve svete hra neda, takze odhad z obrazovky:
-- jmenovky, ktere jsou na obrazovce blizko jmenovky cile a jsou v dosahu ~28 yd.
------------------------------------------------------------------------------------------
local function plateOf(u)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, u)
  return ok and p or nil
end
local function centerOf(p)
  if not p then return nil end
  local ok, x, y = pcall(p.GetCenter, p)
  if ok and type(x) == 'number' and type(y) == 'number' then return x, y end
end
local function classOf(u)
  local cl = safe(pc(UnitClassification, u))
  return cl == 'elite' or cl == 'rareelite' or cl == 'worldboss', cl == 'worldboss'
end

-- pasmo vzdalenosti z dosahu kouzel: 1 = do 10 yd, 2 = do 20, 3 = do 30, 4 = dal (nil = nevime)
local R20 = { 'Fire Blast', 'Searing Pain', 'Scorch' }
local function band(u)
  if safeBool(pc(CheckInteractDistance, u, 3)) == true then return 1 end
  if C_Spell and C_Spell.IsSpellInRange then
    for _, n in ipairs(R20) do
      local id = ns.known(n) and ns.id(n)
      if id then
        local r = safeBool(pc(C_Spell.IsSpellInRange, id, u))
        if r == true then return 2 elseif r == false then break end
      end
    end
  end
  local c = ns.close(u)
  if c == true then return 3 elseif c == false then return 4 end
end
TA.band = band
-- co o mobovi vi databaze (lecitel, CC, utika, patrola)
local function noteDB(r, u, isTarget)
  local d = ns.MobDB and ns.MobDB.forUnit(u)
  if not d then return end
  local nm = d.name
  if #d.heal > 0 then r.healers = r.healers + 1 if not isTarget then r.healerName = r.healerName or nm end
    if isTarget then r.targetHeals = true end end
  if #d.cc > 0 then r.ccers = r.ccers + 1 end
  if #d.summon > 0 then r.summoners = r.summoners + 1 end
  if d.flee then r.fleers = r.fleers + 1 end
  if d.patrol then r.patrols = r.patrols + 1 end
end

function TA.scanPack()
  local now = GetTime()
  if now - TA.packAt < 0.5 then return TA.pack end
  TA.packAt = now
  TA.pack = nil
  if InCombatLockdown() or not UnitExists('target') then return nil end
  if safeBool(pc(UnitCanAttack, 'player', 'target')) ~= true or safeBool(pc(UnitIsDeadOrGhost, 'target')) == true then return nil end
  local tx, ty = centerOf(plateOf('target'))
  local my = safeNum(UnitLevel('player')) or 1
  local tl = safeNum(pc(UnitLevel, 'target')) or my
  local el, boss = classOf('target')
  local r = { n = 1, elite = el and 1 or 0, boss = boss or tl < 0, maxLvl = tl < 0 and (my + 10) or tl, estimated = tx == nil,
    humanoid = 0, demon = 0, healers = 0, ccers = 0, summoners = 0, fleers = 0, patrols = 0, patrolNear = nil }
  pcall(noteDB, r, 'target', true)
  local tb = band('target')
  local ct = safe(pc(UnitCreatureType, 'target'))
  if ct == 'Humanoid' then r.humanoid = 1 elseif ct == 'Demon' or ct == 'Elemental' then r.demon = 1 end
  local plates = C_NamePlate and C_NamePlate.GetNamePlates and pc(C_NamePlate.GetNamePlates)
  local tname = safe(pc(UnitName, 'target'))
  local lim = (UIParent:GetHeight() or 768) * 0.11
  if type(plates) == 'table' then
    for _, pl in ipairs(plates) do
      local u = pl.namePlateUnitToken or (pl.UnitFrame and pl.UnitFrame.unit)
      if u and safeBool(pc(UnitIsUnit, u, 'target')) ~= true and safeBool(pc(UnitCanAttack, 'player', u)) == true
        and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true and safeBool(pc(UnitIsPlayer, u)) ~= true
        and safeBool(pc(UnitAffectingCombat, u)) ~= true then
        local inPack = false
        local x, y = centerOf(pl)
        local ub = band(u)
        if tx and x then
          local d = math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2)
          inPack = d < lim and ns.close(u) ~= false
          -- na obrazovce blizko, ale podle dosahu kouzel jinde (pred / za cilem)
          if inPack and tb and ub and math.abs(tb - ub) >= 2 then inPack = false end
        elseif safe(pc(UnitName, u)) == tname and ns.near(u) then
          inPack = true   -- bez pozic: stejny druh hodne blizko
        end
        if inPack then
          r.n = r.n + 1
          local e2, b2 = classOf(u)
          if e2 then r.elite = r.elite + 1 end
          if b2 then r.boss = true end
          local l2 = safeNum(pc(UnitLevel, u)) or tl
          if l2 < 0 then r.boss = true l2 = my + 10 end
          r.maxLvl = math.max(r.maxLvl, l2)
          local c2 = safe(pc(UnitCreatureType, u))
          if c2 == 'Humanoid' then r.humanoid = r.humanoid + 1 elseif c2 == 'Demon' or c2 == 'Elemental' then r.demon = r.demon + 1 end
          pcall(noteDB, r, u, false)
        elseif ub and ub <= 3 and not r.patrolNear then
          -- patrola v dosahu, ale mimo pack: muze prijit behem boje
          local d = ns.MobDB and ns.MobDB.forUnit(u)
          if d and d.patrol then r.patrolNear = d.name end
        end
      end
    end
  end
  TA.pack = r
  return r
end

------------------------------------------------------------------------------------------
-- Hodnoceni pullu: sila mobu vs. sila party (pocet lidi, mana, HP)
------------------------------------------------------------------------------------------
function TA.rate(c)
  local p = TA.scanPack()
  if not p then return nil end
  local my = safeNum(UnitLevel('player')) or 1
  if p.boss then return 4, p end
  -- sila jednoho moba: elite x3, kazdy level nad tebou +20 %
  local diff = (p.maxLvl or my) - my
  local lvlF = math.max(0.5, math.min(3, 1 + 0.2 * diff))
  local score = ((p.n - p.elite) + p.elite * 3) * lvlF
  if c.mob and c.mob.nb and c.mob.nb >= 2 and c.mob.ttd and c.mob.ttd > 30 then score = score * 1.3 end
  -- sila party: ~1.6 normalniho moba na hrace, krat mana a HP (nejslabsi z vas)
  local players = 1
  for i = 1, 4 do if UnitExists('party' .. i) and safeBool(pc(UnitIsDeadOrGhost, 'party' .. i)) ~= true then players = players + 1 end end
  local mana = c.manaKnown and c.mana or 1
  local hp = (c.php or 100) / 100
  local peer = ns.Duo and ns.Duo.peer()
  if peer then
    if peer.mana then mana = math.min(mana, peer.mana) end
    if peer.hp then hp = math.min(hp, peer.hp / 100) end
  end
  local cap = players * 1.6 * (0.4 + 0.6 * mana) * (0.5 + 0.5 * hp)
  local ratio = score / math.max(0.3, cap)
  local lvl = (ratio < 0.5 and 1) or (ratio < 0.95 and 2) or (ratio < 1.4 and 3) or 4
  p.diff, p.ratio = diff, ratio
  return lvl, p
end

local RATE_TXT = {
  { '|cff66ee77', 'lehke' },
  { '|cffcfe08a', 'ok' },
  { '|cffffaa33', 'tezke, CC' },
  { '|cffff5555', 'moc, po jednom' },
}
function TA.pullText(c)
  if c.inCombat or not c.hostile then return nil end
  local lvl, p = TA.rate(c)
  if not lvl then return nil end
  local notable = p.healers > 0 or p.ccers > 0 or p.summoners > 0 or p.patrolNear or (p.fleers > 0 and p.n >= 2)
  if p.n == 1 and p.elite == 0 and not p.boss and (p.diff or 0) < 2 and lvl <= 2 and not notable then return nil end
  local I = ns.ico
  local t = RATE_TXT[lvl]
  -- lebky = obtiznost, pak pocet mobu a ikonky toho, na co si dat pozor
  local parts = { string.rep(I('skull', 12), lvl) .. ' ' .. t[1] .. ((p.estimated and '~' or '') .. p.n .. 'x') .. '|r' }
  if p.boss then parts[#parts + 1] = '|cffff5555BOSS|r'
  elseif p.elite > 0 then parts[#parts + 1] = '|cffffd100' .. p.elite .. 'x elite|r' end
  if p.diff and p.diff >= 2 then parts[#parts + 1] = '+' .. p.diff .. ' lvl' end
  if p.healers > 0 then parts[#parts + 1] = I('heal') .. (p.healers > 1 and p.healers or '') end
  if p.ccers > 0 then parts[#parts + 1] = I('cc') .. (p.ccers > 1 and p.ccers or '') end
  if p.summoners > 0 then parts[#parts + 1] = I('summon') end
  if p.fleers > 0 then parts[#parts + 1] = I('flee') .. (p.fleers > 1 and p.fleers or '') end
  if p.patrolNear then parts[#parts + 1] = I('patrol') .. ' |cffffcc00patrola|r' end
  local txt = table.concat(parts, ' ') .. '  ' .. t[1] .. t[2] .. '|r'
  -- plan CC pro vic mobu (duo)
  if p.n >= 2 and (lvl >= 2) then
    local plan = TA.ccPlanText(c, p)
    if plan then txt = txt .. '\n|cff9fc7ff' .. plan .. '|r' end
  end
  return txt
end

------------------------------------------------------------------------------------------
-- Domluva CC
------------------------------------------------------------------------------------------
-- co umim ja: Polymorph (mag), Seduction (Succubus), Banish (demon/elemental), Fear (jen mimo dungeon)
local function myCC(c)
  if ns.class == 'MAGE' then
    if ns.known('Polymorph') and ns.cdLeft('Polymorph') <= 0.5 then return 'Polymorph' end
  elseif ns.class == 'WARLOCK' then
    if c.petFamily == 'Succubus' or c.petFamily == 'Incubus' then return 'Seduction' end
    if ns.known('Fear') and not c.instance and ns.cdLeft('Fear') <= 0.5 then return 'Fear' end
  end
end
TA.myCC = myCC

function TA.ccPlanText(c, p)
  local peer = ns.Duo and ns.Duo.peer()
  local mine = myCC(c)
  -- lecitel v packu: ten jde do CC (nebo ho bijte prvniho, kdyz je to cil)
  if p.healerName and mine then
    return ('Plan: %s na lecitele (%s), bijte cil'):format(mine == 'Polymorph' and 'ovce' or mine, p.healerName)
  elseif p.targetHeals and p.n >= 2 then
    return 'Plan: cil se leci - bijte ho prvniho, interrupt na heal'
  end
  if not peer then
    if mine and p.n >= 2 then return ('Plan: %s na druheho, bij prvniho'):format(mine) end
    return nil
  end
  if ns.class ~= 'MAGE' and peer.cls ~= 'MAGE' then
    return mine and ('Plan: %s na druheho, bijte prvniho'):format(mine) or nil
  end
  local me = ns.class == 'MAGE' and 'ty' or peer.name
  local lock = ns.class == 'WARLOCK' and 'ty' or peer.name
  if p.n == 2 then
    return ('Plan: %s ovce na druheho, oba bijte prvniho'):format(me)
  end
  return ('Plan: %s ovce, %s Seduction/Fear na dalsiho, bijte zbytek'):format(me, lock)
end

------------------------------------------------------------------------------------------
-- Rozdeleny cil (duo bez tanka)
------------------------------------------------------------------------------------------
local function partnerUnit()
  local peer = ns.Duo and ns.Duo.peer()
  if peer and peer.unit then return peer.unit, peer.name end
  if GetNumGroupMembers and (safeNum(GetNumGroupMembers()) or 0) == 2 and UnitExists('party1') then
    return 'party1', safe(pc(UnitName, 'party1'))
  end
end

function TA.split(c)
  if not (c.inCombat and c.hostile and c.group) or c.tankUp then TA.splitSince = nil return nil end
  local pu, pname = partnerUnit()
  if not pu then TA.splitSince = nil return nil end
  -- cil parťáka znam jen z jeho addonu (identita moba + HP); porovnani "cil spoluhrace" hra nedovoli
  local PL = ns.Plates
  local pT = PL and PL.peerTarget and PL.peerTarget()
  if not (pT and pT.id) then TA.splitSince = nil return nil end
  local myId = PL.idOf('target')
  local same = myId and PL.match('target', pT.id, myId)
  local comparable = myId and ((pT.id.g and myId.g) or (pT.id.m and myId.m) or (pT.id.n and myId.n))
  if not comparable then same = nil end   -- nelze porovnat (napr. dungeon bez znacek)
  -- jeho cil je ovce (sdilena) -> neresit
  local theirCC = false
  for _, s in ipairs(PL.sheep or {}) do
    if s.untilT > GetTime() and ((s.id.g and s.id.g == pT.id.g) or (s.id.m and s.id.m == pT.id.m)) then theirCC = true end
  end
  if same ~= false or theirCC or c.targetCC then TA.splitSince = nil return nil end
  local now = GetTime()
  TA.splitSince = TA.splitSince or now
  if now - TA.splitSince < 2.5 then return nil end
  local mine = ns.healthPct('target')
  local theirs = pT.hp
  if ns.class == 'WARLOCK' then
    -- warlock muze DoTovat vic mobu; varovat jen kdyz je cil parťáka zjevne niz
    if theirs and mine and theirs + 15 < mine then
      return hint(('%s dorazi jineho moba (%d %%): pomoz mu, zamer jeho cil'):format(pname or 'Partak', math.floor(theirs)),
        'Interface\\Icons\\Ability_Hunter_MarkedForDeath')
    end
    return nil
  end
  if theirs and mine and theirs > mine + 15 then return nil end   -- muj cil je niz: at prepne on
  return hint(('%s bije jineho moba: zamer jeji cil (/assist %s)'):format(pname or 'Partak', pname or ''),
    'Interface\\Icons\\Ability_Hunter_MarkedForDeath')
end

------------------------------------------------------------------------------------------
-- CC v boji (duo): mag ovce na druheho, warlock bere dalsiho / kdyz mag nemuze
------------------------------------------------------------------------------------------
function TA.ccInCombat(c)
  if not (c.inCombat and c.group) or c.tankUp then TA.ccWaitFrom, TA.lockClaimAt = nil, nil return nil end
  local n = (c.enemies and c.enemies.combat) or 0   -- bez ovci
  if n < 2 then TA.ccWaitFrom, TA.lockClaimAt = nil, nil return nil end
  local peer = ns.Duo and ns.Duo.peer()
  local claim = ns.Duo and ns.Duo.ccClaim
  local fresh = claim and GetTime() - claim.at < 6
  local mine = myCC(c)
  if not mine then return nil end
  if ns.class == 'MAGE' then
    if fresh and claim.spell == 'Polymorph' then return nil end
    if GetTime() - (ns.castAt.Polymorph or -99) < 10 then return nil end   -- uz ovci
    if ns.Duo then ns.Duo.claimCC(mine) end
    return { name = 'Polymorph', kind = 'hint', reason = ('%d moby: Polymorph na druheho (focus makro)%s'):format(n,
      peer and (', ' .. peer.name .. ' bije hlavni cil') or '') }
  end
  -- warlock: kdyz mag ovci a jsou jeste dalsi, nebo mag po 1.5 s nic nehlasi
  TA.ccWaitFrom = TA.ccWaitFrom or GetTime()
  local mageSheeps = fresh and claim.spell == 'Polymorph'
  if mageSheeps and n < 2 then return nil end
  if not mageSheeps and peer and peer.cls == 'MAGE' and GetTime() - TA.ccWaitFrom < 1.5 then return nil end
  if fresh and claim.spell ~= 'Polymorph' then return nil end
  -- radu ukazat max 8 s (Seduction/Fear addon u peta nepozna)
  TA.lockClaimAt = TA.lockClaimAt or GetTime()
  if GetTime() - TA.lockClaimAt > 8 or GetTime() - (ns.castAt.Fear or -99) < 8 then return nil end
  if ns.Duo then ns.Duo.claimCC(mine) end
  local who = mageSheeps and (peer.name .. ' ovci jednoho, ') or ''
  if mine == 'Seduction' then
    return hint(('%d moby: %szamer dalsiho a Seduction od %s (jen humanoid)'):format(n, who, c.petFamily),
      'Interface\\Icons\\Spell_Shadow_MindSteal')
  end
  return { name = 'Fear', kind = 'hint', reason = ('%d moby: %sFear na dalsiho (pozor, muze privest dalsi)'):format(n, who) }
end

------------------------------------------------------------------------------------------
-- Multi-DoT (warlock)
------------------------------------------------------------------------------------------
function TA.multiDot(c)
  if ns.class ~= 'WARLOCK' or ns.db.multiDot == false or not c.inCombat then return nil end
  local W = ns.Warlock
  if not (W and W.dottedCount) then return nil end
  local n = (c.enemies and c.enemies.combat) or 0
  if n < 2 then return nil end
  if c.group and c.tankUp and not c.instance then return nil end
  -- aktualni cil musi mit DoTy nahozene a vydrzet
  local d = c.dots or {}
  local hasC = not ns.known('Corruption') or (d['Corruption'] or 0) > 4
  local hasB = not ns.known('Bane of Agony') or (d['Bane of Agony'] or 0) > 4
  if not (hasC and hasB) then return nil end
  if c.tLow20 or (c.ttd and c.ttd < 8) then return nil end
  if (c.php or 100) < 35 then return nil end
  local dotted = W.dottedCount()
  if dotted >= n then return nil end
  return hint(('%d moby, DoTy ma %d: tabni na dalsiho a dej mu Corruption + Bane'):format(n, dotted),
    'Interface\\Icons\\Spell_Shadow_AbominationExplosion')
end

------------------------------------------------------------------------------------------
-- Napojeni na plan
------------------------------------------------------------------------------------------
local E = ns.Engine
if E and E.plan then
  local origPlan = E.plan
  E.plan = function(c, ...)
    local plan, util = origPlan(c, ...)
    if not c or (util and util.urgent) then return plan, util end
    local ok, a = pcall(function()
      local cc = TA.ccInCombat(c)
      if cc then
        local sp = (cc.name == 'Polymorph' or cc.name == 'Fear') and cc.name
          or ((type(cc.reason) == 'string' and cc.reason:find('Seduction')) and 'Seduction') or 'Polymorph'
        TA.ccWanted = { spell = sp, at = GetTime() }
      end
      return cc or TA.split(c) or TA.multiDot(c)
    end)
    if ok and a and not util then util = a end
    local j = ns.Plates and ns.Plates.joined
    if not util and c.inCombat and j and GetTime() - j.at < 3 then
      util = hint(('+1 se pridal: %s'):format(j.name or 'mob'), ns.ICON and ns.ICON.join, true)
    end
    -- ne-mag ve skupine s magem: vycarovana voda/jidlo jsou zadarmo (setri penize za kupovane)
    if not util and not c.inCombat and not c.hostile and ns.class ~= 'MAGE' and ns.Bags.groupMage then
      local mage = ns.Bags.groupMage()
      if mage then
        local cw, cf = ns.Bags.countConj('water'), ns.Bags.countConj('food')
        if cw < 5 or cf < 3 then
          local what = (cw < 5 and cf < 3) and 'vodu a jidlo' or (cw < 5 and 'vodu' or 'jidlo')
          util = hint(('Popros %s o vycarovanou %s - zadarmo, setri penize'):format(mage, what),
            cw < 5 and 'Interface\\Icons\\INV_Drink_18' or 'Interface\\Icons\\INV_Misc_Food_10')
        end
      end
    end
    return plan, util
  end
end

------------------------------------------------------------------------------------------
-- Rady mimo boj (predmety, Conjure, buffy...): kdyz je hrac 8 s ignoruje, schovat je (do konce pristiho boje).
-- Neplati pro pull (nepritel v cili) a nalehave rady.
------------------------------------------------------------------------------------------
local ITEM_IGNORE_AFTER = 8
TA.itemSeen, TA.itemNo = {}, {}
local function isItem(a) return a and type(a.name) == 'string' and not a.urgent and a.kind ~= 'wait' end
local ief = CreateFrame('Frame')
pcall(ief.RegisterEvent, ief, 'PLAYER_REGEN_ENABLED')
ief:SetScript('OnEvent', function() wipe(TA.itemNo) wipe(TA.itemSeen) end)

if E and E.plan then
  local origPlan2 = E.plan
  E.plan = function(c, ...)
    local plan, util = origPlan2(c, ...)
    if not c or c.inCombat or c.hostile then wipe(TA.itemSeen) return plan, util end
    local now = GetTime()
    -- mys nad oknem: schovane predmety ukazat znovu a odpocet pozastavit
    local f = ns.UI and ns.UI.frame
    local hover = f and f.IsMouseOver and f:IsMouseOver()
    if hover then wipe(TA.itemNo) end
    -- co je ted videt (hlavni + utility); co uz neni videt, prestat pocitat
    local shown = {}
    if isItem(plan and plan[1]) then shown[plan[1].name] = true end
    if isItem(util) then shown[util.name] = true end
    for k in pairs(TA.itemSeen) do if not shown[k] then TA.itemSeen[k] = nil end end
    for k in pairs(shown) do
      if hover then TA.itemSeen[k] = now end
      TA.itemSeen[k] = TA.itemSeen[k] or now
      if now - TA.itemSeen[k] > ITEM_IGNORE_AFTER then TA.itemNo[k] = true end
    end
    -- ignorovane predmety vyhodit
    if plan then
      for i = #plan, 1, -1 do
        if isItem(plan[i]) and TA.itemNo[plan[i].name] then table.remove(plan, i) end
      end
    end
    if isItem(util) and TA.itemNo[util.name] then util = nil end
    return plan, util
  end
end

------------------------------------------------------------------------------------------
-- Tagovani v plne oblasti (hodne hracu, malo mobu)
--  * cil uz tagnul nekdo jiny (sedy, UnitIsTapDenied) -> nebij ho, za nej nic nedostanes
--  * nekdo ti ho vzal behem castu -> zastav cast
--  * oblast je "plna" (vic tagnutych mobu kolem / nedavno ti nekdo moba vzal)
--    -> otevri instantem: tag se pocita az pri zasahu, 2.5s Frostbolt casto prohraje
------------------------------------------------------------------------------------------
local TAG_SPELLS = {
  MAGE = { 'Fire Blast', 'Ice Lance' },
  WARLOCK = { 'Curse of Agony', 'Bane of Agony', 'Corruption' },
}
TA.tag = { at = 0, stolenAt = -999, freeAt = -999, players = 0 }
-- cizi hraci v okoli (mimo moji partu): z jmenovek hracu a z mysi / cile.
-- POZOR: combat log (COMBAT_LOG_EVENT_UNFILTERED) Forever addonum zakazuje - registrace
-- vyhodi popup "blocked from an action only available to the Blizzard UI". Nepouzivat.
-- Klic = GUID nebo jmeno, hodnota = kdy naposledy videni. Pocitaji se poslednich 60 s.
local seen = {}
local function notePlayer(u)
  if safeBool(pc(UnitIsPlayer, u)) == true and safeBool(pc(UnitInParty, u)) ~= true
    and safeBool(pc(UnitIsUnit, u, 'player')) ~= true then
    local k = safe(pc(UnitGUID, u)) or safe(pc(UnitName, u))
    if type(k) == 'string' then seen[k] = GetTime() end
  end
end
do
  local mf = CreateFrame('Frame')
  pcall(mf.RegisterEvent, mf, 'UPDATE_MOUSEOVER_UNIT')
  pcall(mf.RegisterEvent, mf, 'PLAYER_TARGET_CHANGED')
  mf:SetScript('OnEvent', function(_, e) notePlayer(e == 'UPDATE_MOUSEOVER_UNIT' and 'mouseover' or 'target') end)
end
local function tagScan()
  local T = TA.tag
  local now = GetTime()
  if now - T.at < 0.5 then return T end
  T.at = now
  local tapped, free, qFree, qName = 0, 0, 0, nil
  local units = ns.Plates and ns.Plates.units or {}
  local QM = ns.Quests and ns.Quests.mobNeed
  for u in pairs(units) do
    -- jmenovka ciziho hrace (jen kdyz ma hrac zapnute jmenovky pratel / nepratel)
    notePlayer(u)
    if safeBool(pc(UnitCanAttack, 'player', u)) == true and safeBool(pc(UnitIsPlayer, u)) ~= true
      and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true then
      local tap = safeBool(pc(UnitIsTapDenied, u))
      if tap == true then tapped = tapped + 1
      elseif tap == false and safeBool(pc(UnitAffectingCombat, u)) == false then
        free = free + 1
        local q = QM and QM(u)
        if q then qFree = qFree + 1 qName = qName or safe(pc(UnitName, u)) T.qObj = q end
      end
    end
  end
  local players = 0
  for k, at in pairs(seen) do
    if now - at > 60 then seen[k] = nil else players = players + 1 end
  end
  T.tapped, T.free, T.players, T.qFree, T.qName = tapped, free, players, qFree, qName
  -- plna oblast: vic cizich (tagnutych) mobu, aspon 3 cizi hraci kolem, nebo mi nekdo nedavno vzal moba
  T.contested = tapped >= 2 or players >= 3 or now - T.stolenAt < 180
  return T
end
function TA.tagInfo() return tagScan() end

function TA.tagHint(c, s, A, ready)
  if s.step ~= 1 or not c.hostile or c.tPlayer then return nil end
  local T = tagScan()
  local now = GetTime()
  local tapped = safeBool(pc(UnitIsTapDenied, 'target'))
  if tapped == false then
    T.freeAt = now
    -- mimo boj na volneho moba, ktery neni na quest, a kolem jsou volni questovi: kratce upozornit
    -- (jen prvni 4 s po vyberu cile, pak uz te to nechava byt)
    local QM = ns.Quests and ns.Quests.mobNeed
    if not c.inCombat and QM and (T.qFree or 0) > 0 and not QM('target')
      and safeBool(pc(UnitAffectingCombat, 'target')) == false then
      local nm = safe(pc(UnitName, 'target'))
      if nm ~= T.qTipName then T.qTipName, T.qTipAt = nm, now end
      if now - (T.qTipAt or 0) < 4 then
        local o = T.qObj
        local cnt = o and o.have and o.need and (' %d/%d'):format(o.have, o.need) or ''
        return A('TAG', ('Tenhle neni na quest. Na quest kolem: %s%s (volnych %d)'):format(T.qName or '?', cnt, T.qFree), 'hint',
          { icon = 'Interface\\GossipFrame\\AvailableQuestIcon' })
      end
    end
    return nil
  end
  if tapped ~= true then return nil end
  local more = (T.qFree or 0) > 0 and (' Volnych na quest kolem: %d (%s).'):format(T.qFree, T.qName or '?')
    or ((T.free or 0) > 0 and (' Volnych kolem: %d.'):format(T.free) or '')
  if (T.players or 0) >= 3 then more = more .. (' Hracu kolem: %d.'):format(T.players) end
  -- byl volny pred chvili a ja na nej castim = vzal mi ho nekdo
  if c.castName and now - T.freeAt < 3 then
    T.stolenAt = now
    return A('TAG', 'Mob ti vzal jiny hrac - zastav cast (pohni se) a vezmi jineho.' .. more, 'hint',
      { urgent = true, icon = 'Interface\Icons\Spell_Shadow_SacrificialShield' })
  end
  return A('TAG', 'Sedy mob = tagnul ho jiny hrac, za nej nic nedostanes.' .. more, 'hint',
    { icon = 'Interface\Icons\Spell_Shadow_SacrificialShield' })
end

-- otvirak do plne oblasti: instant s dosahem (vola se jen mimo boj na volneho moba)
function TA.tagOpener(c, s, A, ready)
  if s.step ~= 1 or c.inCombat or not c.hostile or c.tPlayer or c.tankUp then return nil end
  local T = tagScan()
  if not T.contested then return nil end
  if safeBool(pc(UnitAffectingCombat, 'target')) == true then return nil end
  for _, sp in ipairs(TAG_SPELLS[ns.class] or {}) do
    if ready(sp) and ns.castTime(sp) < 0.1 then
      local id = ns.id and ns.id(sp)
      local inR = id and C_Spell and C_Spell.IsSpellInRange and safeBool(pc(C_Spell.IsSpellInRange, id, 'target'))
      if inR ~= false then
        local why = (T.players or 0) >= 3 and ('%d hracu kolem'):format(T.players) or 'Plna oblast'
        return A(sp, ('%s: tagni instantem (%s), at ti ho nikdo nevezme'):format(why, sp), 'spell', { urgent = true })
      end
    end
  end
end

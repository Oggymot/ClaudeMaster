-- ClaudeMaster: doplnky
--  * priorita preruseni podle toho, co cil kouzli (heal / CC > velky spell > levny dmg)
--  * /cm bug: zaznam poslednich 30 s (co addon videl a co radil)
--  * duo: addon zpravy mezi mágem a warlockem (mana, voda, healthstone, pije)
--  * nove schopnosti: oznameni po levelu / talentu
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

-- ikonka do textu: |T cesta:velikost |t
local ICON = {
  ready = 'Interface\\RaidFrame\\ReadyCheck-Ready', wait = 'Interface\\RaidFrame\\ReadyCheck-Waiting',
  notready = 'Interface\\RaidFrame\\ReadyCheck-NotReady', skull = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8',
  heal = 'Interface\\Icons\\Spell_Holy_Heal', flee = 'Interface\\Icons\\Ability_Rogue_Sprint',
  cc = 'Interface\\Icons\\Spell_Shadow_Possession', sheep = 'Interface\\Icons\\Spell_Nature_Polymorph',
  patrol = 'Interface\\Icons\\Ability_Tracking', fire = 'Interface\\Icons\\Spell_Fire_FlameBolt',
  frost = 'Interface\\Icons\\Spell_Frost_FrostBolt02', shadow = 'Interface\\Icons\\Spell_Shadow_ShadowBolt',
  arcane = 'Interface\\Icons\\Spell_Nature_StarFall', nature = 'Interface\\Icons\\Spell_Nature_Lightning',
  holy = 'Interface\\Icons\\Spell_Holy_HolySmite', swords = 'Interface\\Icons\\Ability_DualWield',
  onme = 'Interface\\Icons\\Ability_Warrior_DefensiveStance', elite = 'Interface\\Icons\\Achievement_Boss_Ragnaros',
  mana = 'Interface\\Icons\\INV_Potion_76', drink = 'Interface\\Icons\\INV_Drink_18', hp = 'Interface\\Icons\\Spell_Holy_SealOfSacrifice',
  summon = 'Interface\\Icons\\Spell_Shadow_RaiseDead', join = 'Interface\\Icons\\Ability_Warrior_Charge',
  quest = 'Interface\\GossipFrame\\AvailableQuestIcon',
}
ns.ICON = ICON
function ns.ico(key, size)
  local p = ICON[key] or key
  size = size or 13
  if p:find('^Interface\\Icons') then return ('|T%s:%d:%d:0:0:64:64:5:59:5:59|t'):format(p, size, size) end
  return ('|T%s:%d|t'):format(p, size)
end
-- ikona tridy (z herni textury trid)
function ns.classIco(cls, size)
  local t = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
  if not t then return '' end
  size = size or 13
  return ('|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t'):format(size, size,
    t[1] * 256, t[2] * 256, t[3] * 256, t[4] * 256)
end

local function auraHas(unit, names)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, 'HELPFUL')
    if not ok then return nil end
    if type(a) ~= 'table' then return ns.inCombat() and nil or false end   -- v boji "konec seznamu" nic neznamena
    local n = safe(a.name)
    if type(n) ~= 'string' then return nil end
    for _, x in ipairs(names) do if n == x then return true end end
  end
  return false
end
ns.auraHas = auraHas

------------------------------------------------------------------------------------------
-- 1) Priorita preruseni
------------------------------------------------------------------------------------------
-- 3 = vzdy prerusit (heal, CC, summon), 2 = vyplati se (velky / dlouhy spell), 1 = levny dmg spell
local HIGH = {
  { 'Heal', 'heal' }, { 'Mend', 'heal' }, { 'Renew', 'heal' }, { 'Rejuvenation', 'heal' }, { 'Regrowth', 'heal' },
  { 'Holy Light', 'heal' }, { 'Flash of Light', 'heal' }, { 'Healing', 'heal' }, { 'Restor', 'heal' }, { 'Drain Life', 'heal' },
  { 'Polymorph', 'CC' }, { 'Fear', 'CC' }, { 'Sleep', 'CC' }, { 'Hex', 'CC' }, { 'Charm', 'CC' }, { 'Mind Control', 'CC' },
  { 'Hibernate', 'CC' }, { 'Howl', 'CC' }, { 'Scream', 'CC' }, { 'Domination', 'CC' }, { 'Banish', 'CC' },
  { 'Entangling', 'CC' }, { 'Seduc', 'CC' }, { 'Terrify', 'CC' }, { 'Paralyz', 'CC' },
  { 'Summon', 'summon' }, { 'Call of', 'summon' }, { 'Raise', 'summon' },
}
local MID = { 'Pyroblast', 'Chain Lightning', 'Volley', 'Blizzard', 'Rain of Fire', 'Flamestrike', 'Arcane Explosion',
  'Mind Flay', 'Shadow Bolt Volley', 'Frost Nova', 'Curse', 'Hellfire', 'Holy Fire', 'Starfire', 'Lightning Shield' }
local DESC_HIGH = { { 'heal', 'heal' }, { 'restores', 'heal' }, { 'fear', 'CC' }, { 'sleep', 'CC' }, { 'polymorph', 'CC' },
  { 'incapacitat', 'CC' }, { 'charm', 'CC' }, { 'stun', 'CC' }, { 'summon', 'summon' } }
local LABEL = { heal = 'heal', CC = 'CC', summon = 'privolani' }

function ns.castPrio(name, sid, durMs)
  if type(name) ~= 'string' then return 2, 'neznamy spell' end
  for _, h in ipairs(HIGH) do
    if name:find(h[1], 1, true) then return 3, LABEL[h[2]], h[2] end
  end
  for _, m in ipairs(MID) do if name:find(m, 1, true) then return 2, 'silny spell' end end
  -- popis kouzla (jde-li cist)
  local d = sid and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, sid))
  if type(d) == 'string' and d ~= '' then
    local dl = d:lower()
    for _, h in ipairs(DESC_HIGH) do
      if dl:find(h[1], 1, true) then return 3, LABEL[h[2]], h[2] end
    end
  end
  if durMs and durMs >= 2900 then return 2, 'dlouhy cast' end
  return 1, 'levny dmg spell'
end

-- pamet: co ktery druh moba kouzli (aby slo setrit interrupt na heal)
function ns.noteMobCast(mob, spell, kind)
  if type(mob) ~= 'string' or type(spell) ~= 'string' then return end
  ns.db.mobCasts = ns.db.mobCasts or {}
  local t = ns.db.mobCasts[mob] or {}
  ns.db.mobCasts[mob] = t
  local isNew = t[spell] == nil
  t[spell] = kind or t[spell] or 'dmg'
  -- novinku poslat parťákovi (sdilena pamet)
  if isNew and ns.Duo and ns.Duo.shareMob then ns.Duo.shareMob('C', mob, spell, t[spell]) end
end
function ns.mobCastInfo(mob)
  local t = type(mob) == 'string' and ns.db.mobCasts and ns.db.mobCasts[mob]
  if not t then return nil end
  local r = {}
  for sp, k in pairs(t) do
    if k == 'heal' then r.heal = sp elseif k == 'CC' then r.cc = sp end
  end
  return r
end

-- Vyplati se prerusit? 'urgent' / 'yes' / 'save' + duvod
function ns.kickWorth(c)
  local p = c.tCastPrio or 2
  local nm = c.tCastName or 'kouzlo'
  if p >= 3 then return 'urgent', ('%s (%s)'):format(nm, c.tCastWhy or '!') end
  if p == 2 then return 'yes', ('%s (%s)'):format(nm, c.tCastWhy or 'silny') end
  -- levny dmg spell
  if c.group and c.tankUp and not c.aggro and not c.tPlayer then
    return 'save', ('%s jen na tanka - interrupt si drz'):format(nm)
  end
  local mi = ns.mobCastInfo(ns.Immune and ns.Immune.tname)
  local lowHP = c.php and c.php < 50
  if mi and (mi.heal or mi.cc) and not lowHP then
    return 'save', ('%s je levny, mob umi %s - drz interrupt na to'):format(nm, mi.heal or mi.cc)
  end
  return 'yes', ('%s (levny, ale nic lepsiho neumi)'):format(nm)
end

------------------------------------------------------------------------------------------
-- 2) /cm bug: kruhovy zaznam poslednich 30 s
------------------------------------------------------------------------------------------
local Bug = { buf = {}, pos = 0, size = 60, last = 0 }
ns.Bug = Bug
local function f1(v) if v == nil then return '-' end if type(v) == 'number' then return ('%.0f'):format(v) end return tostring(v) end

function Bug.push(c, plan, util)
  local now = GetTime()
  if now - Bug.last < 0.5 or not c then return end
  Bug.last = now
  local _, _, lo, hi = ns.healthPct('target')
  local thp = c.thp
  local hp = thp and f1(thp) or ((lo and hi) and (f1(lo) .. '-' .. f1(hi)) or '?')
  local a1, a2 = plan and plan[1], plan and plan[2]
  local dots = {}
  if c.dots then for n, t in pairs(c.dots) do if t and t > 0 then dots[#dots + 1] = n:sub(1, 6) .. '=' .. f1(t) end end end
  local line = ('%.1f %s tok%d hp:%s L20:%s L10:%s ttd:%s mob:%s | ja hp:%s mana:%s | cmb:%s grp:%s tank:%s en:%s/%s onMe:%s | cast:%s(%s) | %s [%s] > %s | util:%s | dots:%s'):format(
    now, tostring(ns.Immune and ns.Immune.tname or '-'), ns.T.token, hp, f1(c.tLow20), f1(c.tLow10), f1(c.ttd),
    c.mob and (c.mob.fleeingNow and 'utika' or (c.mob.flees and 'flees' or 'ok')) or '-',
    (function() local v, ex, l, h = ns.healthPct('player') if ex or not v then return f1(v) end
      return ('%s(%s-%s sc%s)'):format(f1(v), f1(l), f1(h), tostring(ns.db.hpScale)) end)(), c.mana and ('%.0f'):format(c.mana * 100) or '-',
    f1(c.inCombat), f1(c.group), f1(c.tankUp), f1(c.enemies and c.enemies.combat), f1(c.enemies and c.enemies.near), f1(c.enemies and c.enemies.onMe),
    tostring(c.tCastName or (c.tCasting and '?' or '-')), f1(c.tCastPrio),
    a1 and a1.name or '-', a1 and (a1.reason or '') or '', a2 and a2.name or '-',
    util and (util.name .. ':' .. (util.reason or '')) or '-', table.concat(dots, ','))
  Bug.pos = Bug.pos % Bug.size + 1
  Bug.buf[Bug.pos] = line
end

function Bug.save(note)
  local lines = {}
  for i = 1, Bug.size do
    local k = (Bug.pos + i - 1) % Bug.size + 1
    if Bug.buf[k] then lines[#lines + 1] = Bug.buf[k] end
  end
  ns.db.bugs = ns.db.bugs or {}
  local b = ns.db.bugs
  b[#b + 1] = { at = date and date('%Y-%m-%d %H:%M:%S') or '?', note = note or '', class = ns.class,
    level = safeNum(UnitLevel('player')), zone = safe(pc(GetRealZoneText)), instance = safeBool(pc(IsInInstance)) == true,
    talents = ns.talentList and #ns.talentList or nil, lines = lines }
  while #b > 5 do table.remove(b, 1) end
  ns.say(('Bug ulozen (%d radku, %d s). Po /reload je v SavedVariables ClaudeMaster.lua - posli mi ho.'):format(#lines, math.floor(#lines / 2)))
end

------------------------------------------------------------------------------------------
-- 3) Duo: zpravy mezi addony v parte
------------------------------------------------------------------------------------------
-- S,... = stav (mana, HP, voda, healthstone, pije, v boji)   K = "ted prerusuji ja"
-- M^C^mob^spell^kind / M^D^mob^debuff^type^spread / M^F^mob = sdilena pamet mobu
local Duo = { peers = {}, lastSend = 0, prefix = 'CMduo', ok = false, claims = {}, myClaimAt = 0 }
ns.Duo = Duo
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  Duo.ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Duo.prefix)
end

local function unitByName(name)
  for i = 1, 4 do
    local u = 'party' .. i
    if UnitExists(u) and safe(pc(UnitName, u)) == name then return u end
  end
end
local function myName() return safe(pc(UnitName, 'player')) end

local function rawSend(msg)
  if not Duo.ok or not (IsInGroup and IsInGroup()) then return false end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, Duo.prefix, msg, 'PARTY')
  -- novejsi API vraci kod vysledku (0 = ok), starsi nic
  res = safeNum(res)
  if ok and (res == nil or res == 0) then Duo.sent = (Duo.sent or 0) + 1 return true end
  Duo.fail = (Duo.fail or 0) + 1 Duo.failWhy = ok and ('kod ' .. tostring(res)) or tostring(res)
  return false
end

-- Priprava mimo boj (soulstone, healthstone, pet, armor, buff...): parťák s pullem pocka
local PREP = { '^Create ', '^Summon ', '^Conjure ', 'Armor$', 'Skin$', 'Intellect$', 'Brilliance$', '^Life Tap$', '^Evocation$',
  '^Unending Breath$', '^Detect ', '^Fel Domination$' }
local function isPrep(name)
  if type(name) ~= 'string' then return false end
  for _, k in ipairs(PREP) do if name:find(k) then return true end end
  return false
end
local function prepOf(c, plan)
  if not c or c.inCombat then return '' end
  if c.castName and isPrep(c.castName) then return c.castName end
  local a = plan and plan[1]
  if not a then return '' end
  if a.kind == 'item' and type(a.reason) == 'string' and a.reason:find('Soulstone') then return 'Soulstone' end
  if a.kind == 'spell' and isPrep(a.name) then return a.name end
  return ''
end

Duo.rawSend = rawSend

function Duo.send(c, plan)
  if not Duo.ok or not (IsInGroup and IsInGroup()) then return end
  local now = GetTime()
  local prep = prepOf(c, plan):gsub(',', '')
  local mana = ns.mana()
  local hp = ns.healthPct('player')
  local manaP = mana and math.floor(mana * 100) or -1
  local hpP = hp and math.floor(hp) or -1
  -- v boji: hned pri zmene HP/many o 3+ %, jinak jednou za 4 s; mimo boj kazde 3 s
  local changed = math.abs(hpP - (Duo.lastHp or -99)) >= 3 or math.abs(manaP - (Duo.lastMana or -99)) >= 3
  -- pod vodou a dochazi dech (bezi ukazatel) = zadost o Unending Breath; zmena se posila hned
  local uw = (ns.underwater() and ns.breathRunning() ~= false) and 1 or 0
  local gap = now - Duo.lastSend
  local uwNew = uw ~= (Duo.lastUw or 0) and gap >= 0.5
  if c and c.inCombat then
    if not ((changed and gap >= 0.7) or gap >= 4 or uwNew) then return end
  elseif gap < 3 and not (prep ~= (Duo.lastPrep or '') and gap >= 0.5) and not uwNew then return end
  if uw == 1 and (Duo.lastUw or 0) == 0 then
    for nm, p in pairs(Duo.peers) do
      if p.cls == 'WARLOCK' and now - p.at < 15 then
        ns.say(('|cff6fa8ffDochazi ti dech|r - pozadal jsem %s o Unending Breath.'):format(nm))
        break
      end
    end
  end
  Duo.lastSend, Duo.lastHp, Duo.lastMana, Duo.lastPrep, Duo.lastUw = now, hpP, manaP, prep, uw
  local ai = auraHas('player', { 'Arcane Intellect', 'Arcane Brilliance' })
  local drink = auraHas('player', { 'Drink', 'Food', 'Refreshment' })
  local msg = ('S,%s,%d,%d,%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%d'):format(ns.class or '?', manaP,
    ns.Bags.count('water'), ns.Bags.count('food'), ai == nil and -1 or (ai and 1 or 0), ns.Bags.count('stone'),
    drink and 1 or 0, (c and c.inCombat) and 1 or 0, hpP, prep ~= '' and prep or '-',
    ns.Bags.countConj('water'), ns.Bags.countConj('food'), ns.Bags.countConj('mpot'), uw)
  rawSend(msg)
  -- parťák zmlkl (odpojil se / vypnul addon)
  for nm, p in pairs(Duo.peers) do
    if p.linked and now - p.at > 20 then
      p.linked = false
      ns.say(('|cffffcc00Spojeni s addonem u %s ztraceno|r (zadna data 20 s).'):format(nm))
    end
  end
end

-- Interrupt: "ted prerusuji ja" (aby parťák nepreusil zbytecne taky)
function Duo.claimKick()
  local now = GetTime()
  if now - Duo.myClaimAt < 1.5 then return end
  Duo.myClaimAt = now
  rawSend('K')
end
-- kdo z partaku prave hlasi interrupt (do 1.5 s). Pri soucasnem hlaseni vyhrava abecedne nizsi jmeno.
function Duo.claimedBy()
  local now = GetTime()
  local me = myName() or ''
  for nm, t in pairs(Duo.claims) do
    if now - t < 1.5 then
      if now - Duo.myClaimAt < 1.5 and me < nm then return nil end
      return nm
    end
  end
end

-- CC: "ja beru CC (Polymorph / Seduction / Fear)"
function Duo.claimCC(spell)
  local now = GetTime()
  if now - (Duo.myCCAt or 0) < 3 then return end
  Duo.myCCAt = now
  rawSend('C^' .. tostring(spell))
end

-- Sdilena pamet mobu
function Duo.shareMob(kind, mob, a, b, c2)
  if type(mob) ~= 'string' then return end
  local parts = { 'M', kind, mob, a or '', b or '', c2 or '' }
  local msg = table.concat(parts, '^')
  if #msg < 250 then rawSend(msg) end
end
local function recvMob(f, from)
  local kind, mob = f[2], f[3]
  if type(mob) ~= 'string' or mob == '' then return end
  Duo.mobRecv = (Duo.mobRecv or 0) + 1
  if kind == 'C' and f[4] ~= '' then
    ns.db.mobCasts = ns.db.mobCasts or {}
    local t = ns.db.mobCasts[mob] or {}
    ns.db.mobCasts[mob] = t
    if not t[f[4]] then t[f[4]] = (f[5] ~= '' and f[5]) or 'dmg' end
  elseif kind == 'D' and f[4] ~= '' then
    ns.db.mobDebuffs = ns.db.mobDebuffs or {}
    local m = ns.db.mobDebuffs[mob] or {}
    ns.db.mobDebuffs[mob] = m
    if not m[f[4]] then m[f[4]] = { type = f[5] ~= '' and f[5] or nil, spread = f[6] == '1' or nil } end
  elseif kind == 'F' then
    ns.db.mobFlees = ns.db.mobFlees or {}
    ns.db.mobFlees[mob] = true
  end
end

local dev = CreateFrame('Frame')
pcall(dev.RegisterEvent, dev, 'CHAT_MSG_ADDON')
dev:SetScript('OnEvent', function(_, _, prefix, msg, _, sender)
  prefix, msg, sender = safe(prefix), safe(msg), safe(sender)
  if prefix ~= Duo.prefix or type(msg) ~= 'string' or type(sender) ~= 'string' then return end
  local name = sender:match('^([^%- ]+)') or sender   -- 'Jmeno-Realm' nebo 'Jmeno Realm'
  if name == myName() then return end
  if msg == 'K' then Duo.claims[name] = GetTime() return end
  if msg:sub(1, 2) == 'C^' then Duo.ccClaim = { name = name, spell = msg:sub(3), at = GetTime() } return end
  local k2 = msg:sub(1, 2)
  if k2 == 'X^' or k2 == 'P^' then if ns.Plates and ns.Plates.recv then ns.Plates.recv(name, msg) end return end
  -- gear partaka (skore slotu) -> tooltip "Jmeno +12 %"
  if k2 == 'G^' then
    if ns.Gear and ns.Gear.recv then pcall(ns.Gear.recv, name, msg) end
    if ns.Craft and ns.Craft.resetUps then ns.Craft.resetUps() end
    return
  end
  -- questy partaka (QL^ = zabil moba s mym questovym lootem)
  if msg:sub(1, 3) == 'RF^' then if ns.Route and ns.Route.recvFocus then pcall(ns.Route.recvFocus, name, msg) end return end
  if msg:sub(1, 3) == 'RL^' then if ns.Route and ns.Route.recvLog then pcall(ns.Route.recvLog, name, msg) end return end
  if msg:sub(1, 3) == 'QL^' then if ns.Quests and ns.Quests.recvLoot then ns.Quests.recvLoot(name, msg) end return end
  -- sdileni questu (QI^ = moje questy, QW^ = ktere chci)
  if msg:sub(1, 3) == 'QI^' or msg:sub(1, 3) == 'QW^' then
    if ns.Quests and ns.Quests.recvShare then pcall(ns.Quests.recvShare, name, msg) end
    return
  end
  if msg == 'Q' or k2 == 'Q^' then if ns.Quests and ns.Quests.recvPeer then ns.Quests.recvPeer(name, msg) end return end
  if msg:sub(1, 2) == 'M^' then
    local f = {}
    for v in (msg .. '^'):gmatch('([^%^]*)%^') do f[#f + 1] = v end
    recvMob(f, name)
    return
  end
  local f = {}
  for v in msg:gmatch('[^,]+') do f[#f + 1] = v end
  if f[1] ~= 'S' then return end
  local n = function(i) return tonumber(f[i]) end
  local old = Duo.peers[name]
  if not (old and old.linked) then
    ns.say(('|cff66ee77Spojeno:|r addon u %s posila data (mana, HP, voda, healthstone). Stav: /cm duo'):format(name))
  end
  Duo.peers[name] = { linked = true, n = ((old and old.n) or 0) + 1, name = name,
    cls = f[2], mana = (n(3) or -1) >= 0 and n(3) / 100 or nil, water = n(4) or 0, food = n(5) or 0,
    ai = n(6), hs = n(7) or 0, drink = n(8) == 1, combat = n(9) == 1, hp = (n(10) or -1) >= 0 and n(10) or nil, prep = (f[11] and f[11] ~= '-') and f[11] or nil,
    cw = n(12), cf = n(13), cm = n(14), uw = n(15) == 1,
    at = GetTime(), unit = unitByName(name) }
end)

-- parťák s addonem (cerstva data do 15 s)
-- vsichni partaci s addonem (serazeni podle jmena, at se poradi neprehazuje)
function Duo.peerList()
  local now, out = GetTime(), {}
  for nm, p in pairs(Duo.peers) do
    if now - p.at < 15 then
      p.unit = unitByName(nm) or p.unit   -- party1..4 se po zmene party prehazuji
      if p.unit then out[#out + 1] = p end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
function Duo.peer() return Duo.peerList()[1] end
function Duo.peerOfClass(cls)
  for _, p in ipairs(Duo.peerList()) do if p.cls == cls then return p end end
end
-- komu nejvic chybi vycarovana voda / jidlo (mimo boj, tridy, ktere to potrebuji)
local NOWATER = { WARRIOR = true, ROGUE = true, MAGE = true }
function Duo.neediest(kind)
  local best, bestN
  for _, p in ipairs(Duo.peerList()) do
    local n
    if kind == 'water' and not NOWATER[p.cls] then n = p.cw or p.water
    elseif kind == 'food' and p.cls ~= 'MAGE' then n = p.cf or p.food end
    if n and not p.combat and (bestN == nil or n < bestN) then best, bestN = p, n end
  end
  return best
end
-- HP spoluhrace z jeho addonu (Forever v boji cizi HP skryva). Cerstve: v boji 6 s (posila pri zmene), mimo 8 s.
function Duo.hpOf(unit)
  if type(unit) ~= 'string' or not unit:find('^party%d$') then return nil end
  local nm = safe(pc(UnitName, unit))
  local p = nm and Duo.peers[nm]
  if p and p.hp and GetTime() - p.at < 8 then return p.hp end
end

-- Ready check pred pullem: oba (ty i parťák) HP a mana v poradku, nikdo nepije
-- zkratka kouzla: "Arcane Intellect" -> "AI"
local function abbr(s)
  if type(s) ~= 'string' or #s <= 8 then return s end
  local a = s:gsub('(%a)%a*%s*', '%1')
  return a
end
function Duo.ready(c, short)
  local list = Duo.peerList()
  if not list[1] then return nil end
  local me = {}
  if c.php and c.php < 70 then me[#me + 1] = ('HP %d%%'):format(c.php) end
  if c.manaKnown and c.mana < 0.6 then me[#me + 1] = ('mana %d%%'):format(math.floor(c.mana * 100)) end
  if c.drinking or c.eating then me[#me + 1] = 'pijes' end
  local parts = {}
  if #me > 0 then parts[#parts + 1] = 'ty: ' .. table.concat(me, ', ') end
  -- kazdy partak zvlast; READY az kdyz jsou v poradku vsichni
  for _, p in ipairs(list) do
    local them = {}
    if p.drink then them[#them + 1] = 'pije' end
    if p.prep and not p.combat and GetTime() - p.at < 6 then them[#them + 1] = short and abbr(p.prep) or p.prep end
    if p.hp and p.hp < 70 then them[#them + 1] = ('HP %d%%'):format(p.hp) end
    if p.mana and p.mana < 0.6 then them[#them + 1] = ('mana %d%%'):format(math.floor(p.mana * 100)) end
    if p.unit and safeBool(pc(UnitIsDeadOrGhost, p.unit)) == true then them[#them + 1] = 'mrtvy' end
    if #them > 0 then parts[#parts + 1] = ns.classIco(p.cls) .. ' ' .. p.name .. ': ' .. table.concat(them, ', ') end
  end
  if #parts == 0 then return true, ns.ico('ready', 14) .. ' |cff66ee77READY|r' end
  return false, ns.ico('wait', 14) .. ' |cffe0d090' .. table.concat(parts, ' | ') .. '|r'
end

-- /cm duo: stav spojeni
function Duo.status()
  ns.say(('Duo: kanal %s | odeslano %d, chyb %d%s | pamet mobu od partaka: %d'):format(Duo.ok and 'registrovan' or '|cffff5555NEREGISTROVAN|r',
    Duo.sent or 0, Duo.fail or 0, Duo.failWhy and (' (' .. Duo.failWhy .. ')') or '', Duo.mobRecv or 0))
  if not (IsInGroup and IsInGroup()) then ns.say('Nejsi v parte - data se posilaji jen v parte.') end
  local any = false
  for nm, p in pairs(Duo.peers) do
    any = true
    local age = GetTime() - p.at
    ns.say(('  %s (%s): prijato %dx, naposledy pred %.0f s | HP %s, mana %s, voda %d, healthstone %d%s'):format(nm, p.cls or '?', p.n or 1, age,
      p.hp and (p.hp .. '%') or '?', p.mana and (math.floor(p.mana * 100) .. '%') or '?', p.water or 0, p.hs or 0,
      age < 15 and ' |cff66ee77OK|r' or ' |cffff5555stara data|r'))
  end
  if not any then ns.say('  Od nikoho zatim nic neprislo (ma partak novou verzi addonu?).') end
  local G = ns.Gear
  if G and G.peers then
    for nm, p in pairs(G.peers) do
      ns.say(('  vybaveni od %s (%s, lvl %d): pred %.0f s'):format(nm, p.cls or '?', p.lvl or 0, GetTime() - p.at))
    end
    ns.say(G.shareOk and ('  moje vybaveni odeslano pred %.0f s'):format(GetTime() - G.shareOk) or '  moje vybaveni zatim neodeslano')
  end
end

------------------------------------------------------------------------------------------
-- 4) Nove schopnosti
------------------------------------------------------------------------------------------
local function checkNew()
  local book = ns.lastBook
  if type(book) ~= 'table' or next(book) == nil then return end
  local known = ns.db.knownBook
  local firstRun = known == nil
  known = known or {}
  local inAddon = {}
  for _, n in ipairs(ns.SPELLS or {}) do inAddon[n] = true end
  local news = {}
  for name in pairs(book) do
    if not known[name] then
      known[name] = true
      if not firstRun then news[#news + 1] = name end
    end
  end
  ns.db.knownBook = known
  table.sort(news)
  for _, name in ipairs(news) do
    local base = name:gsub(' %(.*%)$', '')
    if inAddon[name] or inAddon[base] then
      ns.say(('|cff66ee77Nova schopnost: %s|r - addon ji zna a zacne ji doporucovat.'):format(name))
    else
      ns.say(('|cffffcc00Nova schopnost: %s|r - addon ji zatim nezna. Udelej /cm dump a posli mi ho.'):format(name))
      ns.db.newUnknown = ns.db.newUnknown or {}
      ns.db.newUnknown[name] = date and date('%Y-%m-%d') or true
    end
  end
end
------------------------------------------------------------------------------------------
-- 4b) Zmeny od vyvojaru (patch): addon na internet nesmi, ale vidi, co hra rika o kouzlech.
-- Snimek sledovanych kouzel (popis, zakladni cooldown, cast time, cena) a porovnani s minulym.
--  * text popisu bez cisel se zmenil = jina mechanika (hlasit vzdy)
--  * zakladni cooldown se zmenil (nezavisi na gearu) = hlasit vzdy
--  * cisla / cast / cena: jen kdyz se zmenil build hry a talenty jsou stejne (jinak to dela gear/talent)
------------------------------------------------------------------------------------------
local function talentSig()
  local l = {}
  for n, r in pairs(ns.talents or {}) do if r > 0 then l[#l + 1] = n .. r end end
  table.sort(l)
  return table.concat(l, ',')
end
local function snapOne(id)
  local d = C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
  if type(d) ~= 'string' or d == '' then return nil end
  local s = { d = d, t = (d:gsub('[%d%.,]+', '#')) }
  s.cd = safeNum(pc(GetSpellBaseCooldown, id))
  local info = C_Spell and C_Spell.GetSpellInfo and pc(C_Spell.GetSpellInfo, id)
  if type(info) == 'table' then s.cast = safeNum(info.castTime) end
  local cost = C_Spell and C_Spell.GetSpellPowerCost and pc(C_Spell.GetSpellPowerCost, id)
  if type(cost) == 'table' and type(cost[1]) == 'table' then s.cost = safeNum(cost[1].cost) end
  return s
end
local function nums(str)
  local l = {}
  for n in str:gmatch('%d+%.?%d*') do l[#l + 1] = n end
  return table.concat(l, ' ')
end
local function checkPatch()
  if InCombatLockdown() then return end
  local _, build = pc(GetBuildInfo)
  build = tostring(safe(build) or '?')
  local db = ns.db
  db.spellSnap = db.spellSnap or {}
  local old, firstRun = db.spellSnap, next(db.spellSnap) == nil
  local tsig = talentSig()
  local newBuild = db.snapBuild and db.snapBuild ~= build
  local sameTalents = db.snapTalents == tsig
  local found = {}
  for _, name in ipairs(ns.SPELLS or {}) do
    local id = ns.known(name) and ns.id(name)
    local s = id and snapOne(id)
    if s then
      local key = name .. '#' .. id   -- novy rank = jine ID, to neni zmena
      local o = old[key]
      if o and not firstRun then
        local why = {}
        if o.t ~= s.t then why[#why + 1] = 'zmeneny popis (mechanika)' end
        if o.cd and s.cd and o.cd ~= s.cd then why[#why + 1] = ('cooldown %g -> %g s'):format(o.cd / 1000, s.cd / 1000) end
        if newBuild and sameTalents then
          if o.t == s.t and nums(o.d) ~= nums(s.d) then why[#why + 1] = ('cisla: %s -> %s'):format(nums(o.d), nums(s.d)) end
          if o.cast and s.cast and o.cast ~= s.cast then why[#why + 1] = ('cast %g -> %g s'):format(o.cast / 1000, s.cast / 1000) end
          if o.cost and s.cost and o.cost ~= s.cost then why[#why + 1] = ('mana %d -> %d'):format(o.cost, s.cost) end
        end
        if #why > 0 then
          found[#found + 1] = { name = name, why = table.concat(why, ', '), old = o.d, new = s.d }
        end
      end
      old[key] = s
    end
  end
  db.snapBuild, db.snapTalents = build, tsig
  if #found == 0 then return end
  db.patchLog = db.patchLog or {}
  local day = date and date('%Y-%m-%d') or '?'
  ns.say(('|cffffcc00Hra zmenila %d kouzel%s|r - doporucovani muze byt mimo. Posli mi /cm zmeny (je to i v SavedVariables).')
    :format(#found, newBuild and (' (novy build ' .. build .. ')') or ''))
  for _, f in ipairs(found) do
    ns.say(('  %s: %s'):format(f.name, f.why))
    table.insert(db.patchLog, 1, { day = day, build = build, name = f.name, why = f.why, old = f.old, new = f.new })
  end
  while #db.patchLog > 60 do table.remove(db.patchLog) end
end
ns.checkPatch = checkPatch
function ns.showPatchLog()
  local l = ns.db.patchLog
  if not l or #l == 0 then ns.say('Zadne zmeny kouzel od hry zatim nezaznamenany.') return end
  ns.say(('Zmeny kouzel, ktere addon zaznamenal (%d, nejnovejsi nahore):'):format(#l))
  for i = 1, math.min(#l, 15) do
    local e = l[i]
    ns.say(('  %s (build %s) %s: %s'):format(e.day, e.build, e.name, e.why))
  end
end

local origScan = ns.scanSpells
if origScan then
  ns.scanSpells = function(...)
    local r = origScan(...)
    pcall(checkNew)
    if C_Timer then C_Timer.After(3, function() pcall(checkPatch) end) else pcall(checkPatch) end
    return r
  end
end

------------------------------------------------------------------------------------------
-- 5) Nejde prerusit: sedy cast bar (stit) + uceni (Counterspell probehl a cil kouzli dal)
------------------------------------------------------------------------------------------
local function barShield(bar)
  if not bar then return nil end
  if safe(bar.notInterruptible) == true then return true end
  local bt = safe(bar.barType)
  if bt == 'uninterruptable' or bt == 'uninterruptible' then return true end
  local sh = bar.BorderShield or bar.Shield
  if sh and sh.IsShown then
    local ok, v = pcall(sh.IsShown, sh)
    if ok and v == true then return true end
  end
  return nil
end
function ns.castShielded()
  local ok, res = pcall(function()
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
      local p = C_NamePlate.GetNamePlateForUnit('target')
      local uf = p and p.UnitFrame
      local cb = uf and (uf.castBar or uf.CastBar)
      if cb and cb:IsVisible() and barShield(cb) then return true end
    end
    local tb = TargetFrameSpellBar or (TargetFrame and TargetFrame.spellbar)
    if tb and tb:IsVisible() and barShield(tb) then return true end
    return false
  end)
  return ok and res or false
end

local KICK_SPELLS = { Counterspell = true, ['Spell Lock'] = true }
local kf = CreateFrame('Frame')
pcall(kf.RegisterUnitEvent, kf, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'pet')
kf:SetScript('OnEvent', function(_, _, unit, _, spellID)
  local name = ns.nameOf and ns.nameOf(safeNum(spellID))
  if not (name and KICK_SPELLS[name]) then return end
  local spell, start = ns.lastTCast, ns.tCastStart
  if type(spell) ~= 'string' or not C_Timer then return end
  C_Timer.After(0.5, function()
    local still = ns.isSet(pc(UnitCastingInfo, 'target')) or ns.isSet(pc(UnitChannelInfo, 'target'))
    if still and ns.tCastStart == start and ns.lastTCast == spell then
      ns.db.noKick = ns.db.noKick or {}
      if not ns.db.noKick[spell] then
        ns.db.noKick[spell] = true
        ns.say(('|cffffcc00%s nejde prerusit|r - zapamatovano, priste interrupt nenabidnu.'):format(spell))
      end
    end
  end)
end)

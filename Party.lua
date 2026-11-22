-- ClaudeMaster: parta. Kdo potrebuje buff, kdo ma curse, na koho jdou moby a kdo ma malo HP.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local P = {}
ns.Party = P

P.UNITS = { 'party1', 'party2', 'party3', 'party4' }
P.PETS = { 'partypet1', 'partypet2', 'partypet3', 'partypet4' }
P.ALL = { 'party1', 'party2', 'party3', 'party4', 'partypet1', 'partypet2', 'partypet3', 'partypet4', 'pet' }

local function unitName(u)
  local n = safe(pc(UnitName, u))
  return type(n) == 'string' and n or u
end
local function alive(u)
  return UnitExists(u) and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true
    and safeBool(pc(UnitIsConnected, u)) ~= false
end
local function inRange(spell, u)
  local id = ns.id(spell)
  if id and C_Spell and C_Spell.IsSpellInRange then
    local v = safeBool(pc(C_Spell.IsSpellInRange, id, u))
    if v ~= nil then return v end
  end
  local r = safeBool(pc(UnitInRange, u))
  if r ~= nil then return r end
  if InCombatLockdown() then return true end
  return safeBool(pc(CheckInteractDistance, u, 4)) ~= false
end
local function auraByName(u, name)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, u, name, 'HELPFUL')
  if not ok then return nil end
  if a ~= nil then return true end
  if ns.inCombat() then return nil end
  return false
end
-- Ma unit neco, co umim odstranit? Filtr RAID vraci jen debuffy, ktere ja muzu dispellnout.
-- I kdyz je obsah skryty, "neco tam je" poznam.
local function hasDispellable(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
  local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, 1, 'HARMFUL|RAID')
  return ok and ns.isSet(a)
end

-- Tank = nekdo s roli TANK, jinak pet (warlockuv voidwalker/sukuba, hunteruv pet)
-- Magicky debuff (odstrani Felhunterovo Devour Magic). Typ jde precist jen mimo boj / kdyz neni skryty.
local function hasMagic(u)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
  for i = 1, 16 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, 'HARMFUL')
    if not ok or type(a) ~= 'table' then return false end
    if safe(a.dispelName) == 'Magic' then return true end
  end
  return false
end

local function isTank(u)
  if u:find('pet') then return true end
  local role = safe(pc(UnitGroupRolesAssigned, u))
  return role == 'TANK'
end
local function isHealer(u)
  return safe(pc(UnitGroupRolesAssigned, u)) == 'HEALER'
end

------------------------------------------------------------------------------------------
-- Interrupty v parte: kdo co pouzil (z UNIT_SPELLCAST_SUCCEEDED spoluhracu a jejich petu)
-- a kdo je na rade. Combat log je na Forever zakazany, tohle event jde.
------------------------------------------------------------------------------------------
P.KICKS = { Kick = 10, Pummel = 10, ['Shield Bash'] = 12, ['Earth Shock'] = 6, Counterspell = 24, ['Spell Lock'] = 24,
  Silence = 45, ['Hammer of Justice'] = 60, Bash = 60, ['Feral Charge'] = 15, ['Wind Shear'] = 6, ['Rebuke'] = 10 }
-- co ktera classa umi (aby slo rict, kdo interrupt ma, i kdyz ho jeste nepouzil)
P.CLASS_KICK = { ROGUE = 'Kick', WARRIOR = 'Pummel', SHAMAN = 'Earth Shock', MAGE = 'Counterspell' }
P.kick = {}          -- jmeno -> { spell, readyAt, usedAt }
P.CC_SPELLS = { Polymorph = 50, Banish = 30, Seduction = 15, Hibernate = 40, Sap = 45, ['Shackle Undead'] = 50, Repentance = 60 }
P.myKicks = 0
P.lastKickAt = 0     -- kdy naposled kdokoli prerusil
local kev = CreateFrame('Frame')
pcall(kev.RegisterEvent, kev, 'UNIT_SPELLCAST_SUCCEEDED')
kev:SetScript('OnEvent', function(_, _, unit, _, spellID)
  unit = safe(unit)
  if type(unit) ~= 'string' then return end
  if not (unit == 'player' or unit == 'pet' or unit:find('^party%d$') or unit:find('^partypet%d$')) then return end
  local name = ns.nameOf(safeNum(spellID))
  -- CC od spoluhrace (ovce od maga, Banish, Seduction...): nebit ten cil
  local ccDur = name and P.CC_SPELLS[name]
  if ccDur and unit ~= 'player' and unit ~= 'pet' and ns.ccGUID then
    local g = safe(pc(UnitGUID, unit .. 'target'))
    if type(g) == 'string' then ns.ccGUID[g] = GetTime() + ccDur if ns.ccAt then ns.ccAt[g] = GetTime() end end
  end
  local cd = name and P.KICKS[name]
  if not cd then return end
  if unit == 'player' or unit == 'pet' then P.myKicks = (P.myKicks or 0) + 1 end
  -- pet patri majiteli
  local owner = unit
  if unit == 'pet' then owner = 'player' elseif unit:find('^partypet') then owner = 'party' .. unit:match('%d') end
  local who = safe(pc(UnitName, owner))
  if type(who) ~= 'string' then return end
  local now = GetTime()
  P.kick[who] = { spell = name, readyAt = now + cd, usedAt = now, unit = owner }
  P.lastKickAt = now
end)

-- Stav interruptu v parte. Vraci: lidi s interruptem (i ja), kdo je na rade a jestli ted nekdo prave prerusil.
function P.kickState()
  local now = GetTime()
  local me = safe(pc(UnitName, 'player'))
  local list = {}
  local function add(unit, defSpell)
    local nm = safe(pc(UnitName, unit))
    if type(nm) ~= 'string' then return end
    local k = P.kick[nm]
    local spell = (k and k.spell) or defSpell
    if not spell then return end
    list[#list + 1] = { name = nm, unit = unit, spell = spell, ready = not k or k.readyAt <= now,
      left = k and math.max(0, k.readyAt - now) or 0, usedAt = k and k.usedAt or 0, me = nm == me }
  end
  -- ja: Counterspell, nebo Felhunter (Spell Lock)
  local myKick = (ns.known('Counterspell') and 'Counterspell')
    or ((UnitExists('pet') and safe(pc(UnitCreatureFamily, 'pet')) == 'Felhunter') and 'Spell Lock') or nil
  add('player', myKick)
  for i = 1, 4 do
    local u = 'party' .. i
    if UnitExists(u) and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true then
      local cls = select(2, UnitClass(u))
      local def = P.CLASS_KICK[cls]
      if cls == 'WARLOCK' and UnitExists('partypet' .. i) and safe(pc(UnitCreatureFamily, 'partypet' .. i)) == 'Felhunter' then
        def = 'Spell Lock'
      end
      add(u, def)
    end
  end
  -- na rade: z tech, co maji interrupt ready, ten, kdo ho pouzil nejdrive (rotace).
  -- Pri shode (napr. nikdo jeste neprerusoval) musi oba addony vybrat STEJNE, jinak vyhraje ten,
  -- jehoz addon zareaguje driv (typicky mag) a druhy nedostane radu nikdy: prednost ma pet
  -- (Spell Lock nestoji hrace nic), pak abecedne jmeno.
  local function before(a, b)
    if a.usedAt ~= b.usedAt then return a.usedAt < b.usedAt end
    local pa, pb = a.spell == 'Spell Lock', b.spell == 'Spell Lock'
    if pa ~= pb then return pa end
    return a.name < b.name
  end
  local nextUp
  for _, k in ipairs(list) do
    if k.ready and (not nextUp or before(k, nextUp)) then nextUp = k end
  end
  -- parťák s addonem prave hlasi "prerusuji ja": je na rade on
  local claimedBy = ns.Duo and ns.Duo.claimedBy and ns.Duo.claimedBy() or nil
  if claimedBy then
    for _, k in ipairs(list) do if k.name == claimedBy then nextUp = k end end
  end
  return { list = list, nextUp = nextUp, justKicked = now - P.lastKickAt < 1.5, others = #list > 1, claimedBy = claimedBy }
end

function P.scan(c)
  local r = { members = {}, needAI = nil, curse = nil, danger = nil, petLow = nil, petDead = nil }
  if not (IsInGroup and IsInGroup()) then return r end
  local on = c.enemies.on or {}
  local inCombat = c.inCombat
  local canDispel = ns.known('Remove Lesser Curse') or ns.known('Remove Curse')
  -- warlock s Felhunterem: Devour Magic na magicke debuffy spoluhracu
  local felhunter = ns.class == 'WARLOCK' and UnitExists('pet') and safe(pc(UnitCreatureFamily, 'pet')) == 'Felhunter'
  for i, u in ipairs(P.UNITS) do
    if UnitExists(u) then
      local m = { unit = u, name = unitName(u), alive = alive(u), tank = isTank(u), healer = isHealer(u) }
      m.mana = safeNum(pc(UnitPowerType, u)) == 0
      m.mobs = on[u] or 0
      m.low = ns.hpBelow(u, 50) == true
      m.veryLow = ns.hpBelow(u, 30) == true
      m.near = (not InCombatLockdown()) and safeBool(pc(CheckInteractDistance, u, 3)) == true
      r.members[#r.members + 1] = m
      if m.alive then
        -- Arcane Intellect (jen mimo boj, v boji auray nejdou cist)
        if not inCombat and m.mana and ns.known('Arcane Intellect') and not r.needAI then
          local has = auraByName(u, 'Arcane Intellect')
          if has == false and auraByName(u, 'Arcane Brilliance') == false and inRange('Arcane Intellect', u) then
            r.needAI = m
          end
        end
        -- warlock pod vodou: Unending Breath i pro partu (auray jen mimo boj)
        if not inCombat and not r.needBreath and ns.known('Unending Breath') and ns.underwater and ns.underwater()
          and auraByName(u, 'Unending Breath') == false and inRange('Unending Breath', u) then
          r.needBreath = m
        end
        -- spoluhrac s addonem sam hlasi "pod vodou, dochazi dech" (funguje i v boji a i kdyz ja nejsem pod vodou)
        if not r.needBreath and ns.known('Unending Breath') and ns.Duo and ns.Duo.peers then
          local p = m.name and ns.Duo.peers[m.name]
          if p and p.uw and GetTime() - p.at < 8 and inRange('Unending Breath', u) then
            m.asked = true
            r.needBreath = m
          end
        end
        if canDispel and not r.curse and hasDispellable(u) and inRange('Remove Lesser Curse', u) then r.curse = m end
        if felhunter and not r.magic and hasMagic(u) then r.magic = m end
        -- spoluhrac (ne tank), na kterem jsou moby
        if m.mobs > 0 and not m.tank then
          local score = m.mobs * 2 + (m.low and 3 or 0) + (m.veryLow and 3 or 0) + (m.healer and 2 or 0)
          if not r.danger or score > r.danger.score then m.score = score r.danger = m end
        end
      end
      -- pet tohoto hrace
      local pu = P.PETS[i]
      if UnitExists(pu) then
        local pm = { unit = pu, name = unitName(pu), owner = m.name, mobs = on[pu] or 0 }
        pm.low = ns.hpBelow(pu, 30) == true
        if alive(pu) and pm.mobs > 0 and pm.low then r.petLow = pm end
      elseif m.alive and m.mobs > 0 and inCombat and (select(2, UnitClass(u)) == 'WARLOCK' or select(2, UnitClass(u)) == 'HUNTER') then
        -- pet chybi a moby jdou po hraci (pet padl nebo je odvolany)
        r.petDead = m
      end
    end
  end
  -- tank: role TANK, jinak hrac (ne pet, ne healer), na kterem je nejvic mobu
  for _, m in ipairs(r.members) do
    if m.alive and m.tank and not m.unit:find('pet') then r.tank = m break end
  end
  -- role casto nejsou nastavene: warrior (pak paladin/druid) je skoro jiste tank
  if not r.tank then
    for _, cls in ipairs({ 'WARRIOR', 'PALADIN', 'DRUID' }) do
      for _, m in ipairs(r.members) do
        if m.alive and not m.healer and select(2, UnitClass(m.unit)) == cls then r.tank = m break end
      end
      if r.tank then break end
    end
  end
  -- posledni moznost (kdo ma nejvic mobu) jen v dungeonu: venku v duu by se "tankem" stal treba mag,
  -- na ktereho zrovna jde mob, a addon by pak cekal na tanka a hlidal threat zbytecne
  local instance = IsInInstance and select(1, IsInInstance()) or false
  if not r.tank and inCombat and instance then
    for _, m in ipairs(r.members) do
      if m.alive and not m.healer and m.mobs >= 1 and (not r.tank or m.mobs > r.tank.mobs) then r.tank = m end
    end
  end
  -- hrac sam sebe: curse na mne
  if canDispel and not r.curse and hasDispellable('player') then r.curse = { unit = 'player', name = 'tobe' } end
  if felhunter and not r.magic and hasMagic('player') then r.magic = { unit = 'player', name = 'tobe' } end
  return r
end

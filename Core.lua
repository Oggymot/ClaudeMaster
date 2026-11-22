-- ClaudeMaster: Core
-- Sbira stav hry tak, aby fungoval i ve WoW Forever, ktery addonum v boji skryva
-- zdravi, auray a cooldowny ("secret values"). Kazda hodnota z API projde pres safe*(),
-- a kdyz je skryta, pouzije se odhad z vlastnich castu, Cooldown Manageru, proc glow
-- eventu nebo trik se StatusBarem (zdravi cile/hrace v pasmech).
local ADDON, ns = ...
local _, playerClass = UnitClass('player')
ns.class = playerClass
ns.enabled = (playerClass == 'MAGE' or playerClass == 'WARLOCK')

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

-- pcall, ktery vraci jen vysledky (nebo nil pri chybe)
local function pc(f, ...)
  if type(f) ~= 'function' then return nil end
  return (function(ok, ...) if ok then return ... end return nil end)(pcall(f, ...))
end
local function safe(v) if issecret(v) then return nil end return v end
local function safeNum(v) if type(v) ~= 'number' or issecret(v) then return nil end return v end
local function safeBool(v)
  if v == nil or issecret(v) then return nil end
  if type(v) == 'boolean' then return v end
  if type(v) == 'number' then return v ~= 0 end
  return nil
end
local function isSet(v) return issecret(v) or v ~= nil end   -- "existuje", i kdyz je skryta
ns.pc, ns.safe, ns.safeNum, ns.safeBool, ns.isSet = pc, safe, safeNum, safeBool, isSet

function ns.say(msg) print('|cff66ccffClaudeMaster|r: ' .. tostring(msg)) end
function ns.inCombat()
  local v = safeBool(pc(UnitAffectingCombat, 'player'))
  if v == nil then v = InCombatLockdown and InCombatLockdown() or false end
  return v
end

------------------------------------------------------------------------------------------
-- Nastaveni
------------------------------------------------------------------------------------------
local DEFAULTS = {
  locked = false, scale = 1, shown = true,
  point = { 'CENTER', 'CENTER', 0, -190 },
  aoe = 3,             -- od kolika mobu v boji je to AoE
  showInfo = true, showReason = true,
  prebarrier = true,   -- Ice Barrier pred pullem
  wandMana = 0.08,     -- pod tolik many wand
  conserveMana = 0.30, -- pod tolik many setri (wand na dorazeni, zadny Blizzard na 2 moby)
  gemMana = 0.70,      -- mana gem pod tolik many v boji
  drinkMana = 0.55,    -- pit mimo boj pod tolik many
  potionHP = 30,       -- healing potion pod tolik HP
  cdLearned = {},
  hpScale = nil,       -- UnitHealthPercent vraci 0-1 nebo 0-100 (nauceno mimo boj)
  debug = false,
  sound = true,        -- zvuk u nalehavych doporuceni
  summary = true,      -- shrnuti po boji
  hideIdle = true,     -- mimo boj a bez doporuceni okno schovat
  multiDot = true,     -- warlock: radit DoTy i na dalsi moby
  plates = true,       -- znacky u jmenovek nepratel
  markBarOn = false,   -- lista se znackami (lebka / mesic) ve skupine: jen kdyz si ji hrac zapne
  tipMob = true,       -- v tooltipu nepritele pamet addonu
  questZone = false,   -- seznam questu: jen questy z aktualni oblasti (/cm questy)
  questSort = false,   -- seznam questu: radit podle vzdalenosti
  learn = true,        -- ucit se z toho, jak hrajes
  tankWait = 1.5,      -- v parte s tankem: tolik sekund po pullu nech tanka nabrat aggro
  aoeDelay = 3,        -- v parte s tankem: AoE az po tolika sekundach (uci se: strhnes aggro -> delsi)
  shardKeep = 3,       -- warlock: tolik soul shardu si drz (Shadowburn/Soul Fire jen nad tim)
  shardWant = 6,       -- warlock: Drain Soul na dorazeni, dokud nemas tolik shardu
}
function ns.initDB()
  ClaudeMasterDB = ClaudeMasterDB or {}
  for k, v in pairs(DEFAULTS) do
    if ClaudeMasterDB[k] == nil then
      if type(v) == 'table' then
        local t = {} for a, b in pairs(v) do t[a] = b end
        ClaudeMasterDB[k] = t
      else ClaudeMasterDB[k] = v end
    end
  end
  ns.db = ClaudeMasterDB
end

------------------------------------------------------------------------------------------
-- Spelly
------------------------------------------------------------------------------------------
local MAGE_SPELLS = {
  'Frostbolt', 'Ice Lance', 'Frost Nova', 'Cone of Cold', 'Blizzard', 'Fire Blast', 'Fireball', 'Scorch',
  'Arcane Explosion', 'Arcane Missiles', 'Counterspell', 'Ice Barrier', 'Ice Block', 'Cold Snap', 'Icy Veins',
  'Evocation', 'Blink', 'Polymorph', 'Frost Armor', 'Ice Armor', 'Mage Armor', 'Molten Armor',
  'Arcane Intellect', 'Shoot', 'Cryoblast', 'Mana Shield', 'Frost Ward', 'Fire Ward', 'Conjure Water',
  'Conjure Food', 'Conjure Mana Agate', 'Conjure Mana Jade', 'Conjure Mana Citrine', 'Conjure Mana Ruby',
  'Remove Lesser Curse', 'Presence of Mind', 'Flamestrike', 'Frostfire Bolt', 'Amplify Magic', 'Dampen Magic',
  'Slow Fall', 'Will to Survive', 'Perception',
  -- talentova kouzla (az je mag vezme, addon s nimi hned pocita)
  'Arcane Power', 'Combustion', 'Blast Wave', 'Pyroblast', 'Arcane Blast', 'Arcane Wrath',
}
local WARLOCK_SPELLS = {
  'Shadow Bolt', 'Immolate', 'Conflagrate', 'Searing Pain', 'Incinerate', 'Soul Fire', 'Shadowburn', 'Corruption',
  'Bane of Agony', 'Bane of Havoc', 'Bane of Doom', 'Curse of Exhaustion', 'Wrack', 'Incinerate',
  'Create Firestone', 'Create Spellstone', 'Summon Incubus',
  'Curse of Agony', 'Curse of the Elements', 'Curse of Shadow', 'Curse of Weakness', 'Curse of Tongues',
  'Curse of Recklessness', 'Curse of Doom', 'Amplify Curse', 'Siphon Life', 'Drain Life', 'Drain Soul', 'Drain Mana',
  'Life Tap', 'Dark Pact', 'Fear', 'Howl of Terror', 'Death Coil', 'Banish', 'Rain of Fire', 'Hellfire',
  'Shadow Ward', 'Demon Armor', 'Demon Skin', 'Health Funnel', 'Fel Domination', 'Inferno',
  'Summon Imp', 'Summon Voidwalker', 'Summon Succubus', 'Summon Felhunter',
  'Create Healthstone', 'Create Soulstone', 'Unending Breath', 'Detect Invisibility', 'Shoot',
  'Will to Survive', 'Perception',
}
ns.SPELLS = (playerClass == 'WARLOCK') and WARLOCK_SPELLS or MAGE_SPELLS
-- Zakladni cooldowny (prepisou se skutecnymi, ktere klient ukaze mimo boj)
ns.BASE_CD = {
  ['Frost Nova'] = 25, ['Cone of Cold'] = 10, ['Fire Blast'] = 8, ['Counterspell'] = 24, ['Ice Barrier'] = 30,
  ['Ice Block'] = 300, ['Cold Snap'] = 600, ['Icy Veins'] = 180, ['Evocation'] = 480, ['Blink'] = 15,
  ['Ice Lance'] = 0, ['Cryoblast'] = 0, ['Presence of Mind'] = 180, ['Frost Ward'] = 30, ['Fire Ward'] = 30,
  ['Will to Survive'] = 180, ['Perception'] = 180,
  ['Arcane Power'] = 180, ['Combustion'] = 180, ['Blast Wave'] = 45,
  -- warlock
  ['Conflagrate'] = 10, ['Shadowburn'] = 15, ['Death Coil'] = 120, ['Howl of Terror'] = 40, ['Soul Fire'] = 60,
  ['Shadow Ward'] = 30, ['Amplify Curse'] = 180, ['Fel Domination'] = 900, ['Inferno'] = 3600, ['Curse of Doom'] = 60,
}
-- Kouzla bez globalniho cooldownu
ns.OFF_GCD = { ['Cold Snap'] = true, ['Icy Veins'] = true, ['Presence of Mind'] = true, ['Counterspell'] = true,
  ['Will to Survive'] = true, ['Perception'] = true, ['Amplify Curse'] = true, ['Fel Domination'] = true,
  ['Arcane Power'] = true, ['Combustion'] = true }
-- Mrazive cooldowny, ktere Cold Snap resetuje
ns.FROST_CDS = { 'Frost Nova', 'Cone of Cold', 'Ice Barrier', 'Ice Block', 'Icy Veins', 'Ice Lance', 'Cryoblast', 'Frost Ward' }
ns.CHANNEL = { ['Blizzard'] = 8, ['Evocation'] = 8, ['Arcane Missiles'] = 5,
  ['Drain Life'] = 5, ['Drain Soul'] = 15, ['Drain Mana'] = 5, ['Health Funnel'] = 10, ['Rain of Fire'] = 8, ['Hellfire'] = 15 }

ns.S = {}         -- name -> {id, icon, cast, cost, known}
ns.ranks = {}     -- name -> { id ranku 1, id ranku 2, ... }
function ns.rankCount(name) local r = ns.ranks[name] return r and #r or 0 end
function ns.rankId(name, k) local r = ns.ranks[name] return r and r[k] end
ns.castAt = {}    -- name -> GetTime() posledniho seslani
local idToName = {}

local function readSpellbook()
  local found = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local lines = safeNum(pc(C_SpellBook.GetNumSpellBookSkillLines)) or 0
    for l = 1, lines do
      local li = pc(C_SpellBook.GetSpellBookSkillLineInfo, l)
      if type(li) == 'table' then
        local off, num = safeNum(li.itemIndexOffset) or 0, safeNum(li.numSpellBookItems) or 0
        for i = off + 1, off + num do
          local it = pc(C_SpellBook.GetSpellBookItemInfo, i, bank)
          if type(it) == 'table' then
            local name, id = safe(it.name), safeNum(it.spellID) or safeNum(it.actionID)
            local passive = safeBool(it.isPassive)
            if type(name) == 'string' and id and not passive then
              found[name] = id   -- posledni = nejvyssi rank
              ns.ranks[name] = ns.ranks[name] or {}
              local r = ns.ranks[name]
              if r[#r] ~= id then r[#r + 1] = id end
            end
          end
        end
      end
    end
  end
  return found
end

function ns.scanSpells()
  ns.ranks = {}
  pcall(ns.scanTalents)
  local book = readSpellbook()
  ns.lastBook = book
  for _, name in ipairs(ns.SPELLS) do
    local e = ns.S[name] or {}
    local id = book[name]
    e.realName = nil
    if not id then
      local RANKS = { Major = 5, Greater = 4, [''] = 3, Lesser = 2, Minor = 1 }
      local best = -1
      for bn, bid in pairs(book) do
        if bn:sub(1, #name + 2) == name .. ' (' then
          local r = RANKS[bn:match('%((%a+)%)$') or ''] or 0
          if r > best then best, id, e.realName = r, bid, bn end
        end
      end
    end
    if not id and next(book) == nil and C_Spell and C_Spell.GetSpellInfo then
      -- starsi API: dotaz podle jmena
      local info = pc(C_Spell.GetSpellInfo, name)
      id = type(info) == 'table' and safeNum(info.spellID) or nil
    end
    e.known = id ~= nil
    if id then
      e.id = id
      idToName[id] = name
      local info = C_Spell and pc(C_Spell.GetSpellInfo, id)
      if type(info) == 'table' then
        e.icon = safe(info.iconID) or e.icon
        local ct = safeNum(info.castTime)
        if ct then e.cast = ct / 1000 end
      end
      if not e.icon and C_Spell and C_Spell.GetSpellTexture then e.icon = safe(pc(C_Spell.GetSpellTexture, id)) end
      if C_Spell and C_Spell.GetSpellPowerCost then
        local costs = pc(C_Spell.GetSpellPowerCost, id)
        if type(costs) == 'table' then
          for _, c in ipairs(costs) do
            local t, v = safeNum(c.type), safeNum(c.cost)
            if t == 0 and v then e.cost = v end
            local pct = safeNum(c.costPercent)
            if t == 0 and not v and pct then e.costPct = pct end
          end
        end
      end
    end
    ns.S[name] = e
  end
  if ns.S['Shoot'] then ns.S['Shoot'].known = ns.S['Shoot'].known and HasWandEquipped and HasWandEquipped() or false end
  ns.scanBindings()
  if ns.checkBarrierBuff then pcall(ns.checkBarrierBuff) end
end

-- Talenty (pro vsechny classy): jmeno -> rank
ns.talents, ns.talentsRead = {}, false
function ns.scanTalents()
  local t = {}
  local nTabs = safeNum(pc(GetNumTalentTabs)) or 0
  for tab = 1, nTabs do
    local n = safeNum(pc(GetNumTalents, tab)) or 0
    for i = 1, n do
      local name, _, _, _, rank = pc(GetTalentInfo, tab, i)
      name, rank = safe(name), safeNum(rank)
      if type(name) == 'string' and rank then t[name] = rank end
    end
  end
  ns.talentList, ns.talentAPI = nil, (next(t) ~= nil) and 'classic' or nil
  -- WoW Forever: buildy jsou v C_Traits (jako moderni WoW), stare GetTalentInfo vraci 0
  if next(t) == nil and C_ClassTalents and C_Traits then
    local cfg = safeNum(pc(C_ClassTalents.GetActiveConfigID))
    if not cfg and C_ClassTalents.GetLastSelectedSavedConfigID and GetSpecializationInfo and GetSpecialization then
      local spec = safeNum(pc(GetSpecializationInfo, safeNum(pc(GetSpecialization)) or 1))
      cfg = spec and safeNum(pc(C_ClassTalents.GetLastSelectedSavedConfigID, spec))
    end
    local info = cfg and pc(C_Traits.GetConfigInfo, cfg)
    if type(info) == 'table' and type(info.treeIDs) == 'table' then
      local list = {}
      for _, tree in ipairs(info.treeIDs) do
        for _, node in ipairs(pc(C_Traits.GetTreeNodes, tree) or {}) do
          local ni = pc(C_Traits.GetNodeInfo, cfg, node)
          if type(ni) == 'table' then
            local entries = type(ni.entryIDs) == 'table' and ni.entryIDs or {}
            local active = type(ni.activeEntry) == 'table' and safeNum(ni.activeEntry.entryID)
            local rank = type(ni.activeEntry) == 'table' and safeNum(ni.activeEntry.rank)
              or safeNum(ni.currentRank) or safeNum(ni.ranksPurchased) or 0
            for _, eid in ipairs(entries) do
              local ei = pc(C_Traits.GetEntryInfo, cfg, eid)
              local def = type(ei) == 'table' and safeNum(ei.definitionID)
              local di = def and pc(C_Traits.GetDefinitionInfo, def)
              local sid = type(di) == 'table' and (safeNum(di.overriddenSpellID) or safeNum(di.spellID))
              local name = type(di) == 'table' and safe(di.overrideName)
              if (type(name) ~= 'string' or name == '') and sid then name = ns.nameOf(sid) end
              if type(name) == 'string' and name ~= '' then
                local r = (active == nil or active == eid) and rank or 0
                if (t[name] or 0) < r or t[name] == nil then t[name] = r end
                list[#list + 1] = { name = name, rank = r, max = safeNum(ni.maxRanks), spellId = sid, tree = tree,
                  node = node, x = safeNum(ni.posX), y = safeNum(ni.posY) }
              end
            end
          end
        end
      end
      ns.talentList = list
      if next(t) ~= nil then ns.talentAPI = 'traits' end
    end
  end
  ns.talents, ns.talentsRead = t, next(t) ~= nil
  if ns.db then ns.db.talentDump = t end
end
-- rank talentu; nil = talenty nejdou precist (pak se nic nevypina)
function ns.talent(name)
  if not ns.talentsRead then return nil end
  return ns.talents[name] or 0
end
function ns.talentReport()
  if not ns.talentsRead then ns.say('Talenty se nepodarilo precist (Forever je mozna skryva).') return end
  local l = {}
  for n, r in pairs(ns.talents) do if r > 0 then l[#l + 1] = n .. ' ' .. r end end
  table.sort(l)
  ns.say('Talenty: ' .. (#l > 0 and table.concat(l, ', ') or 'zadne body'))
end

function ns.known(name) local e = ns.S[name] return e and e.known or false end
-- Forever: popis Ice Barrier zminuje bonus k mrazivemu poskozeni -> drzet ho porad
function ns.checkBarrierBuff()
  local id = ns.id('Ice Barrier')
  local d = id and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
  ns.barrierBuff = type(d) == 'string' and d:find('Frost damage') ~= nil
end
function ns.id(name) local e = ns.S[name] return e and e.id end

-- /cm spells: vypis celeho spellbooku. Do chatu jen kratce, plny seznam s popisy do ClaudeMasterDB.spellDump
-- (ulozi se pri /reload nebo odhlaseni, takze si ho muzu precist ze SavedVariables).
function ns.dumpSpells(quiet)
  if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then ns.say('spellbook API neni dostupne') return end
  local tracked = {}
  for _, n in ipairs(ns.SPELLS) do tracked[n] = true end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local dump, newOnes = {}, {}
  local lines = safeNum(pc(C_SpellBook.GetNumSpellBookSkillLines)) or 0
  for l = 1, lines do
    local li = pc(C_SpellBook.GetSpellBookSkillLineInfo, l)
    if type(li) == 'table' then
      local tab = safe(li.name) or ('tab' .. l)
      local off, num = safeNum(li.itemIndexOffset) or 0, safeNum(li.numSpellBookItems) or 0
      local seen = {}
      for i = off + 1, off + num do
        local it = pc(C_SpellBook.GetSpellBookItemInfo, i, bank)
        if type(it) == 'table' then
          local name, id = safe(it.name), safeNum(it.spellID) or safeNum(it.actionID)
          if type(name) == 'string' then
            local passive = safeBool(it.isPassive) == true
            local desc = id and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
            local sub = id and C_Spell and C_Spell.GetSpellSubtext and safe(pc(C_Spell.GetSpellSubtext, id))
            local e = { tab = tab, name = name, id = id, rank = type(sub) == 'string' and sub or nil,
              passive = passive, tracked = tracked[name] or false,
              desc = type(desc) == 'string' and desc:gsub('[\r\n]+', ' ') or nil }
            if seen[name] then dump[seen[name]] = e else dump[#dump + 1] = e seen[name] = #dump end
          end
        end
      end
    end
  end
  ns.db.spellDump = dump
  if quiet then return dump end
  local curTab
  for _, e in ipairs(dump) do
    if e.tab ~= curTab then curTab = e.tab ns.say('|cffffd100' .. curTab .. '|r') end
    local mark = e.tracked and '|cff55ff55+|r' or (e.passive and '|cff888888p|r' or '|cffff8855?|r')
    ns.say(('  %s %s%s |cff888888(%s)|r'):format(mark, e.name, e.rank and (' ' .. e.rank) or '', tostring(e.id)))
    if not e.tracked and not e.passive then newOnes[#newOnes + 1] = e.name end
  end
  ns.say(('Celkem %d spellu. |cff55ff55+|r = addon pouziva, |cffff8855?|r = nezna, p = pasivni.'):format(#dump))
  if #newOnes > 0 then ns.say('Nezname aktivni: ' .. table.concat(newOnes, ', ')) end
  ns.say('Plny seznam s popisy se ulozi po |cffffffff/reload|r - pak mi napis, at si ho prectu.')
end
function ns.nameOf(id)
  if not id or issecret(id) then return nil end
  if idToName[id] then return idToName[id] end
  local n = C_Spell and C_Spell.GetSpellName and safe(pc(C_Spell.GetSpellName, id))
  if not n and GetSpellInfo then n = safe(pc(GetSpellInfo, id)) end
  if type(n) == 'string' then idToName[id] = n return n end
end
function ns.castTime(name)
  local e = ns.S[name]
  local t = e and e.cast
  if t == nil then
    t = ({ Frostbolt = 2.5, Fireball = 3, Polymorph = 1.5, Scorch = 1.5, Cryoblast = 2,
      ['Shadow Bolt'] = 2.5, Immolate = 1.5, ['Searing Pain'] = 1.5, ['Soul Fire'] = 6, Fear = 1.5, Banish = 1.5 })[name] or 0
  end
  return t
end
function ns.icon(name)
  local e = ns.S[name]
  return (e and e.icon) or 134400
end

------------------------------------------------------------------------------------------
-- Klavesove zkratky (z akcnich listu, mimo boj)
------------------------------------------------------------------------------------------
ns.binds = {}
local function slotBinding(slot)
  local cmd
  if slot <= 12 then cmd = 'ACTIONBUTTON' .. slot
  elseif slot >= 25 and slot <= 36 then cmd = 'MULTIACTIONBAR3BUTTON' .. (slot - 24)
  elseif slot >= 37 and slot <= 48 then cmd = 'MULTIACTIONBAR4BUTTON' .. (slot - 36)
  elseif slot >= 49 and slot <= 60 then cmd = 'MULTIACTIONBAR2BUTTON' .. (slot - 48)
  elseif slot >= 61 and slot <= 72 then cmd = 'MULTIACTIONBAR1BUTTON' .. (slot - 60)
  elseif slot >= 145 and slot <= 156 then cmd = 'MULTIACTIONBAR5BUTTON' .. (slot - 144)
  elseif slot >= 157 and slot <= 168 then cmd = 'MULTIACTIONBAR6BUTTON' .. (slot - 156)
  elseif slot >= 169 and slot <= 180 then cmd = 'MULTIACTIONBAR7BUTTON' .. (slot - 168)
  end
  local key = cmd and GetBindingKey and GetBindingKey(cmd)
  if not key then return nil end
  key = key:gsub('SHIFT%-', 'S'):gsub('CTRL%-', 'C'):gsub('ALT%-', 'A'):gsub('NUMPAD', 'N')
    :gsub('MOUSEWHEELUP', 'WU'):gsub('MOUSEWHEELDOWN', 'WD'):gsub('BUTTON', 'M')
  return key
end
function ns.scanBindings()
  if not GetActionInfo then return end
  local b = {}
  for slot = 1, 180 do
    local kind, id = pc(GetActionInfo, slot)
    local name
    if kind == 'spell' then name = ns.nameOf(safeNum(id))
    elseif kind == 'macro' and GetMacroSpell then name = ns.nameOf(safeNum(pc(GetMacroSpell, id)))
    elseif kind == 'item' then name = 'item:' .. tostring(safe(id)) end
    if name and not b[name] then
      local key = slotBinding(slot)
      if key then b[name] = key end
    end
  end
  ns.binds = b
end

------------------------------------------------------------------------------------------
-- Cooldowny, GCD, cast
------------------------------------------------------------------------------------------
local cdUntil = {}   -- name -> GetTime() konce cooldownu (z vlastnich castu)
ns.cdUntil = cdUntil
local GCD = 1.5
ns.st = { gcdUntil = 0, castName = nil, castEnd = 0, channel = false, lastCast = nil, lastCastAt = 0 }
local st = ns.st

local function cdFor(name)
  return ns.db.cdLearned[name] or ns.BASE_CD[name] or 0
end
ns.cdFor = cdFor

-- Zbyvajici cooldown (bez GCD). 0 = pripraveno.
function ns.cdLeft(name)
  local e = ns.S[name]
  if not e or not e.known then return 999 end
  local now = GetTime()
  local d = C_Spell and C_Spell.GetSpellCooldown and pc(C_Spell.GetSpellCooldown, e.id)
  if type(d) == 'table' then
    local s, du = safeNum(d.startTime), safeNum(d.duration)
    if s and du then
      if du > GCD + 0.1 and s > 0 then
        local left = s + du - now
        if left > 0 then
          cdUntil[name] = s + du
          if not ns.inCombat() and du > 2 then ns.db.cdLearned[name] = math.floor(du * 10 + 0.5) / 10 end
          return left
        end
      end
      if (cdUntil[name] or 0) > now + GCD then cdUntil[name] = nil end   -- klient rika "hotovo"
      return 0
    end
    local active, onGCD = safeBool(d.isActive), safeBool(d.isOnGCD)
    if active == false or onGCD == true then return 0 end
    if active == true then
      local t = cdUntil[name]
      if t and t > now then return t - now end
      return 5   -- bezi, ale nevime jak dlouho
    end
  end
  local t = cdUntil[name]
  if t and t > now then return t - now end
  return 0
end

function ns.gcdLeft()
  local d = C_Spell and C_Spell.GetSpellCooldown and pc(C_Spell.GetSpellCooldown, 61304)
  if type(d) == 'table' then
    local s, du = safeNum(d.startTime), safeNum(d.duration)
    if s and du then
      if du >= 1 and du <= 2 then GCD = du end
      return math.max(0, s + du - GetTime())
    end
  end
  return math.max(0, st.gcdUntil - GetTime())
end

-- Co prave castim: jmeno, kolik zbyva, je to channel?
function ns.casting()
  local now = GetTime()
  local name, _, _, _, endMS = pc(UnitCastingInfo, 'player')
  local ch = false
  if not isSet(name) then
    name, _, _, _, endMS = pc(UnitChannelInfo, 'player')
    ch = isSet(name)
  end
  name, endMS = safe(name), safeNum(endMS)
  if type(name) == 'string' and endMS then
    st.castName, st.castEnd, st.channel = name, endMS / 1000, ch
    return name, math.max(0, endMS / 1000 - now), ch
  end
  if st.castName and st.castEnd > now then return st.castName, st.castEnd - now, st.channel end
  return nil, 0, false
end

function ns.queueLead()
  local v = GetCVar and tonumber(GetCVar('SpellQueueWindow'))
  return math.max(0, math.min(v or 400, 400)) / 1000
end

------------------------------------------------------------------------------------------
-- Mana (i odhad, kdyz je skryta)
------------------------------------------------------------------------------------------
local manaSeen = { cur = nil, max = nil, at = 0, spent = 0 }
function ns.mana()
  local cur, max = safeNum(pc(UnitPower, 'player', 0)), safeNum(pc(UnitPowerMax, 'player', 0))
  if cur and max and max > 0 then
    manaSeen.cur, manaSeen.max, manaSeen.at, manaSeen.spent = cur, max, GetTime(), 0
    return cur / max, true, cur, max
  end
  -- Forever manu skryva: odhad z pasma sondy (po 5 %)
  local P = ns.manaProbe
  if P and P.valid and GetTime() - P.at < 1.5 then
    local lo, hi = 0, 100
    for i, line in ipairs(P.lines) do
      if P.below[i] then hi = math.min(hi, line) else lo = math.max(lo, line) end
    end
    return (lo + hi) / 200, false, lo, hi
  end
  return nil, false   -- nevime
end
function ns.manaMax() return safeNum(pc(UnitPowerMax, 'player', 0)) or manaSeen.max or 1000 end
function ns.cost(name)
  local e = ns.S[name]
  if not e then return 0 end
  if e.cost then return e.cost end
  if e.costPct then return e.costPct / 100 * ns.manaMax() end
  return 0
end
local function spendMana(name) manaSeen.spent = manaSeen.spent + ns.cost(name) end

------------------------------------------------------------------------------------------
-- Auray hrace (mimo boj citelne) + Cooldown Manager + proc glow
------------------------------------------------------------------------------------------
-- dochazi mi dech? (bezi ukazatel dechu; s Unending Breath / vodnim dychanim nebezi)
function ns.breathRunning()
  if not GetMirrorTimerInfo then return nil end
  for i = 1, 3 do
    local timer, _, _, scale, paused = pc(GetMirrorTimerInfo, i)
    if safe(timer) == 'BREATH' then
      local p, sc = safe(paused), safeNum(scale)
      return not (p == 1 or p == true) and (sc == nil or sc < 0)
    end
  end
  return false
end
-- buff na hraci podle jmena, prochazenim vsech buffu (spolehlivejsi nez hledani jmenem)
function ns.playerHasBuff(name)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local a = pc(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HELPFUL')
    if type(a) ~= 'table' then return ns.inCombat() and nil or false end
    if safe(a.name) == name then return true end
  end
  return false
end
-- jsem pod vodou? (plavu pod hladinou, nebo bezi ukazatel dechu)
function ns.underwater()
  if IsSubmerged and safeBool(pc(IsSubmerged)) == true then return true end
  if GetMirrorTimerInfo then
    for i = 1, 3 do
      local timer, _, _, _, paused = pc(GetMirrorTimerInfo, i)
      if safe(timer) == 'BREATH' and safe(paused) ~= 1 and safe(paused) ~= true then return true end
    end
  end
  return false
end
function ns.playerAura(name)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, 'player', name, 'HELPFUL')
  if not ok then return nil end
  if a == nil then return ns.inCombat() and nil or false end   -- v boji "nic" neznamena "neni"
  if issecret(a) then return true end
  return a
end
-- Pozitivni detekce debuffu na cili (v boji muze lhat "neni", takze jen true/nil)
function ns.targetDebuff(name, mine)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
  local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, 'target', name, mine and 'HARMFUL|PLAYER' or 'HARMFUL')
  if not ok then return nil end
  if a ~= nil then return true end
  if not ns.inCombat() then return false end
  return nil
end

-- Herni Cooldown Manager (zapni ho v Options > Gameplay > Combat a dej si na nej Fingers of
-- Frost, Ice Barrier, Frost Nova, Frostbite): ukazuje auray i v boji. Cteme jen, zda ikona sviti.
local CDM = { state = {}, proven = {}, names = {}, next = 0, settle = 0 }
local VIEWERS = { 'EssentialCooldownViewer', 'UtilityCooldownViewer', 'BuffIconCooldownViewer', 'BuffBarCooldownViewer' }
local function cdmNames(cdID)
  local list = CDM.names[cdID]
  if list ~= nil then return list end
  list = false
  local info = C_CooldownViewer and pc(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
  if type(info) == 'table' then
    list = { self = safeBool(info.selfAura) == true }
    local function add(id) local n = ns.nameOf(safeNum(id)) if n then list[n] = true end end
    add(info.spellID) add(info.overrideSpellID) add(info.overrideTooltipSpellID)
    if type(info.linkedSpellIDs) == 'table' and not issecret(info.linkedSpellIDs) then
      for _, id in ipairs(info.linkedSpellIDs) do add(id) end
    end
  end
  if list or not ns.inCombat() then CDM.names[cdID] = list end
  return list
end
function CDM.sweep()
  if not C_CooldownViewer then return end
  local now = GetTime()
  if now < CDM.next then return end
  CDM.next = now + 0.2
  local cur = {}
  for _, vn in ipairs(VIEWERS) do
    local v = _G[vn]
    if v and v.GetChildren and safeBool(pc(v.IsVisible, v)) then
      for _, child in ipairs({ v:GetChildren() }) do
        local cd = rawget(child, 'cooldownID')
        local list = type(cd) == 'number' and not issecret(cd) and cdmNames(cd)
        if list then
          local up = isSet(rawget(child, 'auraInstanceID'))
          local unit = rawget(child, 'auraDataUnit')
          if type(unit) ~= 'string' or issecret(unit) then unit = list.self and 'player' or 'target' end
          for n in pairs(list) do
            if n ~= 'self' then
              local k = unit .. ':' .. n
              cur[k] = cur[k] or up
              if up then CDM.proven[k] = true end
            end
          end
        end
      end
    end
  end
  CDM.state = cur
end
function ns.cdm(unit, name)
  local k = unit .. ':' .. name
  local v = CDM.state[k]
  if v == nil then return nil end
  if unit == 'target' and GetTime() < CDM.settle then return nil end
  if v == false and not CDM.proven[k] then return nil end
  return v
end
ns.CDM = CDM

-- Proc glow na tlacitkach (Fingers of Frost rozsviti Ice Lance apod.)
ns.glow = {}
function ns.glowing(name)
  if ns.glow[name] then return true end
  local id = ns.id(name)
  if not id then return false end
  local f = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
  return safeBool(pc(f, id)) == true
end

------------------------------------------------------------------------------------------
-- Zdravi v pasmech (trik se StatusBarem: hra vykresli skrytou hodnotu, my vidime jen,
-- jestli se zmenila velikost vyplne -> nad/pod carou)
------------------------------------------------------------------------------------------
local probeRoot = CreateFrame('Frame', nil, UIParent)
probeRoot:SetSize(64, 64) probeRoot:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, 0)
probeRoot:SetAlpha(0) probeRoot:EnableMouse(false)
local probeRow = 0
local probes = {}

-- Krokova krivka: 1 pod x, 2 od x vys
local curveCache = {}
local function stepCurve(x)
  if curveCache[x] then return curveCache[x] end
  local c = C_CurveUtil and C_CurveUtil.CreateCurve and pc(C_CurveUtil.CreateCurve)
  if not c then return nil end
  if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(c.SetType, c, Enum.LuaCurveType.Step) end
  local eps = math.max(x * 0.00001, 0.000001)
  pcall(c.AddPoint, c, 0, 1) pcall(c.AddPoint, c, x - eps, 1) pcall(c.AddPoint, c, x, 2) pcall(c.AddPoint, c, 100000, 2)
  curveCache[x] = c
  return c
end

-- Obecna sonda s n carami. Kazde cteni = 3 framy:
--   begin(P) -> false = ted nemerit; prep(P,i,bar) nastavi znamy stav;
--   apply(P,i,bar) preda baru skrytou hodnotu; read(P) z P.fired[i] (zmenila se vypln) udela vysledek.
local function newProbe(n, def)
  local P = { bars = {}, fired = {}, below = {}, phase = 0, ok = nil, at = 0, valid = false }
  for k, v in pairs(def) do P[k] = v end
  for i = 1, n do
    local b = CreateFrame('StatusBar', nil, probeRoot)
    b:SetSize(64, 1) b:SetPoint('BOTTOMLEFT', probeRoot, 'BOTTOMLEFT', 0, probeRow) probeRow = probeRow + 1
    b:SetStatusBarTexture('Interface\Buttons\WHITE8X8') b:SetMinMaxValues(0, 2) b:SetValue(1)
    local clip = CreateFrame('Frame', nil, b)
    clip:SetPoint('TOPLEFT', b, 'TOPLEFT') clip:SetPoint('BOTTOMRIGHT', b:GetStatusBarTexture(), 'BOTTOMRIGHT')
    clip:SetScript('OnSizeChanged', function() P.fired[i] = true end)
    P.bars[i] = b
  end
  function P.reset() P.valid = false P.phase = 0 end
  function P.step()
    if P.ok == nil then   -- samotest: 1 -> 2 musi zmenit velikost
      local b = P.bars[1]
      if P.phase == 0 then b:SetMinMaxValues(0, 2) b:SetValue(1) P.phase = -1 return end
      if P.phase == -1 then wipe(P.fired) b:SetValue(2) P.phase = -2 return end
      P.ok = P.fired[1] == true P.phase = 0
      return
    end
    if not P.ok then return end
    if P.phase == 0 then
      local okB, go = pcall(P.begin, P)
      if not okB or not go then P.valid = false return end
      P.tok = ns.T and ns.T.token
      for i, b in ipairs(P.bars) do pcall(P.prep, P, i, b) end
      P.phase = 1
    elseif P.phase == 1 then
      wipe(P.fired)
      for i, b in ipairs(P.bars) do pcall(P.apply, P, i, b) end
      P.phase = 2
    else
      P.phase = 0
      -- mezitim se zmenil cil: cteni patri staremu cili, zahodit
      if P.tok ~= (ns.T and ns.T.token) then return end
      local okR, good = pcall(P.read, P)
      if okR and good then
        P.valid = true P.at = GetTime()
        if P.onRead then P.onRead(P) end
      end
    end
  end
  probes[#probes + 1] = P
  return P
end
function ns.stepProbes() for _, P in ipairs(probes) do P.step() end end
ns.probes = probes

local function healthReadable(unit)
  local hp, mx = safeNum(pc(UnitHealth, unit)), safeNum(pc(UnitHealthMax, unit))
  return hp ~= nil and mx ~= nil and mx > 0
end
-- pasma "pod carou": musi byt monotonni (pod 20 % => i pod 35 %)
local function readBands(P, firedMeansBelow)
  local res = {}
  for i = 1, #P.lines do
    local f = P.fired[i] == true
    res[i] = (firedMeansBelow and f) or (not firedMeansBelow and not f)
    if i > 1 and res[i - 1] and not res[i] then return false end
  end
  P.below = res
  return true
end

-- Meritko UnitHealthPercent (0-1 nebo 0-100): krivka se zlomem na 1.5
ns.scaleProbe = newProbe(1, {
  begin = function() return ns.db and ns.db.hpScale == nil and UnitHealthPercent ~= nil and stepCurve(1.5) ~= nil
    and safeBool(pc(UnitIsDeadOrGhost, 'player')) ~= true end,
  prep = function(P, i, b) b:SetMinMaxValues(0, 2) b:SetValue(1) end,
  apply = function(P, i, b) b:SetValue(UnitHealthPercent('player', true, stepCurve(1.5))) end,
  -- meritko az po 3 shodnych merenich za sebou (jedno chybne mereni = vsechna HP "pod 20 %")
  read = function(P)
    local v = P.fired[1] and 100 or 1
    if P.last == v then P.same = (P.same or 1) + 1 else P.last, P.same = v, 1 end
    if P.same >= 3 then ns.db.hpScale = v P.last, P.same = nil, nil end
    return true
  end,
})

local function healthProbe(unit, lines)
  return newProbe(#lines, {
    unit = unit, lines = lines,
    begin = function(P)
      return UnitExists(unit) and ns.db and ns.db.hpScale ~= nil and UnitHealthPercent ~= nil
        and not healthReadable(unit) and stepCurve(50) ~= nil
    end,
    prep = function(P, i, b) b:SetMinMaxValues(0, 2) b:SetValue(1) end,
    apply = function(P, i, b)
      b:SetValue(UnitHealthPercent(unit, true, stepCurve(P.lines[i] / 100 * ns.db.hpScale)))
    end,
    read = function(P)
      if not readBands(P, false) then return false end
      -- kontrola meritka: hrac mimo boj "pod vsemi carami" (pod 20 %) je skoro jiste spatne meritko
      if unit == 'player' and P.below[#P.below] and P.below[1] and not ns.inCombat()
        and safeBool(pc(UnitIsDeadOrGhost, 'player')) ~= true then
        P.bad = (P.bad or 0) + 1
        if P.bad >= 2 then ns.db.hpScale = nil P.bad = 0 end   -- zmerit meritko znovu
        return false
      end
      P.bad = 0
      -- horni mez z tohoto a predchoziho cteni (jedno chybne cteni nema spustit "HP dole")
      local hi = 100
      for i, line in ipairs(P.lines) do if P.below[i] then hi = math.min(hi, line) end end
      P.hiPrev, P.hiCur = P.hiCur, hi
      return true
    end,
  })
end
ns.targetProbe = healthProbe('target', { 5, 10, 20, 30, 35, 40, 50, 60, 70, 80, 90 })
ns.playerProbe = healthProbe('player', { 20, 25, 30, 35, 40, 50, 60, 65, 70, 75, 85, 95 })
-- parta a jejich peti (jen kdyz existuji)
ns.unitProbes = { target = ns.targetProbe, player = ns.playerProbe }
ns.unitProbes.pet = healthProbe('pet', { 20, 30, 50, 75 })
for i = 1, 4 do
  ns.unitProbes['party' .. i] = healthProbe('party' .. i, { 30, 50 })
  ns.unitProbes['partypet' .. i] = healthProbe('partypet' .. i, { 30, 50 })
end

-- Mana po 5 %. Kdyz je max citelne: bar 0..(x % z max), nejdriv plny, pak skutecna mana
-- -> zmena = pod carou. Jinak UnitPowerPercent pres krivku.
local MANA_LINES = {}
for x = 5, 95, 5 do MANA_LINES[#MANA_LINES + 1] = x end
ns.manaProbe = newProbe(#MANA_LINES, {
  lines = MANA_LINES,
  begin = function(P)
    if safeNum(pc(UnitPower, 'player', 0)) then return false end   -- citelne primo
    local mx = safeNum(pc(UnitPowerMax, 'player', 0))
    if mx and mx > 0 then P.mode, P.max = 'abs', mx return true end
    if UnitPowerPercent and ns.db and ns.db.hpScale and stepCurve(50) then P.mode = 'curve' return true end
    return false
  end,
  prep = function(P, i, b)
    if P.mode == 'abs' then
      local v = P.lines[i] / 100 * P.max
      b:SetMinMaxValues(0, v) b:SetValue(v)
    else b:SetMinMaxValues(0, 2) b:SetValue(1) end
  end,
  apply = function(P, i, b)
    if P.mode == 'abs' then b:SetValue(UnitPower('player', 0))
    else b:SetValue(UnitPowerPercent('player', 0, false, stepCurve(P.lines[i] / 100 * ns.db.hpScale))) end
  end,
  read = function(P) return readBands(P, P.mode == 'abs') end,
})

-- Presne % kdyz jde, jinak odhad z pasma. Vraci pct, exact
function ns.healthPct(unit)
  local hp, mx = safeNum(pc(UnitHealth, unit)), safeNum(pc(UnitHealthMax, unit))
  if hp and mx and mx > 0 then return hp / mx * 100, true end
  local v = safeNum(pc(UnitHealthPercent, unit))
  if v then return (v <= 1 and v * 100 or v), true end
  -- spoluhrac s addonem: HP posila sam (presnejsi nez sonda, a jde i v boji)
  if ns.Duo and ns.Duo.hpOf then
    local dv = ns.Duo.hpOf(unit)
    if dv then return dv, false, math.max(0, dv - 3), math.min(100, dv + 3) end
  end
  local P = ns.unitProbes and ns.unitProbes[unit]
  if P and P.valid and GetTime() - P.at < 1.5 then
    local lo, hi = 0, 100
    for i, line in ipairs(P.lines) do
      if P.below[i] then hi = math.min(hi, line) else lo = math.max(lo, line) end
    end
    -- vlastni HP: "pod carou" jen kdyz to potvrdi dve cteni za sebou
    if unit == 'player' and P.hiPrev and P.hiPrev > hi then
      hi = P.hiPrev
      if lo > hi then lo = hi end
    end
    return (lo + hi) / 2, false, lo, hi
  end
  return nil
end
-- true/false/nil: je unit pod X %?
function ns.hpBelow(unit, x)
  local pct, exact, lo, hi = ns.healthPct(unit)
  if not pct then return nil end
  if exact then return pct < x end
  if hi <= x then return true end
  if lo >= x then return false end
  return nil
end
-- Meritko pro krivky se musi merit krivkou (scaleProbe), ne podle "holeho" UnitHealthPercent:
-- ten muze vracet 0-100, zatimco krivka dostava 0-1 (pak sonda hlasila ~10 % HP i pri plnem zdravi).
-- Proto ho po kazdem boji / prihlaseni zmerime znovu (3 snimky).
local function learnHpScale()
  if safeBool(pc(UnitIsDeadOrGhost, 'player')) == true then return end
  if ns.healthPct and not ns.inCombat() then ns.db.hpScale = nil end
end

------------------------------------------------------------------------------------------
-- Cil: TTD (time to die) z presnych hodnot nebo z prechodu pres cary
------------------------------------------------------------------------------------------
ns.T = { token = 0, samples = {}, frozenUntil = 0, frozenHits = 0, engagedAt = nil }
local T = ns.T
local function addSample(pct)
  local s = T.samples
  local now = GetTime()
  if #s > 0 and math.abs(s[#s].pct - pct) < 0.5 then return end
  s[#s + 1] = { t = now, pct = pct }
  if #s > 12 then table.remove(s, 1) end
end
ns.targetProbe.onRead = function(P)
  -- zaznamenat prave prekrocenou caru
  local prev = P.prevBelow or {}
  for i, line in ipairs(P.lines) do
    if P.below[i] and prev[i] == false then addSample(line) end
  end
  P.prevBelow = {} for i, v in ipairs(P.below) do P.prevBelow[i] = v end
end
function ns.ttd()
  local s = T.samples
  if #s < 2 then return nil end
  local a, b = s[1], s[#s]
  local dt, dp = b.t - a.t, a.pct - b.pct
  if dt < 1.5 or dp <= 0 then return nil end
  local rate = dp / dt
  local pct = ns.healthPct('target') or b.pct
  return math.max(0, pct / rate)
end
function ns.targetChanged()
  T.token = T.token + 1
  if ns.Immune then ns.Immune.targetChanged() end
  wipe(T.samples)
  T.frozenUntil, T.frozenHits = 0, 0
  T.engagedAt = nil
  ns.targetProbe.reset() ns.targetProbe.prevBelow = nil
  CDM.settle = GetTime() + 0.35 CDM.next = 0
end

------------------------------------------------------------------------------------------
-- Moby kolem (z nameplatu - zapni si nameploty nepratel, klavesa V)
------------------------------------------------------------------------------------------
-- Vzdalenost. CheckInteractDistance je v boji zakazany (hra by addon zablokovala),
-- takze v boji merime dosahem Auto Attacku (melee) a Frostboltu (~30 yd).
local ATTACK_ID = 6603
function ns.near(unit)
  if not InCombatLockdown() then return safeBool(pc(CheckInteractDistance, unit, 3)) end
  if C_Spell and C_Spell.IsSpellInRange and safeBool(pc(UnitCanAttack, 'player', unit)) then
    return safeBool(pc(C_Spell.IsSpellInRange, ATTACK_ID, unit))
  end
  return nil
end
function ns.close(unit)
  if not InCombatLockdown() then return safeBool(pc(CheckInteractDistance, unit, 4)) end
  local id = ns.id('Frostbolt') or ns.id('Fireball')
  if id and C_Spell and C_Spell.IsSpellInRange and safeBool(pc(UnitCanAttack, 'player', unit)) then
    return safeBool(pc(C_Spell.IsSpellInRange, id, unit))
  end
  return nil
end

local PARTY_UNITS = { 'party1', 'party2', 'party3', 'party4', 'partypet1', 'partypet2', 'partypet3', 'partypet4' }
-- Kontrola davu, kterou AoE rozbije (ovce, sap, shackle, trap...)
local CC_AURAS = { 'Polymorph', 'Sap', 'Shackle Undead', 'Hibernate', 'Freezing Trap Effect', 'Banish', 'Seduction',
  'Blind', 'Gouge', 'Repentance', 'Scare Beast', 'Wyvern Sting' }
ns.ccGUID = {}    -- GUID moba, ktereho jsem ovcil -> do kdy
ns.ccAt = ns.ccAt or {}   -- GUID -> kdy jsem / parťák CC dal
local function isCC(u)
  local g = safe(pc(UnitGUID, u))
  if type(g) == 'string' and ns.ccGUID[g] then
    -- ovce se probrala (nekdo ji trefil): mob zase na nekoho miri
    local since = GetTime() - (ns.ccAt[g] or 0)
    if since > 1.5 and safeBool(pc(UnitExists, u .. 'target')) == true then
      ns.ccGUID[g], ns.ccAt[g] = nil, nil
      return false, g
    end
    if ns.ccGUID[g] > GetTime() then return true, g end
    ns.ccGUID[g] = nil
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    for _, n in ipairs(CC_AURAS) do
      local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, u, n, 'HARMFUL')
      if ok and ns.isSet(a) then return true, g end
    end
  end
  return false, g
end
ns.isCC = isCC
-- delka CC z popisu kouzla ("... for 50 sec"), jinak odhad
local ccDurCache = {}
function ns.ccDur(name)
  local id = ns.id and ns.id(name)
  if id and ccDurCache[id] then return ccDurCache[id] end
  local d = id and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
  local n = type(d) == 'string' and tonumber(d:match('(%d+) sec')) or nil
  if n and n >= 5 and n <= 120 then
    ccDurCache[id] = n
    return n
  end
  return name == 'Banish' and 30 or 50
end
-- kolik zbyva moji ovci (nil = zadna / uz neplati)
function ns.sheepLeft()
  local s = ns.sheep
  if not s then return nil end
  local left = s.at + s.dur - GetTime()
  if left <= 0 then ns.sheep = nil return nil end
  if s.guid and not ns.ccGUID[s.guid] then ns.sheep = nil return nil end   -- probrala se
  return left, s
end
function ns.scanEnemies()
  -- cluster = nejvic mobu, ktere bijou stejneho cloveka (ty, tank...) = stoji na jednom miste
  local r = { combat = 0, near = 0, onMe = 0, idle = 0, total = 0, on = {}, cc = 0, ccNear = false, cluster = 0,
    victimKnown = false, thrMax = 0, thrKnown = 0 }
  local grouped = IsInGroup and IsInGroup()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return r end
  local plates = pc(C_NamePlate.GetNamePlates)
  if type(plates) ~= 'table' then return r end
  local meIn = ns.inCombat()
  local fbID = ns.id('Frostbolt') or ns.id('Fireball')
  for _, pl in ipairs(plates) do
    local u = pl.namePlateUnitToken or (pl.UnitFrame and pl.UnitFrame.unit)
    if u and not issecret(u) then
      local can = safeBool(pc(UnitCanAttack, 'player', u))
      local dead = safeBool(pc(UnitIsDeadOrGhost, u))
      local isPlayer = safeBool(pc(UnitIsPlayer, u))
      if can and not dead then
        r.total = r.total + 1
        local inC = safeBool(pc(UnitAffectingCombat, u))
        local onMe = safeBool(pc(UnitIsUnit, u .. 'target', 'player'))
        local near = ns.near(u)
        local inRange = fbID and C_Spell and safeBool(pc(C_Spell.IsSpellInRange, fbID, u))
        if inC == nil then inC = meIn and inRange ~= false end
        if safeBool(pc(UnitIsUnit, u, 'target')) then r.targetNear = near end
        local cc, guid = false, nil
        if inC then cc, guid = isCC(u) end
        -- mob, ktery na nekoho miri, ovce neni (ovce se uz probrala)
        if cc and onMe and guid then ns.ccGUID[guid] = nil cc = false end
        if onMe ~= nil then r.victimKnown = true end
        -- znacky: lebka = bit prvni, mesic = mageova ovce
        local mk = safeNum(pc(GetRaidTargetIndex, u))
        if inC and not cc and mk == 8 then r.skull = true end
        if inC and not cc and mk == 5 then r.moonLoose = true end
        if inC and cc then
          r.cc = r.cc + 1
          if near then r.ccNear = true end
        elseif inC then
          r.combat = r.combat + 1
          if near then r.near = r.near + 1 end
          -- muj threat na tomto mobovi (% k pretazeni aggra), kdyz ho Forever ukaze
          if UnitDetailedThreatSituation then
            local _, _, pct = pc(UnitDetailedThreatSituation, 'player', u)
            pct = safeNum(pct)
            if pct then r.thrKnown = r.thrKnown + 1 r.thrMax = math.max(r.thrMax, pct) end
          end
          -- Forever casto skryva, na koho mob miri: mob v boji u tebe (solo) bereme jako "na tobe"
          if onMe or (onMe == nil and near and not IsInGroup()) then r.onMe = r.onMe + 1 end
          -- na koho z party mob miri
          if grouped and not onMe then
            for _, pu in ipairs(PARTY_UNITS) do
              if UnitExists(pu) and safeBool(pc(UnitIsUnit, u .. 'target', pu)) then
                r.on[pu] = (r.on[pu] or 0) + 1
                break
              end
            end
          end
        elseif not isPlayer and safeBool(pc(UnitIsUnit, u, 'target')) ~= true then
          local close = ns.close(u)
          if close ~= false then r.idle = r.idle + 1 end
        end
      end
    end
  end
  r.cluster = r.onMe
  for _, n in pairs(r.on) do if n > r.cluster then r.cluster = n end end
  -- kdyz Forever neprozradi, na koho moby miri, nezbyva nez pocitat vsechny (bez ovci)
  if not r.victimKnown then r.cluster = r.combat end
  return r
end

------------------------------------------------------------------------------------------
-- Predmety
------------------------------------------------------------------------------------------
ns.ITEMS = {
  gem = { 8008, 8007, 5513, 5514 },                       -- Mana Ruby/Citrine/Jade/Agate
  water = { 8079, 8078, 8077, 3772, 2136, 2288, 5350, 1645, 1708, 1205, 1179, 159 },
  hpot = { 13446, 3928, 1710, 929, 858, 118 },
  mpot = { 13444, 13443, 6149, 3827, 3385, 2455 },
}
ns.itemUsedAt = {}
function ns.bestItem(list)
  for _, id in ipairs(list) do
    local n = safeNum(pc(C_Item and C_Item.GetItemCount or GetItemCount, id)) or 0
    if n > 0 then return id, n end
  end
end
function ns.itemCount(list)
  local total = 0
  for _, id in ipairs(list) do total = total + (safeNum(pc(C_Item and C_Item.GetItemCount or GetItemCount, id)) or 0) end
  return total
end
function ns.itemReady(id, sharedKey, cd)
  local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local s, d = pc(f, id)
  s, d = safeNum(s), safeNum(d)
  if s and d then return not (s > 0 and d > 1.6 and s + d > GetTime()) end
  local used = ns.itemUsedAt[sharedKey]
  return not (used and GetTime() - used < (cd or 120))
end
function ns.itemIcon(id)
  return (C_Item and C_Item.GetItemIconByID and safe(pc(C_Item.GetItemIconByID, id))) or (GetItemIcon and safe(pc(GetItemIcon, id))) or 134400
end

------------------------------------------------------------------------------------------
-- Stav sledovany z vlastnich castu
------------------------------------------------------------------------------------------
ns.barrierUntil = 0
ns.armorUntil, ns.aiUntil = 0, 0
ns.fof = { n = 0, at = 0 }
local DAMAGE = { Frostbolt = true, ['Ice Lance'] = true, ['Fire Blast'] = true, Fireball = true, Scorch = true,
  ['Cone of Cold'] = true, Cryoblast = true, ['Arcane Missiles'] = true, Shoot = false }

local function onCast(spellID)
  local name = ns.nameOf(spellID)
  if not name then return end
  local now = GetTime()
  st.lastCast, st.lastCastAt = name, now
  if name == 'Polymorph' or name == 'Banish' then
    local g = safe(pc(UnitGUID, 'target'))
    local dur = ns.ccDur(name)
    if type(g) == 'string' then ns.ccGUID[g] = now + dur ns.ccAt[g] = now end
    -- moje posledni ovce (kvuli prodlouzeni): kdy, jak dlouho, na kom
    ns.sheep = { spell = name, at = now, dur = dur, guid = type(g) == 'string' and g or nil }
    -- poslat parťákovi identitu moba + delku, at ovci vidi na stejne jmenovce
    if ns.Plates and ns.Plates.sendSheep then pcall(ns.Plates.sendSheep, 'target', dur, name) end
  end
  ns.castAt[name] = now
  if ns.Immune then ns.Immune.onCast(name) end
  if ns.Mem then ns.Mem.onCast(name) end
  spendMana(name)
  if ns.S[name] and ns.S[name].known then
    local cd = cdFor(name)
    if cd > GCD then cdUntil[name] = now + cd end
    if not ns.inCombat() and C_Timer then
      C_Timer.After(0.3, function() ns.cdLeft(name) end)   -- nauci se skutecny cooldown
    end
  end
  if name == 'Cold Snap' then for _, n in ipairs(ns.FROST_CDS) do cdUntil[n] = nil end end
  if name == 'Frost Nova' then
    local rootImmune = ns.Immune and ns.Immune.bad(ns.Immune.info(), 'Frost Nova')
    if T.near ~= false and not rootImmune then T.frozenUntil, T.frozenHits = now + 8, 0 end
  elseif name == 'Ice Barrier' then ns.barrierUntil = now + 60
  elseif name == 'Ice Armor' or name == 'Frost Armor' or name == 'Mage Armor' or name == 'Molten Armor' then
    ns.armorUntil, ns.armorName, ns.armorSitu = now + 1800, name, ns.armorSituNow
  elseif name == 'Arcane Intellect' then ns.aiUntil = now + 1800
  elseif name == 'Restore Mana' then ns.itemUsedAt.gem = now
  elseif name == 'Healing Potion' then ns.itemUsedAt.potion = now
  elseif name:find('Familiar') then ns.itemUsedAt.familiar = now
  end
  if DAMAGE[name] then
    if T.frozenUntil > now then
      T.frozenHits = T.frozenHits + 1
      -- Frost Nova se rozbiji poskozenim; po par zasazich uz se na nej nespoleham
      if T.frozenHits >= 3 then T.frozenUntil = now end
    end
    if ns.fof.n > 0 and (name == 'Frostbolt' or name == 'Ice Lance' or name == 'Cone of Cold' or name == 'Cryoblast') then
      ns.fof.n = ns.fof.n - 1
    end
  end
end

-- Fingers of Frost: pocet stacku (aura mimo boj, jinak glow/CDM + vlastni pocitani)
function ns.fofStacks()
  local a = ns.playerAura('Fingers of Frost')
  if type(a) == 'table' then
    local n = safeNum(a.applications)
    n = (n and n > 0) and n or 1
    ns.fof.n = n
    return n, true
  elseif a == false then ns.fof.n = 0 return 0, true end
  local c = ns.cdm('player', 'Fingers of Frost')
  local g = ns.glowing('Ice Lance')
  if c == false then ns.fof.n = 0 return 0, false end
  if (c or g) and ns.fof.n <= 0 then ns.fof.n = 1 end
  if c == nil and not g and GetTime() - ns.fof.at > 15 then ns.fof.n = 0 end
  return ns.fof.n, false
end

-- Je cil zmrazeny? Vraci zbyvajici sekundy (0 = ne)
function ns.frozenLeft()
  local now = GetTime()
  local left = math.max(0, T.frozenUntil - now)
  if ns.targetDebuff('Frost Nova') or ns.targetDebuff('Frostbite') or ns.targetDebuff('Freeze')
    or ns.cdm('target', 'Frost Nova') or ns.cdm('target', 'Frostbite') then
    left = math.max(left, 1.5)
  elseif ns.cdm('target', 'Frost Nova') == false and ns.cdm('target', 'Frostbite') ~= true then
    left = 0
  end
  return left
end

------------------------------------------------------------------------------------------
-- Eventy
------------------------------------------------------------------------------------------
local ev = CreateFrame('Frame')
ns.ev = ev
local EVENTS = { 'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'SPELLS_CHANGED', 'LEARNED_SPELL_IN_TAB',
  'PLAYER_LEVEL_UP', 'PLAYER_TARGET_CHANGED', 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_FAILED',
  'UNIT_SPELLCAST_INTERRUPTED', 'UNIT_SPELLCAST_SUCCEEDED', 'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP',
  'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 'SPELL_ACTIVATION_OVERLAY_GLOW_HIDE', 'PLAYER_REGEN_ENABLED',
  'PLAYER_REGEN_DISABLED', 'ACTIONBAR_SLOT_CHANGED', 'UPDATE_BINDINGS', 'UNIT_INVENTORY_CHANGED', 'PLAYER_DEAD',
  'BAG_UPDATE_DELAYED', 'GET_ITEM_INFO_RECEIVED', 'GROUP_ROSTER_UPDATE', 'ADDON_ACTION_BLOCKED', 'ADDON_ACTION_FORBIDDEN',
  'TRAIT_CONFIG_UPDATED', 'PLAYER_TALENT_UPDATE', 'CHARACTER_POINTS_CHANGED' }
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end

local pendingScan = false
local function scanSoon()
  if ns.inCombat() then pendingScan = true return end
  if C_Timer then C_Timer.After(0.5, function() if not ns.inCombat() then ns.scanSpells() end end) else ns.scanSpells() end
end

ev:SetScript('OnEvent', function(_, event, a1, a2, a3)
  if event == 'ADDON_ACTION_BLOCKED' or event == 'ADDON_ACTION_FORBIDDEN' then
    -- zapsat KAZDOU blokaci (i jinych addonu a i behem nacitani), at vime, kdo za tim je
    local line = ('%s %s %s: %s%s'):format(date('%H:%M:%S'), event == 'ADDON_ACTION_FORBIDDEN' and 'ZAKAZANO' or 'blok',
      tostring(a1), tostring(a2), (InCombatLockdown() and ' (v boji)' or '')) .. ' @' .. tostring(ns.phase)
    ns.blockedLog = ns.blockedLog or {}
    table.insert(ns.blockedLog, 1, line)
    if ns.db then
      ns.db.blocked = ns.db.blocked or {}
      table.insert(ns.db.blocked, 1, line)
      while #ns.db.blocked > 15 do table.remove(ns.db.blocked) end
      ns.db.blockedStack = debugstack and debugstack(2, 20, 0) or nil
    end
    -- do chatu jen vlastni blokace; cizi addony (GW2_UI apod.) jen tise do logu (/cm status)
    if tostring(a1) ~= ADDON then return end
    local function show() print('|cff66ccffClaudeMaster|r |cffff5555blokace:|r ' .. line) end
    if C_Timer then C_Timer.After(6, show) else show() end
    return
  end
  if event == 'ADDON_LOADED' then
    if a1 == ADDON then ns.initDB() end
    return
  end
  if not ns.enabled or not ns.db then return end
  ns.phase = 'event ' .. event
  if event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then
    ns.scanSpells() learnHpScale()
    if ns.UI then ns.UI.build() end
  elseif event == 'TRAIT_CONFIG_UPDATED' or event == 'PLAYER_TALENT_UPDATE' or event == 'CHARACTER_POINTS_CHANGED' then
    scanSoon()   -- zmena talentu: hned je precti znovu
  elseif event == 'SPELLS_CHANGED' or event == 'LEARNED_SPELL_IN_TAB' or event == 'PLAYER_LEVEL_UP' or event == 'UNIT_INVENTORY_CHANGED' then
    if event ~= 'UNIT_INVENTORY_CHANGED' or a1 == 'player' then scanSoon() end
  elseif event == 'ACTIONBAR_SLOT_CHANGED' or event == 'UPDATE_BINDINGS' then
    if not ns.inCombat() then ns.scanBindings() else pendingScan = true end
  elseif event == 'PLAYER_TARGET_CHANGED' then
    ns.targetChanged()
  elseif event == 'PLAYER_REGEN_ENABLED' then
    if pendingScan then pendingScan = false scanSoon() end
    learnHpScale()
    T.engagedAt = nil
    if ns.Mem then ns.Mem.endFight() end
  elseif event == 'PLAYER_REGEN_DISABLED' then
    T.engagedAt = GetTime()
    if ns.Mem then ns.Mem.startFight() end
    if ns.UI and ns.UI.hideSummary then ns.UI.hideSummary() end
    if ns.UI and ns.UI.combatStart then ns.UI.combatStart() end
  elseif event == 'BAG_UPDATE_DELAYED' or event == 'GET_ITEM_INFO_RECEIVED' then
    if ns.Bags then ns.Bags.markDirty() end
  elseif event == 'PLAYER_DEAD' then
    ns.barrierUntil, ns.armorUntil, ns.aiUntil = 0, 0, 0
  elseif event == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW' or event == 'SPELL_ACTIVATION_OVERLAY_GLOW_HIDE' then
    local n = ns.nameOf(safeNum(a1))
    if n then
      local on = event == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW'
      ns.glow[n] = on or nil
      if n == 'Ice Lance' and on then ns.fof.at = GetTime() if ns.fof.n < 1 then ns.fof.n = 1 end end
    end
  elseif a1 == 'player' then
    local spellID = safeNum(a3)
    if event == 'UNIT_SPELLCAST_START' or event == 'UNIT_SPELLCAST_CHANNEL_START' then
      local n = ns.nameOf(spellID)
      if n and not ns.OFF_GCD[n] then st.gcdUntil = GetTime() + GCD end
      if n then
        st.castName = n
        st.channel = event == 'UNIT_SPELLCAST_CHANNEL_START'
        st.castEnd = GetTime() + (st.channel and (ns.CHANNEL[n] or 3) or ns.castTime(n))
        T.near = ns.near('target')
        if ns.Mem then ns.Mem.playerCast(n) end
      end
    elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then
      local n = ns.nameOf(spellID)
      local wasCasting = st.castName == n and st.castEnd > GetTime() - 0.3 and not st.channel
      if n and not wasCasting and not ns.OFF_GCD[n] and (ns.S[n] and ns.S[n].known) then st.gcdUntil = GetTime() + GCD end
      if n == 'Frost Nova' then T.near = ns.near('target') end
      if n and not wasCasting and not (st.channel and st.castName == n) and ns.Mem then ns.Mem.playerCast(n) end
      if not st.channel then st.castName, st.castEnd = nil, 0 end
      onCast(spellID)
    elseif event == 'UNIT_SPELLCAST_STOP' or event == 'UNIT_SPELLCAST_FAILED' or event == 'UNIT_SPELLCAST_INTERRUPTED'
      or event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
      if event ~= 'UNIT_SPELLCAST_STOP' or not st.channel then st.castName, st.castEnd, st.channel = nil, 0, false end
    end
  end
end)

------------------------------------------------------------------------------------------
-- Hlavni smycka
------------------------------------------------------------------------------------------
local acc = 0
ev:SetScript('OnUpdate', function(_, elapsed)
  if not ns.enabled or not ns.db then return end
  -- sondy (zdravi, mana) bezi kazdy frame (3 framy na jedno cteni), jen kdyz je hodnota skryta
  ns.phase = 'probes'
  ns.stepProbes()
  ns.phase = 'idle'
  acc = acc + elapsed
  if acc < 0.1 then return end
  acc = 0
  ns.phase = 'cdm' CDM.sweep()
  ns.phase = 'bags' if ns.Bags then ns.Bags.update() end
  local pct, exact = ns.healthPct('target')
  if pct and exact and ns.inCombat() then addSample(pct) end
  if ns.Engine and ns.UI and ns.UI.frame then
    local ok, err = pcall(function()
      ns.phase = 'context' local ctx = ns.Engine.context()
      ns.phase = 'plan' local plan, util = ns.Engine.plan(ctx)
      ns.phase = 'ui' ns.UI.update(ctx, plan, util)
      ns.phase = 'mem' if ns.Mem then ns.Mem.tick(ctx, plan) end
      ns.phase = 'bug' if ns.Bug then ns.Bug.push(ctx, plan, util) end
      ns.phase = 'duo' if ns.Duo then ns.Duo.send(ctx, plan) end
      ns.phase = 'idle'
    end)
    if not ok and ns.db.debug then ns.say('chyba: ' .. tostring(err)) end
  end
end)

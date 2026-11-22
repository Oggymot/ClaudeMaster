-- ClaudeMaster: /cm dump
-- Jeden prikaz, ktery do ClaudeMasterDB.fullDump ulozi vse, co addon potrebuje k doladeni:
-- postavu, staty, talenty, spellbook (s popisy, cenou, castem), akcni listy, batohy, vybaveni a buffy.
-- WoW zapisuje SavedVariables az pri /reload nebo odhlaseni, proto se na konci pise "dej /reload".
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local function str(v) v = safe(v) if type(v) == 'string' then return (v:gsub('[\r\n]+', ' ')) end end

-- radky tooltipu (popis itemu / kouzla), kdyz je API k dispozici
local function tipLines(data)
  if type(data) ~= 'table' or type(data.lines) ~= 'table' then return nil end
  local out = {}
  for _, l in ipairs(data.lines) do
    local a, b = str(l.leftText), str(l.rightText)
    if a and a ~= '' then out[#out + 1] = b and (a .. ' | ' .. b) or a end
  end
  return #out > 0 and out or nil
end

local function itemEntry(id, count)
  local name, link, quality, ilvl, req, typ, sub, _, equipLoc
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  name, link, quality, ilvl, req, typ, sub, _, equipLoc = pc(f, id)
  local spellName = pc((C_Item and C_Item.GetItemSpell) or GetItemSpell, id)
  local e = { id = id, count = count, name = str(name), quality = safeNum(quality), ilvl = safeNum(ilvl),
    req = safeNum(req), type = str(typ), sub = str(sub), equipLoc = str(equipLoc), use = str(spellName) }
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then e.tip = tipLines(pc(C_TooltipInfo.GetItemByID, id)) end
  return e
end

local function collect()
  local d = {}
  local now = date and date('%Y-%m-%d %H:%M') or ''
  local _, cls = UnitClass('player')
  local _, race = UnitRace('player')
  local ver, build, _, iface = pc(GetBuildInfo)
  d.meta = { date = now, class = cls, race = race, level = safeNum(pc(UnitLevel, 'player')),
    name = str(pc(UnitName, 'player')), realm = str(pc(GetRealmName)), client = str(ver), build = str(build),
    interface = safeNum(iface), addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and
      str(pc(C_AddOns.GetAddOnMetadata, ADDON, 'Version')), zone = str(pc(GetRealZoneText)) }

  -- staty
  local st = { hpMax = safeNum(pc(UnitHealthMax, 'player')), manaMax = safeNum(pc(UnitPowerMax, 'player', 0)) }
  local STAT = { 'str', 'agi', 'sta', 'int', 'spi' }
  for i, k in ipairs(STAT) do local _, v = pc(UnitStat, 'player', i) st[k] = safeNum(v) end
  st.spellPower = {}
  for sch = 2, 7 do st.spellPower[sch] = safeNum(pc(GetSpellBonusDamage, sch)) end
  st.spellCrit = safeNum(pc(GetSpellCritChance, 3))
  st.spellHit = safeNum(pc(GetCombatRatingBonus, 8))
  st.armor = safeNum((select(2, pc(UnitArmor, 'player'))))
  local base, cast = pc(GetManaRegen)
  st.manaRegen, st.manaRegenCast = safeNum(base), safeNum(cast)
  d.stats = st

  -- talenty: vcetne stromu a max ranku
  d.talents = {}
  local nTabs = safeNum(pc(GetNumTalentTabs)) or 0
  for tab = 1, nTabs do
    local tname, _, points = pc(GetTalentTabInfo, tab)
    local T = { tab = str(tname) or ('tab' .. tab), points = safeNum(points), list = {} }
    local n = safeNum(pc(GetNumTalents, tab)) or 0
    for i = 1, n do
      local name, _, tier, col, rank, maxRank = pc(GetTalentInfo, tab, i)
      name = str(name)
      if name then
        local t = { name = name, rank = safeNum(rank), max = safeNum(maxRank), tier = safeNum(tier), col = safeNum(col) }
        if C_TooltipInfo and C_TooltipInfo.GetTalent then t.tip = tipLines(pc(C_TooltipInfo.GetTalent, tab, i)) end
        T.list[#T.list + 1] = t
      end
    end
    d.talents[#d.talents + 1] = T
  end
  pcall(ns.scanTalents)
  if ns.talentList then
    d.traits = ns.talentList
    -- popis kazdeho talentu (i nevybraneho), at vim, co dela - Forever ma vlastni talenty
    for _, t in ipairs(d.traits) do
      if t.spellId and C_Spell and C_Spell.GetSpellDescription then
        t.desc = str(pc(C_Spell.GetSpellDescription, t.spellId))
      end
    end
  end
  d.talentsReadable, d.talentAPI = ns.talentsRead, ns.talentAPI
  d.traitsDiag = { hasClassTalents = C_ClassTalents ~= nil, hasTraits = C_Traits ~= nil,
    activeConfig = C_ClassTalents and safeNum(pc(C_ClassTalents.GetActiveConfigID)),
    spec = GetSpecialization and safeNum(pc(GetSpecialization)), numTabs = safeNum(pc(GetNumTalentTabs)) }

  -- spellbook (s popisy) + cena, cas castu, dosah
  local spells = ns.dumpSpells(true) or {}
  for _, e in ipairs(spells) do
    if e.id and not e.passive then
      local info = C_Spell and C_Spell.GetSpellInfo and pc(C_Spell.GetSpellInfo, e.id)
      if type(info) == 'table' then
        e.castMs, e.minRange, e.maxRange = safeNum(info.castTime), safeNum(info.minRange), safeNum(info.maxRange)
      end
      local costs = C_Spell and C_Spell.GetSpellPowerCost and pc(C_Spell.GetSpellPowerCost, e.id)
      if type(costs) == 'table' and type(costs[1]) == 'table' then e.cost = safeNum(costs[1].cost) end
      local cd = C_Spell and C_Spell.GetSpellBaseCooldown and safeNum(pc(C_Spell.GetSpellBaseCooldown, e.id))
      if not cd and GetSpellBaseCooldown then cd = safeNum(pc(GetSpellBaseCooldown, e.id)) end
      e.baseCdMs = cd
      local all = ns.ranks[e.name]
      if all and #all > 1 then e.allRanks = all end
    end
  end
  d.spells = spells

  -- akcni listy: co je kde a na jake klavese
  d.actions = {}
  if GetActionInfo then
    for slot = 1, 180 do
      local typ, id = pc(GetActionInfo, slot)
      typ, id = safe(typ), safeNum(id)
      if typ and id then
        local nm
        if typ == 'spell' then nm = ns.nameOf(id)
        elseif typ == 'item' then nm = str(pc((C_Item and C_Item.GetItemNameByID) or GetItemInfo, id))
        elseif typ == 'macro' then nm = str(pc(GetMacroInfo, id)) end
        d.actions[#d.actions + 1] = { slot = slot, type = typ, id = id, name = nm, key = ns.binds and ns.binds[typ == 'item' and ('item:' .. id) or nm] }
      end
    end
  end

  -- batohy
  d.bags = {}
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local counts = {}
  if getNum and getInfo then
    for bag = 0, 4 do
      for slot = 1, safeNum(pc(getNum, bag)) or 0 do
        local info = pc(getInfo, bag, slot)
        local id = type(info) == 'table' and safeNum(info.itemID)
        if id then counts[id] = (counts[id] or 0) + (safeNum(info.stackCount) or 1) end
      end
    end
  end
  for id, n in pairs(counts) do d.bags[#d.bags + 1] = itemEntry(id, n) end
  table.sort(d.bags, function(a, b) return (a.name or '') < (b.name or '') end)

  -- vybaveni
  d.equipped = {}
  for slot = 1, 19 do
    local id = safeNum(pc(GetInventoryItemID, 'player', slot))
    if id then local e = itemEntry(id, 1) e.slot = slot d.equipped[#d.equipped + 1] = e end
  end

  -- buffy hrace (mimo boj jdou precist)
  d.buffs = {}
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local a = pc(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HELPFUL')
      if type(a) ~= 'table' then break end
      local nm = str(a.name)
      if nm then d.buffs[#d.buffs + 1] = { name = nm, id = safeNum(a.spellId) } end
    end
  end

  -- pet
  if UnitExists('pet') then
    d.pet = { name = str(pc(UnitName, 'pet')), family = str(pc(UnitCreatureFamily, 'pet')), level = safeNum(pc(UnitLevel, 'pet')) }
  end

  -- co ted addon vidi a doporucuje
  d.addon = { settings = {}, inGroup = IsInGroup and IsInGroup() or false }
  for k, v in pairs(ns.db) do
    local t = type(v)
    if t == 'number' or t == 'boolean' or t == 'string' then d.addon.settings[k] = v end
  end
  if ns.Warlock then d.addon.warlockOrder = ns.Warlock.order end
  d.addon.blocked = ns.db.blocked
  return d
end

function ns.fullDump()
  if ns.inCombat() then ns.say('Dump jen mimo boj (v boji jsou hodnoty skryte).') return end
  ns.say('Sbiram data...')
  pcall(ns.scanSpells)
  if ns.Bags and ns.Bags.scan then pcall(ns.Bags.scan) end
  -- nactene informace o itemech nemusi byt hned v cache: vyzadej je a dump udelej az za chvili
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  if getNum and getInfo and C_Item and C_Item.RequestLoadItemDataByID then
    for bag = 0, 4 do
      for slot = 1, safeNum(pc(getNum, bag)) or 0 do
        local info = pc(getInfo, bag, slot)
        local id = type(info) == 'table' and safeNum(info.itemID)
        if id then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
    end
  end
  C_Timer.After(1.5, function()
    local ok, d = pcall(collect)
    if not ok then ns.say('Chyba pri dumpu: ' .. tostring(d)) return end
    ns.db.fullDump = d
    local nt = 0
    for _, T in ipairs(d.talents) do for _, t in ipairs(T.list) do if (t.rank or 0) > 0 then nt = nt + 1 end end end
    for _, t in ipairs(d.traits or {}) do if (t.rank or 0) > 0 then nt = nt + 1 end end
    if nt == 0 then ns.say('|cffff8855Talenty: 0 - do souboru jsem ulozil diagnostiku, at vim proc.|r') end
    ns.say(('Hotovo: %d talentu (s body), %d spellu, %d itemu v batohu, %d vybaveni, %d akci.')
      :format(nt, #d.spells, #d.bags, #d.equipped, #d.actions))
    ns.say('Ted dej |cffffffff/reload|r - pak je to v souboru:')
    ns.say('|cffffd100WTF\\Account\\<UCET>\\' .. (d.meta.realm or '<REALM>') .. '\\' .. (d.meta.name or '<POSTAVA>')
      .. '\\SavedVariables\\ClaudeMaster.lua|r')
  end)
end

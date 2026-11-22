-- ClaudeMaster: inventar. Projde batohy a roztridi uzitecne veci podle nazvu a "Use:" kouzla,
-- takze funguje s cimkoli, co mas (ne jen s pevnym seznamem ID).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local B = { items = {}, kinds = {}, dirty = true, nextScan = 0 }
ns.Bags = B

-- Scrolly uzitecne pro maga; "conflict" = buffy, se kterymi se scroll nesepisuje
B.SCROLL_STATS = {
  Intellect = { 'Arcane Intellect', 'Arcane Brilliance' },
  Spirit = { 'Divine Spirit', 'Prayer of Spirit' },
  Stamina = { 'Power Word: Fortitude', 'Prayer of Fortitude' },
  Protection = {},
}
-- Poradi imbue scrollu pro frost maga (Balefrost = mraz). Prvni v seznamu se nabidne.
B.IMBUE_ORDER = { Balefrost = 5, Manablade = 4, Accuracy = 3, Flame = 2, Striking = 1 }
local GEM_NAMES = { ['Mana Agate'] = 1, ['Mana Jade'] = 2, ['Mana Citrine'] = 3, ['Mana Ruby'] = 4, ['Mana Emerald'] = 5 }

local function getItemName(id)
  local n = C_Item and C_Item.GetItemNameByID and safe(pc(C_Item.GetItemNameByID, id))
  if not n and GetItemInfo then n = safe(pc(GetItemInfo, id)) end
  if type(n) == 'string' then return n end
end
local function itemInfo(id)
  -- level, reqLevel, classID, subclassID
  local name, _, _, ilvl, req, _, sub, _, _, _, _, classID, subclassID
  if C_Item and C_Item.GetItemInfo then name, _, _, ilvl, req, _, sub, _, _, _, _, classID, subclassID = pc(C_Item.GetItemInfo, id)
  elseif GetItemInfo then name, _, _, ilvl, req, _, sub, _, _, _, _, classID, subclassID = pc(GetItemInfo, id) end
  return safeNum(ilvl) or 0, safeNum(req) or 0, safe(sub), safeNum(classID), safeNum(subclassID)
end
local function itemSpell(id)
  local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  local n, sid = pc(f, id)
  return safe(n), safeNum(sid)
end

function B.scan()
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  if not getNum or not getInfo then return end
  local items = {}
  for bag = 0, 4 do
    local n = safeNum(pc(getNum, bag)) or 0
    for slot = 1, n do
      local info = pc(getInfo, bag, slot)
      local id = type(info) == 'table' and safeNum(info.itemID)
      if id then
        local it = items[id]
        if not it then it = { id = id, count = 0 } items[id] = it end
        it.count = it.count + (safeNum(info.stackCount) or 1)
      end
    end
  end
  local kinds = { water = {}, food = {}, gem = {}, hpot = {}, mpot = {}, stone = {}, scroll = {}, elixir = {}, bandage = {},
    imbue = {}, nuke = {}, antiElem = {}, defense = {}, buffFood = {}, shard = {}, soulstone = {} }
  local pending = false
  local myLevel = safeNum(UnitLevel('player')) or 60
  for id, it in pairs(items) do
    local name = getItemName(id)
    if not name then
      pending = true
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    else
      it.name = name
      it.ilvl, it.req, it.sub, it.classID, it.subclassID = itemInfo(id)
      it.spell = itemSpell(id)
      it.conjured = name:find('^Conjured') ~= nil
      local usable = it.req <= myLevel
      local sp = it.spell
      if usable then
        if GEM_NAMES[name] then it.rank = GEM_NAMES[name] table.insert(kinds.gem, it)
        elseif name == 'Soul Shard' then table.insert(kinds.shard, it)
        elseif name:find('Soulstone') then table.insert(kinds.soulstone, it)
        elseif name:find('Healthstone') then table.insert(kinds.stone, it)
        elseif name:find('Healing Potion') or name:find('Healing Draught') then table.insert(kinds.hpot, it)
        elseif name:find('Mana Potion') or name:find('Mana Draught') then table.insert(kinds.mpot, it)
        -- vycarovany lektvar many (od maga): stoji jen manu, takze ma prednost pred kupovanym
        elseif it.conjured and (name:find('Mana') or (sp and sp:find('Mana'))) and not (sp and (sp:find('Drink') or sp == 'Refreshment' or sp:find('Food'))) then
          table.insert(kinds.mpot, it)
        elseif name:find('Firestone$') or name:find('Spellstone$') then
          -- warlock: kamen na zbran (Firestone = +crit a ohen, lepsi pro Destruction)
          it.imbue = name
          it.pref = (name:find('Firestone') and 20 or 10) + (name:find('Major') and 4 or name:find('Greater') and 3
            or name:find('Lesser') and 1 or 2)
          table.insert(kinds.imbue, it)
        elseif name:find('^Scroll of Imbue ') then
          it.imbue = name:match('^Scroll of Imbue (.+)$')
          it.pref = B.IMBUE_ORDER[it.imbue] or 0
          table.insert(kinds.imbue, it)
        elseif name == 'Scroll of Cryoblast' then table.insert(kinds.nuke, it)
        elseif name == 'Scroll of Rebuke Elemental' then table.insert(kinds.antiElem, it)
        elseif sp == 'Activating Defenses' then table.insert(kinds.defense, it)
        elseif sp == 'Refreshment' then table.insert(kinds.water, it) table.insert(kinds.food, it)
        elseif sp and sp:find('Drink') then
          it.buff = sp:find('Nutritious') ~= nil
          table.insert(kinds.water, it)
          if it.buff then table.insert(kinds.buffFood, it) end
        elseif sp and sp:find('Food') then
          it.buff = sp:find('Nutritious') ~= nil
          table.insert(kinds.food, it)
          if it.buff then table.insert(kinds.buffFood, it) end
        elseif sp == 'First Aid' or name:find('Bandage') then table.insert(kinds.bandage, it)
        else
          local stat = name:match('^Scroll of (%a+)')
          if stat and B.SCROLL_STATS[stat] and sp then
            it.stat = stat
            table.insert(kinds.scroll, it)
          elseif (name:find('^Elixir') or name:find('^Flask') or it.sub == 'Elixir' or it.sub == 'Flask') and sp then
            table.insert(kinds.elixir, it)
          end
        end
      end
    end
  end
  -- poradi: vycarovane jako prvni (jsou zadarmo), pak nejlepsi
  local function better(a, b)
    if (a.pref or 0) ~= (b.pref or 0) then return (a.pref or 0) > (b.pref or 0) end
    -- obycejne jidlo/piti pred buffovacim (to si nech na dungeon)
    if (a.buff or false) ~= (b.buff or false) then return not a.buff end
    if a.conjured ~= b.conjured then return a.conjured end
    if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    return a.id > b.id
  end
  for _, list in pairs(kinds) do table.sort(list, better) end
  -- nerozpoznane veci s "Use:" efektem (pro /cm items)
  local known = {}
  for _, list in pairs(kinds) do for _, it in ipairs(list) do known[it.id] = true end end
  local other = {}
  for id, it in pairs(items) do
    if it.name and it.spell and not known[id] then other[#other + 1] = it end
  end
  table.sort(other, function(a, b) return a.name < b.name end)
  kinds.other = other
  B.items, B.kinds = items, kinds
  B.dirty = pending
end

function B.update()
  if B.dirty and GetTime() >= B.nextScan then
    B.nextScan = GetTime() + 1
    B.scan()
  end
end
function B.markDirty() B.dirty = true B.nextScan = math.min(B.nextScan, GetTime() + 0.3) end

function B.best(kind)
  local l = B.kinds[kind]
  local it = l and l[1]
  return it and it.id, it
end
function B.count(kind)
  local n = 0
  for _, it in ipairs(B.kinds[kind] or {}) do n = n + it.count end
  return n
end
function B.list(kind) return B.kinds[kind] or {} end
-- kolik mam vycarovanych (od maga, zadarmo)
function B.countConj(kind)
  local n = 0
  for _, it in ipairs(B.kinds[kind] or {}) do if it.conjured then n = n + it.count end end
  return n
end
-- mag ve skupine (krome me): jmeno
function B.groupMage()
  if not (IsInGroup and IsInGroup()) then return nil end
  for i = 1, 4 do
    local u = 'party' .. i
    if UnitExists(u) then
      local _, cls = UnitClass(u)
      if cls == 'MAGE' then return safe(pc(UnitName, u)) or 'mag' end
    end
  end
end

-- Scroll, ktery ti chybi (mimo boj, buff jde precist)
function B.missingScroll()
  for _, it in ipairs(B.list('scroll')) do
    local have = ns.playerAura(it.spell)
    if have == false then
      local blocked = false
      for _, other in ipairs(B.SCROLL_STATS[it.stat] or {}) do
        if ns.playerAura(other) then blocked = true break end
      end
      -- na Intellect si dej radsi vlastni Arcane Intellect
      if it.stat == 'Intellect' and ns.known('Arcane Intellect') then blocked = true end
      if not blocked then return it end
    end
  end
end
-- Zbran bez docasneho vylepseni? (mimo boj citelne)
function B.missingImbue()
  local it = B.list('imbue')[1]
  if not it or not GetWeaponEnchantInfo then return nil end
  local has = pc(GetWeaponEnchantInfo)
  if ns.issecret(has) or has == nil then return nil end
  if has == true or has == 1 then return nil end
  return it
end
-- Najez se buffovaciho jidla (Well Fed chybi)
function B.missingWellFed()
  local it = B.list('buffFood')[1]
  if not it then return nil end
  if ns.playerAura('Well Fed') == false and ns.playerAura(it.spell) == false then return it end
end
-- Elixir, ktery ti chybi
function B.missingElixir()
  for _, it in ipairs(B.list('elixir')) do
    if ns.playerAura(it.spell) == false then return it end
  end
end

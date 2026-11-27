-- ClaudeMaster: pripominka trenera tridy
--  * u trenera si zapamatuje seznam kouzel (level, cena), ktera jeste nemas
--  * po novem levelu napise, co uz se muzes naucit a za kolik (bez zaznamu: kazdy sudy level = nova kouzla)
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum = ns.pc, ns.safe, ns.safeNum

local T = {}
ns.Trainer = T

local function lvl() return safeNum(pc(UnitLevel, 'player')) or 1 end
local function cls() return select(2, pc(UnitClass, 'player')) end
local function money(c) return ns.coin and ns.coin(c) or (tostring(c) .. 'c') end

-- je otevreny trener tridy (ne profese)?
local function classTrainer()
  if IsTradeskillTrainer and pc(IsTradeskillTrainer) then return false end
  return GetNumTrainerServices ~= nil
end

function T.record()
  if not (ns.db and classTrainer()) then return end
  local n = safeNum(pc(GetNumTrainerServices)) or 0
  if n == 0 then return end
  local list = {}
  for i = 1, n do
    local name, sub, typ = pc(GetTrainerServiceInfo, i)
    name, sub, typ = safe(name), safe(sub), safe(typ)
    if type(name) == 'string' and typ ~= 'header' and typ ~= 'used' then
      local req = GetTrainerServiceLevelReq and safeNum(pc(GetTrainerServiceLevelReq, i)) or 0
      local cost = GetTrainerServiceCost and safeNum(pc(GetTrainerServiceCost, i)) or 0
      list[#list + 1] = { name = name, rank = (type(sub) == 'string' and sub ~= '') and sub or nil, lvl = req, cost = cost }
    end
  end
  ns.db.trainSpells = { class = cls(), at = lvl(), list = list }
end

-- co se uz muzes naucit: { {name, rank, lvl, cost} }, celkova cena, zaznam existuje?
function T.pending()
  local rec = ns.db and ns.db.trainSpells
  local L = lvl()
  if not (rec and rec.class == cls() and type(rec.list) == 'table') then return nil end
  local out, sum = {}, 0
  for _, e in ipairs(rec.list) do
    if (e.lvl or 0) <= L then out[#out + 1] = e sum = sum + (e.cost or 0) end
  end
  table.sort(out, function(a, b) return (a.lvl or 0) > (b.lvl or 0) end)
  return out, sum
end

function T.say(levelUp)
  if ns.db and ns.db.trainerTip == false then return end
  local list, sum = T.pending()
  local L = lvl()
  if L >= 60 and not (list and list[1]) then return end
  if list then
    if not list[1] then return end
    local names = {}
    for i, e in ipairs(list) do
      if i > 6 then names[#names + 1] = ('a dalsi %d'):format(#list - 6) break end
      names[#names + 1] = e.name .. (e.rank and (' (' .. e.rank .. ')') or '')
    end
    ns.say(('|cffffd200Trener tridy:|r muzes se naucit %d %s za %s - %s'):format(#list, #list == 1 and 'kouzlo' or (#list < 5 and 'kouzla' or 'kouzel'),
      money(sum), table.concat(names, ', ')))
  elseif levelUp and L % 2 == 0 then
    -- bez zaznamu z trenera: v Classicu ma kazda trida nova kouzla / ranky na kazdem sudem levelu
    ns.say('|cffffd200Trener tridy:|r novy level ' .. L .. ' - u trenera na tebe nejspis cekaji nova kouzla. (Po navsteve trenera si addon seznam zapamatuje.)')
  end
end

local f = CreateFrame('Frame')
for _, e in ipairs({ 'TRAINER_SHOW', 'TRAINER_UPDATE', 'TRAINER_CLOSED', 'PLAYER_LEVEL_UP', 'PLAYER_ENTERING_WORLD' }) do pcall(f.RegisterEvent, f, e) end
local greeted = false
f:SetScript('OnEvent', function(_, e)
  if e == 'TRAINER_SHOW' or e == 'TRAINER_UPDATE' or e == 'TRAINER_CLOSED' then
    if e ~= 'TRAINER_CLOSED' then pcall(T.record) end
  elseif e == 'PLAYER_LEVEL_UP' then
    if C_Timer then C_Timer.After(4, function() pcall(T.say, true) end) end
  elseif e == 'PLAYER_ENTERING_WORLD' and not greeted then
    greeted = true
    if C_Timer then C_Timer.After(12, function() pcall(T.say, false) end) end
  end
end)

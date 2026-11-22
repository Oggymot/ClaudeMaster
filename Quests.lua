-- ClaudeMaster: seznam questu pod minimapou (Objective Tracker)
--  * questZone: sledovat jen questy, ktere maji cil v aktualni oblasti; ostatni se skryji a po navratu
--    do jejich oblasti se zase ukazou (skryva jen ty, ktere skryl addon - rucni volby hrace respektuje)
--  * questSort: radit sledovane questy podle vzdalenosti (nejblizsi nahore), prubezne pri pohybu
-- Meni se jen seznam sledovanych questu, a jen mimo boj (v boji by to mohlo rozbit Blizzard UI).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local Q = { pending = false, last = 0 }
ns.Quests = Q
local QL = C_QuestLog

local function watched(qid)
  if QL.GetQuestWatchType then return pc(QL.GetQuestWatchType, qid) ~= nil end
  if QL.IsQuestWatched then return pc(QL.IsQuestWatched, qid) == true end
end

-- questy s cilem / odevzdanim na aktualni mape
local function onMapSet()
  local set, any = {}, false
  local map = C_Map and C_Map.GetBestMapForUnit and safeNum(pc(C_Map.GetBestMapForUnit, 'player'))
  if map and QL.GetQuestsOnMap then
    local list = pc(QL.GetQuestsOnMap, map)
    for _, q in ipairs(type(list) == 'table' and list or {}) do
      local id = safeNum(q.questID)
      if id then set[id] = true any = true end
    end
  end
  return set, any
end

function Q.update()
  local db = ns.db
  if not (db and QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return end
  if not (db.questZone or db.questSort or next(db.qHidden or {})) then return end
  if InCombatLockdown() then Q.pending = true return end
  Q.pending = false
  db.qHidden = db.qHidden or {}

  local set, anySet = onMapSet()
  local n = safeNum(pc(QL.GetNumQuestLogEntries)) or 0
  local quests = {}
  for i = 1, n do
    local info = pc(QL.GetInfo, i)
    if type(info) == 'table' and not info.isHeader and not info.isHidden and safeNum(info.questID) then
      local qid = info.questID
      local here = info.isOnMap == true or set[qid] == true
      quests[#quests + 1] = { id = qid, here = here, known = info.isOnMap ~= nil or anySet }
    end
  end

  -- kdyz hra u zadneho questu nehlasi "tady", nic neskryvat (radsi nez schovat cely seznam)
  local hereN = 0
  for _, q in ipairs(quests) do if q.here then hereN = hereN + 1 end end
  for _, q in ipairs(quests) do
    local w = watched(q.id)
    if db.questZone then
      if q.here and not w and db.qHidden[q.id] then
        pc(QL.AddQuestWatch, q.id)
        db.qHidden[q.id] = nil
      elseif not q.here and q.known and hereN > 0 and w then
        pc(QL.RemoveQuestWatch, q.id)
        db.qHidden[q.id] = true
      end
    elseif db.qHidden[q.id] then
      -- funkce vypnuta: vratit vse, co addon skryl
      if not w then pc(QL.AddQuestWatch, q.id) end
      db.qHidden[q.id] = nil
    end
  end
  -- questy, ktere uz v logu nejsou (odevzdane / zrusene)
  local inLog = {}
  for _, q in ipairs(quests) do inLog[q.id] = true end
  for id in pairs(db.qHidden) do if not inLog[id] then db.qHidden[id] = nil end end

  if db.questSort and QL.SortQuestWatches then pc(QL.SortQuestWatches) end
end

local function request()
  local now = GetTime()
  if now - Q.last < 1 then Q.pending = true return end
  Q.last = now
  Q.update()
end

local f = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED', 'QUEST_ACCEPTED',
  'QUEST_LOG_UPDATE', 'PLAYER_REGEN_ENABLED' }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript('OnEvent', function() request() end)
-- pri pohybu se meni vzdalenosti: preradit kazdych 5 s (a dobehnout odlozenou aktualizaci)
local acc = 0
f:SetScript('OnUpdate', function(_, el)
  acc = acc + el
  if acc < 5 then return end
  acc = 0
  local db = ns.db
  if db and (Q.pending or db.questSort) then request() end
end)

function Q.toggle(arg)
  local db = ns.db
  if arg == 'zona' or arg == 'zone' then db.questZone = not db.questZone
  elseif arg == 'razeni' or arg == 'sort' then db.questSort = not db.questSort
  else
    local on = not (db.questZone and db.questSort)
    db.questZone, db.questSort = on, on
  end
  ns.say(('Questy: jen aktualni oblast %s, razeni podle vzdalenosti %s'):format(
    db.questZone and '|cff66ee77zap|r' or '|cffff7070vyp|r', db.questSort and '|cff66ee77zap|r' or '|cffff7070vyp|r'))
  Q.last = 0
  request()
end

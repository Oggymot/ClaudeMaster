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

------------------------------------------------------------------------------------------
-- Questovi moby: koho mas zabit (nebo z koho padne questovy item)
--  1) tooltip moba (hra u nej sama ukazuje radek s cilem questu, napr. "Kobold Vermin slain: 3/10")
--  2) jmeno moba = nesplneny cil typu "monster" v quest logu
--  3) databaze dropu: mob dropuje questovy item, ktery jeste sbiras
------------------------------------------------------------------------------------------
Q.objs, Q.objAt, Q.dirty = {}, 0, true
local function objKey(text)
  local t = text:gsub('%s*:?%s*%d+%s*/%s*%d+%s*', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  t = t:gsub('%s+slain$', ''):gsub('%s+killed$', ''):gsub('^Kill%s+', '')
  return t:lower()
end
local function rebuild()
  local now = GetTime()
  if not Q.dirty and now - Q.objAt < 10 then return Q.objs end
  Q.dirty, Q.objAt = false, now
  local out = {}
  local n = (QL and QL.GetNumQuestLogEntries) and safeNum(pc(QL.GetNumQuestLogEntries)) or 0
  for i = 1, n do
    local info = pc(QL.GetInfo, i)
    if type(info) == 'table' and not info.isHeader and safeNum(info.questID) then
      local list = QL.GetQuestObjectives and pc(QL.GetQuestObjectives, info.questID)
      for _, o in ipairs(type(list) == 'table' and list or {}) do
        local text, typ = safe(o.text), safe(o.type)
        if type(text) == 'string' and safe(o.finished) ~= true and (typ == 'monster' or typ == 'item') then
          local have, need = text:match('(%d+)%s*/%s*(%d+)')
          out[#out + 1] = { title = safe(info.title) or '?', text = text, typ = typ, key = objKey(text),
            have = tonumber(have) or safeNum(o.numFulfilled), need = tonumber(need) or safeNum(o.numRequired) }
        end
      end
    end
  end
  Q.objs = out
  return out
end
pcall(f.RegisterEvent, f, 'QUEST_WATCH_UPDATE')
local oldOnEvent = f:GetScript('OnEvent')
f:SetScript('OnEvent', function(self, e, ...)
  if e == 'QUEST_LOG_UPDATE' or e == 'QUEST_ACCEPTED' or e == 'QUEST_WATCH_UPDATE' then Q.dirty = true wipe(Q.cache or {}) end
  if e ~= 'QUEST_WATCH_UPDATE' then oldOnEvent(self, e, ...) end
end)

local TT_OBJ = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
local function fromTooltip(u)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit and TT_OBJ) then return nil end
  local data = pc(C_TooltipInfo.GetUnit, u)
  local lines = type(data) == 'table' and data.lines
  if type(lines) ~= 'table' then return nil end
  for _, ln in ipairs(lines) do
    if safe(ln.type) == TT_OBJ and safe(ln.completed) ~= true then
      local text = safe(ln.leftText)
      if type(text) == 'string' then
        local have, need = text:match('(%d+)%s*/%s*(%d+)')
        if not have or tonumber(have) < tonumber(need) then
          -- najdi cely cil v logu (kvuli nazvu questu)
          local k = objKey(text:gsub('^%s*%-%s*', ''))
          for _, o in ipairs(rebuild()) do if o.key == k then return o end end
          return { title = '?', text = text, key = k, have = tonumber(have), need = tonumber(need) }
        end
      end
    end
  end
  return false
end

Q.cache = {}
-- vraci cil questu pro unit (tabulka), nebo nil
function Q.mobNeed(u)
  if not UnitExists(u) or safeBool(pc(UnitIsPlayer, u)) == true then return nil end
  local name = safe(pc(UnitName, u))
  if type(name) ~= 'string' then return nil end
  local key = safe(pc(UnitGUID, u)) or name
  local now = GetTime()
  local hit = Q.cache[key]
  if hit and now - hit.at < 3 then return hit.v or nil end
  local objs = rebuild()
  local v
  if #objs > 0 then
    v = fromTooltip(u)
    if v == nil or v == false then
      local ln = name:lower()
      for _, o in ipairs(objs) do
        if o.typ == 'monster' and (o.key == ln or o.key:find(ln, 1, true)) then v = o break end
      end
    end
    if not v and ns.MobDB and ns.MobDB.forUnit then
      local r = ns.MobDB.forUnit(u)
      for _, d in ipairs(r and r.drops or {}) do
        local dn = d.name and d.name:lower()
        for _, o in ipairs(objs) do
          if o.typ == 'item' and dn and o.key == dn then v = o break end
        end
        if v then break end
      end
    end
  end
  Q.cache[key] = { at = now, v = v or false }
  return v or nil
end
function Q.hasKillObjectives() return #rebuild() > 0 end

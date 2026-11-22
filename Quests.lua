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

  if db.questSort then Q.sort() end
end

-- sledovane questy v poradi, jak je ukazuje seznam
function Q.watchList()
  local out = {}
  local n = QL.GetNumQuestWatches and safeNum(pc(QL.GetNumQuestWatches)) or 0
  for i = 1, n do
    local id = QL.GetQuestIDForQuestWatchIndex and safeNum(pc(QL.GetQuestIDForQuestWatchIndex, i))
    if id then out[#out + 1] = id end
  end
  return out
end
function Q.dist(id)
  local d = QL.GetDistanceSqToQuest and safeNum(pc(QL.GetDistanceSqToQuest, id))
  return d and math.sqrt(d) or nil
end
-- Razeni podle vzdalenosti. Seznam ukazuje questy v poradi sledovani, takze kdyz hra sama
-- neseradi (SortQuestWatches na Foreveru nemusi existovat / nic nedela), preradime je sami:
-- odebrat a znovu pridat od nejblizsiho. Jen kdyz se zmenilo poradi a max. jednou za 10 s.
Q.sortAt = 0
function Q.sort()
  local list = Q.watchList()
  if #list < 2 then return end
  local d = {}
  for i, id in ipairs(list) do d[id] = Q.dist(id) or (1e9 + i) end
  local want = {}
  for i, id in ipairs(list) do want[i] = id end
  table.sort(want, function(a, b) return d[a] < d[b] end)
  -- /cm questy obratit: kdyby seznam ukazoval opacne nez poradi sledovani
  if ns.db.questReverse then
    local r = {}
    for i = #want, 1, -1 do r[#r + 1] = want[i] end
    want = r
  end
  local function eq(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  if eq(list, want) then return end
  local now = GetTime()
  if now - Q.sortAt < 10 then return end
  Q.sortAt = now
  if not (QL.AddQuestWatch and QL.RemoveQuestWatch) then return end
  Q.how = 'addon'
  local types = {}
  for _, id in ipairs(want) do types[id] = QL.GetQuestWatchType and pc(QL.GetQuestWatchType, id) or nil end
  local function apply(order)
    for _, id in ipairs(order) do pc(QL.RemoveQuestWatch, id) end
    for _, id in ipairs(order) do
      if types[id] ~= nil then pc(QL.AddQuestWatch, id, types[id]) else pc(QL.AddQuestWatch, id) end
    end
  end
  -- hra muze nove sledovany quest davat na zacatek (ne na konec): pak pridavat od nejvzdalenejsiho
  local rev = {}
  for i = #want, 1, -1 do rev[#rev + 1] = want[i] end
  if Q.prepend then apply(rev) return end
  apply(want)
  if Q.prepend == nil and eq(Q.watchList(), rev) then
    Q.prepend = true
    apply(rev)
  elseif Q.prepend == nil then
    Q.prepend = false
  end
end

-- /cm questy info: co hra umi a jak daleko jsou sledovane questy
function Q.info()
  local function has(f) return QL[f] and '|cff66ee77ano|r' or '|cffff5555ne|r' end
  ns.say(('Questy API: SortQuestWatches %s, GetDistanceSqToQuest %s, GetQuestIDForQuestWatchIndex %s, AddQuestWatch %s')
    :format(has('SortQuestWatches'), has('GetDistanceSqToQuest'), has('GetQuestIDForQuestWatchIndex'), has('AddQuestWatch')))
  ns.say(('Zona: %s, razeni: %s (radi: %s, pridava na zacatek: %s, obracene: %s), skrytych addonem: %d'):format(
    tostring(ns.db.questZone), tostring(ns.db.questSort), Q.how or '-', tostring(Q.prepend), tostring(ns.db.questReverse == true), (function() local k = 0 for _ in pairs(ns.db.qHidden or {}) do k = k + 1 end return k end)()))
  for i, id in ipairs(Q.watchList()) do
    local t = QL.GetTitleForQuestID and safe(pc(QL.GetTitleForQuestID, id)) or id
    local dd = Q.dist(id)
    ns.say(('  %d. %s  %s'):format(i, tostring(t), dd and ('%d yd'):format(dd) or '?'))
  end
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
  if arg == 'info' then Q.info() return end
  if arg == 'obratit' or arg == 'reverse' then
    db.questReverse = not db.questReverse
    Q.sortAt = 0 Q.prepend = nil
    ns.say('Questy: obracene poradi ' .. (db.questReverse and 'zap' or 'vyp'))
    request()
    return
  end
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

------------------------------------------------------------------------------------------
-- Questy partaka (duo): co potrebuje zabit / nasbirat on
--  * zprava Q^typ~klic~mam~potrebuji^...  (typ m = zabit, i = item); posila se pri zmene a kazdych 30 s
--  * moby, ktere potrebuje partak, maji na jmenovce vykricnik v barve jeho classy
--  * kdyz umre mob, ze ktereho partakovi muze padnout questovy item -> zprava QL^, partak
--    dostane upozorneni "lootni" (za zabiti mobu kredit v parte dostanou oba, za item ne)
------------------------------------------------------------------------------------------
Q.peer = {}
local lastQ, lastQAt = nil, 0
local function sendMine(force)
  local D = ns.Duo
  if not (D and D.rawSend and D.ok and IsInGroup and IsInGroup()) or D.encounter then return end
  local parts = {}
  for _, o in ipairs(rebuild()) do
    local k = o.key:gsub('[%^~]', '')
    parts[#parts + 1] = ('%s~%s~%d~%d'):format(o.typ == 'item' and 'i' or 'm', k, o.have or 0, o.need or 0)
  end
  local msg = 'Q'
  for _, p in ipairs(parts) do
    if #msg + #p + 1 > 250 then break end
    msg = msg .. '^' .. p
  end
  local now = GetTime()
  if not force and msg == lastQ and now - lastQAt < 30 then return end
  lastQ, lastQAt = msg, now
  D.rawSend(msg)
end
function Q.recvPeer(name, msg)
  local objs = {}
  for part in msg:gmatch('%^([^%^]+)') do
    local t, k, have, need = part:match('^(%a)~([^~]*)~(%d+)~(%d+)$')
    if t and k ~= '' then
      objs[#objs + 1] = { typ = t == 'i' and 'item' or 'monster', key = k, have = tonumber(have), need = tonumber(need) }
    end
  end
  Q.peer[name] = { at = GetTime(), objs = objs }
  wipe(Q.pcache)
end
Q.pcache = {}
-- potrebuje tohoto moba partak? -> jmeno partaka, cil
function Q.peerNeed(u)
  if not next(Q.peer) or not UnitExists(u) then return nil end
  local name = safe(pc(UnitName, u))
  if type(name) ~= 'string' then return nil end
  local hit = Q.pcache[name]
  local now = GetTime()
  if hit and now - hit.at < 5 then return hit.who, hit.o end
  local ln = name:lower()
  local rec = ns.MobDB and ns.MobDB.forUnit and ns.MobDB.forUnit(u)
  local who, obj
  for pn, p in pairs(Q.peer) do
    if now - p.at < 120 then
      for _, o in ipairs(p.objs) do
        if o.typ == 'monster' and (o.key == ln or o.key:find(ln, 1, true)) then who, obj = pn, o break end
        if o.typ == 'item' and rec then
          for _, d in ipairs(rec.drops or {}) do
            if d.name and d.name:lower() == o.key then who, obj = pn, o break end
          end
          if who then break end
        end
      end
    end
    if who then break end
  end
  Q.pcache[name] = { at = now, who = who, o = obj }
  return who, obj
end

-- smrt moba: z ciliho / mizici jmenovky (AoE, nevybrane moby)
local told = {}
local function onDeath(u)
  if safeBool(pc(UnitIsDead, u)) ~= true then return end
  if safeBool(pc(UnitIsTapDenied, u)) == true then return end   -- cizi mob, loot neni nas
  local who, o = Q.peerNeed(u)
  if not who or not o or o.typ ~= 'item' then return end
  local name = safe(pc(UnitName, u)) or '?'
  local key = safe(pc(UnitGUID, u)) or name
  local now = GetTime()
  if told[key] and now - told[key] < 10 then return end
  told[key] = now
  if ns.Duo and ns.Duo.rawSend and not ns.Duo.encounter then
    ns.Duo.rawSend(('QL^%s^%s'):format((name:gsub('%^', '')), o.key))
  end
end
local df = CreateFrame('Frame')
pcall(df.RegisterEvent, df, 'NAME_PLATE_UNIT_REMOVED')
pcall(df.RegisterEvent, df, 'UNIT_HEALTH')
df:SetScript('OnEvent', function(_, e, u)
  u = safe(u)
  if e == 'UNIT_HEALTH' and u ~= 'target' then return end
  if type(u) == 'string' then pcall(onDeath, u) end
end)
-- partak zabil moba, ze ktereho muze padnout muj questovy item
function Q.recvLoot(name, msg)
  local mob, item = msg:match('^QL%^([^%^]*)%^(.*)$')
  if not mob then return end
  ns.say(('|cffffd100%s zabil %s|r - muze na nem byt tvuj questovy item (%s), lootni.'):format(name, mob, item))
  if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
  elseif PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN) end
end

-- tooltip moba: co z nej potrebuje partak (moje questy ukazuje hra sama)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
    if tt ~= GameTooltip then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and safe(unit) or nil
    if type(unit) ~= 'string' then return end
    local who, o = Q.peerNeed(unit)
    if who and o then
      local cnt = (o.need or 0) > 0 and (' %d/%d'):format(o.have or 0, o.need) or ''
      tt:AddLine(('Quest (%s): %s%s'):format(who, o.typ == 'item' and ('drop ' .. o.key) or o.key, cnt), 1, 0.82, 0)
      tt:Show()
    end
  end)
end

-- posilani: pri zmene questu hned (max 1x za 2 s), jinak kazdych 30 s
local sq = 0
local sf = CreateFrame('Frame')
sf:SetScript('OnUpdate', function(_, el)
  sq = sq + el
  if sq < 2 then return end
  sq = 0
  pcall(sendMine, false)
end)

-- ClaudeMaster: plan trasy questu (s databazi ForeverDB, volitelny addon - GPL-3, viz jeho LICENSE-DATA).
-- Kdyz je ForeverDB nainstalovana, addon si ji na vyzadani nacte a:
--  * z questu v logu sestavi poradi zastavek s co nejkratsi cestou (odevzdat / splnit)
--  * u odevzdani rekne, jaky quest navazuje a kam vede (aby se nelitalo zpatky)
--  * nabidne questy "po ceste" pro tvuj level (quest-giveri u trasy)
--  * pri otevreni mapy letu varuje, co jeste v teto oblasti zbyva
-- /cm trasa = okno s trasou (prvni otevreni databazi nacte - chvili to sekne)
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local R = {}
ns.Route = R
local QL = C_QuestLog
local DB

------------------------------------------------------------------------------------------
-- Databaze
------------------------------------------------------------------------------------------
function R.available()
  if ForeverDB and ForeverDB.quest then return true end
  local get = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
  if not get then return false end
  local name, _, _, loadable, reason = pc(get, 'ForeverDB')
  return name ~= nil and reason ~= 'MISSING'
end
function R.load()
  if DB then return true end
  if not (ForeverDB and ForeverDB.quest) then
    if InCombatLockdown() then return false, 'v boji ne' end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if not load then return false, 'nejde nacist' end
    local ok, loaded, why = pcall(load, 'ForeverDB')
    if not ok or not loaded then return false, tostring(why or 'ForeverDB neni nainstalovana') end
  end
  if not (ForeverDB and ForeverDB.quest and ForeverDB.spm) then return false, 'ForeverDB bez dat' end
  DB = ForeverDB
  if ns.MobDB then
    if ns.MobDB.cacheFresh and not ns.MobDB.cacheFresh() then pcall(ns.MobDB.buildCache) end
    if ns.MobDB.reset then pcall(ns.MobDB.reset) end
  end
  return true
end
-- po prihlaseni: jen kdyz tooltipova cache chybi / je ze starsi verze ForeverDB (jinak se databaze nenacita = setri pamet a FPS)
do
  local f = CreateFrame('Frame')
  pcall(f.RegisterEvent, f, 'PLAYER_ENTERING_WORLD')
  local tries = 0
  local function try()
    if DB or not ns.db or ns.db.fdbAuto == false or not R.available() then return end
    if ns.MobDB and ns.MobDB.cacheFresh and ns.MobDB.cacheFresh() then return end
    tries = tries + 1
    if InCombatLockdown() then if tries < 30 and C_Timer then C_Timer.After(10, try) end return end
    pcall(R.load)
  end
  f:SetScript('OnEvent', function()
    f:UnregisterEvent('PLAYER_ENTERING_WORLD')
    if C_Timer then C_Timer.After(12, try) end
  end)
end

------------------------------------------------------------------------------------------
-- Pozice: mapa (uiMap) + procenta*10 z databaze -> svetove souradnice (yardy)
------------------------------------------------------------------------------------------
local wcache = {}
local function world(map, x, y)
  local key = map .. ':' .. x .. ':' .. y
  local w = wcache[key]
  if w == nil then
    w = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
      local cont, v = pc(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 1000, y / 1000))
      if cont and v then
        local wx, wy = v.x or (v.GetXY and v:GetXY()), v.y
        if type(wx) == 'number' and type(wy) == 'number' then w = { c = cont, x = wx, y = wy } end
      end
    end
    wcache[key] = w
  end
  return w or nil
end
local function playerPos()
  local map = C_Map and safeNum(pc(C_Map.GetBestMapForUnit, 'player'))
  if not map then return nil end
  local p = pc(C_Map.GetPlayerMapPosition, map, 'player')
  if not p then return nil end
  local x, y = p.x, p.y
  if p.GetXY then x, y = p:GetXY() end
  x, y = safeNum(x), safeNum(y)
  if not (x and y) or (x == 0 and y == 0) then return nil end
  local cont, v = pc(C_Map.GetWorldPosFromMapPos, map, p)
  if not cont or not v then return nil end
  return { c = cont, x = v.x, y = v.y, map = map }
end
local function dist(a, b)
  if not (a and b) then return 99999 end
  if a.c ~= b.c then return 99999 end
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end
local function mapName(map)
  local i = C_Map and C_Map.GetMapInfo and pc(C_Map.GetMapInfo, map)
  return type(i) == 'table' and safe(i.name) or ('mapa ' .. tostring(map))
end
-- kontinent / svet -> konkretni zona (aby "Kde levelit" neukazovalo Eastern Kingdoms)
local ctype = {}
local function isContinent(map)
  if ctype[map] == nil then
    local i = C_Map and C_Map.GetMapInfo and pc(C_Map.GetMapInfo, map)
    local t = type(i) == 'table' and safeNum(i.mapType)
    ctype[map] = (t ~= nil and t <= 2) or false
  end
  return ctype[map]
end
local function toZone(map, x, y, w)
  if not (map and x and w and isContinent(map) and C_Map.GetMapInfoAtPosition and CreateVector2D) then return map, x, y end
  local z = pc(C_Map.GetMapInfoAtPosition, map, x / 1000, y / 1000)
  local zid = type(z) == 'table' and safeNum(z.mapID)
  if not zid or zid == map or isContinent(zid) then return map, x, y end
  local um, v = pc(C_Map.GetMapPosFromWorldPos, w.c, CreateVector2D(w.x, w.y), zid)
  if not (um and v and v.x) then return map, x, y end
  return zid, math.floor(v.x * 1000), math.floor(v.y * 1000)
end
-- body jednoho zdroje ("c123" / "o456"): { {map, x, y, w}, ... }
local scache = {}
local function spots(key)
  if scache[key] then return scache[key] end
  local out = {}
  local m = DB.spm[key]
  if type(m) == 'table' then
    for map, xy in pairs(m) do
      for i = 1, #xy - 1, 2 do
        local w = world(map, xy[i], xy[i + 1])
        if w then
          local zm, zx, zy = toZone(map, xy[i], xy[i + 1], w)
          out[#out + 1] = { map = zm, x = zx, y = zy, w = w }
        end
      end
    end
  end
  -- jen svetove souradnice (spw: { {kontinent, x, y, x, y, ...} }) -> mapa pro sipku pres hru
  if #out == 0 and type(DB.spw) == 'table' and type(DB.spw[key]) == 'table' then
    for _, e in ipairs(DB.spw[key]) do
      local cont = e[1]
      -- instance (dungeon) se preskoci: viz R.instance
      for i = 2, (cont == 0 or cont == 1 or cont == 530) and math.min(#e - 1, 12) or 0, 2 do
        local w = { c = cont, x = e[i], y = e[i + 1] }
        local map, mx, my
        if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
          local um, v = pc(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(e[i], e[i + 1]))
          if um and v then map, mx, my = um, math.floor((v.x or 0) * 1000), math.floor((v.y or 0) * 1000) end
          if map then map, mx, my = toZone(map, mx, my, w) end
        end
        out[#out + 1] = { map = map, x = mx, y = my, w = w }
      end
    end
  end
  scache[key] = out
  return out
end
-- dungeony: id instance (spw) -> nazev, vchod (D.dng podle jmena)
local INST = { [30] = 'Alterac Valley', [33] = 'Shadowfang Keep', [34] = 'The Stockade', [36] = 'The Deadmines',
  [43] = 'Wailing Caverns', [47] = 'Razorfen Kraul', [48] = 'Blackfathom Deeps', [70] = 'Uldaman', [90] = 'Gnomeregan',
  [109] = "The Temple of Atal'Hakkar", [129] = 'Razorfen Downs', [189] = 'Scarlet Monastery', [209] = "Zul'Farrak",
  [229] = 'Blackrock Spire', [230] = 'Blackrock Depths', [249] = "Onyxia's Lair", [289] = 'Scholomance', [309] = "Zul'Gurub",
  [329] = 'Stratholme', [349] = 'Maraudon', [369] = 'Deeprun Tram', [389] = 'Ragefire Chasm', [409] = 'Molten Core',
  [429] = 'Dire Maul', [449] = "Champions' Hall", [450] = 'Hall of Legends', [469] = 'Blackwing Lair', [489] = 'Warsong Gulch',
  [509] = "Ruins of Ahn'Qiraj", [529] = 'Arathi Basin', [531] = "Temple of Ahn'Qiraj", [533] = 'Naxxramas' }
local SHOW = { ["The Temple of Atal'Hakkar"] = 'Sunken Temple' }
local entr = {}
local function entrance(name)
  if entr[name] == nil then
    entr[name] = false
    for _, d in pairs(DB.dng or {}) do
      local e = type(d) == 'table' and d[1] == name and type(d[3]) == 'table' and d[3]
      if e then
        local w = world(e[1], e[2], e[3])
        if w then entr[name] = { map = e[1], x = e[2], y = e[3], w = w } break end
      end
    end
  end
  return entr[name] or nil
end
-- { id, name, p = vchod } nebo nil
function R.instance(key)
  local list = type(DB.spw) == 'table' and DB.spw[key]
  if type(list) ~= 'table' then return nil end
  for _, e in ipairs(list) do
    local id = e[1]
    if id ~= 0 and id ~= 1 and id ~= 530 then
      local name = INST[id]
      if not name and GetRealZoneText then local z = safe(pc(GetRealZoneText, id)) if type(z) == 'string' and z ~= '' then name = z end end
      name = name or ('instance ' .. id)
      return { id = id, name = SHOW[name] or name, p = entrance(name) }
    end
  end
end
local function npcName(key)
  local id = tonumber(key:sub(2))
  local t = key:sub(1, 1) == 'c' and DB.npc[id] or DB.obj and DB.obj[id]
  return t and t[1] or key
end
-- nejblizsi bod ze seznamu zdroju
local function nearest(keys, from)
  local best, bd, bk
  for _, k in ipairs(keys or {}) do
    for _, s in ipairs(spots(k)) do
      local d = dist(from, s.w)
      if not bd or d < bd then best, bd, bk = s, d, k end
    end
  end
  return best, bd, bk
end
-- misto plneni questu (qsp: { [map] = {x,y,...} }), nejblizsi bod
local function gameWaypoint(qid)
  -- navigace hry (sipka questu): mapa + pozice dalsiho kroku / odevzdani
  if not (QL.GetNextWaypoint) then return nil end
  local map, x, y = pc(QL.GetNextWaypoint, qid)
  map, x, y = safeNum(map), safeNum(x), safeNum(y)
  if not (map and x and y) then return nil end
  local px, py = math.floor(x * 1000), math.floor(y * 1000)
  local w = world(map, px, py)
  return w and { map = map, x = px, y = py, w = w } or nil
end
local function objective(qid, from)
  local m = DB.qsp and DB.qsp[qid]
  local x = DB.qx and DB.qx[qid]
  if type(m) ~= 'table' and type(x) == 'table' and type(x[16]) == 'table' then m = x[16] end
  if type(m) ~= 'table' then
    local g = gameWaypoint(qid)
    if g then return g, dist(from, g.w) end
    return nil
  end
  local best, bd
  for map, xy in pairs(m) do
    for i = 1, #xy - 1, 2 do
      local w = world(map, xy[i], xy[i + 1])
      local d = w and dist(from, w)
      if w and (not bd or d < bd) then best, bd = { map = map, x = xy[i], y = xy[i + 1], w = w }, d end
    end
  end
  if best then best.map, best.x, best.y = toZone(best.map, best.x, best.y, best.w) end
  return best, bd
end
local function done(qid) return QL.IsQuestFlaggedCompleted and safeBool(pc(QL.IsQuestFlaggedCompleted, qid)) == true end

------------------------------------------------------------------------------------------
-- Hodnota questu: XP (z hry u questu v logu, jinak z databaze s ohledem na level), penize, odmeny
------------------------------------------------------------------------------------------
local function xpFactor(qlvl)
  local lvl = safeNum(pc(UnitLevel, 'player')) or 1
  local d = lvl - (qlvl or lvl)
  if d >= 10 then return 0.1 elseif d >= 9 then return 0.2 elseif d >= 8 then return 0.4
  elseif d >= 7 then return 0.6 elseif d >= 6 then return 0.8 end
  return 1
end
local vcache = {}
local UP = '|TInterface\\AddOns\\ClaudeMaster\\Textures\\UpgradeArrow:12:12|t'
function R.value(qid, inLog)
  local c = vcache[qid]
  if c and GetTime() - c.at < 30 then return c end
  local v = { at = GetTime(), items = {} }
  if inLog and GetQuestLogRewardXP then v.xp = safeNum(pc(GetQuestLogRewardXP, qid)) end
  if inLog and GetQuestLogRewardMoney then v.money = safeNum(pc(GetQuestLogRewardMoney, qid)) end
  if not v.xp or v.xp == 0 then
    local r = DB.qrw and DB.qrw[qid]
    local info = DB.quest[qid]
    if type(r) == 'table' and r[2] then v.xp = math.floor(r[2] * xpFactor(info and info[2])) v.est = true end
  end
  -- odmeny (jen quest v logu - hra je zna presne): nejlepsi vylepseni podle vah gearu
  if inLog and GetQuestLogItemLink then
    local G = ns.Gear
    local function scan(kind, n)
      for i = 1, n do
        local link = safe(pc(GetQuestLogItemLink, kind, i, qid))
        if type(link) == 'string' then
          local it = { link = link, kind = kind }
          if G and G.parse and G.compare and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local st, blocked = G.parse(pc(C_TooltipInfo.GetHyperlink, link))
            if st and not blocked then
              local pct = pc(G.compare, link, st)
              it.pct = safeNum(pct)
            end
          end
          v.items[#v.items + 1] = it
          if it.pct and it.pct > 0.03 and (not v.best or it.pct > v.best.pct) then v.best = it end
        end
      end
    end
    scan('choice', safeNum(pc(GetNumQuestLogChoices, qid, true)) or safeNum(pc(GetNumQuestLogChoices, qid)) or 0)
    scan('reward', safeNum(pc(GetNumQuestLogRewards, qid)) or 0)
  end
  local maxXP = safeNum(pc(UnitXPMax, 'player'))
  v.pctLvl = (v.xp and maxXP and maxXP > 0) and (v.xp / maxXP * 100) or nil
  vcache[qid] = v
  return v
end
-- kratky text hodnoty do radku
function R.valueText(v, noPct)
  local p = {}
  if v.xp and v.xp > 0 then
    local col = (v.pctLvl and v.pctLvl >= 5) and '|cff40ff60' or ((v.pctLvl and v.pctLvl < 1) and '|cff888888' or '|cffffd200')
    p[#p + 1] = ('%s%s%d XP%s|r'):format(col, v.est and '~' or '+', v.xp, (v.pctLvl and not noPct) and (' (%d %%)'):format(math.floor(v.pctLvl + 0.5)) or '')
  end
  if v.best then
    p[#p + 1] = ('%s|cff40ff60%s +%d %%|r'):format(UP, (v.best.link:match('%[(.-)%]') or '?'), math.floor(v.best.pct * 100 + 0.5))
  end
  return table.concat(p, ' ')
end
-- tooltip: vsechny odmeny
function R.valueTip(v)
  local t = {}
  if v.xp then t[#t + 1] = ('XP: %d%s'):format(v.xp, v.pctLvl and (' (%d %% levelu)'):format(math.floor(v.pctLvl + 0.5)) or '') end
  if v.money and v.money > 0 then t[#t + 1] = 'Penize: ' .. (GetCoinTextureString and GetCoinTextureString(v.money) or v.money) end
  for _, it in ipairs(v.items) do
    t[#t + 1] = ('%s %s%s'):format(it.kind == 'choice' and 'na vyber:' or 'odmena:', it.link,
      it.pct and (it.pct > 0.03 and (' |cff40ff60+%d %%|r'):format(math.floor(it.pct * 100 + 0.5))
        or (' |cff888888%d %%|r'):format(math.floor(it.pct * 100 - 0.5))) or '')
  end
  return table.concat(t, '\n')
end

------------------------------------------------------------------------------------------
-- Questy v logu -> zastavky
------------------------------------------------------------------------------------------
local function logQuests()
  local out = {}
  for i = 1, safeNum(pc(QL.GetNumQuestLogEntries)) or 0 do
    local info = pc(QL.GetInfo, i)
    local id = type(info) == 'table' and not info.isHeader and not info.isHidden and safeNum(info.questID)
    if id then
      local comp = QL.IsComplete and safeBool(pc(QL.IsComplete, id))
      out[#out + 1] = { id = id, title = safe(info.title) or (DB.quest[id] and DB.quest[id][1]) or ('#' .. id), complete = comp == true }
    end
  end
  return out
end

-- trasa: nejblizsi soused od hrace (max 10 zastavek)
------------------------------------------------------------------------------------------
-- Parta: questy partaku (RL^id:stav,...; stav 1 = splneno) -> spolecna trasa
------------------------------------------------------------------------------------------
R.peerLogs = {}   -- [jmeno] = { q = { [id] = complete }, at }
local function short(name) return (name or '?'):gsub('%-.*$', '') end
local function inParty(name)
  for i = 1, 4 do
    local u = 'party' .. i
    if UnitExists(u) and short(safe(pc(UnitName, u))) == short(name) then return u end
  end
end
function R.recvLog(name, msg)
  local q, prog = {}, {}
  for e in msg:sub(4):gmatch('[^,]+') do
    local id, c, pr = e:match('^(%d+):(%d):?(.*)$')
    if id then
      q[tonumber(id)] = c == '1'
      if pr and pr ~= '' then prog[tonumber(id)] = pr end
    end
  end
  R.peerLogs[name] = { q = q, prog = prog, at = GetTime() }
end
-- cile questu v mem logu: { {text, done, have, need}, ... }
local function objectives(qid)
  local out = {}
  local l = QL.GetQuestObjectives and pc(QL.GetQuestObjectives, qid)
  for _, o in ipairs(type(l) == 'table' and l or {}) do
    local t = safe(o.text)
    if type(t) == 'string' and t ~= '' then
      local name, a, b = t:match('^(.-):%s*(%d+)%s*/%s*(%d+)$')
      if not name then a, b, name = t:match('^(%d+)%s*/%s*(%d+)%s+(.+)$') end   -- Forever: "0/1 Ancient Egg"
      out[#out + 1] = { text = name or t, done = safeBool(o.finished) == true,
        have = tonumber(a) or safeNum(o.numFulfilled), need = tonumber(b) or safeNum(o.numRequired) }
    end
  end
  return out
end
R.objectives = objectives
-- prvni nesplneny cil s pocty ("5/15") - kompaktni rezim
local function progShort(qid)
  for _, o in ipairs(objectives(qid)) do
    if not o.done and o.need and o.need >= 1 then return (o.have or 0) .. '/' .. o.need end
  end
end
-- vsechny cile pro partu: "5/15+0/1" (cil bez poctu = 1/1 nebo 0/1)
local function progAll(qid)
  local p = {}
  for _, o in ipairs(objectives(qid)) do
    local need = o.need or 1
    local have = o.need and (o.have or 0) or (o.done and 1 or 0)
    if o.done then have = need end
    p[#p + 1] = have .. '/' .. need
  end
  return p[1] and table.concat(p, '+') or nil
end
local function parseProg(s)
  local out = {}
  for a, b in (s or ''):gmatch('(%d+)/(%d+)') do out[#out + 1] = { have = tonumber(a), need = tonumber(b) } end
  return out
end
local lastLog, lastLogAt = nil, -99
local function sendLog()
  local D = ns.Duo
  if not (D and D.rawSend and D.ok and IsInGroup and IsInGroup()) or not QL.GetNumQuestLogEntries then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local parts, len = {}, 3
  for i = 1, safeNum(pc(QL.GetNumQuestLogEntries)) or 0 do
    local info = pc(QL.GetInfo, i)
    local id = type(info) == 'table' and not info.isHeader and not info.isHidden and safeNum(info.questID)
    if id then
      local comp = QL.IsComplete and safeBool(pc(QL.IsComplete, id))
      local pr = not comp and progAll(id)
      local p = id .. ':' .. (comp and '1' or '0') .. (pr and (':' .. pr) or '')
      if len + #p + 1 > 250 then break end
      parts[#parts + 1] = p len = len + #p + 1
    end
  end
  local msg = 'RL^' .. table.concat(parts, ',')
  local now = GetTime()
  if msg == lastLog and now - lastLogAt < 45 then return end
  lastLog, lastLogAt = msg, now
  D.rawSend(msg)
end
R.sendLog = sendLog
-- aktivni partaci s addonem (posledni log mladsi nez 2 min a jsou v parte)
local function peers()
  local out = {}
  for name, l in pairs(R.peerLogs) do
    if GetTime() - l.at < 120 and inParty(name) then out[#out + 1] = { name = name, unit = inParty(name), q = l.q, prog = l.prog or {} } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
R.peers = peers
-- pozice clena party (stejny start trasy pro vsechny = stejna trasa)
local function unitPos(unit)
  if unit == 'player' then return playerPos() end
  local map = C_Map and safeNum(pc(C_Map.GetBestMapForUnit, unit))
  local p = map and pc(C_Map.GetPlayerMapPosition, map, unit)
  if not p then return nil end
  local x, y = p.x, p.y
  if p.GetXY then x, y = p:GetXY() end
  if not (safeNum(x) and safeNum(y)) or (x == 0 and y == 0) then return nil end
  local cont, v = pc(C_Map.GetWorldPosFromMapPos, map, p)
  if not cont or not v then return nil end
  return { c = cont, x = v.x, y = v.y, map = map }
end

function R.plan()
  if not DB then return nil, 'databaze neni nactena' end
  local me = playerPos()
  if not me then return nil, 'pozice neni k dispozici (instance?)' end
  local myName = short(safe(pc(UnitName, 'player')))
  -- kdo ma jaky quest: [id] = { title, obj = {jmena}, turn = {jmena}, mine = 'obj'/'turnin' }
  local Qs = {}
  local function note(id, who, complete, title)
    local e = Qs[id] or { id = id, title = title or (DB.quest[id] and DB.quest[id][1]) or ('#' .. id), obj = {}, turn = {} }
    if title then e.title = title end
    table.insert(complete and e.turn or e.obj, who)
    Qs[id] = e
  end
  for _, q in ipairs(logQuests()) do note(q.id, myName, q.complete, q.title) end
  local ps = peers()
  for _, pr in ipairs(ps) do for id, c in pairs(pr.q) do if DB.quest[id] then note(id, short(pr.name), c) end end end
  -- start: hrac s abecedne prvnim jmenem (u vsech stejny) - kdyz jeho pozici zname
  local start = me
  if #ps > 0 then
    local names = { { n = myName, u = 'player' } }
    for _, pr in ipairs(ps) do names[#names + 1] = { n = short(pr.name), u = pr.unit } end
    table.sort(names, function(a, b) return a.n < b.n end)
    start = unitPos(names[1].u) or me
  end
  local stops, ids = {}, {}
  for id in pairs(Qs) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = Qs[id]
    local q = { id = id, title = e.title }
    if #e.turn > 0 then stops[#stops + 1] = { q = q, kind = 'turnin', keys = DB.qe[id] or {}, who = e.turn } end
    if #e.obj > 0 then stops[#stops + 1] = { q = q, kind = 'obj', who = e.obj } end
  end
  local function mineIn(s) for _, w in ipairs(s.who) do if w == myName then return true end end end
  local function locate(s, pos)
    if s.kind == 'turnin' then
      local p, d, k = nearest(s.keys, pos)
      if not p and mineIn(s) then p = gameWaypoint(s.q.id) d = p and dist(pos, p.w) end
      return p, d, k
    end
    return objective(s.q.id, pos)
  end
  local route, pos, left = {}, start, stops
  while #left > 0 and #route < 10 do
    local bi, bp, bd, bk
    for i, s in ipairs(left) do
      local p, d, k = locate(s, pos)
      if p and (not bd or d < bd - 0.01) then bi, bp, bd, bk = i, p, d, k end
    end
    if not bi then break end
    local s = table.remove(left, bi)
    s.p, s.d, s.npc, s.mine = bp, dist(me, bp.w), bk, mineIn(s)
    -- na stejnem miste (u stejneho NPC / do 40 yd) se vyridi i dalsi questy
    s.also = {}
    for i = #left, 1, -1 do
      local o = left[i]
      local p, d, k = locate(o, bp.w)
      if p and (d < 40 or (k and k == bk)) then
        table.remove(left, i)
        o.p, o.npc, o.mine = p, k, mineIn(o)
        table.insert(s.also, 1, o)
      end
    end
    -- navazujici quest (qx[7]) po odevzdani
    if s.kind == 'turnin' then
      local x = DB.qx[s.q.id]
      local nxt = type(x) == 'table' and x[7]
      if nxt and DB.quest[nxt] and not done(nxt) and not R.inLogSet()[nxt] then
        local op = objective(nxt, bp.w)
        s.next = { id = nxt, title = DB.quest[nxt][1], where = op and mapName(op.map) or nil, v = R.value(nxt, false),
          far = op and dist(bp.w, op.w) or nil }
      end
    end
    route[#route + 1] = s
    pos = bp.w
  end
  R.lastRoute, R.lastMe, R.lastMyName = route, me, myName
  return route
end

-- questy k vzeti blizko trasy (giver do 250 yd od tebe nebo 150 yd od zastavky)
local myFac
local function factionOk(key)
  if not myFac then
    local f = safe(pc(UnitFactionGroup, 'player'))
    myFac = f == 'Horde' and 'H' or 'A'
  end
  local id = tonumber(key:sub(2))
  local nf = DB.nfac and key:sub(1, 1) == 'c' and DB.nfac[id]
  return not nf or nf:find(myFac, 1, true) ~= nil
end
local pickAt, pickCache = -99, nil
function R.pickups(route)
  if not DB then return {} end
  if pickCache and GetTime() - pickAt < 10 then return pickCache end
  local me = R.lastMe or playerPos()
  if not me then return {} end
  local inLog = {}
  for _, q in ipairs(logQuests()) do inLog[q.id] = true end
  local lvl = safeNum(pc(UnitLevel, 'player')) or 1
  local pts = { me }
  for _, s in ipairs(route or {}) do if s.p then pts[#pts + 1] = s.p.w end end
  local out = {}
  for qid, givers in pairs(DB.qg) do
    local info = DB.quest[qid]
    if info and not inLog[qid] and (info[3] or 1) <= lvl and (info[2] or lvl) >= lvl - 4 and (info[2] or 0) <= lvl + 3 then
      local x = DB.qx[qid]
      local pre = type(x) == 'table' and x[3]
      local ok = true
      if type(pre) == 'table' then for _, p in ipairs(pre) do if not done(p) then ok = false break end end end
      if ok and not done(qid) then
        for _, k in ipairs(givers) do
          if factionOk(k) then
            for _, s in ipairs(spots(k)) do
              local d0 = dist(me, s.w)
              local near = d0 < 250
              if not near then for i = 2, #pts do if dist(pts[i], s.w) < 150 then near = true break end end end
              if near then
                out[#out + 1] = { id = qid, title = info[1], lvl = info[2], npc = npcName(k), p = s, d = d0, v = R.value(qid, false) }
                break
              end
            end
          end
          if out[#out] and out[#out].id == qid then break end
        end
      end
    end
  end
  -- vyhodnost: XP za cestu (bliz a vic XP = driv)
  local function score(q) return ((q.v and q.v.xp) or 0) / (q.d + 150) end
  table.sort(out, function(a, b) return score(a) > score(b) end)
  while #out > 6 do table.remove(out) end
  pickCache, pickAt = out, GetTime()
  return out
end

------------------------------------------------------------------------------------------
-- Sipka na mape
------------------------------------------------------------------------------------------
function R.waypoint(p, title)
  if not (p and p.map and p.x and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
  local pt = UiMapPoint.CreateFromCoordinates(p.map, p.x / 1000, p.y / 1000)
  pc(C_Map.SetUserWaypoint, pt)
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pc(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  ns.say('Sipka: ' .. (title or '?'))
end

-- aktivovat quest jako ve hre (zluta oblast na mape, sipka, nahore v seznamu); kdyz ho hra na mape
-- nezna (casto na Foreveru) nebo neni v logu, sipka na misto z databaze. Shift = otevrit mapu.
function R.focus(qid, p, title)
  local inLog = qid and QL.GetLogIndexForQuestID and (safeNum(pc(QL.GetLogIndexForQuestID, qid)) or 0) > 0
  if inLog then
    local w = QL.GetQuestWatchType and pc(QL.GetQuestWatchType, qid)
    if w == nil and QL.AddQuestWatch and not InCombatLockdown() then pc(QL.AddQuestWatch, qid) end
    -- zna hra polohu? (quest je na mape cile / hra ma dalsi bod cesty)
    local known = gameWaypoint(qid) ~= nil
    if not known and p and p.map and QL.GetQuestsOnMap then
      local l = pc(QL.GetQuestsOnMap, p.map)
      for _, q in ipairs(type(l) == 'table' and l or {}) do if safeNum(q.questID) == qid then known = true break end end
    end
    if known and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
      if C_Map and C_Map.ClearUserWaypoint then pc(C_Map.ClearUserWaypoint) end
      pc(C_SuperTrack.SetSuperTrackedQuestID, qid)
      ns.say('Aktivni quest: ' .. (title or ('#' .. qid)))
    elseif p then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pc(C_SuperTrack.SetSuperTrackedQuestID, qid) end
      R.waypoint(p, title)
    elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
      pc(C_SuperTrack.SetSuperTrackedQuestID, qid)
      ns.say('Aktivni quest: ' .. (title or ('#' .. qid)) .. ' (polohu hra ani databaze nezna)')
    end
    if ns.Quests and ns.Quests.update then pcall(ns.Quests.update) end
  elseif p then
    R.waypoint(p, title)
  end
  -- Shift: otevrit mapu na zone cile
  if IsShiftKeyDown and IsShiftKeyDown() and p and p.map and not InCombatLockdown() then
    if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
    if WorldMapFrame and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, p.map) end
  end
end

-- PvP quest: battleground zona v databazi (AV / WSG / AB / kategorie Battlegrounds) nebo stitek hry "PvP"
local BG = { [2597] = true, [3277] = true, [3358] = true, [-25] = true }
local pvpc = {}
function R.isPvP(qid)
  if not qid then return false end
  if pvpc[qid] ~= nil then return pvpc[qid] end
  local x = DB and DB.qx and DB.qx[qid]
  local r = type(x) == 'table' and BG[x[11]] == true or false
  local sure = r or not QL.GetQuestTagInfo
  if not r and QL.GetQuestTagInfo then
    local t = pc(QL.GetQuestTagInfo, qid)
    if type(t) == 'table' then
      local id, nm = safeNum(t.tagID), safe(t.tagName)
      r = id == 41 or (type(nm) == 'string' and nm:find('PvP') ~= nil)
      sure = true
    end
  end
  if sure then pvpc[qid] = r end   -- hra data questu jeste nema: zkusit priste
  return r
end
local function pvpIcon()
  local f = safe(pc(UnitFactionGroup, 'player'))
  return '|TInterface\\Icons\\INV_BannerPVP_0' .. (f == 'Horde' and '2' or '1') .. ':14:14:0:0:64:64:5:59:5:59|t'
end

-- hezci tooltip kroku: nazev, co a kde, odmeny, cile (vc. partaka)
local function richTip(tt)
  local G = GameTooltip
  G:AddLine(tt.title, 1, 0.82, 0)
  if tt.pvp then G:AddLine(pvpIcon() .. ' PvP quest', 1, 0.35, 0.35) end
  G:AddDoubleLine(tt.action, tt.dist or '', 1, 1, 1, 0.7, 0.7, 0.7)
  if tt.zone then G:AddDoubleLine('Zona', tt.zone, 0.55, 0.6, 0.7, 1, 1, 1) end
  if tt.who then G:AddDoubleLine('Parta', tt.who, 0.55, 0.6, 0.7, 0.4, 0.8, 1) end
  local v = tt.v
  if v and (v.xp or (v.money and v.money > 0) or (v.items and v.items[1])) then
    G:AddLine(' ')
    if v.xp and v.xp > 0 then
      G:AddDoubleLine('XP', ('%s%d|r%s'):format(v.est and '|cffffd200~' or '|cffffd200', v.xp,
        v.pctLvl and ('  |cff888888(%d %% levelu)|r'):format(math.floor(v.pctLvl + 0.5)) or ''), 0.55, 0.6, 0.7, 1, 1, 1)
    end
    if v.money and v.money > 0 then
      G:AddDoubleLine('Penize', GetCoinTextureString and GetCoinTextureString(v.money) or tostring(v.money), 0.55, 0.6, 0.7, 1, 1, 1)
    end
    for _, it in ipairs(v.items or {}) do
      local pct = it.pct and (it.pct > 0.03 and (' |cff40ff60+%d %%|r'):format(math.floor(it.pct * 100 + 0.5))
        or (' |cff888888%d %%|r'):format(math.floor(it.pct * 100 - 0.5))) or ''
      G:AddDoubleLine(it.kind == 'choice' and 'Na vyber' or 'Odmena', it.link .. pct, 0.55, 0.6, 0.7, 1, 1, 1)
    end
  end
  if tt.objs and tt.objs[1] then
    G:AddLine(' ')
    G:AddLine('Cile', 0.4, 0.8, 1)
    for _, o in ipairs(tt.objs) do G:AddDoubleLine(o[1], o[2] or '', 1, 1, 1, 1, 1, 1) end
  end
end

------------------------------------------------------------------------------------------
-- Okno
------------------------------------------------------------------------------------------
local frame
local function yd(d) return d and d < 99999 and (math.floor(d + 0.5) .. ' yd') or 'jiny kontinent' end
local RH = 30
local function cfg() return ns.db end
local function W() return math.max(300, math.min(900, (cfg() and cfg().routeW) or 440)) end
local function openQuest(qid)
  if not (qid and ns.Options and ns.Options.toggle and ns.Explore) then return end
  ns.Options.toggle('explore')
  if ns.Options.exploreShow then ns.Options.exploreShow(ns.Explore.quest(qid)) end
end
local icon
local function applyLook(f)
  local T = ns.THEME
  local tr = cfg().routeAlpha
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], tr and 0.3 or 0.94)
  local b = T.border
  f:SetBackdropBorderColor(b[1], b[2], b[3], tr and 0.15 or (b[4] or 1))
  if f.btns then
    f.btns.c.t:SetTextColor(cfg().routeCompact and 1 or 0.55, cfg().routeCompact and 0.82 or 0.6, cfg().routeCompact and 0 or 0.7)
    f.btns.a.t:SetTextColor(tr and 1 or 0.55, tr and 0.82 or 0.6, tr and 0 or 0.7)
  end
end
local function build()
  local f = CreateFrame('Frame', 'ClaudeMasterRoute', UIParent, 'BackdropTemplate')
  f:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
  local T = ns.THEME
  f:SetFrameStrata('MEDIUM') f:SetSize(W(), 200)
  f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag('LeftButton') f:SetClampedToScreen(true)
  if f.SetResizeBounds then f:SetResizeBounds(300, 80, 900, 1000) elseif f.SetMinResize then f:SetMinResize(300, 80) f:SetMaxResize(900, 1000) end
  f:SetResizable(true)
  f:SetScript('OnDragStart', f.StartMoving)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.routePoint = { p, rp, x, y }
  end)
  local pt = ns.db.routePoint
  if pt then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint('RIGHT', -260, 80) end
  f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') f.title:SetPoint('TOPLEFT', 10, -8)
  f.title:SetText('Trasa questu') f.title:SetTextColor(unpack(T.title))
  f.sum = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') f.sum:SetPoint('TOPLEFT', 10, -24)
  f.sum:SetTextColor(0.6, 0.65, 0.73)
  local sh = CreateFrame('Frame', nil, f)
  sh:SetPoint('TOPLEFT', f.sum, 'TOPLEFT', -2, 2) sh:SetPoint('BOTTOMRIGHT', f.sum, 'BOTTOMRIGHT', 2, -2)
  sh:EnableMouse(true)
  sh:SetScript('OnEnter', function(self)
    if not R.sumTip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_TOP') GameTooltip:AddLine(R.sumTip, 1, 1, 1, true) GameTooltip:Show()
  end)
  sh:SetScript('OnLeave', function() GameTooltip:Hide() end)
  -- tlacitka v hlavicce: kompaktni / pruhledny / minimalizovat / zavrit
  local function hb(txt, tipT, tipD, onClick)
    local b = CreateFrame('Button', nil, f)
    b:SetSize(18, 18)
    b.t = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') b.t:SetPoint('CENTER') b.t:SetText(txt)
    b:SetHighlightTexture('Interface\\Buttons\\WHITE8X8', 'ADD') b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    b:SetScript('OnClick', onClick)
    b:SetScript('OnEnter', function(self)
      GameTooltip:SetOwner(self, 'ANCHOR_TOP') GameTooltip:AddLine(tipT, 1, 1, 1) GameTooltip:AddLine(tipD, 0.8, 0.8, 0.8, true) GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    return b
  end
  local x = CreateFrame('Button', nil, f, 'UIPanelCloseButton') x:SetSize(20, 20) x:SetPoint('TOPRIGHT', 2, 2)
  x:SetScript('OnClick', function() cfg().routeOpen, cfg().routeMin = nil, nil f:Hide() end)
  f.btns = {}
  f.btns.m = hb('_', 'Minimalizovat', 'Schova okno do ikony. Najeti na ikonu ukaze trasu, klik ji zase otevre.', function() R.minimize(true) end)
  f.btns.m:SetPoint('RIGHT', x, 'LEFT', -2, 0)
  f.btns.a = hb('T', 'Pruhledny rezim', 'Skoro pruhledne pozadi, okno tolik neprekazi.', function()
    cfg().routeAlpha = not cfg().routeAlpha or nil applyLook(f) R.refresh() end)
  f.btns.a:SetPoint('RIGHT', f.btns.m, 'LEFT', -2, 0)
  f.btns.c = hb('K', 'Kompaktni rezim', 'Jeden radek na krok, bez podrobnosti (ty jsou v tooltipu).', function()
    cfg().routeCompact = not cfg().routeCompact or nil applyLook(f) R.refresh() end)
  f.btns.c:SetPoint('RIGHT', f.btns.a, 'LEFT', -2, 0)
  -- zmena velikosti (sirka + max. vyska), kolecko = posun
  local grip = CreateFrame('Button', nil, f)
  grip:SetSize(14, 14) grip:SetPoint('BOTTOMRIGHT', -1, 1) grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
  grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
  grip:SetScript('OnMouseDown', function() f.sizing = true f:StartSizing('BOTTOMRIGHT') end)
  grip:SetScript('OnMouseUp', function()
    f:StopMovingOrSizing() f.sizing = false
    cfg().routeW = math.floor(f:GetWidth() + 0.5) cfg().routeH = math.floor(f:GetHeight() + 0.5)
    local p, _, rp, xx, yy = f:GetPoint() cfg().routePoint = { p, rp, xx, yy }
    R.refresh()
  end)
  grip:SetScript('OnDoubleClick', function() cfg().routeW, cfg().routeH = nil, nil f:SetWidth(W()) R.refresh() end)
  grip:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_TOP') GameTooltip:AddLine('Velikost okna', 1, 1, 1)
    GameTooltip:AddLine('Tahni za roh (sirka a max. vyska). Dvojklik = puvodni. Kolecko mysi = posun seznamu.', 0.8, 0.8, 0.8, true) GameTooltip:Show()
  end)
  grip:SetScript('OnLeave', function() GameTooltip:Hide() end)
  f.scroll, f.sizing = 0, false
  f:EnableMouseWheel(true)
  f:SetScript('OnMouseWheel', function(_, d) f.scroll = math.max(0, (f.scroll or 0) - d * 2) R.refresh() end)
  f.rows = {}
  for i = 1, 40 do
    local b = CreateFrame('Button', nil, f)
    b:SetSize(W() - 12, RH)
    b.bg = b:CreateTexture(nil, 'BACKGROUND') b.bg:SetAllPoints()
    b.stripe = b:CreateTexture(nil, 'ARTWORK') b.stripe:SetTexture('Interface\\Buttons\\WHITE8X8') b.stripe:SetWidth(2)
    b.stripe:SetPoint('TOPLEFT') b.stripe:SetPoint('BOTTOMLEFT')
    b.num = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') b.num:SetPoint('LEFT', 6, 0) b.num:SetWidth(18) b.num:SetJustifyH('RIGHT')
    b.text = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight') b.text:SetJustifyH('LEFT') b.text:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.sub:SetJustifyH('LEFT') b.sub:SetWordWrap(false)
    b.sub:SetTextColor(0.6, 0.64, 0.72)
    b.right = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.right:SetJustifyH('RIGHT')
    b.right2 = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.right2:SetPoint('BOTTOMRIGHT', -6, 3) b.right2:SetJustifyH('RIGHT')
    b.right2:SetTextColor(0.6, 0.64, 0.72)
    b:SetHighlightTexture('Interface\\Buttons\\WHITE8X8', 'ADD') b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    b:SetScript('OnClick', function(self, btn)
      -- navazujici quest: klik = detail; krok: klik = sipka, pravy klik = detail
      if self.qid and (btn == 'RightButton' or self.detailFirst) then openQuest(self.qid) return end
      if self.qid or self.p then R.focus(self.qid, self.p, self.label) end
    end)
    b:SetScript('OnEnter', function(self)
      if not (self.tip or self.qid or self.tt) then return end
      GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
      if self.tt then richTip(self.tt)
      elseif self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
      GameTooltip:AddLine(' ')
      local H = { 0.45, 0.5, 0.58 }
      if self.detailFirst then GameTooltip:AddLine('Klik: detail questu', H[1], H[2], H[3])
      else
        if self.qid then GameTooltip:AddLine('Klik: aktivovat  -  Shift: i mapa  -  Pravy: detail', H[1], H[2], H[3])
        elseif self.p then GameTooltip:AddLine('Klik: sipka na mape', H[1], H[2], H[3]) end
      end
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    f.rows[i] = b
  end
  applyLook(f)
  f:Hide()
  return f
end

local KIND = { turnin = { '|TInterface\\RaidFrame\\ReadyCheck-Ready:15:15|t', 0.25, 1, 0.38, 'Odevzdat' },
  obj = { '|TInterface\\GossipFrame\\IncompleteQuestIcon:15:15|t', 1, 0.82, 0, 'Splnit' } }
-- zona mapy (podzona / mesto / patro -> zona), at jde porovnat "tady" vs. jinde
local zcache = {}
local function zoneOf(map)
  if not map then return nil end
  if zcache[map] ~= nil then return zcache[map] or nil end
  local m, guard = map, 0
  while m and guard < 6 do
    local i = C_Map and C_Map.GetMapInfo and pc(C_Map.GetMapInfo, m)
    local t = type(i) == 'table' and safeNum(i.mapType)
    if not t or t <= 3 then break end
    m = safeNum(i.parentMapID) guard = guard + 1
  end
  zcache[map] = m or false
  return m
end
-- obsah trasy (bez vykresleni): radky + souhrn
local function collect()
  local lines = {}
  local function add(l) lines[#lines + 1] = l end
  local sumXP, steps = 0, 0
  if not DB then
    add({ msg = '|cffff8855ForeverDB neni nactena.|r' })
  else
    local route, why = R.plan()
    if not route then add({ msg = '|cff9aa6b8' .. tostring(why) .. '|r' })
    else
      if #route == 0 then add({ msg = '|cff9aa6b8Zadne questy v logu se znamou polohou.|r' }) end
      local me = R.lastMyName
      local function whoTag(s)
        local others = {}
        for _, w in ipairs(s.who or {}) do if w ~= me then others[#others + 1] = w end end
        if #others == 0 then return '' end
        return s.mine and (' |cff66ccff(i ' .. table.concat(others, ', ') .. ')|r') or (' |cff66ccff[' .. table.concat(others, ', ') .. ']|r')
      end
      local myZone = R.lastMe and zoneOf(R.lastMe.map)
      local function here(p) return p and p.map and myZone and zoneOf(p.map) == myZone end
      for i, s in ipairs(route) do
        local where = s.p and mapName(s.p.map) or '?'
        local isHere = here(s.p)
        local v = s.mine and R.value(s.q.id, true) or R.value(s.q.id, false)
        steps = steps + 1
        if s.mine and s.kind == 'turnin' and v.xp then sumXP = sumXP + v.xp end
        local k = KIND[s.kind]
        -- cile (jen rozpracovane): moje pocty + postup partaku
        local obj = (s.kind == 'obj' and s.mine) and objectives(s.q.id) or {}
        -- postup partaku po cilech: [i] = { "Cherri 0/12", ... }
        local peerAt, peerAny = {}, false
        if s.kind == 'obj' then
          for _, pr in ipairs(R.peers()) do
            local pg = pr.prog and pr.prog[s.q.id]
            for i, c in ipairs(parseProg(pg)) do
              local col = c.have >= c.need and '|cff40ff60' or '|cff66ccff'
              peerAt[i] = peerAt[i] or {}
              table.insert(peerAt[i], ('%s%s %d/%d|r'):format(col, short(pr.name), c.have, c.need))
              peerAny = true
            end
          end
        end
        local function peerTxt(i) return peerAt[i] and ('  ' .. table.concat(peerAt[i], ', ')) or '' end
        local objTip = {}
        for i, o in ipairs(obj) do
          objTip[#objTip + 1] = (o.done and '|cff40ff60' or '|cffffffff') .. (o.need and ((o.have or 0) .. '/' .. o.need .. ' ') or '- ') .. o.text .. '|r' .. peerTxt(i)
        end
        if not obj[1] and peerAny then
          for i in ipairs(peerAt) do objTip[#objTip + 1] = (i .. '. cil:') .. peerTxt(i) end
        end
        local ps = s.mine and s.kind == 'obj' and progShort(s.q.id)
        -- v teto zone: kdo / kde + vzdalenost; jinde jen zona
        local sub
        if isHere then sub = s.kind == 'turnin' and (s.npc and npcName(s.npc) or '?') or 'misto plneni'
        else sub = where end
        local objs = {}
        for oi, o in ipairs(obj) do
          objs[#objs + 1] = { (o.done and '|cff40ff60' or '|cffffffff') .. (o.need and ((o.have or 0) .. '/' .. o.need .. ' ') or '') .. o.text .. '|r', peerTxt(oi) }
        end
        if not obj[1] and peerAny then for oi in ipairs(peerAt) do objs[#objs + 1] = { (oi .. '. cil'), peerTxt(oi) } end end
        local others = {}
        for _, w in ipairs(s.who or {}) do if w ~= me then others[#others + 1] = w end end
        local pvp = R.isPvP(s.q.id)
        local tt = { title = s.q.title, zone = where, dist = yd(s.d), v = s.mine and v or nil, objs = objs, pvp = pvp,
          who = others[1] and (s.mine and ('ty + ' .. table.concat(others, ', ')) or (table.concat(others, ', ') .. ' (ty ho nemas)')) or nil,
          action = s.kind == 'turnin' and ('|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff40ff60Odevzdat|r u ' .. (s.npc and npcName(s.npc) or '?'))
            or '|TInterface\\GossipFrame\\IncompleteQuestIcon:14:14|t |cffffd200Splnit|r - misto plneni' }
        local pv = pvp and (pvpIcon() .. ' ') or ''
        add({ num = i, color = k, first = i == 1, tt = tt, text = k[1] .. ' ' .. pv .. s.q.title .. whoTag(s), right = s.mine and R.valueText(v, true) or '',
          ctext = k[1] .. ' ' .. pv .. s.q.title .. (ps and (' |cffffffff' .. ps .. '|r') or '') .. whoTag(s), objTip = objTip,
          sub = sub, right2 = isHere and yd(s.d) or '', p = s.p, label = s.q.title, qid = s.q.id, short = s.q.title,
          tip = k[5] .. ': ' .. s.q.title .. '\n' .. (s.kind == 'turnin' and ('Odevzdat u %s (%s)'):format(s.npc and npcName(s.npc) or '?', where) or ('Misto plneni: ' .. where))
            .. (isHere and '' or (', ' .. yd(s.d))) .. '\n' .. R.valueTip(v) })
        -- radky cilu pod krokem (jako seznam questu ve hre); v kompaktnim rezimu jen v tooltipu
        local nobj = 0
        for i, o in ipairs(obj) do
          nobj = nobj + 1
          if nobj > 4 then break end
          add({ small = true, obj = true, qid = s.q.id, p = s.p, label = s.q.title,
            text = ('        %s%s%s|r%s'):format(o.done and '|cff40ff60' or '|cffdddddd', o.need and ((o.have or 0) .. '/' .. o.need .. ' ') or '- ', o.text, peerTxt(i)) })
        end
        -- quest ma jen partak (moje cile nezname): aspon jeho pocty
        if not obj[1] and peerAny then
          for i in ipairs(peerAt) do
            if i > 4 then break end
            add({ small = true, obj = true, qid = s.q.id, p = s.p, label = s.q.title, text = '        ' .. peerTxt(i):sub(3) })
          end
        end
        for _, o in ipairs(s.also or {}) do
          local ov = o.mine and R.value(o.q.id, true)
          if o.mine and o.kind == 'turnin' and ov and ov.xp then sumXP = sumXP + ov.xp end
          local who = {}
          for _, w in ipairs(o.who or {}) do who[#who + 1] = (w == me) and 'ty' or w end
          local verb = #who > 1 and { 'odevzdate', 'splnite' } or (who[1] == 'ty' and { 'odevzdas', 'splnis' } or { 'odevzda', 'splni' })
          add({ small = true, text = ('      |cff66ccff+|r %s tu %s |cff9aa6b8i:|r %s %s'):format(table.concat(who, ' + '),
            o.kind == 'turnin' and ('|cff40ff60' .. verb[1] .. '|r') or ('|cffffd200' .. verb[2] .. '|r'), o.q.title, ov and R.valueText(ov, true) or ''),
            p = o.p, label = o.q.title, qid = o.q.id, tip = 'Na stejnem miste: ' .. o.q.title })
        end
        if s.next then
          local far = s.next.far and s.next.far > 400
          add({ small = true, qid = s.next.id, detailFirst = true, tip = 'Navazujici quest: ' .. s.next.title,
            text = ('      |cffffd200->|r |cff9aa6b8navazuje:|r %s %s%s'):format(s.next.title, R.valueText(s.next.v, true),
            s.next.where and (' |cff9aa6b8(' .. s.next.where .. (far and ', daleko' or ', blizko') .. ')|r') or '') })
        end
      end
      local pick = R.pickups(route)
      if #pick > 0 then
        add({ head = 'Po ceste muzes vzit' })
        -- nejdriv questy v teto zone (zvyraznene), pak ostatni (tlumene, jen zona)
        local near, far = {}, {}
        for _, q in ipairs(pick) do table.insert(here(q.p) and near or far, q) end
        local ICO = '|TInterface\\GossipFrame\\AvailableQuestIcon:15:15|t '
        for _, q in ipairs(near) do
          local pvp = R.isPvP(q.id)
          add({ tt = { title = ('[%d] %s'):format(q.lvl or 0, q.title), zone = mapName(q.p.map), dist = yd(q.d), v = q.v, pvp = pvp,
              action = '|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t |cffffd200Vzit|r u ' .. q.npc },
            text = ICO .. (pvp and (pvpIcon() .. ' ') or '') .. ('|cff9aa6b8[%d]|r |cffffffff%s|r'):format(q.lvl or 0, q.title), right = R.valueText(q.v, true), sub = q.npc,
            right2 = yd(q.d), p = q.p, label = q.title, qid = q.id, color = { '', 0.3, 1, 0.45 }, first = q.d and q.d < 400, bright = true,
            tip = ('Quest dava %s (%s), %s\n%s'):format(q.npc, mapName(q.p.map), yd(q.d), R.valueTip(q.v)) })
        end
        for _, q in ipairs(far) do
          local pvp = R.isPvP(q.id)
          add({ tt = { title = ('[%d] %s'):format(q.lvl or 0, q.title), zone = mapName(q.p.map), dist = yd(q.d), v = q.v, pvp = pvp,
              action = '|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t |cffffd200Vzit|r u ' .. q.npc },
            text = (pvp and (pvpIcon() .. ' ') or '') .. ('|cff777777[%d] %s|r'):format(q.lvl or 0, q.title), right = R.valueText(q.v, true), sub = mapName(q.p.map),
            right2 = '', p = q.p, label = q.title, qid = q.id, color = { '', 0.4, 0.5, 0.6 },
            tip = ('Quest dava %s (%s), %s\n%s'):format(q.npc, mapName(q.p.map), yd(q.d), R.valueTip(q.v)) })
        end
      end
    end
  end
  local maxXP = safeNum(pc(UnitXPMax, 'player'))
  local sum = steps > 0 and ('%d krok%s  -  odevzdanim ziskas |cffffd200+%d XP|r'):format(steps, steps == 1 and '' or (steps < 5 and 'y' or 'u'), sumXP) or ''
  R.sumTip = (steps > 0 and maxXP and maxXP > 0) and ('Odevzdanim vsech kroku ziskas %d XP = %d %% levelu.'):format(sumXP, math.floor(sumXP / maxXP * 100 + 0.5)) or nil
  return lines, sum, steps
end

function R.refresh()
  if not frame or not frame:IsShown() or frame.sizing then return end
  local lines, sum = collect()
  local compact, tr = cfg().routeCompact, cfg().routeAlpha
  local w = W()
  local np = #R.peers()
  frame:SetWidth(w)
  frame.title:SetText(np > 0 and ('Trasa questu |cff66ccff- parta (%d)|r'):format(np + 1) or 'Trasa questu')
  frame.sum:SetText(sum) frame.sum:SetShown(not compact)
  local maxH = cfg().routeH
  local rh = compact and 17 or RH
  local y, odd = compact and -26 or -42, false
  local start = math.min(frame.scroll or 0, math.max(0, #lines - 1))
  frame.scroll = start
  if compact then
    local f = {}
    for _, l in ipairs(lines) do if not l.obj then f[#f + 1] = l end end
    lines = f
  end
  local sup = ns.Quests and ns.Quests.superId and ns.Quests.superId()
  local shown = 0
  for i, r in ipairs(frame.rows) do
    local l = lines[i + start]
    local h = l and ((l.small or l.msg) and (compact and 15 or 16) or (l.head and (compact and 18 or 22) or rh))
    if not l or (maxH and -y + h + 8 > maxH) then r:Hide()
    else
      shown = shown + 1
      r:SetWidth(w - 12)
      r:SetHeight(h) r:ClearAllPoints() r:SetPoint('TOPLEFT', 6, y) y = y - h
      r.p, r.label, r.tip, r.qid, r.detailFirst, r.tt = l.p, l.label, l.tip, l.qid, l.detailFirst, l.tt
      if compact and l.sub then r.tip = (l.sub .. (l.right2 and l.right2 ~= '' and (', ' .. l.right2) or '')) .. (l.tip and ('\n' .. l.tip) or '') end
      if l.objTip and l.objTip[1] then r.tip = (r.tip and (r.tip .. '\n') or '') .. '|cffffd200Cile:|r\n' .. table.concat(l.objTip, '\n') end
      r.num:SetText(l.num and (l.num .. '.') or '')
      r.right:SetText(l.right or '') r.right2:SetText((not compact) and l.right2 or '')
      r.right:ClearAllPoints()
      if compact then r.right:SetPoint('RIGHT', -6, 0) else r.right:SetPoint('TOPRIGHT', -6, -3) end
      r.text:ClearAllPoints() r.sub:SetText((not compact) and l.sub or '')
      r.stripe:SetShown(l.color ~= nil and not l.head)
      local focus = sup and l.qid == sup and not l.small and not l.head
      r.stripe:SetWidth(focus and 4 or 2)
      local fc = (l.color and l.color[2]) and l.color or { '', 1, 0.82, 0 }
      if focus then r.stripe:Show() r.stripe:SetVertexColor(fc[2], fc[3], fc[4], 1)
      elseif l.color then r.stripe:SetVertexColor(l.color[2], l.color[3], l.color[4], l.first and 1 or 0.45) end
      local a = tr and 0.5 or 1
      if l.head then
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.text:SetPoint('BOTTOMLEFT', 4, 3) r.text:SetText('|cff66ccff' .. l.head .. '|r')
        odd = false
      elseif l.small or l.msg then
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.text:SetPoint('LEFT', 4, 0) r.text:SetText(l.text or l.msg) r.text:SetWidth(w - 24)
      else
        odd = not odd
        if focus then r.bg:SetColorTexture(fc[2], fc[3], fc[4], 0.16 * a)
        else r.bg:SetColorTexture(1, 1, 1, (l.first and 0.08 or (odd and 0.035 or 0.012)) * a) end
        local rw = math.max(r.right:GetStringWidth() or 0, compact and 0 or (r.right2:GetStringWidth() or 0))
        local left = l.num and 28 or 10
        if compact then r.text:SetPoint('LEFT', left, 0) else r.text:SetPoint('TOPLEFT', left, -3) end
        r.text:SetText(compact and l.ctext or l.text) r.text:SetWidth(w - 24 - left - rw - 8)
        r.sub:ClearAllPoints() r.sub:SetPoint('BOTTOMLEFT', left, 3) r.sub:SetWidth(w - 24 - left - rw - 8)
      end
      r:Show()
    end
  end
  local more = #lines - start - shown
  frame.sum:SetText(sum .. ((start > 0 or more > 0) and ('  |cff888888(%s%s)|r'):format(start > 0 and ('^' .. start .. ' ') or '', more > 0 and ('v' .. more) or '') or ''))
  frame:SetHeight(maxH or (-y + 8))
end

-- minimalizace do ikony (najeti = prehled trasy, klik = otevrit, pravy klik = zavrit)
local function buildIcon()
  local b = CreateFrame('Button', 'ClaudeMasterRouteIcon', UIParent, 'BackdropTemplate')
  b:SetSize(34, 34) b:SetFrameStrata('MEDIUM') b:SetClampedToScreen(true)
  b:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
  b:SetBackdropColor(0, 0, 0, 0.6) b:SetBackdropBorderColor(unpack(ns.THEME.border))
  b.tex = b:CreateTexture(nil, 'ARTWORK') b.tex:SetPoint('TOPLEFT', 3, -3) b.tex:SetPoint('BOTTOMRIGHT', -3, 3)
  b.tex:SetTexture('Interface\\Icons\\INV_Misc_Map_01') b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.n = b:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal') b.n:SetPoint('BOTTOMRIGHT', -2, 2)
  b.at = 0
  b:SetMovable(true) b:RegisterForDrag('LeftButton')
  b:SetScript('OnDragStart', b.StartMoving)
  b:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    cfg().routeIconPoint = { p, rp, x, y }
  end)
  local pt = cfg().routeIconPoint
  if pt then b:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  elseif frame then b:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0) else b:SetPoint('RIGHT', -260, 80) end
  b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  b:SetScript('OnClick', function(_, btn)
    if btn == 'RightButton' then cfg().routeMin, cfg().routeOpen = nil, nil b:Hide() return end
    R.minimize(false)
  end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:AddLine('Trasa questu', 1, 0.82, 0)
    local ok, lines, sum = pcall(collect)
    if ok then
      if sum ~= '' then GameTooltip:AddLine(sum, 0.8, 0.8, 0.8) end
      local n = 0
      for _, l in ipairs(lines) do
        if l.num or l.head then
          n = n + 1
          if n > 14 then break end
          if l.head then GameTooltip:AddLine(l.head, 0.4, 0.8, 1)
          else
            local sup = ns.Quests and ns.Quests.superId and ns.Quests.superId()
            GameTooltip:AddDoubleLine((sup and l.qid == sup and '|cffffd200>|r ' or '') .. l.num .. '. ' .. (l.ctext or l.text), l.right2 or '', 1, 1, 1, 0.6, 0.6, 0.6)
          end
        elseif not l.small and l.text then
          n = n + 1
          if n > 14 then break end
          GameTooltip:AddDoubleLine('  ' .. l.text, l.right2 or '', 0.85, 0.85, 0.85, 0.6, 0.6, 0.6)
        elseif l.msg then GameTooltip:AddLine(l.msg, 1, 1, 1, true) end
      end
    end
    GameTooltip:AddLine('Klik = otevrit, pravy klik = zavrit, tahem presunout', 0.55, 0.85, 1)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  return b
end
function R.minimize(on)
  if not frame then frame = build() end
  if on then
    cfg().routeMin, cfg().routeOpen = true, true
    frame:Hide()
    icon = icon or buildIcon()
    local ok, _, _, steps = pcall(collect)
    icon.n:SetText(ok and steps and steps > 0 and steps or '')
    icon:Show()
  else
    cfg().routeMin = nil
    if icon then icon:Hide() end
    frame:Show()
    R.refresh()
  end
end

function R.toggle()
  if not frame then frame = build() end
  if frame:IsShown() then cfg().routeOpen = nil frame:Hide() return end
  if icon and icon:IsShown() then R.minimize(false) return end
  if not DB then
    if not R.available() then
      ns.say('Trasa potrebuje addon ForeverDB (nainstaluj ho vedle ClaudeMasteru, napr. pres WowUp).')
      return
    end
    ns.say('Nacitam ForeverDB (chvili to muze seknout)...')
    local ok, why = R.load()
    if not ok then ns.say('ForeverDB se nepodarilo nacist: ' .. tostring(why)) return end
  end
  cfg().routeOpen = true
  frame:Show()
  R.refresh()
end

-- po restartu hry / /reload: okno trasy (nebo ikona) zase tam, kde bylo, ve stejnem stylu
do
  local f = CreateFrame('Frame')
  pcall(f.RegisterEvent, f, 'PLAYER_ENTERING_WORLD')
  local tries = 0
  local function restore()
    local db = ns.db
    if not db or not (db.routeOpen or db.routeMin) then return end
    if frame and (frame:IsShown() or (icon and icon:IsShown())) then return end
    tries = tries + 1
    if InCombatLockdown() then if tries < 30 and C_Timer then C_Timer.After(5, restore) end return end
    if not DB then
      if not R.available() then return end
      local ok = R.load()
      if not ok then return end
    end
    if not frame then frame = build() end
    if db.routeMin then R.minimize(true) else frame:Show() R.refresh() end
  end
  f:SetScript('OnEvent', function()
    f:UnregisterEvent('PLAYER_ENTERING_WORLD')
    if C_Timer then C_Timer.After(3, restore) else restore() end
  end)
end

-- prubezne obnovovani okna (mimo boj, kazde 3 s)
local acc, sendAcc = 0, 0
local lastPos, lastRefresh, logDirty = nil, 0, true
local qev = CreateFrame('Frame')
pcall(qev.RegisterEvent, qev, 'QUEST_LOG_UPDATE')
pcall(qev.RegisterEvent, qev, 'SUPER_TRACKING_CHANGED')
-- sdileny focus v parte: kdo zmeni aktivni quest, tomu druhemu se aktivuje taky (kdyz ho ma)
local lastFocus, applying = nil, false
local function curSuper() return ns.Quests and ns.Quests.superId and ns.Quests.superId() end
function R.recvFocus(name, msg)
  if not ns.db or ns.db.partyFocus == false then return end
  local id = tonumber(msg:match('^RF%^(%d+)'))
  if not id or id == curSuper() then lastFocus = id return end
  if not (QL.GetLogIndexForQuestID and (safeNum(pc(QL.GetLogIndexForQuestID, id)) or 0) > 0) then return end
  if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
  applying, lastFocus = true, id
  pc(C_SuperTrack.SetSuperTrackedQuestID, id)
  if C_Timer then C_Timer.After(0.5, function() applying = false end) else applying = false end
end
qev:SetScript('OnEvent', function(_, e)
  logDirty = true
  if e == 'SUPER_TRACKING_CHANGED' and not applying and ns.db and ns.db.partyFocus ~= false then
    local id = curSuper()
    local D = ns.Duo
    if id and id ~= lastFocus and D and D.rawSend and D.ok and IsInGroup and IsInGroup() then
      lastFocus = id
      D.rawSend('RF^' .. id)
    end
  end
  -- zmena aktivniho questu: hned prekreslit zvyrazneni
  if e == 'SUPER_TRACKING_CHANGED' and frame and frame:IsShown() and not InCombatLockdown() then
    if C_Timer then C_Timer.After(0.1, function() pcall(R.refresh) end) else pcall(R.refresh) end
  end
end)
local tick = CreateFrame('Frame')
tick:SetScript('OnUpdate', function(_, el)
  acc = acc + el
  if acc < 3 then return end
  acc = 0
  if icon and icon:IsShown() and (logDirty or GetTime() - (icon.at or 0) > 20) and not InCombatLockdown() then
    icon.at, logDirty = GetTime(), false
    local ok, _, _, steps = pcall(collect)
    icon.n:SetText(ok and steps and steps > 0 and steps or '')
  end
  sendAcc = (sendAcc or 0) + 1
  if sendAcc >= 4 then sendAcc = 0 pcall(sendLog) end
  if frame and frame:IsShown() and not InCombatLockdown() then
    -- prepocet jen pri pohybu (25+ yd), zmene logu nebo jednou za 15 s
    local me = playerPos()
    local now = GetTime()
    local moved = not (me and lastPos) or dist(me, lastPos) > 25
    if moved or logDirty or now - lastRefresh > 15 then
      lastPos, lastRefresh, logDirty = me, now, false
      pcall(R.refresh)
    end
  end
end)

------------------------------------------------------------------------------------------
-- Pred odletem: co v teto oblasti jeste zbyva
------------------------------------------------------------------------------------------
local ev = CreateFrame('Frame')
pcall(ev.RegisterEvent, ev, 'TAXIMAP_OPENED')
ev:SetScript('OnEvent', function()
  if not ns.db or ns.db.routeWarn == false then return end
  if not DB then return end   -- jen kdyz je databaze uz nactena (Pruzkumnik / trasa); kvuli tomu ji nenacitame
  local me = playerPos()
  if not me then return end
  local turn, obj = {}, {}
  for _, q in ipairs(logQuests()) do
    if q.complete then
      local p, d = nearest(DB.qe[q.id], me)
      if p and d < 600 then turn[#turn + 1] = q.title end
    else
      local p, d = objective(q.id, me)
      if p and d < 600 then obj[#obj + 1] = q.title end
    end
  end
  if #turn + #obj == 0 then return end
  ns.say('|cffffd200Nez odletis:|r' .. (#turn > 0 and (' odevzdat tady ' .. table.concat(turn, ', ') .. '.') or '')
    .. (#obj > 0 and (' Dokoncit tady: ' .. table.concat(obj, ', ') .. '.') or ''))
end)

-- pro Pruzkumnika (Explore.lua)
R.spots, R.world, R.dist, R.playerPos, R.mapName, R.npcName, R.done, R.factionOk, R.objective, R.nearest =
  spots, world, dist, playerPos, mapName, npcName, done, factionOk, objective, nearest
function R.DB() return DB end
function R.inLogSet()
  local t = {}
  if not DB then return t end
  for _, q in ipairs(logQuests()) do t[q.id] = true end
  return t
end

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
  return true
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
      for i = 2, math.min(#e - 1, 12), 2 do
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
function R.valueText(v)
  local p = {}
  if v.xp and v.xp > 0 then
    local col = (v.pctLvl and v.pctLvl >= 5) and '|cff40ff60' or ((v.pctLvl and v.pctLvl < 1) and '|cff888888' or '|cffffd200')
    p[#p + 1] = ('%s%s%d XP%s|r'):format(col, v.est and '~' or '+', v.xp, v.pctLvl and (' (%d %%)'):format(math.floor(v.pctLvl + 0.5)) or '')
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
  local q = {}
  for id, c in msg:gmatch('(%d+):(%d)') do q[tonumber(id)] = c == '1' end
  R.peerLogs[name] = { q = q, at = GetTime() }
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
      local p = id .. ':' .. ((QL.IsComplete and safeBool(pc(QL.IsComplete, id))) and '1' or '0')
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
    if GetTime() - l.at < 120 and inParty(name) then out[#out + 1] = { name = name, unit = inParty(name), q = l.q } end
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

------------------------------------------------------------------------------------------
-- Okno
------------------------------------------------------------------------------------------
local frame
local function yd(d) return d and d < 99999 and (math.floor(d + 0.5) .. ' yd') or 'jiny kontinent' end
local W, RH = 440, 30
local function build()
  local f = CreateFrame('Frame', 'ClaudeMasterRoute', UIParent, 'BackdropTemplate')
  f:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
  local T = ns.THEME
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.94) f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata('MEDIUM') f:SetSize(W, 200)
  f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag('LeftButton') f:SetClampedToScreen(true)
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
  local x = CreateFrame('Button', nil, f, 'UIPanelCloseButton') x:SetSize(20, 20) x:SetPoint('TOPRIGHT', 2, 2)
  x:SetScript('OnClick', function() f:Hide() end)
  f.rows = {}
  for i = 1, 22 do
    local b = CreateFrame('Button', nil, f)
    b:SetSize(W - 12, RH)
    b.bg = b:CreateTexture(nil, 'BACKGROUND') b.bg:SetAllPoints()
    b.stripe = b:CreateTexture(nil, 'ARTWORK') b.stripe:SetTexture('Interface\\Buttons\\WHITE8X8') b.stripe:SetWidth(2)
    b.stripe:SetPoint('TOPLEFT') b.stripe:SetPoint('BOTTOMLEFT')
    b.num = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') b.num:SetPoint('LEFT', 6, 0) b.num:SetWidth(18) b.num:SetJustifyH('RIGHT')
    b.text = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight') b.text:SetJustifyH('LEFT') b.text:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.sub:SetJustifyH('LEFT') b.sub:SetWordWrap(false)
    b.sub:SetTextColor(0.6, 0.64, 0.72)
    b.right = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.right:SetPoint('TOPRIGHT', -6, -3) b.right:SetJustifyH('RIGHT')
    b.right2 = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.right2:SetPoint('BOTTOMRIGHT', -6, 3) b.right2:SetJustifyH('RIGHT')
    b.right2:SetTextColor(0.6, 0.64, 0.72)
    b:SetHighlightTexture('Interface\\Buttons\\WHITE8X8', 'ADD') b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    b:SetScript('OnClick', function(self) if self.p then R.waypoint(self.p, self.label) end end)
    b:SetScript('OnEnter', function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
      GameTooltip:AddLine(self.tip, 1, 1, 1, true)
      if self.p then GameTooltip:AddLine('Klik = sipka na mape', 0.55, 0.85, 1) end
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    f.rows[i] = b
  end
  f:Hide()
  return f
end

local KIND = { turnin = { '|cff40ff60Odevzdat|r', 0.25, 1, 0.38 }, obj = { '|cffffd200Splnit|r', 1, 0.82, 0 } }
function R.refresh()
  if not frame or not frame:IsShown() then return end
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
      for i, s in ipairs(route) do
        local where = s.p and mapName(s.p.map) or '?'
        local v = s.mine and R.value(s.q.id, true) or R.value(s.q.id, false)
        steps = steps + 1
        if s.mine and s.kind == 'turnin' and v.xp then sumXP = sumXP + v.xp end
        local k = KIND[s.kind]
        add({ num = i, color = k, first = i == 1, text = k[1] .. '  ' .. s.q.title .. whoTag(s), right = s.mine and R.valueText(v) or '',
          sub = s.kind == 'turnin' and ((s.npc and npcName(s.npc) or '?') .. ', ' .. where) or ('misto plneni, ' .. where),
          right2 = yd(s.d), p = s.p, label = s.q.title,
          tip = (s.kind == 'turnin' and ('Odevzdat u %s (%s)'):format(s.npc and npcName(s.npc) or '?', where) or ('Misto plneni: ' .. where))
            .. '\n' .. R.valueTip(v) })
        for _, o in ipairs(s.also or {}) do
          local ov = o.mine and R.value(o.q.id, true)
          if o.mine and o.kind == 'turnin' and ov and ov.xp then sumXP = sumXP + ov.xp end
          local who = {}
          for _, w in ipairs(o.who or {}) do who[#who + 1] = (w == me) and 'ty' or w end
          local verb = #who > 1 and { 'odevzdate', 'splnite' } or (who[1] == 'ty' and { 'odevzdas', 'splnis' } or { 'odevzda', 'splni' })
          add({ small = true, text = ('      |cff66ccff+|r %s tu %s |cff9aa6b8i:|r %s %s'):format(table.concat(who, ' + '),
            o.kind == 'turnin' and ('|cff40ff60' .. verb[1] .. '|r') or ('|cffffd200' .. verb[2] .. '|r'), o.q.title, ov and R.valueText(ov) or ''),
            p = o.p, label = o.q.title, tip = 'Na stejnem miste: ' .. o.q.title })
        end
        if s.next then
          local far = s.next.far and s.next.far > 400
          add({ small = true, text = ('      |cffffd200->|r |cff9aa6b8navazuje:|r %s %s%s'):format(s.next.title, R.valueText(s.next.v),
            s.next.where and (' |cff9aa6b8(' .. s.next.where .. (far and ', daleko' or ', blizko') .. ')|r') or '') })
        end
      end
      local pick = R.pickups(route)
      if #pick > 0 then
        add({ head = 'Po ceste muzes vzit' })
        for _, q in ipairs(pick) do
          add({ text = ('|cff9aa6b8[%d]|r %s'):format(q.lvl or 0, q.title), right = R.valueText(q.v), sub = q.npc .. ', ' .. mapName(q.p.map),
            right2 = yd(q.d), p = q.p, label = q.title, color = { '', 0.4, 0.8, 1 },
            tip = ('Quest dava %s (%s)\n%s'):format(q.npc, mapName(q.p.map), R.valueTip(q.v)) })
        end
      end
    end
  end
  local maxXP = safeNum(pc(UnitXPMax, 'player'))
  local np = #R.peers()
  frame.title:SetText(np > 0 and ('Trasa questu |cff66ccff- parta (%d)|r'):format(np + 1) or 'Trasa questu')
  frame.sum:SetText(steps > 0 and ('%d krok%s  -  odevzdanim ziskas |cffffd200+%d XP|r%s'):format(steps, steps == 1 and '' or (steps < 5 and 'y' or 'u'),
    sumXP, (maxXP and maxXP > 0) and (' (%d %% levelu)'):format(math.floor(sumXP / maxXP * 100 + 0.5)) or '') or '')
  local y, odd = -42, false
  for i, r in ipairs(frame.rows) do
    local l = lines[i]
    if not l then r:Hide()
    else
      local h = (l.small or l.msg) and 16 or (l.head and 22 or RH)
      r:SetHeight(h) r:ClearAllPoints() r:SetPoint('TOPLEFT', 6, y) y = y - h
      r.p, r.label, r.tip = l.p, l.label, l.tip
      r.num:SetText(l.num and (l.num .. '.') or '')
      r.right:SetText(l.right or '') r.right2:SetText(l.right2 or '')
      r.text:ClearAllPoints() r.sub:SetText(l.sub or '')
      r.stripe:SetShown(l.color ~= nil and not l.head)
      if l.color then r.stripe:SetVertexColor(l.color[2], l.color[3], l.color[4], l.first and 1 or 0.45) end
      if l.head then
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.text:SetPoint('BOTTOMLEFT', 4, 3) r.text:SetText('|cff66ccff' .. l.head .. '|r')
        odd = false
      elseif l.small or l.msg then
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.text:SetPoint('LEFT', 4, 0) r.text:SetText(l.text or l.msg) r.text:SetWidth(W - 24)
      else
        odd = not odd
        r.bg:SetColorTexture(1, 1, 1, l.first and 0.08 or (odd and 0.035 or 0.012))
        local rw = math.max(r.right:GetStringWidth() or 0, r.right2:GetStringWidth() or 0)
        local left = l.num and 28 or 10
        r.text:SetPoint('TOPLEFT', left, -3) r.text:SetText(l.text) r.text:SetWidth(W - 24 - left - rw - 8)
        r.sub:ClearAllPoints() r.sub:SetPoint('BOTTOMLEFT', left, 3) r.sub:SetWidth(W - 24 - left - rw - 8)
      end
      r:Show()
    end
  end
  frame:SetHeight(-y + 8)
end

function R.toggle()
  if not frame then frame = build() end
  if frame:IsShown() then frame:Hide() return end
  if not DB then
    if not R.available() then
      ns.say('Trasa potrebuje addon ForeverDB (nainstaluj ho vedle ClaudeMasteru, napr. pres WowUp).')
      return
    end
    ns.say('Nacitam ForeverDB (chvili to muze seknout)...')
    local ok, why = R.load()
    if not ok then ns.say('ForeverDB se nepodarilo nacist: ' .. tostring(why)) return end
  end
  frame:Show()
  R.refresh()
end

-- prubezne obnovovani okna (mimo boj, kazde 3 s)
local acc, sendAcc = 0, 0
local tick = CreateFrame('Frame')
tick:SetScript('OnUpdate', function(_, el)
  acc = acc + el
  if acc < 3 then return end
  acc = 0
  sendAcc = (sendAcc or 0) + 1
  if sendAcc >= 4 then sendAcc = 0 pcall(sendLog) end
  if frame and frame:IsShown() and not InCombatLockdown() then pcall(R.refresh) end
end)

------------------------------------------------------------------------------------------
-- Pred odletem: co v teto oblasti jeste zbyva
------------------------------------------------------------------------------------------
local ev = CreateFrame('Frame')
pcall(ev.RegisterEvent, ev, 'TAXIMAP_OPENED')
ev:SetScript('OnEvent', function()
  if not ns.db or ns.db.routeWarn == false then return end
  if not DB and R.available() then pcall(R.load) end   -- databaze se nacte jednou (u letce, mimo boj)
  if not DB then return end
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

-- ClaudeMaster: Pruzkumnik nad databazi ForeverDB (volitelny addon).
-- Vyhledavani questu / NPC / itemu / oblasti a chytre filtry:
--  * Kde levelit: oblasti s nejvic questy pro tvuj level (a kolik XP daji)
--  * Dropy pro tebe: zelene a lepsi itemy z mobu tveho levelu, ktere jsou pro tebe vylepsenim (vahy gearu)
--  * Blizko: questy k vzeti a rare moby pobliz
-- Vysledky = radky {text, p (pozice pro sipku), tip, link}
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local X = {}
ns.Explore = X

local function R() return ns.Route end
local function DB() return R() and R().DB() end
local function lvl() return safeNum(pc(UnitLevel, 'player')) or 1 end
local function yd(d) return d and d < 99999 and (math.floor(d + 0.5) .. ' yd') or '' end

-- prvni pozice zdroje (NPC / objekt) a vzdalenost od hrace
local function firstSpot(key, me)
  local best, bd
  for _, s in ipairs(R().spots(key)) do
    local d = R().dist(me, s.w)
    if not bd or d < bd then best, bd = s, d end
  end
  return best, bd
end
local function where(p) return p and p.map and R().mapName(p.map) or '?' end
local QCOL = { [0] = 'ff9d9d9d', 'ffffffff', 'ff1eff00', 'ff0070dd', 'ffa335ee', 'ffff8000' }
local function itemName(id)
  local it = DB().item[id]
  return ('|c%s%s|r'):format(QCOL[it and it[2] or 1] or 'ffffffff', it and it[1] or '?')
end
local function itemIcon(id)
  local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  return f and pc(f, id) or 'Interface\\Icons\\INV_Misc_QuestionMark'
end
local ICON = {
  quest = 'Interface\\GossipFrame\\AvailableQuestIcon',
  zone = 'Interface\\Icons\\INV_Misc_Map_01',
  npc = 'Interface\\Icons\\INV_Misc_GroupNeedMore',
  rare = 'Interface\\Icons\\Ability_Hunter_MarkedForDeath',
}

-- quest pro me: level, frakce giveru, predpoklady, ne hotovy / v logu
local function questOk(qid, inLog, L, spread)
  local D = DB()
  local info = D.quest[qid]
  if not info or inLog[qid] then return false end
  local ql, minl = info[2] or 0, info[3] or 1
  if minl > L or ql < L - (spread or 3) or ql > L + 3 then return false end
  if R().done(qid) then return false end
  local x = D.qx[qid]
  local pre = type(x) == 'table' and x[3]
  if type(pre) == 'table' then for _, p in ipairs(pre) do if D.quest[p] and not R().done(p) then return false end end end
  return true
end

------------------------------------------------------------------------------------------
-- Kde levelit: oblasti podle poctu questu pro tvuj level
------------------------------------------------------------------------------------------
function X.leveling()
  local D, out = DB(), {}
  local me = R().playerPos()
  local inLog, L = R().inLogSet(), lvl()
  local zones = {}
  for qid, givers in pairs(D.qg) do
    if questOk(qid, inLog, L) then
      local key
      for _, k in ipairs(givers) do if R().factionOk(k) then key = k break end end
      local s = key and R().spots(key)[1]
      if s and s.map then
        local z = zones[s.map] or { map = s.map, n = 0, xp = 0, p = s }
        z.n = z.n + 1
        local r = D.qrw and D.qrw[qid]
        z.xp = z.xp + ((type(r) == 'table' and r[2]) or 0)
        zones[s.map] = z
      end
    end
  end
  local list = {}
  for _, z in pairs(zones) do list[#list + 1] = z end
  table.sort(list, function(a, b) return a.xp > b.xp end)
  local maxXP = safeNum(pc(UnitXPMax, 'player')) or 0
  local top = list[1] and math.max(1, list[1].xp) or 1
  for i, z in ipairs(list) do
    if i > 12 then break end
    local d = me and R().dist(me, z.p.w)
    out[#out + 1] = { icon = ICON.zone, title = '|cffffd200' .. R().mapName(z.map) .. '|r',
      sub = ('%d questu pro tvuj level%s'):format(z.n, maxXP > 0 and (', cca %.1f levelu'):format(z.xp / maxXP) or ''),
      right = ('|cffffd200~%d XP|r'):format(z.xp), right2 = yd(d), bar = z.xp / top,
      p = z.p, open = function() return X.zone(z.map) end, tip = 'Klik = questy v teto oblasti, pravy klik = sipka.' }
  end
  if #out == 0 then out[1] = { text = '|cff9aa6b8Zadne questy pro tvuj level nenalezeny.|r' } end
  return out
end

------------------------------------------------------------------------------------------
-- Dropy pro tebe: itemy z mobu tveho levelu, ktere jsou vylepsenim (po kouskach - hodnoceni cte tooltipy)
------------------------------------------------------------------------------------------
local dropJob
function X.drops(done)
  local D = DB()
  local L = lvl()
  local G = ns.Gear
  if not (G and G.parse and G.compare and C_TooltipInfo and C_TooltipInfo.GetItemByID) then
    return { { text = '|cff9aa6b8Hodnoceni gearu neni k dispozici.|r' } }
  end
  -- kandidati: zelene+ vybaveni s pozadavkem levelu blizko tveho, ktere nekde pada
  local cands = {}
  for id, it in pairs(D.item) do
    local q, req, cls = it[2], it[3], it[5]
    if (q or 0) >= 2 and (cls == 2 or cls == 4) and req and req >= L - 4 and req <= L + 2 and D.drop[id] then
      cands[#cands + 1] = id
    end
  end
  local res = {}
  if dropJob then dropJob.cancel = true end
  local job = { cancel = false }
  dropJob = job
  local i = 0
  local function step()
    if job.cancel then return end
    local n = 0
    while i < #cands and n < 40 do
      i, n = i + 1, n + 1
      local id = cands[i]
      local data = pc(C_TooltipInfo.GetItemByID, id)
      local link = 'item:' .. id
      local st, blocked = G.parse(data)
      if st and not blocked then
        local pct = safeNum(pc(G.compare, link, st))
        if pct and pct > 0.05 then
          -- nejlepsi zdroj: nejvyssi sance
          local dl, bestNpc, bestCh = D.drop[id], nil, 0
          for j = 1, #dl - 1, 2 do if dl[j + 1] > bestCh then bestNpc, bestCh = dl[j], dl[j + 1] end end
          res[#res + 1] = { id = id, pct = pct, npc = bestNpc, ch = bestCh }
        end
      end
    end
    if i < #cands then C_Timer.After(0.05, step) return end
    table.sort(res, function(a, b) return a.pct * math.max(0.01, a.ch) > b.pct * math.max(0.01, b.ch) end)
    local out = {}
    local me = R().playerPos()
    for k, r in ipairs(res) do
      if k > 20 then break end
      local key = r.npc and ('c' .. r.npc)
      local p = key and firstSpot(key, me)
      local npc = key and R().npcName(key) or '?'
      local _, d = key and firstSpot(key, me)
      out[#out + 1] = { icon = itemIcon(r.id), title = itemName(r.id),
        sub = ('pada z %s (%.1f %%), %s'):format(npc, (r.ch or 0) / 100, p and where(p) or 'dungeon / neznama poloha'),
        right = ('|cff40ff60+%d %%|r'):format(math.floor(r.pct * 100 + 0.5)), right2 = yd(d),
        p = p, link = 'item:' .. r.id, open = function() return X.item(r.id) end }
    end
    if #out == 0 then out[1] = { text = '|cff9aa6b8Zadny drop pro tvuj level by pro tebe nebyl vylepsenim.|r' } end
    done(out)
  end
  step()
  return { { text = ('|cff9aa6b8Hodnotim %d itemu...|r'):format(#cands) } }
end

------------------------------------------------------------------------------------------
-- Blizko: questy k vzeti a rare moby
------------------------------------------------------------------------------------------
function X.nearby()
  local D, out = DB(), {}
  local me = R().playerPos()
  if not me then return { { text = '|cff9aa6b8Pozice neni k dispozici.|r' } } end
  local inLog, L = R().inLogSet(), lvl()
  local qs = {}
  for qid, givers in pairs(D.qg) do
    if questOk(qid, inLog, L, 5) then
      for _, k in ipairs(givers) do
        if R().factionOk(k) then
          local p, d = firstSpot(k, me)
          if p and d < 800 then qs[#qs + 1] = { qid = qid, p = p, d = d, npc = R().npcName(k) } break end
        end
      end
    end
  end
  table.sort(qs, function(a, b) return a.d < b.d end)
  if qs[1] then out[#out + 1] = { head = 'Questy k vzeti' } end
  for i, q in ipairs(qs) do
    if i > 15 then break end
    local info = D.quest[q.qid]
    local v = R().value and R().value(q.qid, false)
    out[#out + 1] = { icon = ICON.quest, title = ('|cff9aa6b8[%d]|r %s'):format(info[2] or 0, info[1]),
      sub = ('%s, %s'):format(q.npc, where(q.p)), right = v and R().valueText(v) or '', right2 = yd(q.d),
      p = q.p, open = function() return X.quest(q.qid) end }
  end
  -- rare moby (rare: { at = { {map, x, y}, ... } })
  if D.rare then
    local rs = {}
    for npc, r in pairs(D.rare) do
      local n = D.npc[npc]
      if n and (n[3] or 0) >= L - 5 and (n[3] or 0) <= L + 5 and type(r.at) == 'table' then
        for _, a in ipairs(r.at) do
          local w = R().world(a[1], a[2], a[3])
          local d = w and R().dist(me, w)
          if d and d < 1500 then rs[#rs + 1] = { name = n[1], lvl = n[3], d = d, p = { map = a[1], x = a[2], y = a[3], w = w } } break end
        end
      end
    end
    table.sort(rs, function(a, b) return a.d < b.d end)
    if #rs > 0 then out[#out + 1] = { head = 'Rare moby pobliz' } end
    for i, r in ipairs(rs) do
      if i > 5 then break end
      out[#out + 1] = { icon = ICON.rare, title = ('|cffff9933%s|r |cff9aa6b8[%d]|r'):format(r.name, r.lvl or 0),
        sub = 'rare - ' .. where(r.p), right2 = yd(r.d), p = r.p }
    end
  end
  if #out == 0 then out[1] = { text = '|cff9aa6b8Nic pobliz.|r' } end
  return out
end

------------------------------------------------------------------------------------------
-- Hledani: text (quest / NPC / item), nebo "z:oblast" = questy v oblasti pro tvuj level
------------------------------------------------------------------------------------------
function X.search(text)
  local D, out = DB(), {}
  text = (text or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if #text < 3 then return { { text = '|cff9aa6b8Napis aspon 3 znaky (nebo z:oblast, napr. z:tanaris).|r' } } end
  local me = R().playerPos()
  local L = lvl()
  local zone = text:match('^z:%s*(.+)$')
  if zone then
    local inLog = R().inLogSet()
    for qid, givers in pairs(D.qg) do
      if questOk(qid, inLog, L, 6) then
        for _, k in ipairs(givers) do
          local p = R().factionOk(k) and R().spots(k)[1]
          if p and p.map and R().mapName(p.map):lower():find(zone, 1, true) then
            local info = D.quest[qid]
            local v = R().value and R().value(qid, false)
            out[#out + 1] = { icon = ICON.quest, title = ('|cff9aa6b8[%d]|r %s'):format(info[2] or 0, info[1]),
              sub = ('%s, %s'):format(R().npcName(k), where(p)), right = v and R().valueText(v) or '',
              right2 = me and yd(R().dist(me, p.w)) or '', p = p, lv = info[2] or 0, open = function() return X.quest(qid) end }
            break
          end
        end
      end
    end
    table.sort(out, function(a, b) return (a.lv or 0) < (b.lv or 0) end)
    while #out > 30 do table.remove(out) end
    if #out == 0 then out[1] = { text = '|cff9aa6b8V teto oblasti nejsou questy pro tvuj level.|r' } end
    return out
  end
  local function add(row) if #out < 30 then out[#out + 1] = row end end
  local seen = {}
  for qid, info in pairs(D.quest) do
    if #out >= 10 then break end
    local g = D.qg[qid] and D.qg[qid][1]
    if info[1] and info[1]:lower():find(text, 1, true) and not seen[info[1] .. tostring(g)] then
      seen[info[1] .. tostring(g)] = true
      local p, d = nil, nil
      if g then p, d = firstSpot(g, me) end
      add({ icon = ICON.quest, title = ('|cff9aa6b8[%d]|r %s'):format(info[2] or 0, info[1]),
        sub = ('quest - %s%s'):format(g and R().npcName(g) or 'neznamy zadavatel', p and (', ' .. where(p)) or ''),
        right2 = yd(d), p = p, open = function() return X.quest(qid) end })
    end
  end
  local nn = 0
  for id, n in pairs(D.npc) do
    if nn >= 10 then break end
    if n[1] and n[1]:lower():find(text, 1, true) and not n[1]:find('UNUSED') then
      local p, d = firstSpot('c' .. id, me)
      if p then
        nn = nn + 1
        add({ icon = ICON.npc, title = ('|cff66ccff%s|r |cff9aa6b8[%s]|r'):format(n[1], n[3] or '?'),
          sub = ('NPC%s - %s'):format(n[2] and (' <' .. n[2] .. '>') or '', where(p)), right2 = yd(d), p = p })
      end
    end
  end
  local ni = 0
  for id, it in pairs(D.item) do
    if ni >= 10 then break end
    if it[1] and it[1]:lower():find(text, 1, true) then
      ni = ni + 1
      local dl = D.drop[id]
      local src, p, d = 'item', nil, nil
      if dl then
        local key = 'c' .. dl[1]
        p, d = firstSpot(key, me)
        src = ('pada z %s (%.1f %%)'):format(R().npcName(key), (dl[2] or 0) / 100)
      elseif D.vend and D.vend[id] then src = 'koupis u vendora' end
      add({ icon = itemIcon(id), title = itemName(id), sub = src .. (p and (', ' .. where(p)) or ''), right2 = yd(d), p = p, link = 'item:' .. id,
        open = function() return X.item(id) end })
    end
  end
  if #out == 0 then out[1] = { text = '|cff9aa6b8Nic nenalezeno.|r' } end
  return out
end

------------------------------------------------------------------------------------------
-- Detaily (klik na vysledek): oblast -> questy, quest -> detail, item -> zdroje
------------------------------------------------------------------------------------------
local function qrow(qid, me, extra)
  local D = DB()
  local info = D.quest[qid]
  if not info then return nil end
  local g, p, d = nil, nil, nil
  for _, k in ipairs(D.qg[qid] or {}) do if R().factionOk(k) then g = k break end end
  if g then p, d = firstSpot(g, me) end
  local v = R().value and R().value(qid, false)
  local st = R().done(qid) and ' |cff40ff60(hotovo)|r' or (R().inLogSet()[qid] and ' |cff66ccff(v logu)|r' or '')
  return { icon = ICON.quest, title = ('|cff9aa6b8[%d]|r %s%s'):format(info[2] or 0, info[1], st),
    sub = (extra and (extra .. ' - ') or '') .. (g and (R().npcName(g) .. (p and (', ' .. where(p)) or '')) or 'neznamy zadavatel'),
    right = v and R().valueText(v) or '', right2 = yd(d), p = p, link = 'quest:' .. qid, open = function() return X.quest(qid) end }
end

function X.zone(map)
  local D, out = DB(), {}
  local me = R().playerPos()
  local inLog, L = R().inLogSet(), lvl()
  for qid, givers in pairs(D.qg) do
    if questOk(qid, inLog, L, 6) then
      for _, k in ipairs(givers) do
        if R().factionOk(k) then
          local hit
          for _, sp in ipairs(R().spots(k)) do if sp.map == map then hit = true break end end
          if hit then
            local r = qrow(qid, me)
            if r then r.lv = D.quest[qid][2] or 0 out[#out + 1] = r end
          end
          break
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.lv < b.lv end)
  while #out > 29 do table.remove(out) end
  if #out == 0 then out[1] = { text = '|cff9aa6b8V teto oblasti nejsou questy pro tvuj level.|r' } end
  return out, R().mapName(map)
end

-- quest -> itemy z odmeny (inverzni index k D.rew: item -> {questy})
local rewIdx
local function rewards(qid)
  if not rewIdx then
    rewIdx = {}
    for it, qs in pairs(DB().rew or {}) do
      for _, q in ipairs(qs) do rewIdx[q] = rewIdx[q] or {} table.insert(rewIdx[q], it) end
    end
  end
  return rewIdx[qid] or {}
end
local function gearPct(id)
  local G = ns.Gear
  if not (G and G.parse and G.compare and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local st, blocked = G.parse(pc(C_TooltipInfo.GetItemByID, id))
  if not st or blocked then return nil end
  return safeNum(pc(G.compare, 'item:' .. id, st))
end
local function itemRow(id, sub, me)
  local pct = gearPct(id)
  return { icon = itemIcon(id), title = itemName(id), sub = sub,
    right = pct and pct > 0.03 and ('|cff40ff60+%d %%|r'):format(math.floor(pct * 100 + 0.5)) or '',
    link = 'item:' .. id, open = function() return X.item(id) end }
end
local function spotRow(icon, key, me, label)
  local p, d = firstSpot(key, me)
  return { icon = icon, title = R().npcName(key), sub = label .. (p and (' - ' .. where(p)) or ' - neznama poloha (dungeon?)'),
    right2 = yd(d), p = p }
end

function X.quest(qid)
  local D, out = DB(), {}
  local info = D.quest[qid]
  if not info then return { { text = '|cff9aa6b8Quest neni v databazi.|r' } }, '?' end
  local me = R().playerPos()
  local x = type(D.qx[qid]) == 'table' and D.qx[qid] or {}
  local v = R().value(qid, R().inLogSet()[qid] or false)
  local maxXP = safeNum(pc(UnitXPMax, 'player'))
  out[#out + 1] = { icon = ICON.quest, title = ('|cffffd200%s|r'):format(info[1]),
    sub = ('level %d, od levelu %d%s'):format(info[2] or 0, info[3] or 1, R().done(qid) and ' - uz mas hotovo' or ''),
    right = v and R().valueText(v) or '', link = 'quest:' .. qid, tip = v and R().valueTip(v) or nil }
  out[#out + 1] = { head = 'Kde' }
  for _, k in ipairs(D.qg[qid] or {}) do
    if R().factionOk(k) then out[#out + 1] = spotRow(ICON.npc, k, me, 'zadava') end
  end
  local op, od = R().objective(qid, me)
  if op then out[#out + 1] = { icon = ICON.zone, title = 'Misto plneni', sub = where(op), right2 = yd(od), p = op } end
  for _, k in ipairs(D.qe[qid] or {}) do
    if R().factionOk(k) then out[#out + 1] = spotRow('Interface\\GossipFrame\\ActiveQuestIcon', k, me, 'odevzdat') end
  end
  local rw = rewards(qid)
  local fac = type(x[15]) == 'table' and x[15]
  if #rw > 0 or fac then out[#out + 1] = { head = 'Odmeny' } end
  for _, id in ipairs(rw) do out[#out + 1] = itemRow(id, 'odmena (nekdy na vyber)', me) end
  if fac and fac[1] then
    local get = GetFactionInfoByID or (C_Reputation and C_Reputation.GetFactionDataByID)
    local fi = get and pc(get, fac[1])
    local fname = type(fi) == 'table' and safe(fi.name) or (type(fi) == 'string' and fi) or ('frakce ' .. fac[1])
    out[#out + 1] = { icon = 'Interface\\Icons\\INV_Misc_Note_02', title = fname, sub = 'reputace', right = ('|cff66ccff+%d|r'):format(fac[2] or 0) }
  end
  local pre, nxt = type(x[3]) == 'table' and x[3] or {}, x[7]
  if #pre > 0 or nxt then out[#out + 1] = { head = 'Retez questu' } end
  for _, q in ipairs(pre) do local r = qrow(q, me, 'predtim') if r then out[#out + 1] = r end end
  if nxt then local r = qrow(nxt, me, 'navazuje') if r then out[#out + 1] = r end end
  return out, info[1]
end

function X.item(id)
  local D, out = DB(), {}
  local it = D.item[id]
  if not it then return { { text = '|cff9aa6b8Item neni v databazi.|r' } }, '?' end
  local me = R().playerPos()
  local r = itemRow(id, ('vyzaduje level %d'):format(it[3] or 1), me)
  r.open = nil
  out[1] = r
  local dl = D.drop[id]
  if dl then
    out[#out + 1] = { head = 'Pada z' }
    local list = {}
    for j = 1, #dl - 1, 2 do list[#list + 1] = { npc = dl[j], ch = dl[j + 1] } end
    table.sort(list, function(a, b) return a.ch > b.ch end)
    for k, e in ipairs(list) do
      if k > 10 then break end
      local key = 'c' .. e.npc
      local n = D.npc[e.npc]
      local row = spotRow(n and (n[5] or 0) >= 2 and ICON.rare or ICON.npc, key, me,
        ('%.1f %%%s'):format(e.ch / 100, n and n[3] and (', level ' .. n[3]) or ''))
      out[#out + 1] = row
    end
  end
  local od = D.odrop and D.odrop[id]
  if od then
    out[#out + 1] = { head = 'Z truhel / objektu' }
    for j = 1, math.min(#od - 1, 10), 2 do out[#out + 1] = spotRow('Interface\\Icons\\INV_Box_01', 'o' .. od[j], me, ('%.1f %%'):format((od[j + 1] or 0) / 100)) end
  end
  local qs = D.rew and D.rew[id]
  if qs then
    out[#out + 1] = { head = 'Odmena z questu' }
    for _, q in ipairs(qs) do local qr = qrow(q, me) if qr then out[#out + 1] = qr end end
  end
  local vs = D.vend and D.vend[id]
  if vs then
    out[#out + 1] = { head = 'Prodavaji' }
    for k, n in ipairs(vs) do
      if k > 6 then break end
      if R().factionOk('c' .. n) then out[#out + 1] = spotRow('Interface\\Icons\\INV_Misc_Bag_10', 'c' .. n, me, 'vendor') end
    end
  end
  if #out == 1 then out[2] = { text = '|cff9aa6b8Zdroj neni v databazi znamy.|r' } end
  return out, it[1]
end

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
  for i, z in ipairs(list) do
    if i > 12 then break end
    local d = me and R().dist(me, z.p.w)
    out[#out + 1] = { text = ('|cffffd200%s|r - %d questu, ~%d XP%s %s'):format(R().mapName(z.map), z.n, z.xp,
      maxXP > 0 and (' (%.1f levelu)'):format(z.xp / maxXP) or '', d and d < 99999 and ('|cff9aa6b8' .. yd(d) .. '|r') or ''),
      p = z.p, tip = 'Questy pro tvuj level v teto oblasti. Klik = sipka do oblasti.' }
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
      local nm = D.item[r.id][1]
      local npc = key and R().npcName(key) or '?'
      out[#out + 1] = { text = ('|cff40ff60+%d %%|r %s |cff9aa6b8- %s (%.1f %%), %s|r'):format(math.floor(r.pct * 100 + 0.5), nm, npc,
        (r.ch or 0) / 100, where(p)), p = p, link = 'item:' .. r.id, tip = ('Pada z: %s (%s). Klik = sipka.'):format(npc, where(p)) }
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
  for i, q in ipairs(qs) do
    if i > 15 then break end
    local info = D.quest[q.qid]
    local v = R().value and R().value(q.qid, false)
    out[#out + 1] = { text = ('[%d] %s %s |cff9aa6b8- %s, %s|r'):format(info[2] or 0, info[1], v and R().valueText(v) or '', q.npc, yd(q.d)),
      p = q.p, tip = ('Quest dava %s (%s)'):format(q.npc, where(q.p)) }
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
    if #rs > 0 then out[#out + 1] = { text = '|cff66ccffRare moby pobliz:|r' } end
    for i, r in ipairs(rs) do
      if i > 5 then break end
      out[#out + 1] = { text = ('   |cffff9933%s|r [%d] |cff9aa6b8- %s, %s|r'):format(r.name, r.lvl or 0, where(r.p), yd(r.d)), p = r.p }
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
            out[#out + 1] = { text = ('[%d] %s |cff9aa6b8- %s, %s|r'):format(info[2] or 0, info[1], R().npcName(k), where(p)), p = p,
              lv = info[2] or 0 }
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
      local p = g and firstSpot(g, me)
      add({ text = ('|cffffd200Quest|r [%d] %s |cff9aa6b8- %s%s|r'):format(info[2] or 0, info[1], g and R().npcName(g) or '?',
        p and (', ' .. where(p)) or ''), p = p })
    end
  end
  local nn = 0
  for id, n in pairs(D.npc) do
    if nn >= 10 then break end
    if n[1] and n[1]:lower():find(text, 1, true) and not n[1]:find('UNUSED') then
      local p, d = firstSpot('c' .. id, me)
      if p then
        nn = nn + 1
        add({ text = ('|cff66ccffNPC|r %s%s [%s] |cff9aa6b8- %s %s|r'):format(n[1], n[2] and (' <' .. n[2] .. '>') or '', n[3] or '?', where(p), yd(d)), p = p })
      end
    end
  end
  local ni = 0
  for id, it in pairs(D.item) do
    if ni >= 10 then break end
    if it[1] and it[1]:lower():find(text, 1, true) then
      ni = ni + 1
      local dl = D.drop[id]
      local src, p = '', nil
      if dl then
        local key = 'c' .. dl[1]
        p = firstSpot(key, me)
        src = ('pada z %s (%.1f %%)'):format(R().npcName(key), (dl[2] or 0) / 100)
      elseif D.vp and D.vp[id] then src = 'koupis u vendora' end
      add({ text = ('|cffa335eeItem|r %s |cff9aa6b8- %s%s|r'):format(it[1], src, p and (', ' .. where(p)) or ''), p = p, link = 'item:' .. id })
    end
  end
  if #out == 0 then out[1] = { text = '|cff9aa6b8Nic nenalezeno.|r' } end
  return out
end

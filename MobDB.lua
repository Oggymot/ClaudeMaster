-- ClaudeMaster: znalosti o mobech z databaze (MobData.lua, vmangos = classic 1.12)
-- Forever neni cisty classic, takze databaze je jen VYCHOZI ODHAD:
-- co addon sam ve hre zjisti (Immune.lua, Memory.lua, mobCasts), ma vzdy prednost.
-- Hledame podle jmena (venku citelne); v dungeonu hra jmeno i ID skryva -> databaze tam nepomuze.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local MD = { byName = nil, cache = {}, spellTag = nil }
ns.MobDB = MD

-- mechanic_immune_mask: bit = 1 << (mechanika - 1)
local MECH = { polymorph = 65536, fear = 16, root = 64, snare = 1024, stun = 2048, freeze = 4096, banish = 131072,
  silence = 256, charm = 1, sleep = 512, horror = 8388608 }
local SCH = { fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }
local SCHOOL_OF = { F = 'fire', R = 'frost', S = 'shadow', A = 'arcane', N = 'nature', H = 'holy', P = 'physical' }
local CZ = { fire = 'ohen', frost = 'mraz', shadow = 'stin', arcane = 'arcane', nature = 'priroda', holy = 'svetlo', physical = 'fyzicky' }
MD.CZ = CZ
local function has(mask, bit) return mask and bit and math.floor(mask / bit) % 2 == 1 end

local function index()
  if MD.byName then return end
  MD.byName = {}
  for id, s in pairs(ns.MOBDATA or {}) do
    local name = s:match('^([^|]*)')
    local l = MD.byName[name]
    if not l then l = {} MD.byName[name] = l end
    l[#l + 1] = id
  end
end

------------------------------------------------------------------------------------------
-- ForeverDB (volitelna): presnejsi dropy pro Forever (vc. novych itemu a dropu ze skutecnych killu)
------------------------------------------------------------------------------------------
-- Celou databazi (~40 MB) neni dobre drzet v pameti kvuli tooltipum (zpomaluje GC = trhane FPS).
-- Proto se z ni jednou vytahne mala cache retezcu (ns.db.fdbc) a ta se pouziva i v dalsich sezenich.
local function FDB() return ns.Route and ns.Route.DB and ns.Route.DB() end
local function fdbVersion()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local v = get and safe(pc(get, 'ForeverDB', 'Version'))
  if type(v) == 'string' and v ~= '' then return v end
  local D = FDB()
  return D and D.meta and D.meta.hash or nil
end
-- force = Pruzkumnik (bere data vzdy); tooltipy respektuji nastaveni
local function C(force)
  if not force and ns.db and ns.db.fdbAuto == false then return nil end
  local c = ns.db and ns.db.fdbc
  return (c and c.drops) and c or nil
end
function MD.cacheFresh()
  local c = C(true)
  local v = fdbVersion()
  return c ~= nil and c.schema == 9 and (v == nil or c.ver == v)
end
-- sestavi cache z nactene databaze
function MD.buildCache()
  local D = FDB()
  if not (D and D.drop and ns.db) then return false end
  local per = {}
  for item, dl in pairs(D.drop) do
    local it = D.item[item]
    local q, cls = it and it[2] or 1, it and it[5]
    for j = 1, #dl - 1, 2 do
      local ch = (dl[j + 1] or 0) / 100
      local kind
      if cls == 12 then kind = 'q'
      elseif q >= 2 then kind = tostring(math.min(q, 5))
      elseif q == 1 and ch >= 5 then kind = 'c' end
      if kind and it and it[1] and ch >= 0.5 then
        local l = per[dl[j]]
        if not l then l = {} per[dl[j]] = l end
        l[#l + 1] = { id = item, chance = ch, kind = kind, name = it[1] }
      end
    end
  end
  local W = { ['5'] = 8, ['4'] = 5, ['3'] = 3, ['2'] = 1.5, c = 1 }
  local drops = {}
  for npc, l in pairs(per) do
    table.sort(l, function(a, b)
      if (a.kind == 'q') ~= (b.kind == 'q') then return a.kind == 'q' end
      local sa, sb = a.chance * (W[a.kind] or 1), b.chance * (W[b.kind] or 1)
      if sa ~= sb then return sa > sb end
      return a.id < b.id
    end)
    local parts = {}
    for i = 1, math.min(6, #l) do
      local d = l[i]
      parts[i] = ('%d~%s~%s~%s'):format(d.id, ('%.2f'):format(d.chance):gsub('%.?0+$', ''), d.kind, d.name:gsub('[~;]', ''))
    end
    drops[npc] = table.concat(parts, ';')
  end
  local gold = {}
  for npc, g in pairs(D.gold or {}) do
    if type(g) == 'table' and g[1] then gold[npc] = ('%d,%d,%d,%d'):format(g[1], g[2] or g[1], g[3] or g[1], g[4] or 0) end
  end
  -- moby mimo vmangos databazi (jen ty, ktere neco dropi / maji penize)
  local names = {}
  for id, n in pairs(D.npc) do
    if n[1] and not (ns.MOBDATA and ns.MOBDATA[id]) and (drops[id] or gold[id]) then
      local e = ('%d:%d:%d:%d'):format(id, n[3] or 1, n[4] or n[3] or 1, n[5] or 0)
      names[n[1]] = names[n[1]] and (names[n[1]] .. ',' .. e) or e
    end
  end
  local lv = {}
  for id in pairs(drops) do local n = D.npc[id] if n and n[3] then lv[id] = (n[3]) .. ',' .. (n[4] or n[3]) end end
  local start = {}
  for item, qid in pairs(D.start or {}) do
    local q = D.quest[qid]
    if q and q[1] then start[item] = ('%d|%d|%d|%s'):format(qid, q[3] or 1, q[2] or 0, q[1]) end
  end
  -- zony questu: kde se plni (cil, moby, zdroje itemu) a kde se odevzdava -> "1425,1446|1453"
  local cont = {}
  local function zoneMap(m)
    if cont[m] == nil then
      local i = C_Map and C_Map.GetMapInfo and pc(C_Map.GetMapInfo, m)
      local t = type(i) == 'table' and safeNum(i.mapType)
      cont[m] = (t ~= nil and t <= 2)   -- svet / kontinent: neurcuje zonu
    end
    return not cont[m]
  end
  local spotsOf = ns.Route and ns.Route.spots
  local function addMaps(set, key)
    local m = D.spm[key]
    local direct = false
    if type(m) == 'table' then for map in pairs(m) do if zoneMap(map) then set[map] = true direct = true end end end
    -- jen svetove souradnice / kontinent: prevod pres trasu (zona podle polohy)
    if not direct and spotsOf then
      local ok, sp = pcall(spotsOf, key)
      if ok and type(sp) == 'table' then
        for i, p in ipairs(sp) do if i > 8 then break end if p.map and zoneMap(p.map) then set[p.map] = true end end
      end
    end
  end
  local qz = {}
  for qid in pairs(D.quest) do
    local x = type(D.qx[qid]) == 'table' and D.qx[qid] or {}
    local o, e = {}, {}
    local sp = (D.qsp and D.qsp[qid]) or x[16]
    if type(sp) == 'table' then for map in pairs(sp) do if zoneMap(map) then o[map] = true end end end
    for _, nid in ipairs(type(x[8]) == 'table' and x[8] or {}) do addMaps(o, 'c' .. nid) end
    for _, iid in ipairs(type(x[10]) == 'table' and x[10] or {}) do
      local dl = D.drop[iid]
      if dl then for j = 1, math.min(#dl - 1, 6), 2 do addMaps(o, 'c' .. dl[j]) end end
      local od = D.odrop and D.odrop[iid]
      if od then for j = 1, math.min(#od - 1, 6), 2 do addMaps(o, 'o' .. od[j]) end end
    end
    for _, k in ipairs(D.qe[qid] or {}) do addMaps(e, k) end
    -- o plneni nic nevime: quest se obvykle plni v oblasti, kde se bere
    if not next(o) then for _, k in ipairs(D.qg[qid] or {}) do addMaps(o, k) end end
    local function list(t) local r = {} for m in pairs(t) do r[#r + 1] = m end table.sort(r) return table.concat(r, ',') end
    local so, se = list(o), list(e)
    if so ~= '' or se ~= '' then qz[qid] = so .. '|' .. se end
  end
  -- questove itemy: item -> questy, ktere ho potrebuji (x[10]); info o questu pro stav v tooltipu moba
  local iq, qi = {}, {}
  local fok = ns.Route and ns.Route.factionOk
  for qid, info in pairs(D.quest) do
    local x = type(D.qx[qid]) == 'table' and D.qx[qid] or {}
    local items = type(x[10]) == 'table' and x[10] or nil
    if items and items[1] then
      local gk, any
      for _, k in ipairs(D.qg[qid] or {}) do
        any = true
        if not fok or fok(k) then gk = k break end
      end
      if gk or not any then
        local gname, gmap = '', 0
        if gk then
          local id = tonumber(gk:sub(2))
          local t = gk:sub(1, 1) == 'c' and D.npc[id] or (D.obj and D.obj[id])
          gname = (t and t[1] or ''):gsub('|', '')
          local ok, sp = pcall(spotsOf or function() return {} end, gk)
          if ok and type(sp) == 'table' and sp[1] and sp[1].map then gmap = sp[1].map end
        end
        local pre = type(x[3]) == 'table' and table.concat(x[3], ',') or ''
        qi[qid] = ('%d|%d|%d|%s|%d|%s|%s'):format(info[2] or 0, info[3] or 1, safeNum(x[2]) or 0, gname, gmap, pre, (info[1] or '?'):gsub('|', ''))
        for _, it in ipairs(items) do iq[it] = iq[it] and (iq[it] .. ',' .. qid) or tostring(qid) end
      end
    end
  end
  -- itemy, ktere prodavaji vendori (pro nakupni seznam profesi)
  local vend = {}
  for it in pairs(D.vend or {}) do vend[it] = 1 end
  -- nakupni cena u vendora (nejlevnejsi): vp[npc][item] = { cena, pocet }
  for _, items in pairs(D.vp or {}) do
    if type(items) == 'table' then
      for it, e in pairs(items) do
        local pr = type(e) == 'table' and tonumber(e[1])
        if pr and pr > 0 and (vend[it] == 1 or not vend[it] or pr < vend[it]) then vend[it] = pr end
      end
    end
  end
  -- hranice barev receptu profesi (SkillLineAbility): [spell] = "zluta,seda"
  local sla = {}
  for sp, l in pairs(D.sla or {}) do
    local e = type(l) == 'table' and l[1]
    if type(e) == 'table' and (e[3] or 0) > 0 and (e[4] or 0) > 0 then sla[sp] = e[3] .. ',' .. e[4] end
  end
  -- recepty jako item (Pattern / Recipe / Formula / Plans / Schematic / Manual): [jmeno receptu] = "itemId|zdroj" (v vendor, d drop, q quest)
  local pat = {}
  for id, it in pairs(D.item) do
    local nm = it[1] or ''
    local rn = nm:match('^Pattern: (.+)$') or nm:match('^Recipe: (.+)$') or nm:match('^Formula: (.+)$') or nm:match('^Plans: (.+)$')
      or nm:match('^Schematic: (.+)$') or nm:match('^Manual: (.+)$')
    if rn then
      local src = (D.vend and D.vend[id] and 'v' or '') .. (D.drop[id] and 'd' or '') .. (D.rew and D.rew[id] and 'q' or '')
      -- kde: vendori (max 4) a nejcastejsi dropy (max 2) -> "v:npc:mapa:x:y,d:npc:mapa:x:y"
      local pts = {}
      local function add(kind, npc)
        if not spotsOf then return end
        local ok, sp = pcall(spotsOf, 'c' .. npc)
        local p = ok and type(sp) == 'table' and sp[1]
        if p and p.map and p.x then pts[#pts + 1] = ('%s:%d:%d:%d:%d'):format(kind, npc, p.map, p.x, p.y) end
      end
      for k, npc in ipairs(D.vend and D.vend[id] or {}) do if k > 4 then break end add('v', npc) end
      local dl = D.drop[id]
      if dl then
        local best = {}
        for j = 1, #dl - 1, 2 do best[#best + 1] = { dl[j], dl[j + 1] } end
        table.sort(best, function(a, b) return a[2] > b[2] end)
        for k = 1, math.min(2, #best) do add('d', best[k][1]) end
      end
      pat[rn] = id .. '|' .. src .. '|' .. table.concat(pts, ',')
    end
  end
  -- treneri vyssich ranku (Expert / Artisan / Master) podle podtitulku: [slovo profese] = "id|jmeno|podtitulek|frakce|mapa;..."
  local WORDS = { 'Tailor', 'Blacksmith', 'Leatherworker', 'Alchemist', 'Enchanter', 'Engineer', 'Cook', 'Chef', 'Herbalist', 'Miner',
    'Skinner', 'Fisherman', 'First Aid', 'Jewelcrafter', 'Clothier', 'Armorsmith', 'Weapon Crafter', 'Leather Goods' }
  local trn = {}
  for id, n in pairs(D.npc) do
    local sub = n[2]
    if type(sub) == 'string' and (sub:find('Artisan') or sub:find('Expert') or sub:find('Master')) then
      for _, w in ipairs(WORDS) do
        if sub:find(w, 1, true) then
          local map = 0
          if spotsOf then
            local ok, sp = pcall(spotsOf, 'c' .. id)
            if ok and type(sp) == 'table' and sp[1] and sp[1].map then map = sp[1].map end
          end
          local e = ('%d|%s|%s|%s|%d'):format(id, (n[1] or '?'):gsub('[|;]', ''), sub:gsub('[|;]', ''), (D.nfac and D.nfac[id]) or 'AH', map)
          trn[w] = trn[w] and (trn[w] .. ';' .. e) or e
          break
        end
      end
    end
  end
  ns.db.fdbc = { schema = 8, sla = sla, pat = pat, trn = trn, vend = vend, ver = fdbVersion(), drops = drops, gold = gold, names = names, lv = lv, start = start, qz = qz, iq = iq, qi = qi }
  MD.reset()
  return true
end

local dcache = {}
local function fdbDrops(npc, force)
  local c = C(force)
  if not c then
    if FDB() and not C(true) then MD.buildCache() c = C(force) end
    if not c then return nil end
  end
  local s = c.drops[npc]
  if not s then return nil end
  local l = dcache[npc]
  if l then return l end
  l = {}
  for id, ch, kind, name in s:gmatch('(%d+)~([%d%.]+)~(%w)~([^;]*)') do
    l[#l + 1] = { id = tonumber(id), chance = tonumber(ch), kind = kind, name = name }
  end
  dcache[npc] = l
  return l
end
local function fdbLevels(npc)
  local c = C()
  local s = c and c.lv and c.lv[npc]
  if not s then return nil end
  local lo, hi = s:match('(%d+),(%d+)')
  return tonumber(lo), tonumber(hi)
end
-- penize z moba (ForeverDB, skutecne killy): { avg, min, max, n } v copperech
function MD.money(id, force)
  local c = C(force)
  local s = c and type(id) == 'number' and c.gold[id]
  if not s then return nil end
  local a, mn, mx, n = s:match('(%d+),(%d+),(%d+),(%d+)')
  if not a then return nil end
  return { avg = tonumber(a), min = tonumber(mn), max = tonumber(mx), n = tonumber(n) }
end
-- zony questu z ForeverDB: obj = { [uiMap] = true } (plneni), turn = { ... } (odevzdani); nil = nevime
local qzc = {}
function MD.questMaps(qid)
  local c = C(true)
  local s = c and c.qz and c.qz[qid]
  if not s then return nil end
  local e = qzc[qid]
  if e then return e.obj, e.turn end
  local so, se = s:match('^([^|]*)|(.*)$')
  e = { obj = {}, turn = {} }
  for m in (so or ''):gmatch('%d+') do e.obj[tonumber(m)] = true end
  for m in (se or ''):gmatch('%d+') do e.turn[tonumber(m)] = true end
  qzc[qid] = e
  return e.obj, e.turn
end
-- questovy item: k jakemu questu je a jak na tom jsem -> kratky barevny stav + popis do tooltipu
local CB = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
function MD.questFor(item)
  local c = C(true)
  local s = c and c.iq and c.iq[item]
  if not s then return nil end
  local QL = C_QuestLog
  local lvl = safeNum(pc(UnitLevel, 'player')) or 1
  local _, cls = pc(UnitClass, 'player')
  local cbit = CB[safe(cls) or ''] or 0
  local best, br
  for qs in s:gmatch('%d+') do
    local q = tonumber(qs)
    local e = c.qi[q]
    if e then
      local ql, mn, cm, gname, gmap, pre, title = e:match('^(%d+)|(%d+)|(%d+)|([^|]*)|(%d+)|([^|]*)|(.*)$')
      ql, mn, cm, gmap = tonumber(ql), tonumber(mn), tonumber(cm), tonumber(gmap)
      local okClass = not cm or cm == 0 or cbit == 0 or math.floor(cm / cbit) % 2 == 1
      if okClass then
        local r, txt
        local inLog = QL and QL.GetLogIndexForQuestID and (safeNum(pc(QL.GetLogIndexForQuestID, q)) or 0) > 0
        local done = QL and QL.IsQuestFlaggedCompleted and safeBool(pc(QL.IsQuestFlaggedCompleted, q)) == true
        if inLog then r, txt = 1, '|cff40ff60mas quest|r'
        elseif done then r, txt = 6, '|cff888888uz hotovo|r'
        elseif mn and mn > lvl then r, txt = 4, ('|cffff5555quest od lvl %d|r'):format(mn)
        else
          local missing = false
          for p in (pre or ''):gmatch('%d+') do
            if not (QL and QL.IsQuestFlaggedCompleted and safeBool(pc(QL.IsQuestFlaggedCompleted, tonumber(p))) == true) then missing = true end
          end
          if missing then r, txt = 5, '|cffffcc00chybi predchozi quest|r'
          elseif ql and ql < lvl - 9 then r, txt = 3, '|cff9d9d9dsedy quest|r'
          else r, txt = 2, '|cffffd200vezmi quest|r' end
        end
        if not br or r < br then
          local zone = gmap and gmap > 0 and C_Map and C_Map.GetMapInfo and pc(C_Map.GetMapInfo, gmap)
          zone = type(zone) == 'table' and safe(zone.name) or nil
          best, br = { short = txt, title = title, giver = gname ~= '' and gname or nil, zone = zone, lvl = ql, min = mn, rank = r }, r
        end
      end
    end
  end
  return best
end
-- recept (spell) -> skill, kdy zezloutne a kdy zesedne (zelena = v pulce)
function MD.skillRange(spell)
  local c = C(true)
  local s = c and c.sla and spell and c.sla[spell]
  if not s then return nil end
  local y, g = s:match('(%d+),(%d+)')
  return tonumber(y), tonumber(g)
end
-- recept se uci z itemu (patternu)? -> itemId, zdroj ('v' vendor, 'd' drop, 'q' quest; muze byt vic)
function MD.patternFor(recipeName)
  local c = C(true)
  local s = c and c.pat and recipeName and c.pat[recipeName]
  if not s then return nil end
  local id, src, pts = s:match('^(%d+)|([^|]*)|?(.*)$')
  local list = {}
  for kind, npc, map, x, y in (pts or ''):gmatch('(%a):(%d+):(%d+):(%d+):(%d+)') do
    list[#list + 1] = { kind = kind, npc = tonumber(npc), map = tonumber(map), x = tonumber(x), y = tonumber(y) }
  end
  return tonumber(id), src or '', list
end
-- treneri vyssiho ranku pro profesi: { {id, name, sub, fac, map}, ... }
function MD.trainers(word)
  local c = C(true)
  local s = c and c.trn and word and c.trn[word]
  local out = {}
  for e in (s or ''):gmatch('[^;]+') do
    local id, nm, sub, fac, map = e:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(%d+)$')
    if id then out[#out + 1] = { id = tonumber(id), name = nm, sub = sub, fac = fac, map = tonumber(map) } end
  end
  return out
end
function MD.isVendor(item)
  local c = C(true)
  return c and c.vend and item and c.vend[item] ~= nil or false
end
-- nakupni cena u vendora v copperech (nil = nevime / neprodava)
function MD.vendorPrice(item)
  local c = C(true)
  local v = c and c.vend and item and c.vend[item]
  return (type(v) == 'number' and v > 1) and v or nil
end
-- questy, ktere item potrebuji (cil questu, x[10]): { qid, ... } nebo nil = databaze nevi
function MD.itemQuests(item)
  local c = C(true)
  local s = c and c.iq and item and c.iq[item]
  if not s then return nil end
  local out = {}
  for q in s:gmatch('%d+') do out[#out + 1] = tonumber(q) end
  return out
end
-- item uz neni potreba: vsechny questy, ktere ho chteji, mas hotove (a zadny neni v logu)
function MD.questItemDone(item)
  local qs = MD.itemQuests(item)
  if not qs or not qs[1] then return false end
  local QL = C_QuestLog
  if not (QL and QL.IsQuestFlaggedCompleted) then return false end
  for _, q in ipairs(qs) do
    local inLog = QL.GetLogIndexForQuestID and (safeNum(pc(QL.GetLogIndexForQuestID, q)) or 0) > 0
    if inLog or safeBool(pc(QL.IsQuestFlaggedCompleted, q)) ~= true then return false end
  end
  return true
end
-- item zacina quest: { qid, minLvl, lvl, title }
function MD.startsQuest(item)
  local c = C()
  local s = c and c.start and c.start[item]
  if not s then return nil end
  local q, mn, lv, t = s:match('^(%d+)|(%d+)|(%d+)|(.*)$')
  if not q then return nil end
  return { qid = tonumber(q), min = tonumber(mn), lvl = tonumber(lv), title = t }
end
function MD.coin(c)
  if ns.coin then return ns.coin(c) end
  c = math.floor(c + 0.5)
  if c >= 10000 then return ('%dg %ds'):format(math.floor(c / 10000), math.floor(c / 100) % 100) end
  if c >= 100 then return ('%ds %dc'):format(math.floor(c / 100), c % 100) end
  return c .. 'c'
end
function MD.dropsOf(id) return fdbDrops(id, true) end
-- databaze se nacetla: zahodit cache, at se dropy prepocitaji
function MD.reset() MD.cache = {} dcache = {} qzc = {} end

local function parse(id)
  local c = MD.cache[id]
  if c then return c end
  local s = ns.MOBDATA and ns.MOBDATA[id]
  if not s then return nil end
  local f = {}
  for v in (s .. '|'):gmatch('([^|]*)|') do f[#f + 1] = v end
  local r = { id = id, name = f[1], lmin = tonumber(f[2]), lmax = tonumber(f[3]), rank = tonumber(f[4]), ctype = tonumber(f[5]),
    mech = tonumber(f[6]) or 0, school = tonumber(f[7]) or 0, flee = f[9] == '1', cls = tonumber(f[10]), help = tonumber(f[11]),
    res = {}, spells = {}, heal = {}, cc = {}, summon = {}, dmgSchool = {} }
  for sc, v in (f[8] or ''):gmatch('(%a)(%d+)') do r.res[SCHOOL_OF[sc]] = tonumber(v) end
  for sp in (f[12] or ''):gmatch('[^;]+') do
    local tag, sc, cast, name = sp:match('^(%a):(%a)(%+?)(.+)$')
    if tag then
      local e = { tag = tag, school = SCHOOL_OF[sc], cast = cast == '+', name = name }
      r.spells[#r.spells + 1] = e
      if tag == 'h' then r.heal[#r.heal + 1] = name
      elseif tag == 'c' then r.cc[#r.cc + 1] = name
      elseif tag == 's' then r.summon[#r.summon + 1] = name
      elseif tag == 'd' and e.school ~= 'physical' then r.dmgSchool[e.school] = true end
    end
  end
  r.patrol = f[14] == '1'
  r.drops = {}
  for d in (f[13] or ''):gmatch('[^;]+') do
    local id, ch, kind, name = d:match('^(%d+)~([%d%.]+)~(%w)~(.+)$')
    if id then r.drops[#r.drops + 1] = { id = tonumber(id), chance = tonumber(ch), kind = kind, name = name } end
  end
  -- ForeverDB ma prednost (Forever != classic); levely moba podle Foreveru
  local fd = fdbDrops(id)
  if fd then
    r.drops, r.fdb = fd, true
    r.dlmin, r.dlmax = fdbLevels(id)
  end
  r.immPoly = has(r.mech, MECH.polymorph)
  r.immFear = has(r.mech, MECH.fear)
  r.immRoot = has(r.mech, MECH.root)
  r.immSnare = has(r.mech, MECH.snare)
  r.immStun = has(r.mech, MECH.stun)
  r.immBanish = has(r.mech, MECH.banish)
  r.immSchool = {}
  for nm, bit in pairs(SCH) do if has(r.school, bit) then r.immSchool[nm] = true end end
  MD.cache[id] = r
  return r
end

-- zaznam podle jmena; pri vic zaznamech se stejnym jmenem ten, jehoz level sedi
local function fdbOnly(name, level)
  local c = C()
  local s = c and c.names and c.names[name]
  if not s then return nil end
  local best, bd, blo, bhi, brk
  for sid, slo, shi, rk in s:gmatch('(%d+):(%d+):(%d+):(%d+)') do
    local id, lo, hi = tonumber(sid), tonumber(slo), tonumber(shi)
    local d = level and ((level < lo and lo - level) or (level > hi and level - hi) or 0) or 0
    if not bd or d < bd then best, bd, blo, bhi, brk = id, d, lo, hi, tonumber(rk) end
  end
  if not best then return nil end
  local key = 'f' .. best
  if MD.cache[key] then return MD.cache[key] end
  local r = { id = best, name = name, lmin = blo, lmax = bhi, rank = brk or 0, mech = 0, school = 0,
    res = {}, spells = {}, heal = {}, cc = {}, summon = {}, dmgSchool = {}, immSchool = {}, drops = fdbDrops(best) or {}, fdb = true, fdbOnly = true }
  r.dlmin, r.dlmax = blo, bhi
  MD.cache[key] = r
  return r
end

function MD.byNameLevel(name, level)
  if type(name) ~= 'string' then return nil end
  index()
  local l = MD.byName[name]
  if not l then return fdbOnly(name, level) end
  if #l == 1 or not level then return parse(l[1]) end
  local best, bd
  for _, id in ipairs(l) do
    local r = parse(id)
    local d = 0
    if level < r.lmin then d = r.lmin - level elseif level > r.lmax then d = level - r.lmax end
    if not bd or d < bd then best, bd = r, d end
  end
  return best
end
function MD.forUnit(u)
  local name = safe(pc(UnitName, u))
  if type(name) ~= 'string' then return nil end
  local lv = safeNum(pc(UnitLevel, u))
  return MD.byNameLevel(name, lv and lv > 0 and lv or nil)
end

local SPELL_FIELD = '^' .. ('[^|]*|'):rep(11) .. '([^|]*)'   -- 12. pole = kouzla
-- typ kouzla podle jmena napric vsemi moby (pro prioritu preruseni)
function MD.tagOf(spell)
  if type(spell) ~= 'string' then return nil end
  if not MD.spellTag then
    MD.spellTag = {}
    for _, s in pairs(ns.MOBDATA or {}) do
      local sp = s:match(SPELL_FIELD)
      if sp then
        for tag, name in sp:gmatch('(%a):%a%+?([^;]+)') do
          if tag == 'h' or tag == 'c' or tag == 's' then MD.spellTag[name] = tag end
        end
      end
    end
  end
  return MD.spellTag[spell]
end

-- dropy pro tooltip: jmeno itemu z vlastni hry (presne a barevne), jinak z databaze
local QCOL = { ['2'] = 'ff1eff00', ['3'] = 'ff0070dd', ['4'] = 'ffa335ee', ['5'] = 'ffff8000', c = 'ffffffff', q = 'ffffd100' }
function MD.dropText(r, level)
  if not r or #r.drops == 0 then return nil end
  -- Forever moba preskaloval na jiny level: bezne dropy nesedi, questove itemy asi ano
  local lo, hi = r.dlmin or r.lmin, r.dlmax or r.lmax
  local off = level and lo and (level < lo - 3 or level > hi + 3)
  local p = {}
  for _, d in ipairs(r.drops) do
    if not off or d.kind == 'q' then
      local nm = d.name
      local gi = C_Item and C_Item.GetItemInfo and safe(pc(C_Item.GetItemInfo, d.id)) or safe(pc(GetItemInfo, d.id))
      if type(gi) == 'string' and gi ~= '' then nm = gi end
      local ch = d.kind == 'q' and 'quest' or (d.chance >= 1 and ('%d%%'):format(math.floor(d.chance + 0.5)) or ('%.1f%%'):format(d.chance))
      p[#p + 1] = ('|c%s%s|r %s'):format(QCOL[d.kind] or 'ffffffff', nm, ch)
    end
  end
  if #p == 0 then return nil end
  local txt = table.concat(p, ', ')
  if off then txt = txt .. ('  |cff888888(%s lvl %d-%d, jinak se lisi)|r'):format(r.fdb and 'databaze' or 'classic', lo, hi) end
  return txt
end

-- dropy jako radky { jmeno (barevne), sance } + zda level nesedi
function MD.dropRows(r, level)
  if not r or #r.drops == 0 then return nil end
  local lo, hi = r.dlmin or r.lmin, r.dlmax or r.lmax
  local off = level and lo and (level < lo - 3 or level > hi + 3)
  local rows = {}
  for _, d in ipairs(r.drops) do
    if not off or d.kind == 'q' then
      local nm = d.name
      local gi = C_Item and C_Item.GetItemInfo and safe(pc(C_Item.GetItemInfo, d.id)) or safe(pc(GetItemInfo, d.id))
      if type(gi) == 'string' and gi ~= '' then nm = gi end
      local ch = d.kind == 'q' and 'quest' or (d.chance >= 1 and ('%d %%'):format(math.floor(d.chance + 0.5)) or ('%.1f %%'):format(d.chance))
      local qf = MD.questFor and MD.questFor(d.id)
      if qf then ch = qf.short
      elseif MD.startsQuest and MD.startsQuest(d.id) then ch = ch .. ' |cffffd200(zacina quest)|r' end
      rows[#rows + 1] = { ('|c%s%s|r'):format(QCOL[d.kind] or 'ffffffff', nm), ch, qf = qf }
    end
  end
  if #rows == 0 then return nil end
  return rows, off
end

-- kratky popis pro tooltip / info
function MD.describe(r)
  if not r then return nil end
  local p = {}
  if r.rank == 1 or r.rank == 2 then p[#p + 1] = '|cffffcc00elite|r' elseif r.rank == 3 then p[#p + 1] = '|cffff5555boss|r' end
  local imm = {}
  for sc in pairs(r.immSchool) do imm[#imm + 1] = CZ[sc] end
  if r.immPoly then imm[#imm + 1] = 'ovce' end
  if r.immFear then imm[#imm + 1] = 'fear' end
  if r.immRoot then imm[#imm + 1] = 'root' end
  if r.immStun then imm[#imm + 1] = 'stun' end
  table.sort(imm)
  if #imm > 0 then p[#p + 1] = '|cffff7070imunni:|r ' .. table.concat(imm, ', ') end
  local res = {}
  for sc, v in pairs(r.res) do if not r.immSchool[sc] then res[#res + 1] = CZ[sc] end end
  table.sort(res)
  if #res > 0 then p[#p + 1] = 'odolny: ' .. table.concat(res, ', ') end
  if #r.heal > 0 then p[#p + 1] = '|cff66ee77leci:|r ' .. table.concat(r.heal, ', ') end
  if #r.cc > 0 then p[#p + 1] = '|cffff7070CC:|r ' .. table.concat(r.cc, ', ') end
  if #r.summon > 0 then p[#p + 1] = 'privolava pomoc' end
  if r.flee then p[#p + 1] = '|cffffcc00utika|r' end
  if r.patrol then p[#p + 1] = 'patroluje' end
  return #p > 0 and table.concat(p, ', ') or nil
end

------------------------------------------------------------------------------------------
-- Napojeni (vlastni pozorovani maji prednost)
------------------------------------------------------------------------------------------
-- imunity: doplnit z databaze, co jsme se jeste nenaucili
if ns.Immune and ns.Immune.info then
  local orig = ns.Immune.info
  ns.Immune.info = function(...)
    local r = orig(...)
    local ok, d = pcall(MD.forUnit, 'target')
    if ok and d and r then
      for sc in pairs(d.immSchool) do if not r.schools[sc] then r.schools[sc] = 'db' end end
      if d.immPoly and not r.spells.Polymorph then r.spells.Polymorph = 'db' end
      if d.immFear and not r.spells.Fear then r.spells.Fear = 'db' r.spells.Seduction = r.spells.Seduction or 'db' end
      if d.immRoot and not r.spells['Frost Nova'] then r.spells['Frost Nova'] = 'db' end
      if d.immBanish and not r.spells.Banish then r.spells.Banish = 'db' end
      r.db = d
    end
    return r
  end
end

-- pamet moba: kouzli / utika z databaze, dokud nemame vlastni data
if ns.Mem and ns.Mem.info then
  local orig = ns.Mem.info
  ns.Mem.info = function(name, ctype, group)
    local r = orig(name, ctype, group)
    local d = type(name) == 'string' and MD.byNameLevel(name)
    if not (r and d) then return r end
    r.db = d
    if (r.n or 0) < 3 then
      if not r.caster and next(d.dmgSchool) then
        r.caster = true
        r.school = (d.dmgSchool.fire and 'fire') or (d.dmgSchool.frost and 'frost') or (d.dmgSchool.shadow and 'shadow') or nil
      end
      if d.flee and (not r.flees or r.fleeGuess) then r.flees, r.fleeGuess = true, nil end
      -- databaze vi, ze neutika (zadny skript na utek): zrusit odhad "humanoid asi utika"
      if not d.flee and r.fleeGuess then r.flees, r.fleeGuess = false, nil end
    end
    return r
  end
end

-- heal / CC moba (setreni interruptu)
if ns.mobCastInfo then
  local orig = ns.mobCastInfo
  ns.mobCastInfo = function(mob)
    local r = orig(mob)
    local d = MD.byNameLevel(mob)
    if d and (#d.heal > 0 or #d.cc > 0) then
      r = r or {}
      r.heal = r.heal or d.heal[1]
      r.cc = r.cc or d.cc[1]
    end
    return r
  end
end

-- priorita preruseni: databaze zna leceni / CC / privolani i u kouzel s nejasnym jmenem
if ns.castPrio then
  local orig = ns.castPrio
  ns.castPrio = function(name, sid, durMs)
    local p, why, kind = orig(name, sid, durMs)
    if (p or 0) < 3 then
      local t = MD.tagOf(name)
      if t == 'h' then return 3, 'leceni', 'heal'
      elseif t == 'c' then return 3, 'CC', 'CC'
      elseif t == 's' then return 3, 'privolava', 'summon' end
    end
    return p, why, kind
  end
end

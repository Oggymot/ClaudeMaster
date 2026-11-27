-- ClaudeMaster: pomocnik pro levelovani profesi (okno profese / TradeSkill)
--  * tlacitko "Vyrob": vybere recept, ktery ted nejlip zvedne skill (oranzovy > zluty > zeleny), a jednim klikem
--    vyrobi davku; kdyz recept behem vyroby zezelena a je jiny lepsi, davku zastavi
--  * dalsi kroky: co vyrabet pak
--  * nakupni seznam: co chybi na nejlepsi recepty (klik = kde to sehnat v Pruzkumnikovi)
--  * trener: kdyz jsi u stropu ranku
-- Kazdou vyrobu spousti klik hrace (Blizzard nedovoli vyrabet bez kliknuti).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local C = {}
ns.Craft = C

local RANK = { optimal = 4, medium = 3, easy = 2, trivial = 1 }
local COLOR = { optimal = 'ffff8040', medium = 'ffffff00', easy = 'ff40c040', trivial = 'ff808080' }
local LABEL = { optimal = 'oranzovy - jisty bod', medium = 'zluty - casto bod', easy = 'zeleny - obcas bod', trivial = 'sedy - uz nic' }
local BATCH = { optimal = 10, medium = 5, easy = 3 }   -- kolik naraz (pak se znovu prehodnoti)

local function api(n) return _G[n] end
local function itemId(link) return type(link) == 'string' and tonumber(link:match('item:(%d+)')) or nil end

-- precte okno profese: { name, rank, max, list = { {i, name, kind, avail, reag = { {name, need, have, link} }, link} } }
local function scanOld()
  local GL, GN, GI = api('GetTradeSkillLine'), api('GetNumTradeSkills'), api('GetTradeSkillInfo')
  if not (GL and GN and GI) then return nil end
  local name, rank, max = pc(GL)
  name, rank, max = safe(name), safeNum(rank), safeNum(max)
  if not name or name == 'UNKNOWN' then return nil end
  local out = { name = name, rank = rank or 0, max = max or 0, list = {} }
  local NR, RI, RL, IL = api('GetTradeSkillNumReagents'), api('GetTradeSkillReagentInfo'), api('GetTradeSkillReagentItemLink'), api('GetTradeSkillItemLink')
  for i = 1, safeNum(pc(GN)) or 0 do
    local rn, kind, avail = pc(GI, i)
    rn, kind = safe(rn), safe(kind)
    if rn and kind and kind ~= 'header' and kind ~= 'subheader' then
      local r = { i = i, name = rn, kind = kind, avail = safeNum(avail) or 0, reag = {}, link = IL and safe(pc(IL, i)) }
      for j = 1, (NR and safeNum(pc(NR, i))) or 0 do
        local an, _, need, have = pc(RI, i, j)
        r.reag[#r.reag + 1] = { name = safe(an) or '?', need = safeNum(need) or 1, have = safeNum(have) or 0, link = RL and safe(pc(RL, i, j)) }
      end
      out.list[#out.list + 1] = r
    end
  end
  return out
end

-- novejsi rozhrani (Forever): C_TradeSkillUI, recepty podle ID
local DIFF = { [0] = 'optimal', [1] = 'medium', [2] = 'easy', [3] = 'trivial' }
local function itemCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f and safeNum(pc(f, id)) or 0
end
-- v bance (hra si to pamatuje i po zavreni banky - staci ji jednou otevrit)
local function bankCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not (f and id) then return 0 end
  local all = safeNum(pc(f, id, true)) or 0
  return math.max(0, all - itemCount(id))
end
C.bankCount = bankCount
-- cena z aukce (nejnizsi za kus, posledni videna); stara > 3 dny se nebere
function C.ahPrice(id)
  local t = id and ns.db and ns.db.ahPrice and ns.db.ahPrice[id]
  if not t then return nil end
  if time and t.at and time() - t.at > 3 * 86400 then return nil end
  return t.p
end
local function itemName(id)
  local f = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return f and safe(pc(f, id)) or ('item ' .. id)
end
local function diffOf(info)
  local d = info.difficulty
  if type(d) == 'string' and RANK[d] then return d end
  if type(d) == 'number' and DIFF[d] then return DIFF[d] end
  local r = safeNum(info.relativeDifficulty)
  if r and DIFF[r] then return DIFF[r] end
  return nil
end
local function scanModern()
  local T = C_TradeSkillUI
  if not T then return nil end
  local name, rank, max
  if T.GetTradeSkillLine then
    local _, n, r, m = pc(T.GetTradeSkillLine)
    name, rank, max = safe(n), safeNum(r), safeNum(m)
  end
  if (not name or name == '') then
    for _, fn in ipairs({ 'GetChildProfessionInfo', 'GetBaseProfessionInfo' }) do
      local i = T[fn] and pc(T[fn])
      if type(i) == 'table' and safe(i.professionName) and safe(i.professionName) ~= '' then
        name, rank, max = safe(i.professionName), safeNum(i.skillLevel), safeNum(i.maxSkillLevel)
        break
      end
    end
  end
  if not name or name == '' or name == 'UNKNOWN' then return nil end
  local ids = (T.GetAllRecipeIDs and pc(T.GetAllRecipeIDs)) or (T.GetFilteredRecipeIDs and pc(T.GetFilteredRecipeIDs))
  if type(ids) ~= 'table' then return nil end
  local out = { name = name, rank = rank or 0, max = max or 0, list = {}, modern = true }
  for _, id in ipairs(ids) do
    local info = T.GetRecipeInfo and pc(T.GetRecipeInfo, id)
    if type(info) == 'table' and info.learned == false and safe(info.name) then
      -- neznamy recept (trener / recept z dropu): jen pro radu, co se naucit
      local kind = diffOf(info)
      -- odkud se uci (trener / vendor / drop) a zda splnujes pozadavky (skill)
      local src = T.GetRecipeSourceText and safe(pc(T.GetRecipeSourceText, id))
      src = type(src) == 'string' and src:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|n', ' ') or nil
      local reqOk, reqSkill = true, nil
      local req = T.GetRecipeRequirements and pc(T.GetRecipeRequirements, id)
      for _, q in ipairs(type(req) == 'table' and req or {}) do
        if type(q) == 'table' then
          if q.met == false then reqOk = false end
          local nm = safe(q.name)
          local sk = type(nm) == 'string' and tonumber(nm:match('%((%d+)%)'))
          if sk then reqSkill = sk end
        end
      end
      if not reqSkill and src then reqSkill = tonumber(src:match('%((%d+)%)')) end
      out.unlearned = out.unlearned or {}
      out.unlearned[#out.unlearned + 1] = { i = id, name = safe(info.name), kind = kind or '?', icon = safe(info.icon), src = src,
        reqOk = reqOk, reqSkill = reqSkill, trainer = src and (src:find('[Tt]rainer') or src:find('[Tt]rener')) and true or false,
        link = T.GetRecipeItemLink and safe(pc(T.GetRecipeItemLink, id)) }
    elseif type(info) == 'table' and info.learned ~= false and safe(info.name) then
      local kind = diffOf(info)
      local r = { i = id, name = safe(info.name), kind = kind or 'trivial', avail = safeNum(info.numAvailable), reag = {},
        ups = safeNum(info.numSkillUps),
        icon = safe(info.icon), link = (T.GetRecipeItemLink and safe(pc(T.GetRecipeItemLink, id))) or safe(info.hyperlink) }
      if T.GetRecipeNumReagents and T.GetRecipeReagentInfo then
        for j = 1, safeNum(pc(T.GetRecipeNumReagents, id)) or 0 do
          local an, _, need, have = pc(T.GetRecipeReagentInfo, id, j)
          r.reag[#r.reag + 1] = { name = safe(an) or '?', need = safeNum(need) or 1, have = safeNum(have) or 0,
            link = T.GetRecipeReagentItemLink and safe(pc(T.GetRecipeReagentItemLink, id, j)) }
        end
      elseif T.GetRecipeSchematic then
        local sch = pc(T.GetRecipeSchematic, id, false)
        for _, slot in ipairs(type(sch) == 'table' and type(sch.reagentSlotSchematics) == 'table' and sch.reagentSlotSchematics or {}) do
          local rg = type(slot.reagents) == 'table' and slot.reagents[1]
          local iid = rg and safeNum(rg.itemID)
          if iid and (slot.reagentType == nil or slot.reagentType == 1 or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)) then
            r.reag[#r.reag + 1] = { name = itemName(iid), need = safeNum(slot.quantityRequired) or 1, have = itemCount(iid), link = 'item:' .. iid }
          end
        end
      end
      -- kolik kusu vyrobis: hra (GetCraftableCount), jinak z materialu v taskach
      if not r.avail and T.GetCraftableCount then r.avail = safeNum(pc(T.GetCraftableCount, id)) end
      if not r.avail then
        local m
        for _, a in ipairs(r.reag) do local k = math.floor(a.have / math.max(1, a.need)) m = m and math.min(m, k) or k end
        r.avail = m or 0
      end
      out.list[#out.list + 1] = r
    end
  end
  return out
end
function C.scan()
  local s = scanOld()
  if s and #s.list > 0 then return s end
  return scanModern() or s
end
-- okno profese (stare TradeSkillFrame / nove ProfessionsFrame)
local function host()
  for _, n in ipairs({ 'TradeSkillFrame', 'ProfessionsFrame' }) do
    local fr = _G[n]
    if fr and fr.IsShown and fr:IsShown() then return fr end
  end
end

-- kolik materialu chybi na n kusu receptu
local function missing(r, n)
  local miss, total = {}, 0
  for _, a in ipairs(r.reag) do
    local m = a.need * n - a.have
    if m > 0 then
      local id = itemId(a.link)
      local v = id and ns.MobDB and ns.MobDB.isVendor and ns.MobDB.isVendor(id)
      miss[#miss + 1] = { name = a.name, n = m, have = a.have, link = a.link, vendor = v }
      -- material od vendora je snadny (jen koupit), ostatni (farmit / AH) tezky
      total = total + (v and m * 0.1 or m * 10)
    end
  end
  return miss, total
end
-- vyber: nejvyssi barva, ktera jde vyrobit; v ramci barvy nejmin materialu na kus (levnejsi)
local function cost(r) local c = 0 for _, a in ipairs(r.reag) do c = c + a.need end return c end
-- cena za bod skillu: material (vendor = nakupni cena, jinak co by dal vendor za prodej, vlastni polotovar = jeho material)
-- / ocekavany pocet bodu (oranzovy 1, zluty ~0.6, zeleny ~0.25) * body za kus
local CHANCE = { optimal = 1, medium = 0.6, easy = 0.25, trivial = 0 }
local priceCache = {}
local function sellPrice(id)
  local gi = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not gi then return nil end
  return safeNum(select(11, pc(gi, id)))
end
local function unitCost(a, byName, depth)
  local id = itemId(a.link)
  local key = id or a.name
  if priceCache[key] then return priceCache[key] end
  local MD = ns.MobDB
  local v = id and MD and MD.vendorPrice and MD.vendorPrice(id)
  local own = byName[a.name]
  local ah = id and C.ahPrice(id)
  local c
  if v then c = ah and math.min(v, ah) or v
  elseif own and depth < 2 then
    c = 0
    for _, x in ipairs(own.reag) do c = c + x.need * (unitCost(x, byName, depth + 1) or 0) end
    if ah and ah < c then c = ah end   -- polotovar je v aukci levnejsi nez z vlastni suroviny
  elseif ah then c = ah
  else c = id and sellPrice(id) or nil end
  priceCache[key] = c or 0
  return c or 0
end
function C.pointCost(r, byName)
  local c = 0
  for _, a in ipairs(r.reag) do c = c + a.need * unitCost(a, byName, 0) end
  -- vyrobek jde prodat vendorovi: odecist (muze vyjit i zisk)
  local out = itemId(r.link)
  r.mat, r.sell = c, (out and sellPrice(out)) or 0
  r.ahSell = out and C.ahPrice(out) and math.floor(C.ahPrice(out) * 0.95) or nil   -- aukce si bere 5 %
  -- polotovary (Bolt...) se neprodavaji, pouziji se dal
  if byName and r.link and r.sell > 0 then
    for _, x in ipairs(byName.__reagNames or {}) do if x == r.name then r.sell = 0 break end end
  end
  c = c - r.sell
  r.cc = c
  local exp = (CHANCE[r.kind] or 0) * (r.ups or 1)
  if exp <= 0 then return nil end
  return c / exp
end
function C.plan(s)
  priceCache = {}
  local byNameP = {}
  for _, r in ipairs(s.list) do byNameP[r.name] = r end
  local used = {}
  for _, r in ipairs(s.list) do for _, a in ipairs(r.reag) do if byNameP[a.name] then used[a.name] = true end end end
  byNameP.__reagNames = {}
  for nm in pairs(used) do table.insert(byNameP.__reagNames, nm) end
  for _, r in ipairs(s.list) do r.ppt = C.pointCost(r, byNameP) end
  if ns.db then
    ns.db.craftOut = ns.db.craftOut or {}
    for _, r in ipairs(s.list) do
      local out = itemId(r.link)
      if out and r.kind ~= 'trivial' then ns.db.craftOut[out] = { n = r.name, m = math.floor(r.mat or 0), v = r.sell or 0 } end
    end
  end
  local can, cant = {}, {}
  for _, r in ipairs(s.list) do
    if (RANK[r.kind] or 0) >= 2 then table.insert(r.avail > 0 and can or cant, r) end
  end
  local function better(a, b)
    -- nejlevnejsi bod skillu (cena materialu / sance na bod); zeleny jen kdyz nic jineho
    if (a.kind == 'easy') ~= (b.kind == 'easy') then return b.kind == 'easy' end
    local pa, pb = math.floor(math.max(0, a.ppt or 1e9)), math.floor(math.max(0, b.ppt or 1e9))
    if pa ~= pb then return pa < pb end
    if RANK[a.kind] ~= RANK[b.kind] then return RANK[a.kind] > RANK[b.kind] end
    local ca, cb = cost(a), cost(b)
    if ca ~= cb then return ca < cb end
    return a.name < b.name
  end
  table.sort(can, better)
  -- co nejde: nejlepsi barva a nejmin chybejiciho materialu na par kusu (vendor / vlastni polotovar = skoro nic)
  local byName0 = {}
  for _, r in ipairs(s.list) do byName0[r.name] = r end
  for _, r in ipairs(cant) do
    local miss, t = missing(r, 5)
    r.vendorOnly = #miss > 0
    for _, m in ipairs(miss) do
      local own = byName0[m.name]
      if own and own.avail > 0 and not m.vendor then t = t - m.n * 9.5 m.own = true end
      if not m.vendor and not m.own then r.vendorOnly = false end
    end
    r.missTotal = t
  end
  table.sort(cant, function(a, b)
    if (RANK[a.kind] >= 3) ~= (RANK[b.kind] >= 3) then return RANK[a.kind] >= 3 end
    if a.vendorOnly ~= b.vendorOnly then return a.vendorOnly end
    if a.vendorOnly then
      local pa, pb = math.floor(math.max(0, a.ppt or 1e9)), math.floor(math.max(0, b.ppt or 1e9))
      if pa ~= pb then return pa < pb end
    end
    if RANK[a.kind] ~= RANK[b.kind] then return RANK[a.kind] > RANK[b.kind] end
    return a.missTotal < b.missTotal
  end)
  local best = can[1]
  -- zeleny recept nema smysl, kdyz chybi jen par veci na oranzovy / zluty
  if best and best.kind == 'easy' and cant[1] and RANK[cant[1].kind] > 2 and (cant[1].missTotal <= 6 or cant[1].vendorOnly) then best = nil end
  -- lepsi recept blokuje jen polotovar, ktery umis vyrobit (napr. Bolt of Linen Cloth): nejdriv polotovar
  local byName = {}
  for _, r in ipairs(s.list) do byName[r.name] = r end
  local prep
  for _, r in ipairs(cant) do
    if RANK[r.kind] < 3 or (best and RANK[r.kind] <= RANK[best.kind]) then break end
    -- kolik kusu dovoli material, ktery vyrobit nejde (napr. nit od vendora); max davka
    local cap = BATCH[r.kind] or 3
    for _, a in ipairs(r.reag) do
      if not byName[a.name] then cap = math.min(cap, math.floor(a.have / a.need)) end
    end
    local miss = cap > 0 and missing(r, cap) or {}
    local ok, first = #miss > 0, nil
    for _, m in ipairs(miss) do
      local src = byName[m.name]
      if not (src and src.avail > 0) then ok = false break end
      first = first or { recipe = src, n = math.min(m.n, src.avail), target = r }
    end
    if ok and first then prep = first break end
  end
  s.prep = prep
  return best, can, cant
end

------------------------------------------------------------------------------------------
-- Plan levelovani: sance na bod podle hranic barev (ForeverDB) a simulace po bodech skillu
------------------------------------------------------------------------------------------
-- sance na bod pri skillu sk: oranzovy 1, pak (seda - sk) / (seda - zluta), sedy 0
local function chanceAt(r, sk, rank)
  local MD = ns.MobDB
  local y, g
  if MD and MD.skillRange and type(r.i) == 'number' and r.i > 1000 then y, g = MD.skillRange(r.i) end
  if y and g and g > 0 then
    if sk >= g then return 0 end
    if sk < y or g <= y then return 1 end
    return (g - sk) / (g - y)
  end
  -- hranice nezname: jen podle dnesni barvy, max par bodu
  if sk > rank + 5 then return 0 end
  return CHANCE[r.kind] or 0
end
C.chanceAt = chanceAt
-- kolik kusu jeste (prumerne) da skill, nez recept zesedne
function C.remaining(r, rank)
  local n = 0
  for sk = rank, rank + 150 do
    local p = chanceAt(r, sk, rank)
    if p <= 0 then break end
    n = n + 1 / (p * math.max(1, r.ups or 1))
  end
  return n
end
-- barvy pro plan: 'all' = vse, 'oy' = oranzove + zlute, 'o' = jen oranzove (jisty bod)
function C.mode(s) return (ns.db and ns.db.craftMode and ns.db.craftMode[s.name]) or 'all' end
function C.setMode(s, m)
  ns.db.craftMode = ns.db.craftMode or {}
  ns.db.craftMode[s.name] = (m ~= 'all') and m or nil
end
-- sance s ohledem na zvolene barvy (zluta = do pulky mezi zlutou a sedou)
local function chanceMode(r, sk, rank, mode)
  local p = chanceAt(r, sk, rank)
  if mode == 'all' or p <= 0 then return p end
  local MD = ns.MobDB
  local y, g
  if MD and MD.skillRange and type(r.i) == 'number' and r.i > 1000 then y, g = MD.skillRange(r.i) end
  if not (y and g) then
    -- hranice nezname: jen dnesni barva
    if mode == 'o' then return r.kind == 'optimal' and p or 0 end
    return (r.kind == 'optimal' or r.kind == 'medium') and p or 0
  end
  if sk < y then return p end                          -- oranzovy
  if mode == 'o' then return 0 end
  return (sk < math.floor((y + g) / 2)) and p or 0     -- zluty (zelena zacina v pulce)
end
-- kolik kusu jeste da skill v ramci zvolenych barev
function C.remaining(r, rank, mode)
  local n = 0
  for sk = rank, rank + 150 do
    local p = chanceMode(r, sk, rank, mode or 'all')
    if p <= 0 then break end
    n = n + 1 / (p * math.max(1, r.ups or 1))
  end
  return n
end
-- cilovy skill planu (nil = strop ranku)
function C.target(s)
  local t = ns.db and ns.db.craftTarget and ns.db.craftTarget[s.name]
  if t and t <= s.rank then return nil end
  return t
end
function C.setTarget(s, v)
  ns.db.craftTarget = ns.db.craftTarget or {}
  local top = (s.max and s.max > s.rank) and s.max or (s.rank + 75)
  if v and (v <= s.rank or v >= top) then v = nil end
  ns.db.craftTarget[s.name] = v
end
-- vybrane recepty (zaskrtnute); bez volby = oranzove a zlute
function C.selected(s, r)
  local t = ns.db and ns.db.craftSel and ns.db.craftSel[s.name]
  if t and t[r.name] ~= nil then return t[r.name] end
  return r.kind == 'optimal' or r.kind == 'medium'
end
function C.toggle(s, r)
  ns.db.craftSel = ns.db.craftSel or {}
  local t = ns.db.craftSel[s.name] or {}
  ns.db.craftSel[s.name] = t
  t[r.name] = not C.selected(s, r)
end
-- simulace: na kazdy bod skillu nejlevnejsi vybrany recept (cena kusu / sance); usek po useku
function C.simulate(s)
  local mode = C.mode(s)
  local sel = {}
  for _, r in ipairs(s.list) do if r.kind ~= 'trivial' and C.selected(s, r) then sel[#sel + 1] = r end end
  local segs, per, mats = {}, {}, {}
  local top = (s.max and s.max > s.rank) and s.max or (s.rank + 75)
  local tg = C.target(s)
  if tg and tg > s.rank and tg < top then top = tg end
  for sk = s.rank, top - 1 do
    local best, bc, bp
    for _, r in ipairs(sel) do
      local p = chanceMode(r, sk, s.rank, mode) * math.max(1, r.ups or 1)
      if p > 0 then
        -- zisk = cena 0 (jinak by vyhravaly zelene recepty jen kvuli vic kusum); pri shode vyssi sance
        -- + "cena za cas" na kazdy kus (5s + 20 % materialu), at plan nejede zelene recepty jen proto, ze na nich vydelas
        local c = (math.max(0, r.cc or 0) + 500 + 0.2 * (r.mat or 0)) / p
        if not bc or c < bc - 0.01 or (math.abs(c - bc) <= 0.01 and p > bp) then best, bc, bp = r, c, p end
      end
    end
    if not best then break end
    local seg = segs[#segs]
    if seg and seg.r == best then seg.to = sk + 1 seg.n = seg.n + 1 / bp
    else segs[#segs + 1] = { r = best, from = sk, to = sk + 1, n = 1 / bp } end
    per[best] = (per[best] or 0) + 1 / bp
  end
  -- material: soucet za vsechny kusy (cele kusy nahoru)
  local total, matT, sellT, crafts = 0, 0, 0, 0
  for r, n in pairs(per) do
    local k = math.ceil(n)
    crafts = crafts + k
    matT, sellT = matT + k * (r.mat or 0), sellT + k * (r.sell or 0)
    for _, a in ipairs(r.reag) do
      local key = a.name
      local e = mats[key] or { name = a.name, need = 0, have = a.have, link = a.link }
      e.need = e.need + a.need * k
      mats[key] = e
    end
    total = total + k * (r.cc or 0)
  end
  -- chybejici polotovar, ktery si vyrobis (Bolt of Mageweave z Mageweave Cloth): rozepsat na surovinu
  local byName = {}
  for _, r in ipairs(s.list) do byName[r.name] = r end
  for _, m in pairs(mats) do
    local miss = m.need - m.have
    local own = byName[m.name]
    if miss > 0 and own and #own.reag > 0 then
      m.craft = miss
      m.sub = {}
      for _, a in ipairs(own.reag) do
        m.sub[#m.sub + 1] = { name = a.name, need = a.need * miss, have = a.have, link = a.link }
      end
    end
  end
  return segs, mats, total, matT, sellT, crafts
end

------------------------------------------------------------------------------------------
-- Okno vedle profese
------------------------------------------------------------------------------------------
local f, state
local place
local WHITE = 'Interface\\Buttons\\WHITE8X8'
-- chytre umisteni panelu vedle okna: vpravo / vlevo / pod / nad - prvni misto, ktere je na obrazovce
-- a neprekryva jine otevrene okno (profese, aukce, vendor, tasky, nase panely)
local AVOID = { 'ProfessionsFrame', 'TradeSkillFrame', 'AuctionHouseFrame', 'AuctionFrame', 'MerchantFrame', 'BankFrame',
  'ContainerFrameCombinedBags', 'ContainerFrame1', 'ContainerFrame2', 'ContainerFrame3', 'ContainerFrame4', 'ContainerFrame5',
  'ClaudeMasterCraft', 'ClaudeMasterCraftAH', 'ClaudeMasterCraftShop', 'ClaudeMasterRoute', 'CharacterFrame', 'WorldMapFrame' }
local function rectOf(fr)
  if not (fr and fr.IsShown and fr:IsShown() and fr.GetLeft and fr:GetLeft()) then return nil end
  local sc = (fr:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return { l = fr:GetLeft() * sc, r = fr:GetRight() * sc, t = fr:GetTop() * sc, b = fr:GetBottom() * sc }
end
local function overlap(a, b) return a.l < b.r - 2 and a.r > b.l + 2 and a.b < b.t - 2 and a.t > b.b + 2 end
function C.placeSmart(fr, hostFr, gap, rightOff)
  gap = gap or 4
  local h = rectOf(hostFr)
  fr:ClearAllPoints()
  if not h then fr:SetPoint('CENTER', UIParent, 'CENTER', 300, 0) return end
  local w, ht = fr:GetWidth(), fr:GetHeight()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local cands = {
    { 'TOPLEFT', 'TOPRIGHT', (rightOff or 0) + gap, 0, h.r + (rightOff or 0) + gap, h.t },
    { 'TOPRIGHT', 'TOPLEFT', -gap, 0, h.l - gap - w, h.t },
    { 'TOPLEFT', 'BOTTOMLEFT', 0, -gap, h.l, h.b - gap },
    { 'BOTTOMLEFT', 'TOPLEFT', 0, gap, h.l, h.t + gap + ht },
  }
  local others = {}
  for _, n in ipairs(AVOID) do
    local o = _G[n]
    if o and o ~= fr and o ~= hostFr then local r = rectOf(o) if r then others[#others + 1] = r end end
  end
  local fallback
  for _, c in ipairs(cands) do
    local r = { l = c[5], r = c[5] + w, t = c[6], b = c[6] - ht }
    if r.l >= 0 and r.r <= W and r.b >= 0 and r.t <= H then
      fallback = fallback or c
      local ok = true
      for _, o in ipairs(others) do if overlap(r, o) then ok = false break end end
      if ok then fr:SetPoint(c[1], hostFr, c[2], c[3], c[4]) return end
    end
  end
  local c = fallback or cands[1]
  fr:SetPoint(c[1], hostFr, c[2], c[3], c[4])
end
local function accent2(a) local c = ns.THEME and ns.THEME.ui or { 0.3, 0.7, 1 } return c[1], c[2], c[3], a or 1 end
local function build()
  local T = ns.THEME
  f = CreateFrame('Frame', 'ClaudeMasterCraft', UIParent, 'BackdropTemplate')
  f:SetSize(300, 120)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.94) f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata('HIGH') f:SetClampedToScreen(true)
  -- presouvani (tahem za okraj / nadpis) a zmena velikosti (roh); poloha se pamatuje relativne k oknu profese
  f:SetMovable(true) f:SetResizable(true) f:EnableMouse(true) f:RegisterForDrag('LeftButton')
  if f.SetResizeBounds then f:SetResizeBounds(240, 100, 700, 900) elseif f.SetMinResize then f:SetMinResize(240, 100) end
  f:SetScript('OnDragStart', f.StartMoving)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local h = host()
    if h and ns.db then
      ns.db.craftOff = { self:GetLeft() - h:GetRight(), self:GetTop() - h:GetTop() }
    end
    place()
  end)
  local grip = CreateFrame('Button', nil, f)
  grip:SetSize(14, 14) grip:SetPoint('BOTTOMRIGHT', -1, 1) grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
  grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
  grip:SetScript('OnMouseDown', function() f.sizing = true f:StartSizing('BOTTOMRIGHT') end)
  grip:SetScript('OnMouseUp', function()
    f:StopMovingOrSizing() f.sizing = false
    if ns.db then ns.db.craftW, ns.db.craftH = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) end
    local h = host()
    if h and ns.db then ns.db.craftOff = { f:GetLeft() - h:GetRight(), f:GetTop() - h:GetTop() } end
    C.refresh()
  end)
  grip:SetScript('OnDoubleClick', function()
    if ns.db then ns.db.craftW, ns.db.craftH, ns.db.craftOff = nil, nil, nil end
    C.refresh()
  end)
  grip:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_TOP') GameTooltip:AddLine('Velikost panelu', 1, 1, 1)
    GameTooltip:AddLine('Tahni za roh. Panel presunes tahem za nadpis. Dvojklik = puvodni velikost i misto.', 0.8, 0.8, 0.8, true) GameTooltip:Show()
  end)
  grip:SetScript('OnLeave', function() GameTooltip:Hide() end)
  f.sizing = false
  f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') f.title:SetPoint('TOPLEFT', 10, -8)
  f.title:SetTextColor(unpack(T.title))
  f.skill = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') f.skill:SetPoint('TOPRIGHT', -62, -10)
  local pb = CreateFrame('Button', nil, f, 'BackdropTemplate')
  pb:SetSize(48, 16) pb:SetPoint('TOPRIGHT', -8, -7)
  pb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  pb.t = pb:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') pb.t:SetPoint('CENTER') pb.t:SetText('Plan')
  pb:SetScript('OnClick', function() C.planMode = not C.planMode C.refresh() end)
  pb:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_TOP') GameTooltip:AddLine('Plan levelovani', 1, 1, 1)
    GameTooltip:AddLine('Zaskrtni recepty, ktere chces delat; addon spocita nejlevnejsi postup az do stropu ranku, kolik kusu ktereho receptu a material.', 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  pb:SetScript('OnLeave', function() GameTooltip:Hide() end)
  f.planBtn = pb
  -- tlacitka barev planu (radek "Barvy")
  f.md = {}
  for i, d in ipairs({ { 'all', 'vse' }, { 'oy', 'O+Z' }, { 'o', 'O' } }) do
    local tb = CreateFrame('Button', nil, f, 'BackdropTemplate')
    tb:SetSize(34, 14)
    tb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    tb:SetFrameLevel(f:GetFrameLevel() + 20)   -- nad radky panelu (jinak klik chyti radek)
    tb.t = tb:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') tb.t:SetPoint('CENTER') tb.t:SetText(d[2])
    tb.key = d[1]
    tb:SetScript('OnClick', function(self) if f.mdFn then f.mdFn(self.key) end end)
    tb:SetScript('OnEnter', function(self)
      GameTooltip:SetOwner(self, 'ANCHOR_TOP')
      GameTooltip:AddLine(({ all = 'Vsechny barvy (i zelene - vic kusu, levnejsi)', oy = 'Jen oranzove a zlute', o = 'Jen oranzove - kazdy kus = jisty bod' })[self.key], 1, 1, 1)
      GameTooltip:Show()
    end)
    tb:SetScript('OnLeave', function() GameTooltip:Hide() end)
    tb:Hide()
    f.md[i] = tb
  end
  -- tlacitka cile skillu (ukazi se na radku "Cil skillu")
  f.tg = {}
  local defs = { { 'm5', '-5' }, { 'm1', '-1' }, { 'p1', '+1' }, { 'p5', '+5' }, { 'max', 'max' } }
  for i, d in ipairs(defs) do
    local tb = CreateFrame('Button', nil, f, 'BackdropTemplate')
    tb:SetSize(d[1] == 'max' and 32 or 24, 14)
    tb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    tb:SetFrameLevel(f:GetFrameLevel() + 20)   -- nad radky panelu (jinak klik chyti radek)
    tb.t = tb:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') tb.t:SetPoint('CENTER') tb.t:SetText(d[2])
    tb.key = d[1]
    tb:SetScript('OnClick', function(self) if f.tgFn then f.tgFn(self.key) end end)
    tb:Hide()
    f.tg[i] = tb
  end
  -- velke tlacitko "Vyrob"
  local b = CreateFrame('Button', nil, f, 'BackdropTemplate')
  b:SetPoint('TOPLEFT', 8, -28) b:SetPoint('TOPRIGHT', -8, -28) b:SetHeight(40)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b:SetBackdropColor(0.2, 0.45, 0.2, 0.55) b:SetBackdropBorderColor(0.35, 0.8, 0.35, 0.9)
  b.icon = b:CreateTexture(nil, 'ARTWORK') b.icon:SetSize(32, 32) b.icon:SetPoint('LEFT', 4, 0) b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.text = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight') b.text:SetPoint('TOPLEFT', 42, -5) b.text:SetPoint('RIGHT', -6, 0)
  b.text:SetJustifyH('LEFT') b.text:SetWordWrap(false)
  b.sub = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') b.sub:SetPoint('BOTTOMLEFT', 42, 5) b.sub:SetPoint('RIGHT', -6, 0)
  b.sub:SetJustifyH('LEFT') b.sub:SetWordWrap(false)
  b:SetHighlightTexture(WHITE, 'ADD') b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
  b:SetScript('OnClick', function() C.craft() end)
  b:SetScript('OnEnter', function(self)
    if not (state and state.best) then return end
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    if state.best.link then pcall(GameTooltip.SetHyperlink, GameTooltip, state.best.link) else GameTooltip:AddLine(state.best.name) end
    GameTooltip:AddLine(' ')
    GameTooltip:AddLine('Klik = vyrobit davku. Kdyz recept zezelena a mas lepsi, vyroba se sama zastavi.', 0.55, 0.85, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  f.btn = b
  -- radky: dalsi kroky, nakupni seznam, trener
  f.lines = {}
  for i = 1, 40 do
    local l = CreateFrame('Button', nil, f)
    l:SetHeight(16) l:SetPoint('LEFT', 10, 0) l:SetPoint('RIGHT', -10, 0)
    l.bg = l:CreateTexture(nil, 'BACKGROUND') l.bg:SetAllPoints() l.bg:SetColorTexture(1, 1, 1, 0)
    l.hl = l:CreateTexture(nil, 'HIGHLIGHT') l.hl:SetAllPoints() l.hl:SetColorTexture(1, 1, 1, 0.07)
    l.icon = l:CreateTexture(nil, 'ARTWORK') l.icon:SetSize(14, 14) l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    l.text = l:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') l.text:SetJustifyH('LEFT') l.text:SetWordWrap(false)
    l.right = l:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') l.right:SetPoint('RIGHT', -2, 0) l.right:SetJustifyH('RIGHT')
    l.hline = l:CreateTexture(nil, 'ARTWORK') l.hline:SetTexture(WHITE) l.hline:SetHeight(1)
    l.hline:SetPoint('BOTTOMLEFT', 0, 1) l.hline:SetPoint('BOTTOMRIGHT', 0, 1)
    l:SetScript('OnClick', function(self) if self.onClick then self.onClick(self) end end)
    l:SetScript('OnEnter', function(self)
      if not (self.link or self.tip) then return end
      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      if self.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) end
      if self.tip then GameTooltip:AddLine(self.tip, 0.55, 0.85, 1, true) end
      GameTooltip:Show()
    end)
    l:SetScript('OnLeave', function() GameTooltip:Hide() end)
    f.lines[i] = l
  end
  f:Hide()
end

function place()
  local h = host()
  local off = ns.db and ns.db.craftOff
  f:SetWidth((ns.db and ns.db.craftW) or 300)
  -- hrac si panel posunul: drzet jeho misto; jinak chytre (vpravo za svislymi tlacitky profesi, nebo jinde)
  if h and off then f:ClearAllPoints() f:SetPoint('TOPLEFT', h, 'TOPRIGHT', off[1], off[2])
  elseif h then C.placeSmart(f, h, 4, 52)
  else f:ClearAllPoints() f:SetPoint('RIGHT', UIParent, 'RIGHT', -300, 100) end
end

-- kde sehnat material: Pruzkumnik (ForeverDB) - detail itemu
-- kratka cena: nad 1g "1g 20s", nad 1s jen stribro, jinak copper (s ikonami minci)
local function shortCoin(c)
  c = math.floor(c + 0.5)
  if not ns.coin then return c .. 'c' end
  if c >= 10000 then return ns.coin(math.floor(c / 100) * 100) end
  if c >= 100 then return ns.coin(math.floor(c / 100 + 0.5) * 100) end
  return ns.coin(c)
end
local function ppt(r, plain)
  if not (r and r.ppt) then return '' end
  local t
  if r.ppt <= -1 then t = '|cff40ff60zisk ~' .. shortCoin(-r.ppt) .. '|r'
  elseif r.ppt < 1 then t = 'zdarma'
  else t = '~' .. shortCoin(r.ppt) end
  return plain and (t .. '/bod') or (' |cff9aa6b8' .. t .. '|cff9aa6b8/bod|r')
end
local function findItem(link, name)
  local id = itemId(link)
  if not (id and ns.Explore and ns.Options and ns.Options.toggle) then ns.say('Material: ' .. tostring(name)) return end
  if ns.Route and not ns.Route.DB() then
    if not (ns.Route.available and ns.Route.available()) then ns.say('Kde sehnat ' .. tostring(name) .. ': potrebuje addon ForeverDB.') return end
    ns.Route.load()
  end
  ns.Options.toggle('explore')
  if ns.Options.exploreShow then ns.Options.exploreShow(ns.Explore.item(id)) end
end

function C.refresh()
  if not f then build() end
  if f.sizing then return end
  local s = C.scan()
  if not s or not (C.open or host()) then f:Hide() return end
  local best, can, cant = C.plan(s)
  state = { s = s, best = best }
  local prep = s.prep
  -- tlacitko dela prvni krok planu (stejne barvy, cil a zaskrtnute recepty jako plan)
  local planBuy, planN
  local segs = C.simulate(s)
  local first = segs[1]
  if first then
    local pr = first.r
    planN = math.max(1, math.ceil(first.n))
    if pr.avail > 0 then
      best, prep = pr, nil
    else
      best, prep = nil, nil
      local byName = {}
      for _, r in ipairs(s.list) do byName[r.name] = r end
      local miss = missing(pr, planN)
      local allOwnOrVendor, ownFirst = true, nil
      for _, m in ipairs(miss) do
        local own = byName[m.name]
        if own and own.avail > 0 then ownFirst = ownFirst or { recipe = own, n = math.min(m.n, own.avail), target = pr }
        elseif not m.vendor then allOwnOrVendor = false end
      end
      if ownFirst then prep = ownFirst
      elseif allOwnOrVendor and #miss > 0 then planBuy = pr end
      if not prep and not planBuy then planBuy = nil end
    end
    state.best = best
  end
  f.title:SetText('Levelovani: ' .. s.name)
  f.skill:SetText(('|cffffd200%d|r / %d'):format(s.rank, s.max))
  local b = f.btn
  if prep then
    state.best, state.n = prep.recipe, prep.n
    local tex = prep.recipe.icon or (api('GetTradeSkillIcon') and safe(pc(api('GetTradeSkillIcon'), prep.recipe.i)))
    b.icon:SetTexture(tex or 'Interface\\Icons\\INV_Misc_QuestionMark')
    b.text:SetText(('Vyrob %dx |cffffffff%s|r'):format(prep.n, prep.recipe.name))
    b.sub:SetText(('|cff9aa6b8polotovar na |c%s%s|r|cff9aa6b8 (%s)|r'):format(COLOR[prep.target.kind] or 'ffffffff', prep.target.name, LABEL[prep.target.kind] or ''))
    b:Enable() b:SetAlpha(1)
  elseif best then
    local n = math.min(best.avail, planN or BATCH[best.kind] or 1)
    state.n = n
    local tex = best.icon or (api('GetTradeSkillIcon') and safe(pc(api('GetTradeSkillIcon'), best.i)))
    b.icon:SetTexture(tex or 'Interface\\Icons\\INV_Misc_QuestionMark')
    b.text:SetText(('Vyrob %dx |c%s%s|r'):format(n, COLOR[best.kind] or 'ffffffff', best.name))
    b.sub:SetText(('|cff9aa6b8%s, mas na %d%s  -  %s|r'):format(best.kind == 'optimal' and 'oranzovy' or (best.kind == 'medium' and 'zluty' or 'zeleny'),
      best.avail, (best.ups and best.ups > 1) and (', +%d/kus'):format(best.ups) or '', ppt(best, true)))
    b:Enable() b:SetAlpha(1)
  else
    b.icon:SetTexture('Interface\\Icons\\INV_Misc_Bag_10')
    local useful = 0
    for _, r in ipairs(s.list) do if RANK[r.kind] >= 3 then useful = useful + 1 end end
    local buy = planBuy or (not first and cant[1] and RANK[cant[1].kind] >= 3 and cant[1].vendorOnly and cant[1])
    local buyN = planBuy and planN or 5
    if s.rank >= s.max and s.max > 0 then
      b.text:SetText('|cffffcc00Strop ranku - jdi k trenerovi|r') b.sub:SetText('')
    elseif buy then
      local m = missing(buy, buyN)
      local parts = {}
      for _, x in ipairs(m) do if x.vendor then parts[#parts + 1] = x.n .. 'x ' .. x.name end end
      for _, x in ipairs(m) do if not x.vendor then parts[#parts + 1] = '|cff40c040vyrob ' .. x.n .. 'x ' .. x.name .. '|r' end end
      b.text:SetText(('%dx |c%s%s|r'):format(buyN, COLOR[buy.kind] or 'ffffffff', buy.name))
      b.sub:SetText('|cffffd200kup u vendora:|r |cff9aa6b8' .. table.concat(parts, ', ') .. '  -  ' .. ppt(buy, true) .. '|r')
    elseif useful == 0 then
      b.text:SetText('|cffffcc00Zadny oranzovy / zluty recept|r') b.sub:SetText('|cff9aa6b8nove recepty u trenera|r')
    elseif first then
      b.text:SetText(('|cffff8855Chybi material na %dx|r |c%s%s|r'):format(planN, COLOR[first.r.kind] or 'ffffffff', first.r.name))
      b.sub:SetText('|cff9aa6b8co sehnat - viz nize (v planu)|r')
    else
      b.text:SetText('|cffff8855Chybi material|r') b.sub:SetText('|cff9aa6b8co sehnat - viz nize|r')
    end
    b:Disable() b:SetAlpha(0.7)
  end
  -- radky
  local rows = {}
  local function row(text, extra) extra = extra or {} extra.text = text rows[#rows + 1] = extra end
  local function head(t, tip) rows[#rows + 1] = { head = t, text = '', tip = tip } end
  local function icn(link) local id = itemId(link) local f2 = (C_Item and C_Item.GetItemIconByID) or GetItemIcon return id and f2 and safe(pc(f2, id)) or nil end
  local function col(r, t) return ('|c%s%s|r'):format(COLOR[r.kind] or 'ffffffff', t or r.name) end
  local G = '|cff9aa6b8'
  f.planBtn:SetBackdropColor(accent2(C.planMode and 0.5 or 0.12)) f.planBtn:SetBackdropBorderColor(accent2(C.planMode and 1 or 0.5))
  local TRAIN = 'Interface\\GossipFrame\\TrainerGossipIcon'
  if s.max > 0 and s.max - s.rank <= 10 and s.max < 300 then
    row(('|cffffcc00Dalsi rank u trenera|r'), { icon = TRAIN, right = G .. ('strop %d|r'):format(s.max), tip = 'Bez noveho ranku se skill nad strop nezvedne.' })
  end
  -- malo uzitecnych receptu: u trenera budou nove (oranzove)
  local orange, yellow = 0, 0
  for _, r in ipairs(s.list) do if r.kind == 'optimal' then orange = orange + 1 elseif r.kind == 'medium' then yellow = yellow + 1 end end
  if orange == 0 and yellow <= 2 and not (s.max > 0 and s.max - s.rank <= 10) then
    row('|cffffcc00Nove recepty u trenera|r', { icon = TRAIN, right = G .. ('oranz. 0, zlut. %d|r'):format(yellow),
      tip = 'Recepty, ktere znas, uz skoro nedavaji skill. Nove (oranzove) se uci u trenera nebo z receptu (drop, vendor).' })
  end
  -- nove recepty: ty, ktere neumis a pro tvuj skill by byly oranzove (Forever u neznamych receptu neposila zdroj; hranice barev ma ForeverDB)
  local un = {}
  local MD = ns.MobDB
  for _, r in ipairs(s.unlearned or {}) do
    local y, g
    if MD and MD.skillRange and type(r.i) == 'number' then y, g = MD.skillRange(r.i) end
    if y and g and y > s.rank and y <= s.rank + 30 and g > s.rank then r.yellowAt = y un[#un + 1] = r end
  end
  table.sort(un, function(a, b) if a.yellowAt ~= b.yellowAt then return a.yellowAt > b.yellowAt end return a.name < b.name end)
  local nextC = {}
  for _, r in ipairs(can) do if r ~= best and #nextC < 2 then nextC[#nextC + 1] = r end end
  if nextC[1] then head('Pak') end
  for _, r in ipairs(nextC) do
    row(col(r), { icon = r.icon, right = G .. ('mas na %d|r'):format(r.avail) .. ppt(r), link = r.link })
  end
  -- nakupni seznam: nejlepsi recepty, na ktere material chybi (oranzove / zlute)
  local shown = 0
  for _, r in ipairs(cant) do
    if shown >= ((ns.db and ns.db.craftH and ns.db.craftH > 260) and 5 or 2) or RANK[r.kind] < 3 then break end
    if shown == 0 then head('Chybi material (na 5 ks)') end
    shown = shown + 1
    local miss = missing(r, 5)
    row(col(r), { icon = r.icon, right = ppt(r), link = r.link })
    for _, m in ipairs(miss) do
      local own
      for _, x in ipairs(s.list) do if x.name == m.name then own = x end end
      row(('%dx %s'):format(m.n, m.name), { indent = 14, icon = icn(m.link),
        right = own and '|cff40c040vyrobis|r' or (m.vendor and '|cffffd200vendor|r' or (G .. 'mas ' .. m.have .. '|r')),
        link = m.link, tip = 'Klik = kde sehnat (Pruzkumnik: vendori, dropy)', onClick = function() findItem(m.link, m.name) end })
    end
  end
  if un[1] then
    head(('Nove recepty pro tvuj skill (%d)'):format(#un), 'Recepty, ktere neumis a byly by pro tebe oranzove. Uci se u trenera, nebo z receptu (vendor / drop).')
    local lim = (ns.db and ns.db.craftH and ns.db.craftH > 260) and 8 or 4
    for i, r in ipairs(un) do
      if i > lim then break end
      row(('|cffff8040%s|r'):format(r.name), { icon = r.icon, right = G .. ('oranz. do %d|r'):format(r.yellowAt), link = r.link })
    end
  end
  if C.planMode then
    rows = {}
    -- seznam receptu se zaskrtnutim
    local list = {}
    for _, r in ipairs(s.list) do if r.kind ~= 'trivial' then list[#list + 1] = r end end
    table.sort(list, function(a, b) if RANK[a.kind] ~= RANK[b.kind] then return RANK[a.kind] > RANK[b.kind] end return a.name < b.name end)
    head('Recepty v planu', 'Klik na recept = pridat / odebrat z planu.')
    for _, r in ipairs(list) do
      local on = C.selected(s, r)
      local rem = C.remaining(r, s.rank, C.mode(s))
      row(on and col(r) or ('|cff808080' .. r.name .. '|r'), { icon = on and 'Interface\\Buttons\\UI-CheckBox-Check' or 'Interface\\Buttons\\UI-CheckBox-Up',
        right = G .. ('~%d ks|r'):format(math.floor(rem + 0.5)) .. ppt(r),
        link = r.link, tip = 'Klik = pridat / odebrat z planu', onClick = function() C.toggle(s, r) C.refresh() end })
    end
    local segs, mats, total, matT, sellT, crafts = C.simulate(s)
    head('Nastaveni')
    local top = (s.max and s.max > s.rank) and s.max or (s.rank + 75)
    local tg = C.target(s) or top
    local md = C.mode(s)
    row(('Barvy  %s'):format(md == 'o' and '|cffff8040oranzove|r' or (md == 'oy' and '|cffff8040oranz.|r + |cffffff00zlute|r' or G .. 'vse|r')),
      { modes = function(m) C.setMode(s, m) C.refresh() end })
    row(('Cil  |cffffffff%d|r %s(+%d)|r'):format(tg, G, tg - s.rank),
      { controls = function(btn)
          local cur = C.target(s) or top
          if btn == 'm5' then C.setTarget(s, math.max(s.rank + 1, cur - 5))
          elseif btn == 'p5' then C.setTarget(s, math.min(top, cur + 5))
          elseif btn == 'm1' then C.setTarget(s, math.max(s.rank + 1, cur - 1))
          elseif btn == 'p1' then C.setTarget(s, math.min(top, cur + 1))
          else C.setTarget(s, nil) end
          C.refresh()
        end })
    if segs[1] then
      head(('Plan  %d -> %d'):format(segs[1].from, segs[#segs].to))
      row(('|cffffffff%d vyrob|r'):format(crafts), {
        right = total < 0 and ('|cff40ff60zisk ~' .. shortCoin(-total) .. '|r') or ('|cffffd200~' .. shortCoin(total) .. '|r'),
        tip = ('Material ~%s, prodej vyrobku vendorovi ~%s.\nMaterial: vendor za nakupni cenu, ostatni za cenu z aukce (kdyz ji addon videl), jinak za prodejni. Polotovary se nepocitaji jako prodej.'):format(shortCoin(matT), shortCoin(sellT)) })
      if segs[#segs].to < (C.target(s) or top) then
        row(('|cffffcc00Od %d uz %s|r'):format(segs[#segs].to, md == 'o' and 'neni oranzovy recept' or (md == 'oy' and 'neni oranz. ani zluty' or 'nic nedava skill')),
          { icon = TRAIN, tip = 'Nove recepty u trenera nebo z receptu.' })
      end
      for _, g in ipairs(segs) do
        row(('|cffffffff%dx|r %s'):format(math.ceil(g.n), col(g.r)), { icon = g.r.icon, right = G .. ('%d-%d|r'):format(g.from, g.to), link = g.r.link })
      end
      head('Material')
      local ml = {}
      for _, m in pairs(mats) do ml[#ml + 1] = m end
      table.sort(ml, function(a, b) return a.name < b.name end)
      local planMats = {}
      for _, m in ipairs(ml) do
        local mid = itemId(m.link)
        m.bank = bankCount(mid)
        local miss = m.need - m.have - m.bank
        if mid then planMats[mid] = { name = m.name, need = m.need } end
        for _, sb in ipairs(m.sub or {}) do local sid = itemId(sb.link) if sid then planMats[sid] = { name = sb.name, need = sb.need } end end
        local vend = mid and ns.MobDB and ns.MobDB.isVendor and ns.MobDB.isVendor(mid)
        local st
        if miss > 0 then st = ('|cffff8855chybi %d|r'):format(miss) .. (vend and ' |cffffd200vendor|r' or '')
        else st = '|cff40c040mas|r' end
        if m.bank > 0 then st = ('|cff66ccff%d v bance|r  '):format(m.bank) .. st end
        row(('%dx %s'):format(m.need, m.name), { icon = icn(m.link), right = st,
          link = m.link, tip = 'Klik = kde sehnat', onClick = function() findItem(m.link, m.name) end })
        -- polotovar: vyrob ho ze suroviny, kterou mas / sezenes
        for _, sb in ipairs(m.sub or {}) do
          local sbank = bankCount(itemId(sb.link))
          local sm = sb.need - sb.have - sbank
          row(('|cff40c040vyrob %dx|r z %dx %s'):format(m.craft, sb.need, sb.name), { indent = 14, icon = icn(sb.link),
            right = (sbank > 0 and ('|cff66ccff%d v bance|r  '):format(sbank) or '') .. (sm > 0 and ('|cffff8855chybi %d|r'):format(sm) or '|cff40c040mas|r'),
            link = sb.link, tip = 'Klik = kde sehnat', onClick = function() findItem(sb.link, sb.name) end })
        end
      end
      C.planShop = mats
      if ns.db then ns.db.craftPlanMats = planMats end
    else
      head('Plan')
      row(G .. 'Zadny vybrany recept uz nedava skill.|r')
      C.planShop = nil
    end
  end
  if #rows == 0 and best then row('|cff9aa6b8Vse potrebne mas - klikej na tlacitko.|r') end
  local y = -74
  local tgShown, mdShown = false, false
  local stripe = 0
  local maxH = ns.db and ns.db.craftH
  for i, l in ipairs(f.lines) do
    local r = rows[i]
    local hgt = r and (r.head and 22 or (r.text == ' ' and 6 or 16)) or 16
    if r and maxH and -y + hgt + 8 > maxH then r = nil end
    if r then
      l:SetHeight(hgt)
      l:ClearAllPoints() l:SetPoint('TOPLEFT', 8, y) l:SetPoint('TOPRIGHT', -8, y) y = y - hgt
      local ind = r.indent or 0
      l.icon:ClearAllPoints()
      if r.icon then l.icon:SetTexture(r.icon) l.icon:SetPoint('LEFT', 2 + ind, 0) l.icon:Show() else l.icon:Hide() end
      l.text:ClearAllPoints()
      l.text:SetPoint('LEFT', (r.icon and 20 or 2) + ind, r.head and -2 or 0)
      l.right:SetText(r.right or '')
      l.text:SetPoint('RIGHT', l.right, 'LEFT', -6, 0)
      if r.head then
        l.text:SetText(r.head) l.text:SetTextColor(accent2()) l.text:SetFontObject('GameFontNormalSmall')
        l.hline:SetVertexColor(accent2(0.3)) l.hline:Show() l.bg:SetColorTexture(1, 1, 1, 0) stripe = 0
      else
        l.text:SetText(r.text) l.text:SetTextColor(1, 1, 1) l.text:SetFontObject('GameFontHighlightSmall')
        l.hline:Hide()
        stripe = stripe + 1
        l.bg:SetColorTexture(1, 1, 1, (r.text ~= ' ' and stripe % 2 == 0) and 0.03 or 0)
      end
      if r.text == ' ' then l.hl:Hide() else l.hl:Show() end
      l.link, l.tip, l.onClick = r.link, r.tip, r.onClick
      l:Show()
      if r.modes then
        f.mdFn = r.modes
        local prev
        local cur = state and state.s and C.mode(state.s) or 'all'
        for k = #f.md, 1, -1 do
          local tb = f.md[k]
          tb:ClearAllPoints()
          if prev then tb:SetPoint('RIGHT', prev, 'LEFT', -3, 0) else tb:SetPoint('RIGHT', l, 'RIGHT', 0, 0) end
          local on = tb.key == cur
          tb:SetBackdropColor(accent2(on and 0.5 or 0.15)) tb:SetBackdropBorderColor(accent2(on and 1 or 0.6))
          tb:Show()
          prev = tb
        end
        mdShown = true
      end
      if r.controls then
        f.tgFn = r.controls
        local prev
        for k = #f.tg, 1, -1 do
          local tb = f.tg[k]
          tb:ClearAllPoints()
          if prev then tb:SetPoint('RIGHT', prev, 'LEFT', -3, 0) else tb:SetPoint('RIGHT', l, 'RIGHT', 0, 0) end
          tb:SetBackdropColor(accent2(0.15)) tb:SetBackdropBorderColor(accent2(0.6))
          tb:Show()
          prev = tb
        end
        tgShown = true
      end
    else l:Hide() end
  end
  if not tgShown then for _, tb in ipairs(f.tg) do tb:Hide() end end
  if not mdShown then for _, tb in ipairs(f.md) do tb:Hide() end end
  f:SetHeight(maxH or (-y + 8))
  f:Show()
  place()
  C.saveShop(s, cant)
end

------------------------------------------------------------------------------------------
-- Nakupni seznam (material od vendora) a nakup jednim klikem u obchodnika
------------------------------------------------------------------------------------------
-- ulozi: co koupit na 5x nejlepsich receptu, na ktere chybi jen vendor material
function C.saveShop(s, cant)
  if not ns.db then return end
  local items, n = {}, 0
  if C.planMode and C.planShop then
    for _, m in pairs(C.planShop) do
      local id = itemId(m.link)
      if id and m.need > m.have and ns.MobDB and ns.MobDB.isVendor and ns.MobDB.isVendor(id) then
        items[id] = { name = m.name, want = m.need, for_ = 'plan levelovani' }
      end
    end
    ns.db.craftShop = next(items) and { prof = s.name, items = items } or nil
    return
  end
  for _, r in ipairs(cant or {}) do
    if n >= 3 or RANK[r.kind] < 3 then break end
    if r.vendorOnly then
      n = n + 1
      for _, a in ipairs(r.reag) do
        local id = itemId(a.link)
        if id and ns.MobDB and ns.MobDB.isVendor and ns.MobDB.isVendor(id) then
          local want = a.need * 5
          local e = items[id]
          if not e then items[id] = { name = a.name, want = want, for_ = r.name } else e.want = e.want + want end
        end
      end
    end
  end
  ns.db.craftShop = next(items) and { prof = s.name, items = items } or nil
end

local mf
local function moneyStr(c) return ns.coin and ns.coin(c) or tostring(c) end
local function merchantList()
  local shop = ns.db and ns.db.craftShop
  if not (shop and shop.items) then return {} end
  local out = {}
  local NI, IL, II = api('GetMerchantNumItems'), api('GetMerchantItemLink'), api('GetMerchantItemInfo')
  if not (NI and IL) then return out end
  for i = 1, safeNum(pc(NI)) or 0 do
    local id = itemId(safe(pc(IL, i)))
    local e = id and shop.items[id]
    if e then
      local have = itemCount(id)
      local need = e.want - have
      if need > 0 then
        local price, bundle = 0, 1
        if II then
          local _, _, p, q = pc(II, i)
          price, bundle = safeNum(p) or 0, math.max(1, safeNum(q) or 1)
        elseif C_MerchantFrame and C_MerchantFrame.GetItemInfo then
          local t = pc(C_MerchantFrame.GetItemInfo, i)
          if type(t) == 'table' then price, bundle = safeNum(t.price) or 0, math.max(1, safeNum(t.stackCount) or 1) end
        end
        local buys = math.ceil(need / bundle)
        out[#out + 1] = { i = i, id = id, name = e.name, need = need, bundle = bundle, buys = buys, cost = buys * price, for_ = e.for_ }
      end
    end
  end
  return out
end
local function buildMerchant()
  local T = ns.THEME
  mf = CreateFrame('Frame', 'ClaudeMasterCraftShop', UIParent, 'BackdropTemplate')
  mf:SetSize(260, 80)
  mf:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  mf:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.94) mf:SetBackdropBorderColor(unpack(T.border))
  mf:SetFrameStrata('HIGH')
  mf.title = mf:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') mf.title:SetPoint('TOPLEFT', 10, -8)
  mf.title:SetTextColor(unpack(T.title))
  mf.text = mf:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') mf.text:SetPoint('TOPLEFT', 10, -26) mf.text:SetPoint('RIGHT', -10, 0)
  mf.text:SetJustifyH('LEFT')
  local b = CreateFrame('Button', nil, mf, 'BackdropTemplate')
  b:SetHeight(24) b:SetPoint('BOTTOMLEFT', 8, 8) b:SetPoint('BOTTOMRIGHT', -8, 8)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b:SetBackdropColor(0.2, 0.45, 0.2, 0.55) b:SetBackdropBorderColor(0.35, 0.8, 0.35, 0.9)
  b.t = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight') b.t:SetPoint('CENTER')
  b:SetHighlightTexture(WHITE, 'ADD') b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
  b:SetScript('OnClick', function() C.buyAll() end)
  mf.btn = b
  mf:Hide()
end
function C.merchant()
  if not (_G.MerchantFrame and _G.MerchantFrame:IsShown()) then if mf then mf:Hide() end return end
  local list = merchantList()
  if not list[1] then if mf then mf:Hide() end return end
  if not mf then buildMerchant() end
  local lines, total = {}, 0
  for _, e in ipairs(list) do
    lines[#lines + 1] = ('%dx %s  %s'):format(e.buys * e.bundle, e.name, moneyStr(e.cost))
    total = total + e.cost
  end
  mf.title:SetText('Material na profese')
  mf.text:SetText(table.concat(lines, '\n'))
  mf.btn.t:SetText('Koupit vse  ' .. moneyStr(total))
  local money = safeNum(pc(GetMoney)) or 0
  mf.btn:SetAlpha(money >= total and 1 or 0.5)
  mf:SetHeight(26 + mf.text:GetStringHeight() + 42)
  mf:Show()
  C.placeSmart(mf, _G.MerchantFrame)
end
-- nakup (klik hrace): po davkach podle velikosti stacku
function C.buyAll()
  local BUY = api('BuyMerchantItem')
  if not BUY then return end
  local money = safeNum(pc(GetMoney)) or 0
  for _, e in ipairs(merchantList()) do
    if e.cost <= money then
      if e.bundle > 1 then
        for _ = 1, e.buys do pcall(BUY, e.i) end
      else
        local max = api('GetMerchantItemMaxStack') and safeNum(pc(api('GetMerchantItemMaxStack'), e.i)) or 20
        local left = e.need
        while left > 0 do
          local q = math.min(left, math.max(1, max))
          pcall(BUY, e.i, q)
          left = left - q
        end
      end
      money = money - e.cost
      ns.say(('Koupeno %dx %s (na %s)'):format(e.buys * e.bundle, e.name, e.for_ or 'profese'))
    else
      ns.say(('Na %s nemas dost penez.'):format(e.name))
    end
  end
  if C_Timer then C_Timer.After(0.6, function() pcall(C.merchant) end) end
end
local mev = CreateFrame('Frame')
for _, e in ipairs({ 'MERCHANT_SHOW', 'MERCHANT_UPDATE', 'MERCHANT_CLOSED', 'BAG_UPDATE_DELAYED' }) do pcall(mev.RegisterEvent, mev, e) end
mev:SetScript('OnEvent', function(_, e)
  if e == 'MERCHANT_CLOSED' then if mf then mf:Hide() end return end
  if ns.db and ns.db.craftHelp == false then return end
  if e == 'BAG_UPDATE_DELAYED' and not (mf and mf:IsShown()) then return end
  if C_Timer then C_Timer.After(0.15, function() pcall(C.merchant) end) else pcall(C.merchant) end
end)

-- vyroba davky (klik hrace = hardware udalost)
function C.craft()
  if not (state and state.best and state.n and state.n > 0) then return end
  if InCombatLockdown() then ns.say('V boji vyrabet nejde.') return end
  local r = state.best
  local T = C_TradeSkillUI
  local DT
  if state.s and state.s.modern and T and T.CraftRecipe then DT = T.CraftRecipe else DT = api('DoTradeSkill') end
  if not DT then ns.say('Hra nema funkci na vyrobu.') return end
  C.active = { name = r.name, kind = r.kind, at = GetTime() }
  local ok, err = pcall(DT, r.i, state.n)
  if not ok then ns.say('Vyroba se nepodarila: ' .. tostring(err)) C.active = nil end
end

-- behem davky: recept zezelenal a jiny je lepsi -> zastavit (at nepalis material)
local function check()
  local a = C.active
  if not a then return end
  local T = C_TradeSkillUI
  if T and T.IsRecipeRepeating and GetTime() - (a.at or 0) > 2 and safeBool(pc(T.IsRecipeRepeating)) == false then C.active = nil return end
  local s = C.scan()
  if not s then return end
  local cur, best
  for _, r in ipairs(s.list) do if r.name == a.name then cur = r end end
  best = C.plan(s)
  if cur and RANK[cur.kind] < RANK[a.kind] and best and best.name ~= cur.name and RANK[best.kind] > RANK[cur.kind] then
    local stop = api('StopTradeSkillRepeat') or (C_TradeSkillUI and C_TradeSkillUI.StopRecipeRepeat)
    if stop then pcall(stop) end
    ns.say(('|cffffd200%s|r uz je %s - prepinam na |cffffd200%s|r (klikni znovu).'):format(cur.name, cur.kind == 'easy' and 'zeleny' or 'sedy', best.name))
    C.active = nil
  end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'TRADE_SKILL_SHOW', 'TRADE_SKILL_UPDATE', 'TRADE_SKILL_LIST_UPDATE', 'TRADE_SKILL_DATA_SOURCE_CHANGED', 'TRADE_SKILL_CLOSE',
  'BAG_UPDATE_DELAYED', 'CHAT_MSG_SKILL', 'SKILL_LINES_CHANGED' }) do
  pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript('OnEvent', function(_, e)
  if ns.db and ns.db.craftHelp == false then if f then f:Hide() end return end
  if e == 'TRADE_SKILL_CLOSE' then if f then f:Hide() end C.active, C.open = nil, false return end
  if e == 'TRADE_SKILL_SHOW' then C.open = true end
  if pending then return end
  pending = true
  C_Timer.After(0.15, function()
    pending = false
    if C.open or host() then
      if e == 'TRADE_SKILL_UPDATE' or e == 'TRADE_SKILL_LIST_UPDATE' or e == 'SKILL_LINES_CHANGED' then pcall(check) end
      pcall(C.refresh)
    end
  end)
end)

-- /cm profese: vypis, co hra v okne profese vraci (ladeni na Foreveru)
function C.dump()
  local s = C.scan()
  if not s then
    local T = C_TradeSkillUI
    local fns = {}
    if T then for k, v in pairs(T) do if type(v) == 'function' and (k:find('Recipe') or k:find('Profession') or k:find('Line') or k:find('Craft')) then fns[#fns + 1] = k end end end
    table.sort(fns)
    ns.say(('Okno profese nenacteno. Ramce: TradeSkillFrame %s, ProfessionsFrame %s. Stare API: GetTradeSkillLine %s, GetNumTradeSkills %s.'):format(
      tostring(_G.TradeSkillFrame ~= nil), tostring(_G.ProfessionsFrame ~= nil), tostring(api('GetTradeSkillLine') ~= nil), tostring(api('GetNumTradeSkills') ~= nil)))
    ns.say('C_TradeSkillUI: ' .. (T and table.concat(fns, ', ') or 'NEEXISTUJE'))
    if T and T.GetTradeSkillLine then ns.say('GetTradeSkillLine: ' .. tostring(select(2, pc(T.GetTradeSkillLine)))) end
    if T and T.GetAllRecipeIDs then local ids = pc(T.GetAllRecipeIDs) ns.say('GetAllRecipeIDs: ' .. (type(ids) == 'table' and #ids or tostring(ids))) end
    return
  end
  local T = C_TradeSkillUI
  ns.say(('Profese: %s %d/%d, receptu: %d, rozhrani: %s, vyroba: %s, stop: %s'):format(s.name, s.rank, s.max, #s.list,
    s.modern and 'nove (C_TradeSkillUI)' or 'stare',
    (s.modern and T and T.CraftRecipe or api('DoTradeSkill')) and 'ano' or 'NE',
    (api('StopTradeSkillRepeat') or (T and T.StopRecipeRepeat)) and 'ano' or 'ne'))
  -- surova data prvnich receptu (ladeni barev)
  local T2 = C_TradeSkillUI
  local ids = T2 and T2.GetAllRecipeIDs and pc(T2.GetAllRecipeIDs)
  for k = 1, 3 do
    local id = type(ids) == 'table' and ids[k]
    local info = id and T2.GetRecipeInfo and pc(T2.GetRecipeInfo, id)
    if type(info) == 'table' then
      ns.say(('  [raw] %s: difficulty=%s relativeDifficulty=%s numSkillUps=%s learned=%s numAvailable=%s'):format(tostring(info.name),
        tostring(info.difficulty), tostring(info.relativeDifficulty), tostring(info.numSkillUps), tostring(info.learned), tostring(info.numAvailable)))
    end
  end
  -- surova data receptu, ktere neumis (zdroj a pozadavky) - pro sekci "U trenera"
  local shownU = 0
  for _, r in ipairs(s.unlearned or {}) do
    if shownU >= 3 then break end
    shownU = shownU + 1
    local req = T2 and T2.GetRecipeRequirements and pc(T2.GetRecipeRequirements, r.i)
    local rq = {}
    for _, q in ipairs(type(req) == 'table' and req or {}) do
      if type(q) == 'table' then rq[#rq + 1] = ('%s/%s'):format(tostring(q.name), tostring(q.met)) else rq[#rq + 1] = tostring(q) end
    end
    ns.say(('  [neumis] %s: zdroj="%s" pozadavky={%s} -> trener=%s skill=%s'):format(r.name, tostring(r.src), table.concat(rq, '; '),
      tostring(r.trainer), tostring(r.reqSkill)))
  end
  local best = C.plan(s)
  local cnt = { optimal = 0, medium = 0, easy = 0, trivial = 0 }
  for _, r in ipairs(s.list) do cnt[r.kind] = (cnt[r.kind] or 0) + 1 end
  local ucnt = { optimal = 0, medium = 0, easy = 0, trivial = 0 }
  for _, r in ipairs(s.unlearned or {}) do ucnt[r.kind] = (ucnt[r.kind] or 0) + 1 end
  ns.say(('Umis: oranzovych %d, zlutych %d, zelenych %d, sedych %d. Neumis (hra zna): %d (oranz. %d, zlut. %d, zel. %d).'):format(
    cnt.optimal, cnt.medium, cnt.easy, cnt.trivial, #(s.unlearned or {}), ucnt.optimal, ucnt.medium, ucnt.easy))
  -- jen uzitecne (ne sede), od nejlepsich
  local list = {}
  for _, r in ipairs(s.list) do if r.kind ~= 'trivial' then list[#list + 1] = r end end
  table.sort(list, function(a, b) if RANK[a.kind] ~= RANK[b.kind] then return (RANK[a.kind] or 0) > (RANK[b.kind] or 0) end return a.name < b.name end)
  for i, r in ipairs(list) do
    if i > 25 then ns.say(('  ... a dalsich %d'):format(#list - 25)) break end
    local mats = {}
    for _, a in ipairs(r.reag) do mats[#mats + 1] = ('%dx %s (%d)'):format(a.need, a.name, a.have) end
    ns.say(('  %s|c%s%s|r [%s] mas na %d%s: %s'):format(r == best and '>> ' or '', COLOR[r.kind] or 'ffffffff', r.name, r.kind, r.avail, ppt(r), table.concat(mats, ', ')))
  end
  if #list == 0 then ns.say('  (zadny recept, ktery by dal skill)') end
end

------------------------------------------------------------------------------------------
-- Aukce: precte nabidky hledaneho itemu, zapamatuje nejnizsi cenu za kus; u materialu z planu spocita,
-- kolik bude stat potrebne mnozstvi, u vyrobku porovna aukci s vendorem
------------------------------------------------------------------------------------------
local af
local function remember(id, list)
  if not (id and list[1] and ns.db) then return end
  table.sort(list, function(a, b) return a.u < b.u end)
  ns.db.ahPrice = ns.db.ahPrice or {}
  ns.db.ahPrice[id] = { p = math.floor(list[1].u), at = time and time() or 0 }
  C.ahList = { id = id, list = list }
end
local function buildAH()
  local T = ns.THEME
  af = CreateFrame('Frame', 'ClaudeMasterCraftAH', UIParent, 'BackdropTemplate')
  af:SetSize(280, 80)
  af:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  af:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.94) af:SetBackdropBorderColor(unpack(T.border))
  af:SetFrameStrata('HIGH')
  af.title = af:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') af.title:SetPoint('TOPLEFT', 10, -8) af.title:SetTextColor(unpack(T.title))
  af.text = af:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') af.text:SetPoint('TOPLEFT', 10, -26) af.text:SetPoint('RIGHT', -10, 0)
  af.text:SetJustifyH('LEFT')
  af:Hide()
end
function C.ahShow()
  local cur = C.ahList
  local host = _G.AuctionHouseFrame or _G.AuctionFrame
  if not (cur and host and host:IsShown()) then if af then af:Hide() end return end
  local id, list = cur.id, cur.list
  local lines = {}
  local name = (ns.db.craftPlanMats and ns.db.craftPlanMats[id] and ns.db.craftPlanMats[id].name) or itemName(id)
  local low = list[1].u
  lines[#lines + 1] = ('Nejlevneji: %s/ks  (%d nabidek)'):format(shortCoin(low), #list)
  -- material z planu: kolik chybi a za kolik ho koupis z nejlevnejsich nabidek
  local pm = ns.db.craftPlanMats and ns.db.craftPlanMats[id]
  if pm then
    local have = itemCount(id) + bankCount(id)
    local need = pm.need - have
    if need > 0 then
      local left, cost = need, 0
      for _, e in ipairs(list) do
        if left <= 0 then break end
        local q = math.min(left, e.q)
        cost, left = cost + q * e.u, left - q
      end
      lines[#lines + 1] = ('|cffffd200Plan potrebuje %d|r (mas %d): koupit %d ks ~ %s%s'):format(pm.need, have, need - math.max(0, left),
        shortCoin(cost), left > 0 and (' |cffff8855(v aukci chybi %d)|r'):format(left) or '')
      local vp = ns.MobDB and ns.MobDB.vendorPrice and ns.MobDB.vendorPrice(id)
      if vp then
        lines[#lines + 1] = vp < low and ('|cffff8855U vendora levneji: %s/ks|r'):format(shortCoin(vp)) or ('U vendora: %s/ks'):format(shortCoin(vp))
      end
    else
      lines[#lines + 1] = ('|cff40c040Na plan mas dost (%d / %d)|r'):format(have, pm.need)
    end
  end
  -- vyrobek: aukce vs vendor vs cena materialu
  local co = ns.db.craftOut and ns.db.craftOut[id]
  if co then
    local net = math.floor(low * 0.95)
    lines[#lines + 1] = ('Vyrobek: aukce ~%s (po poplatku), vendor %s, material %s'):format(shortCoin(net), shortCoin(co.v or 0), shortCoin(co.m or 0))
    lines[#lines + 1] = net > (co.v or 0) and '|cff40c040Vyplati se prodat v aukci.|r' or '|cffffd200Vyplati se spis vendor.|r'
  end
  if not (pm or co) then lines[#lines + 1] = '|cff9aa6b8Cena ulozena - plan profesi ji pouzije.|r' end
  if not af then buildAH() end
  af.title:SetText(name or '?')
  af.text:SetText(table.concat(lines, '\n'))
  af:SetHeight(32 + af.text:GetStringHeight() + 8)
  af:Show()
  C.placeSmart(af, host)
end
-- stare rozhrani aukce (QueryAuctionItems)
local function oldList()
  local N, IL, II = api('GetNumAuctionItems'), api('GetAuctionItemLink'), api('GetAuctionItemInfo')
  if not (N and IL and II) then return end
  local by = {}
  for i = 1, safeNum(pc(N, 'list')) or 0 do
    local id = itemId(safe(pc(IL, 'list', i)))
    local r = { pc(II, 'list', i) }
    local count, buyout = safeNum(r[3]), safeNum(r[10])
    if id and count and count > 0 and buyout and buyout > 0 then
      by[id] = by[id] or {}
      table.insert(by[id], { u = buyout / count, q = count })
    end
  end
  local best, bn
  for id, l in pairs(by) do remember(id, l) if not bn or #l > bn then best, bn = id, #l end end
  if best then C.ahList = { id = best, list = by[best] } end
end
-- nove rozhrani (C_AuctionHouse): komodity a itemy
local function commodity(id)
  local A = C_AuctionHouse
  if not (A and A.GetNumCommoditySearchResults and id) then return end
  local l = {}
  for i = 1, safeNum(pc(A.GetNumCommoditySearchResults, id)) or 0 do
    local r = pc(A.GetCommoditySearchResultInfo, id, i)
    if type(r) == 'table' and safeNum(r.unitPrice) and safeNum(r.quantity) then l[#l + 1] = { u = r.unitPrice, q = r.quantity } end
  end
  remember(id, l)
end
local function itemSearch(key)
  local A = C_AuctionHouse
  if not (A and A.GetNumItemSearchResults and type(key) == 'table') then return end
  local id = safeNum(key.itemID)
  local l = {}
  for i = 1, safeNum(pc(A.GetNumItemSearchResults, key)) or 0 do
    local r = pc(A.GetItemSearchResultInfo, key, i)
    local q = type(r) == 'table' and safeNum(r.quantity) or 1
    local b = type(r) == 'table' and safeNum(r.buyoutAmount)
    if b and b > 0 then l[#l + 1] = { u = b / math.max(1, q), q = q } end
  end
  remember(id, l)
end
local aev = CreateFrame('Frame')
for _, e in ipairs({ 'AUCTION_ITEM_LIST_UPDATE', 'COMMODITY_SEARCH_RESULTS_UPDATED', 'ITEM_SEARCH_RESULTS_UPDATED',
  'AUCTION_HOUSE_CLOSED', 'AUCTION_HOUSE_SHOW' }) do pcall(aev.RegisterEvent, aev, e) end
aev:SetScript('OnEvent', function(_, e, arg)
  if e == 'AUCTION_HOUSE_CLOSED' then if af then af:Hide() end C.ahList = nil return end
  if ns.db and ns.db.craftHelp == false then return end
  if e == 'AUCTION_ITEM_LIST_UPDATE' then pcall(oldList)
  elseif e == 'COMMODITY_SEARCH_RESULTS_UPDATED' then pcall(commodity, safeNum(arg))
  elseif e == 'ITEM_SEARCH_RESULTS_UPDATED' then pcall(itemSearch, arg) end
  pcall(C.ahShow)
end)

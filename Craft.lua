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
function C.plan(s)
  local can, cant = {}, {}
  for _, r in ipairs(s.list) do
    if (RANK[r.kind] or 0) >= 2 then table.insert(r.avail > 0 and can or cant, r) end
  end
  local function better(a, b)
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
-- Okno vedle profese
------------------------------------------------------------------------------------------
local f, state
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local function build()
  local T = ns.THEME
  f = CreateFrame('Frame', 'ClaudeMasterCraft', UIParent, 'BackdropTemplate')
  f:SetSize(300, 120)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.94) f:SetBackdropBorderColor(unpack(T.border))
  f:SetFrameStrata('HIGH') f:SetClampedToScreen(true)
  f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') f.title:SetPoint('TOPLEFT', 10, -8)
  f.title:SetTextColor(unpack(T.title))
  f.skill = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') f.skill:SetPoint('TOPRIGHT', -10, -10)
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
  for i = 1, 12 do
    local l = CreateFrame('Button', nil, f)
    l:SetHeight(15) l:SetPoint('LEFT', 10, 0) l:SetPoint('RIGHT', -10, 0)
    l.text = l:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall') l.text:SetAllPoints() l.text:SetJustifyH('LEFT') l.text:SetWordWrap(false)
    l:SetScript('OnClick', function(self) if self.onClick then self.onClick() end end)
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

local function place()
  local h = host()
  f:ClearAllPoints()
  -- vpravo od okna profese jsou svisla tlacitka profesi (~50 px): panel az za ne
  if h then f:SetPoint('TOPLEFT', h, 'TOPRIGHT', 56, -14)
  else f:SetPoint('RIGHT', UIParent, 'RIGHT', -300, 100) end
end

-- kde sehnat material: Pruzkumnik (ForeverDB) - detail itemu
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
  local s = C.scan()
  if not s or not (C.open or host()) then f:Hide() return end
  local best, can, cant = C.plan(s)
  state = { s = s, best = best }
  local prep = s.prep
  place()
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
    local n = math.min(best.avail, BATCH[best.kind] or 1)
    state.n = n
    local tex = best.icon or (api('GetTradeSkillIcon') and safe(pc(api('GetTradeSkillIcon'), best.i)))
    b.icon:SetTexture(tex or 'Interface\\Icons\\INV_Misc_QuestionMark')
    b.text:SetText(('Vyrob %dx |c%s%s|r'):format(n, COLOR[best.kind] or 'ffffffff', best.name))
    b.sub:SetText(('|cff9aa6b8%s, materialu na %d ks%s|r'):format(LABEL[best.kind] or best.kind, best.avail,
      (best.ups and best.ups > 1) and (', +%d skill/kus'):format(best.ups) or ''))
    b:Enable() b:SetAlpha(1)
  else
    b.icon:SetTexture('Interface\\Icons\\INV_Misc_Bag_10')
    local useful = 0
    for _, r in ipairs(s.list) do if RANK[r.kind] >= 3 then useful = useful + 1 end end
    local buy = cant[1] and RANK[cant[1].kind] >= 3 and cant[1].vendorOnly and cant[1]
    if s.rank >= s.max and s.max > 0 then
      b.text:SetText('|cffffcc00Strop ranku - jdi k trenerovi|r') b.sub:SetText('')
    elseif buy then
      local m = missing(buy, 5)
      local parts = {}
      for _, x in ipairs(m) do if x.vendor then parts[#parts + 1] = x.n .. 'x ' .. x.name end end
      for _, x in ipairs(m) do if not x.vendor then parts[#parts + 1] = '|cff40c040vyrob ' .. x.n .. 'x ' .. x.name .. '|r' end end
      b.text:SetText(('Kup u vendora -> 5x |c%s%s|r'):format(COLOR[buy.kind] or 'ffffffff', buy.name))
      b.sub:SetText('|cff9aa6b8kupit: ' .. table.concat(parts, ', ') .. '|r')
    elseif useful == 0 then
      b.text:SetText('|cffffcc00Zadny oranzovy / zluty recept|r') b.sub:SetText('|cff9aa6b8nove recepty u trenera|r')
    else
      b.text:SetText('|cffff8855Chybi material|r') b.sub:SetText('|cff9aa6b8co sehnat - viz nize|r')
    end
    b:Disable() b:SetAlpha(0.7)
  end
  -- radky
  local rows = {}
  local function row(text, extra) extra = extra or {} extra.text = text rows[#rows + 1] = extra end
  if s.max > 0 and s.max - s.rank <= 10 and s.max < 300 then
    row(('|cffffcc00Trener:|r skill %d/%d - dalsi rank (do %d) se uci u trenera.'):format(s.rank, s.max, s.max + 75),
      { tip = 'Bez noveho ranku se skill nad strop nezvedne.' })
  end
  -- malo uzitecnych receptu: u trenera budou nove (oranzove)
  local orange, yellow = 0, 0
  for _, r in ipairs(s.list) do if r.kind == 'optimal' then orange = orange + 1 elseif r.kind == 'medium' then yellow = yellow + 1 end end
  if orange == 0 and yellow <= 2 and not (s.max > 0 and s.max - s.rank <= 10) then
    row(('|cffffcc00Trener:|r oranzovych receptu 0, zlutych %d - u trenera %s budou nove recepty.'):format(yellow, s.name),
      { tip = 'Recepty, ktere znas, uz skoro nedavaji skill. Nove (oranzove) se uci u trenera nebo z receptu (drop, vendor).' })
  end
  -- recepty, ktere jeste neumis (hra je zna): co se naucit (oranzove / zlute)
  -- u trenera: recepty, na ktere uz mas skill (pozadavky splnene); nejvyssi pozadavek = nejvic skillu
  local un, soon = {}, 0
  for _, r in ipairs(s.unlearned or {}) do
    if r.trainer and r.reqOk ~= false then
      if not r.reqSkill or r.reqSkill <= s.rank then
        if not r.reqSkill or r.reqSkill >= s.rank - 40 then un[#un + 1] = r end
      elseif r.reqSkill <= s.rank + 15 then soon = soon + 1 end
    end
  end
  table.sort(un, function(a, b) if (a.reqSkill or 0) ~= (b.reqSkill or 0) then return (a.reqSkill or 0) > (b.reqSkill or 0) end return a.name < b.name end)
  if un[1] then
    row(('|cffffcc00U trenera ted naucis:|r %d recept%s'):format(#un, #un == 1 and '' or (#un < 5 and 'y' or 'u')),
      { tip = 'Recepty od trenera, na ktere uz mas skill. Nove recepty davaji skill (oranzove).' })
    for i, r in ipairs(un) do
      if i > 4 then break end
      row(('   |cffff8040%s|r%s'):format(r.name, r.reqSkill and (' |cff9aa6b8(%d)|r'):format(r.reqSkill) or ''), { link = r.link, tip = r.src })
    end
  elseif soon > 0 then
    row(('|cff9aa6b8U trenera: dalsich %d receptu do +15 skillu.|r'):format(soon))
  end
  local nextC = {}
  for _, r in ipairs(can) do if r ~= best and #nextC < 2 then nextC[#nextC + 1] = r end end
  if nextC[1] then row('|cff66ccffPak:|r') end
  for _, r in ipairs(nextC) do
    row(('   |c%s%s|r |cff9aa6b8(mas na %d)|r'):format(COLOR[r.kind] or 'ffffffff', r.name, r.avail), { link = r.link })
  end
  -- nakupni seznam: nejlepsi recepty, na ktere material chybi (oranzove / zlute)
  local shown = 0
  for _, r in ipairs(cant) do
    if shown >= 2 or RANK[r.kind] < 3 then break end
    shown = shown + 1
    local miss = missing(r, 5)
    row(('|cffff8855Chybi na 5x|r |c%s%s|r:'):format(COLOR[r.kind] or 'ffffffff', r.name), { link = r.link })
    for _, m in ipairs(miss) do
      local own
      for _, x in ipairs(s.list) do if x.name == m.name then own = x end end
      row(('   %dx %s |cff9aa6b8(mas %d)|r%s'):format(m.n, m.name, m.have,
        own and ' |cff40c040- vyrobis sam|r' or (m.vendor and ' |cffffd200- vendor|r' or '')),
        { link = m.link, tip = 'Klik = kde sehnat (Pruzkumnik: vendori, dropy)', onClick = function() findItem(m.link, m.name) end })
    end
  end
  if #rows == 0 and best then row('|cff9aa6b8Vse potrebne mas - klikej na tlacitko.|r') end
  local y = -74
  for i, l in ipairs(f.lines) do
    local r = rows[i]
    if r then
      l:ClearAllPoints() l:SetPoint('TOPLEFT', 10, y) l:SetPoint('TOPRIGHT', -10, y) y = y - 15
      l.text:SetText(r.text) l.link, l.tip, l.onClick = r.link, r.tip, r.onClick
      l:Show()
    else l:Hide() end
  end
  f:SetHeight(-y + 8)
  f:Show()
  C.saveShop(s, cant)
end

------------------------------------------------------------------------------------------
-- Nakupni seznam (material od vendora) a nakup jednim klikem u obchodnika
------------------------------------------------------------------------------------------
-- ulozi: co koupit na 5x nejlepsich receptu, na ktere chybi jen vendor material
function C.saveShop(s, cant)
  if not ns.db then return end
  local items, n = {}, 0
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
  mf:ClearAllPoints()
  local host = _G.MerchantFrame
  if host and host:IsShown() then mf:SetPoint('TOPLEFT', host, 'TOPRIGHT', 4, -30) else mf:SetPoint('CENTER') end
  mf:Show()
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
    ns.say(('  %s|c%s%s|r [%s] mas na %d: %s'):format(r == best and '>> ' or '', COLOR[r.kind] or 'ffffffff', r.name, r.kind, r.avail, table.concat(mats, ', ')))
  end
  if #list == 0 then ns.say('  (zadny recept, ktery by dal skill)') end
end

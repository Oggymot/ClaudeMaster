-- ClaudeMaster: radce na gear. Kazdy item ohodnoti podle vah statu (podle tridy / specu)
-- a porovna s tim, co mas na sobe:
--  * tooltip itemu: sipka nahoru/dolu a o kolik % je lepsi / horsi (nebo "od lvl X")
--  * mimo boj: v batohu je lepsi kus -> tip, klik ho nasadi
--  * /cm gear = seznam vylepseni z batohu, /cm gear <spec> = jine vahy, /cm vahy str=1 sta=0.5 ... = vlastni
-- Staty cteme z tooltipu (funguje i s nahodnymi priponami "of the Owl" apod.).
local ADDON, ns = ...
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local G = {}
ns.Gear = G

------------------------------------------------------------------------------------------
-- Vahy statu (EP: kolik "bodu" ma 1 jednotka statu; % = 1 % critu/hitu)
------------------------------------------------------------------------------------------
-- Hodnoty { na lvl 45, na lvl 60 } se prolinaji podle levelu (pod 45 klesaji). Odvozeno z
-- MythicSim Forever enginu (spell power = 1, u melee sila = 1): crit/hit rostou s gearem a levelem.
G.SPECS = {
  frost = { label = 'Frost Mage', sp = 1, frostsp = 1, int = { 0.15, 0.25 }, spi = { 0.05, 0.1 }, sta = 0.2,
    spcrit = { 4.1, 10 }, sphit = { 4.8, 13 }, mp5 = 1, armor = 0.003 },
  arcane = { label = 'Arcane Mage', sp = 1, arcanesp = 1, int = { 0.4, 0.7 }, spi = 0.1, sta = 0.2,
    spcrit = { 4, 9 }, sphit = { 4.5, 12 }, mp5 = 1.2, armor = 0.003 },
  fire = { label = 'Fire Mage', sp = 1, firesp = 1, int = { 0.15, 0.25 }, spi = 0.05, sta = 0.2,
    spcrit = { 5, 11 }, sphit = { 4.8, 13 }, mp5 = 1, armor = 0.003 },
  destro = { label = 'Destruction Warlock', sp = 1, shadowsp = 0.85, firesp = 0.35, int = { 0.1, 0.25 },
    spi = { 0.15, 0.2 }, sta = 0.35, spcrit = { 2.9, 8 }, sphit = { 3.3, 11 }, mp5 = 0.6, armor = 0.003 },
  -- ret (sila = 1 = 2 AP): spell power ~ 2 AP (Righteousness, Holy Strike, Judgement, Consecration)
  ret = { label = 'Retribution Paladin', str = 1, agi = 0.5, ap = 0.5, sp = 1, holysp = 1, sta = 0.4, int = 0.15,
    spi = 0.05, crit = 10, hit = 9, dps = 7, armor = 0.015, mp5 = 0.8, def = 0.3 },
  prot = { label = 'Protection Paladin', sta = 1, armor = 0.06, def = 1.2, block = 0.5, str = 0.7, agi = 0.6, dodge = 12,
    parry = 10, sp = 0.6, holysp = 0.6, int = 0.2, dps = 2, hit = 6 },
  holy = { label = 'Holy Paladin', heal = 1, sp = 1, int = 0.8, mp5 = 2, spcrit = 8, spi = 0.2, sta = 0.2, armor = 0.003 },
  balance = { label = 'Balance Druid', sp = 1, natsp = 0.7, arcanesp = 0.3, int = 0.3, spi = 0.2, sta = 0.2,
    spcrit = { 4, 9 }, sphit = { 4.5, 11 }, mp5 = 1, armor = 0.003 },
  feral = { label = 'Feral Druid', agi = 1.05, str = 1, ap = 0.5, sta = 0.5, crit = 14, hit = 14, armor = 0.02 },
  generic = { label = 'obecne', sta = 0.5, armor = 0.01, str = 0.5, agi = 0.5, int = 0.5, sp = 0.5 },
}
local CLASS_DEFAULT = { MAGE = 'frost', WARLOCK = 'destro', PALADIN = 'ret', DRUID = 'balance' }

function G.spec()
  local s = ns.db and ns.db.gearSpec
  if s == 'custom' and ns.db.gearWeights then return 'custom' end
  if s and G.SPECS[s] then return s end
  return CLASS_DEFAULT[ns.class] or 'generic'
end
local wCache, wKey
function G.weights()
  local s = G.spec()
  if s == 'custom' then return ns.db.gearWeights end
  local lvl = safeNum(UnitLevel('player')) or 60
  if wKey == s .. lvl then return wCache end
  local t = (lvl - 45) / 15
  local w = {}
  for k, v in pairs(G.SPECS[s]) do
    if type(v) == 'table' then
      if t >= 0 then w[k] = v[1] + (v[2] - v[1]) * math.min(1, t)
      else w[k] = v[1] * math.max(0.3, lvl / 45) end
    elseif type(v) == 'number' then w[k] = v end
  end
  wCache, wKey = w, s .. lvl
  return w
end

------------------------------------------------------------------------------------------
-- Cteni statu z radku tooltipu
------------------------------------------------------------------------------------------
local STAT = { Strength = 'str', Agility = 'agi', Stamina = 'sta', Intellect = 'int', Spirit = 'spi', Armor = 'armor',
  Defense = 'def' }
local SCHOOL = { Frost = 'frostsp', Fire = 'firesp', Shadow = 'shadowsp', Holy = 'holysp', Arcane = 'arcanesp', Nature = 'natsp' }

-- pozor: gsub vraci 2 hodnoty a tonumber(x, 0) spadne -> nejdriv do promenne
local function num(s) local x = (s or ''):gsub(',', '') return tonumber(x) end
local function parseLine(t, st)
  local v, k = t:match('^%+(%d+) (%a+)$')
  if v and STAT[k] then st[STAT[k]] = (st[STAT[k]] or 0) + num(v) return end
  v = t:match('^([%d,]+) Armor$') if v then st.armor = (st.armor or 0) + num(v) return end
  v = t:match('^(%d+) Block$') if v then st.block = (st.block or 0) + num(v) return end
  v = t:match('%(([%d%.]+) damage per second%)') if v then st.dps = (st.dps or 0) + num(v) return end
  if not t:find('^Equip:') then return end
  local h, d = t:match('healing done by up to (%d+) and damage done by up to (%d+)')
  if h then st.heal = (st.heal or 0) + num(h) st.sp = (st.sp or 0) + num(d) return end
  v = t:match('damage and healing done by magical spells and effects by up to (%d+)')
  if v then st.sp = (st.sp or 0) + num(v) st.heal = (st.heal or 0) + num(v) return end
  v = t:match('healing done by spells and effects by up to (%d+)') if v then st.heal = (st.heal or 0) + num(v) return end
  local sch
  sch, v = t:match('damage done by (%a+) spells and effects by up to (%d+)')
  if sch and SCHOOL[sch] then st[SCHOOL[sch]] = (st[SCHOOL[sch]] or 0) + num(v) return end
  v = t:match('critical strike with spells by (%d+)') if v then st.spcrit = (st.spcrit or 0) + num(v) return end
  v = t:match('critical strike by (%d+)') if v then st.crit = (st.crit or 0) + num(v) return end
  v = t:match('chance to hit with spells by (%d+)') if v then st.sphit = (st.sphit or 0) + num(v) return end
  v = t:match('chance to hit by (%d+)') if v then st.hit = (st.hit or 0) + num(v) return end
  v = t:match('[Aa]ttack [Pp]ower by (%d+)') if v then st.ap = (st.ap or 0) + num(v) return end
  v = t:match('Restores (%d+) [Mm]ana per 5') if v then st.mp5 = (st.mp5 or 0) + num(v) return end
  v = t:match('Restores (%d+) [Hh]ealth per 5') if v then st.hp5 = (st.hp5 or 0) + num(v) return end
  v = t:match('[Dd]efense by (%d+)') if v then st.def = (st.def or 0) + num(v) return end
  v = t:match('dodge an attack by (%d+)') if v then st.dodge = (st.dodge or 0) + num(v) return end
  v = t:match('parry an attack by (%d+)') if v then st.parry = (st.parry or 0) + num(v) return end
  v = t:match('block attacks with a shield by (%d+)') if v then st.blockpct = (st.blockpct or 0) + num(v) return end
end
local function isRed(c)
  if type(c) ~= 'table' then return false end
  local ok, r, g, b = pcall(function() return c.r, c.g, c.b end)
  return ok and type(r) == 'number' and r > 0.9 and g < 0.3 and b < 0.3
end
-- data = tooltip data (C_TooltipInfo / postcall) -> staty, nelze nosit?, od levelu
function G.parse(data)
  if type(data) ~= 'table' or type(data.lines) ~= 'table' then return nil end
  local st, blocked, reqLvl = {}, false, nil
  for _, l in ipairs(data.lines) do
    local t = safe(l.leftText)
    if type(t) == 'string' then
      parseLine(t, st)
      if isRed(l.leftColor) or isRed(l.rightColor) then
        local lv = t:match('^Requires Level (%d+)')
        if lv then reqLvl = tonumber(lv) elseif not t:find('^Durability') then blocked = true end
      end
    end
    local r = safe(l.rightText)
    if type(r) == 'string' and isRed(l.rightColor) then blocked = true end   -- napr. "Plate" cervene = neumis
  end
  return st, blocked, reqLvl
end
function G.score(st, w)
  if not st then return 0 end
  w = w or G.weights()
  local s = 0
  for k, v in pairs(st) do s = s + v * (w[k] or 0) end
  -- obecna spell power plati i pro skolu specu (sp = vsechny skoly)
  return s
end

------------------------------------------------------------------------------------------
-- Sloty
------------------------------------------------------------------------------------------
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local function equipLocOf(link)
  local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if not f then return nil end
  local _, _, _, loc = pc(f, link)
  return safe(loc)
end
-- tooltip data: presne (bag / slot postavy), jinak podle odkazu
local TI = C_TooltipInfo or {}
local function tipData(kind, a, b, link)
  local d
  if kind == 'bag' and TI.GetBagItem then d = pc(TI.GetBagItem, a, b)
  elseif kind == 'inv' and TI.GetInventoryItem then d = pc(TI.GetInventoryItem, 'player', a) end
  if type(d) ~= 'table' and link and TI.GetHyperlink then d = pc(TI.GetHyperlink, link) end
  return d
end
local eqCache, eqAt = nil, -99
local function equipped()
  if eqCache and GetTime() - eqAt < 2 then return eqCache end
  local t = {}
  for slot = 1, 18 do
    local link = safe(pc(GetInventoryItemLink, 'player', slot))
    if link then
      local st = G.parse(tipData('inv', slot, nil, link))
      t[slot] = { link = link, st = st, score = G.score(st), loc = equipLocOf(link) }
    end
  end
  eqCache, eqAt = t, GetTime()
  return t
end
function G.invalidate() eqCache = nil end

-- Porovnani: skore noveho vs. to, co by nahradil. -> pct (0.12 = +12 %), nahrazovany item, slot
function G.compare(link, st)
  local loc = equipLocOf(link)
  local slots = loc and SLOTS[loc]
  if not slots or loc == 'INVTYPE_TRINKET' then return nil end
  local eq = equipped()
  local new = G.score(st)
  local old, oldLink, slot
  if loc == 'INVTYPE_2HWEAPON' then
    local mh, oh = eq[16], eq[17]
    old = (mh and mh.score or 0) + (oh and oh.score or 0)
    oldLink, slot = mh and mh.link, 16
  else
    for _, s in ipairs(slots) do
      local e = eq[s]
      local sc = e and e.score or 0
      if e and e.link == link then return nil end      -- to uz mas na sobe
      if old == nil or sc < old then old, oldLink, slot = sc, e and e.link, s end
    end
    -- jednorucni zbran / offhand misto obourucni: porovnat s celou obouruckou
    local mh = eq[16]
    if (slot == 16 or slot == 17) and mh and mh.loc == 'INVTYPE_2HWEAPON' then
      if slot == 17 then return nil end   -- offhand k obourucce nejde
      old, oldLink = mh.score, mh.link
    end
  end
  if new <= 0 and old <= 0 then return nil end
  local pct = old > 0 and (new - old) / old or 1
  return pct, oldLink, slot, new, old
end

------------------------------------------------------------------------------------------
-- Tooltip itemu: sipka + %
------------------------------------------------------------------------------------------
local UP = '|TInterface\\AddOns\\ClaudeMaster\\Textures\\UpgradeArrow:14:14|t'
local DOWN = '|TInterface\\AddOns\\ClaudeMaster\\Textures\\DowngradeArrow:14:14|t'
local function onItemTip(tt, data)
  if not ns.db or ns.db.gearTips == false then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local okL, _, link = pcall(tt.GetItem, tt)
  link = okL and safe(link) or nil
  if type(link) ~= 'string' then return end
  local st, blocked, req = G.parse(data)
  if not st and C_TooltipInfo and C_TooltipInfo.GetHyperlink then st, blocked, req = G.parse(pc(C_TooltipInfo.GetHyperlink, link)) end
  if not st then return end
  local pct, oldLink = G.compare(link, st)
  if not pct then return end
  local oldName = oldLink and oldLink:match('%[(.-)%]') or 'prazdny slot'
  local lvl = safeNum(UnitLevel('player')) or 60
  local txt
  if blocked then
    txt = '|cff888888CM: tohle nosit neumis|r'
  elseif pct > 0.02 then
    txt = ('%s |cff40ff60+%d %%|r |cff9aa6b8vs %s|r'):format(UP, math.floor(pct * 100 + 0.5), oldName)
    if req and req > lvl then txt = txt .. (' |cffffcc00(od lvl %d)|r'):format(req) end
  elseif pct < -0.02 then
    txt = ('%s |cffff6060%d %%|r |cff9aa6b8vs %s|r'):format(DOWN, math.floor(pct * 100 - 0.5), oldName)
  else
    txt = '|cff9aa6b8CM: stejne jako ' .. oldName .. '|r'
  end
  tt:AddLine(txt)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data) pcall(onItemTip, tt, data) end)
end

------------------------------------------------------------------------------------------
-- Vylepseni v batohu
------------------------------------------------------------------------------------------
local upCache, upAt = nil, -99
function G.upgrades(force)
  if not force and upCache and GetTime() - upAt < 3 then return upCache end
  local list = {}
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  G.lastAll = {}
  if not (getNum and getInfo) then return list end
  local lvl = safeNum(UnitLevel('player')) or 60
  for bag = 0, 4 do
    for slot = 1, safeNum(pc(getNum, bag)) or 0 do
      local info = pc(getInfo, bag, slot)
      local link = type(info) == 'table' and safe(info.hyperlink)
      if type(link) == 'string' and equipLocOf(link) and SLOTS[equipLocOf(link)] then
        local st, blocked, req = G.parse(tipData('bag', bag, slot, link))
        local why
        if not st then why = 'nejde precist'
        elseif blocked then why = 'neumis nosit'
        elseif req and req > lvl then why = 'od lvl ' .. req end
        local pct, oldLink, eqSlot, new
        if not why then
          pct, oldLink, eqSlot, new = G.compare(link, st)
          if not pct then why = 'nesrovnavam (trinket / uz mas)' end
        end
        G.lastAll[#G.lastAll + 1] = { link = link, pct = pct, why = why }
        if not why then
          if pct > 0.03 and new > 1 then
            list[#list + 1] = { link = link, id = safeNum(info.itemID), pct = pct, old = oldLink, slot = eqSlot, bag = bag, bslot = slot }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.pct > b.pct end)
  upCache, upAt = list, GetTime()
  G.upMap = {}
  for _, u in ipairs(list) do G.upMap[u.bag .. ':' .. u.bslot] = u end
  return list
end

function G.report()
  local s = G.spec()
  ns.say(('Gear: vahy %s   (/cm gear frost, arcane, fire, destro, ret, prot, holy, balance, feral, auto)'):format(
    s == 'custom' and 'vlastni' or G.SPECS[s].label))
  local l = G.upgrades(true)
  local all = G.lastAll or {}
  if #all == 0 then ns.say('V batohu nemas zadny gear (zbran / brneni).') return end
  for _, e in ipairs(all) do
    if e.why then ns.say(('  |cff888888- %s: %s|r'):format(e.link, e.why))
    else
      ns.say(('  %s %s  %s%+d %%|r'):format(e.pct > 0.03 and UP or (e.pct < -0.03 and DOWN or '='), e.link,
        e.pct > 0.03 and '|cff40ff60' or (e.pct < -0.03 and '|cffff6060' or '|cff9aa6b8'), math.floor(e.pct * 100 + 0.5)))
    end
  end
  if #l == 0 then ns.say('Nic z batohu neni lepsi nez to, co mas na sobe.') end
end
-- /cm vahy str=1 sta=0.5 crit=14 ...  (napr. z MythicSim stat weights)
function G.setWeights(arg)
  local w, n = {}, 0
  for k, v in (arg or ''):gmatch('(%a+)%s*=%s*([%d%.]+)') do w[k:lower()] = tonumber(v) n = n + 1 end
  if n == 0 then
    ns.say('Pouziti: /cm vahy str=1 agi=0.6 sta=0.4 int=0.3 spi=0.1 sp=1 ap=0.5 crit=14 hit=14 spcrit=9 sphit=11 mp5=1 dps=7 armor=0.01')
    return
  end
  ns.db.gearWeights, ns.db.gearSpec = w, 'custom'
  G.invalidate() upCache = nil
  ns.say(('Vlastni vahy ulozeny (%d statu). Zpet: /cm gear auto'):format(n))
end
function G.setSpec(arg)
  if arg == 'auto' or arg == '' then ns.db.gearSpec = nil
  elseif G.SPECS[arg] then ns.db.gearSpec = arg
  else G.report() return end
  G.invalidate() upCache = nil
  G.report()
end

-- zmena gearu / batohu -> prepocitat
local f = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_EQUIPMENT_CHANGED', 'BAG_UPDATE_DELAYED', 'PLAYER_LEVEL_UP' }) do pcall(f.RegisterEvent, f, e) end
f:SetScript('OnEvent', function()
  G.invalidate() upCache = nil
  if C_Timer and G.refreshBags then C_Timer.After(0.2, function() pcall(G.refreshBags) end) end
end)

------------------------------------------------------------------------------------------
-- Zelena sipka v rohu itemu v batohu (jako Pawn): vylepseni pro tebe
------------------------------------------------------------------------------------------
local ARROW = 'Interface\\AddOns\\ClaudeMaster\\Textures\\UpgradeArrow'   -- sipky z addonu Pawn (CC BY-NC-ND, viz Textures)
local function mark(btn, on)
  if not btn then return end
  if on and not btn.cmUp then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetTexture(ARROW) t:SetSize(16, 16) t:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 1, -1)
    btn.cmUp = t
  end
  if btn.cmUp then btn.cmUp:SetShown(on and true or false) end
end
local function eachButton(frame, fn)
  if not frame or not frame:IsShown() then return end
  if frame.EnumerateValidItems then
    for _, b in frame:EnumerateValidItems() do fn(b) end
  else
    local name = frame:GetName()
    for i = 1, 40 do
      local b = name and _G[name .. 'Item' .. i]
      if not b then break end
      fn(b)
    end
  end
end
function G.refreshBags()
  if not ns.db or ns.db.gearTips == false or InCombatLockdown() then return end
  pcall(G.upgrades)
  local map = G.upMap or {}
  local function upd(b)
    local bag = b.GetBagID and b:GetBagID() or (b:GetParent() and b:GetParent():GetID())
    local slot = b:GetID()
    mark(b, bag and slot and map[bag .. ':' .. slot] ~= nil)
  end
  eachButton(_G.ContainerFrameCombinedBags, upd)
  for i = 1, 13 do eachButton(_G['ContainerFrame' .. i], upd) end
end
-- prekreslit, kdyz se batoh otevre / zmeni (hook = bez taintu)
local function hookFrame(fr)
  if fr and not fr.cmHooked then
    fr.cmHooked = true
    if fr.UpdateItems then hooksecurefunc(fr, 'UpdateItems', function() pcall(G.refreshBags) end) end
    fr:HookScript('OnShow', function() if C_Timer then C_Timer.After(0.05, function() pcall(G.refreshBags) end) end end)
  end
end
local hk = CreateFrame('Frame')
hk:RegisterEvent('PLAYER_LOGIN')
hk:SetScript('OnEvent', function()
  pcall(hookFrame, _G.ContainerFrameCombinedBags)
  for i = 1, 13 do pcall(hookFrame, _G['ContainerFrame' .. i]) end
end)

------------------------------------------------------------------------------------------
-- Tip v panelu: mimo boj a bez cile nabidni lepsi kus z batohu (klik = nasadit)
------------------------------------------------------------------------------------------
local E = ns.Engine
if E and E.plan then
  local origPlan = E.plan
  E.plan = function(c, ...)
    local plan, util = origPlan(c, ...)
    if not util and not c.inCombat and not c.hostile and ns.db.gearTips ~= false then
      local ok, l = pcall(G.upgrades)
      local u = ok and l and l[1]
      if u and u.id then
        util = { name = 'item:' .. u.id, kind = 'item', item = u.id,
          reason = ('Lepsi gear v batohu: %s (+%d %%) - klik = nasadit'):format(u.link:match('%[(.-)%]') or '?',
            math.floor(u.pct * 100 + 0.5)) }
      end
    end
    return plan, util
  end
end

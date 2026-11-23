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
  affli = { label = 'Affliction Warlock', sp = 1, shadowsp = 1, int = { 0.1, 0.2 }, spi = { 0.2, 0.25 }, sta = 0.4,
    spcrit = { 1.5, 4 }, sphit = { 3.5, 11 }, mp5 = 0.6, armor = 0.003 },
  demo = { label = 'Demonology Warlock', sp = 1, shadowsp = 0.9, firesp = 0.2, int = { 0.15, 0.25 }, spi = 0.15, sta = 0.5,
    spcrit = { 2.5, 6 }, sphit = { 3.3, 11 }, mp5 = 0.6, armor = 0.005 },
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
  -- resto: heal = 1; spirit (regenerace pri castu, Bloom talent) a int drzi manu, mp5 hodne
  resto = { label = 'Restoration Druid', heal = 1, sp = 0.9, int = 0.6, spi = 0.55, mp5 = 1.8, spcrit = 6, sta = 0.2,
    armor = 0.003 },
  feral = { label = 'Feral Druid', agi = 1.05, str = 1, ap = 0.5, sta = 0.5, crit = 14, hit = 14, armor = 0.02 },
  generic = { label = 'obecne', sta = 0.5, armor = 0.01, str = 0.5, agi = 0.5, int = 0.5, sp = 0.5 },
}
local CLASS_DEFAULT = { MAGE = 'frost', WARLOCK = 'destro', PALADIN = 'ret', DRUID = 'balance' }

function G.spec()
  local s = ns.db and ns.db.gearSpec
  if s == 'custom' and ns.db.gearWeights then return 'custom' end
  if s and G.SPECS[s] then return s end
  -- druid: podle talentu (resto / balance / feral)
  if ns.class == 'DRUID' and ns.Druid and ns.Druid.spec then
    local d = ns.Druid.spec()
    if d == 'resto' then return 'resto' elseif d == 'feral' then return 'feral' end
  end
  return CLASS_DEFAULT[ns.class] or 'generic'
end
local wCache = {}
-- vahy pro libovolny spec a level (i pro partaka v parte)
function G.weightsFor(s, lvl)
  if s == 'custom' then return ns.db.gearWeights or {} end
  if not G.SPECS[s] then s = 'generic' end
  lvl = lvl or 60
  if wCache[s .. lvl] then return wCache[s .. lvl] end
  local t = (lvl - 45) / 15
  local w = {}
  for k, v in pairs(G.SPECS[s]) do
    if type(v) == 'table' then
      if t >= 0 then w[k] = v[1] + (v[2] - v[1]) * math.min(1, t)
      else w[k] = v[1] * math.max(0.3, lvl / 45) end
    elseif type(v) == 'number' then w[k] = v end
  end
  wCache[s .. lvl] = w
  return w
end
function G.weights() return G.weightsFor(G.spec(), safeNum(UnitLevel('player')) or 60) end

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
  v = t:match('[Ss]pell [Dd]amage by up to (%d+)') or t:match('[Ss]pell [Pp]ower by (%d+)')
  if v then st.sp = (st.sp or 0) + num(v) return end
  local lo = t:lower()
  for name, key in pairs(STAT) do
    v = lo:match(name:lower() .. ' by (%d+)')
    if v then st[key] = (st[key] or 0) + num(v) return end
  end
end
local function total(st) local n = 0 for _, x in pairs(st) do n = n + x end return n end
local function secs(n, u)
  n = tonumber(n) or 0
  u = (u or ''):lower()
  if u:find('^min') then return n * 60 elseif u:find('^hour') then return n * 3600 end
  return n
end
-- "Use:" efekt: prumerny prinos = bonus * trvani / cooldown (odhad); co nejde spocitat -> fl.unk
local function useLine(t, st, fl)
  local d, du = t:match('for (%d+) (%a+)')
  local dur = d and secs(d, du)
  local cd
  local cm, cs = t:match('%((%d+) Min (%d+) Sec Cooldown%)')
  if cm then cd = tonumber(cm) * 60 + tonumber(cs)
  else
    local c, cu = t:match('%((%d+) (%a+) Cooldown%)')
    if c then cd = secs(c, cu) end
  end
  local body = t:gsub('^Use: ', '')
  local tmp = {}
  parseLine('Equip: ' .. body, tmp)
  if total(tmp) > 0 and dur and cd and cd > 0 then
    local k = math.min(1, dur / cd)
    for s, x in pairs(tmp) do st[s] = (st[s] or 0) + x * k end
    fl.est = true
  else
    fl.unk = true
  end
end
local function isRed(c)
  if type(c) ~= 'table' then return false end
  local ok, r, g, b = pcall(function() return c.r, c.g, c.b end)
  return ok and type(r) == 'number' and r > 0.9 and g < 0.3 and b < 0.3
end
-- data = tooltip data (C_TooltipInfo / postcall) -> staty, nelze nosit?, od levelu, priznaky
-- priznaky: est = Use: odhad, unk = efekt nelze spocitat, bound = Soulbound, classes = "Classes:" radek
function G.parse(data)
  if type(data) ~= 'table' or type(data.lines) ~= 'table' then return nil end
  local st, blocked, reqLvl, fl = {}, false, nil, {}
  for _, l in ipairs(data.lines) do
    local t = safe(l.leftText)
    if type(t) == 'string' then
      if t:find('^Use:') then useLine(t, st, fl)
      elseif t:find('^Chance on hit:') then fl.unk = true
      else
        local before = total(st)
        parseLine(t, st)
        if t:find('^Equip:') and total(st) == before then fl.unk = true end
      end
      if t == 'Soulbound' then fl.bound = true end
      if t == 'Binds when equipped' then fl.boe = true end
      fl.classes = fl.classes or t:match('^Classes: (.+)')
      if isRed(l.leftColor) or isRed(l.rightColor) then
        local lv = t:match('^Requires Level (%d+)')
        if lv then reqLvl = tonumber(lv) elseif not t:find('^Durability') then blocked = true end
      end
    end
    local r = safe(l.rightText)
    if type(r) == 'string' and isRed(l.rightColor) then blocked = true end   -- napr. "Plate" cervene = neumis
  end
  return st, blocked, reqLvl, fl
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
-- nejlepsi jednorucni zbran a offhand/stit v batohu (k porovnani s obouruckou)
local MH1 = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OHT = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local bbCache, bbAt = nil, -99
local function bagBest()
  if bbCache and GetTime() - bbAt < 3 then return bbCache end
  local r = {}
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local lvl = safeNum(UnitLevel('player')) or 60
  if getNum and getInfo then
    for bag = 0, 4 do
      for slot = 1, safeNum(pc(getNum, bag)) or 0 do
        local info = pc(getInfo, bag, slot)
        local link = type(info) == 'table' and safe(info.hyperlink)
        local loc = type(link) == 'string' and equipLocOf(link)
        local kind = loc and (MH1[loc] and 'mh' or (OHT[loc] and 'oh'))
        if kind then
          local st, blocked, req = G.parse(tipData('bag', bag, slot, link))
          if st and not blocked and not (req and req > lvl) then
            local sc = G.score(st)
            if not r[kind] or sc > r[kind].score then r[kind] = { score = sc, link = link } end
          end
        end
      end
    end
  end
  bbCache, bbAt = r, GetTime()
  return r
end
function G.compare(link, st)
  local loc = equipLocOf(link)
  local slots = loc and SLOTS[loc]
  if not slots then return nil end
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
    -- jednorucni zbran / stit misto obouruckly: porovnat dvojici (s nejlepsim parakem z batohu) s obouruckou
    local mh = eq[16]
    local partner
    if (slot == 16 or slot == 17) and mh and mh.loc == 'INVTYPE_2HWEAPON' then
      local bb = bagBest()
      partner = (slot == 17) and bb.mh or bb.oh
      if slot == 17 and not partner then return nil end   -- stit bez jednorucni zbrane nejde nosit
      new = new + (partner and partner.score or 0)
      old, oldLink = mh.score, mh.link
    end
    if new <= 0 and old <= 0 then return nil end
    local pct = old > 0 and (new - old) / old or 1
    return pct, oldLink, slot, new, old, partner and partner.link
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
local QUEST_TEX = 'Interface\\GossipFrame\\AvailableQuestIcon'
local COIN_TEX = 'Interface\\MoneyFrame\\UI-GoldIcon'
local function onItemTip(tt, data)
  if not ns.db or ns.db.gearTips == false then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local okL, _, link = pcall(tt.GetItem, tt)
  link = okL and safe(link) or nil
  if type(link) ~= 'string' then return end
  local st, blocked, req, fl = G.parse(data)
  if not st and C_TooltipInfo and C_TooltipInfo.GetHyperlink then st, blocked, req, fl = G.parse(pc(C_TooltipInfo.GetHyperlink, link)) end
  fl = fl or {}
  if st then pcall(G.myTip, tt, link, st, blocked, req, fl) end
  -- itemy na quest (hra u nich nic nepise)
  local qn = (G.questByLink and G.questByLink[link]) or (G.questNeed and G.questNeed(link))
  if qn then
    local cnt = (qn.need and qn.need > 0) and (' %d/%d'):format(qn.have or 0, qn.need) or ''
    tt:AddLine('|T' .. QUEST_TEX .. ':14:14|t |cffffd100Quest:|r ' .. qn.title .. cnt .. ' |cff9aa6b8- neprodavat|r')
  end
  -- u vendora: proc to radime prodat
  if (G.merchant or G.bank) and G.sellWhy then
    local why = G.sellWhy(tt, link)
    if why then tt:AddLine('|T' .. COIN_TEX .. ':14:14|t |cffffd100Prodat:|r |cffdddddd' .. why .. '|r', 1, 1, 1, true) end
  end
  -- material / recept pro profesi partaka
  if G.matPeers and not fl.bound then
    local mp = G.matPeers(link, data)
    for i, p in ipairs(mp) do
      if i > 3 then break end
      tt:AddLine(('%s |cff66ccff%s|r |cff40ff60vyuzije (%s)|r'):format(UP, p.name, p.prof))
    end
  end
  -- parta s addonem: komu by se to hodilo (jen kdyz to neni Soulbound)
  if st and not fl.bound and G.peerUps then
    for i, p in ipairs(G.peerUps(link, st, req, fl)) do
      if i > 3 then break end
      local s = p.empty and ('%s |cff66ccff%s|r |cff40ff60muze vyuzit (prazdny slot)|r'):format(UP, p.name)
        or ('%s |cff66ccff%s|r |cff40ff60+%d %%|r'):format(UP, p.name, math.floor(p.pct * 100 + 0.5))
      if p.req then s = s .. (' |cffffcc00(od lvl %d)|r'):format(p.req) end
      tt:AddLine(s)
    end
  end
end
function G.myTip(tt, link, st, blocked, req, fl)
  local pct, oldLink, _, _, _, partner = G.compare(link, st)
  if fl.unk and equipLocOf(link) and SLOTS[equipLocOf(link)] then
    tt:AddLine('|cff9aa6b8CM: efekt (proc / Use) nelze spocitat - jen staty|r')
  end
  if not pct then return end
  local oldName = oldLink and oldLink:match('%[(.-)%]') or 'prazdny slot'
  if partner then oldName = oldName .. ' |cffffffff(s ' .. (partner:match('%[(.-)%]') or '?') .. ')|r' end
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
  if fl.est and not blocked then txt = txt .. ' |cffffcc00(odhad Use:)|r' end
  tt:AddLine(txt)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data) pcall(onItemTip, tt, data) end)
end

------------------------------------------------------------------------------------------
-- Vylepseni v batohu
------------------------------------------------------------------------------------------
-- itemy, ktere potrebujes na quest (cile typu "5/10 Linen Cloth") -> [nazev malymi] = { title, have, need }
local qiCache, qiAt = nil, -99
function G.questItems()
  if qiCache and GetTime() - qiAt < 5 then return qiCache end
  local t = {}
  local QL = C_QuestLog
  if QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives then
    for i = 1, safeNum(pc(QL.GetNumQuestLogEntries)) or 0 do
      local info = pc(QL.GetInfo, i)
      local id = type(info) == 'table' and not info.isHeader and safeNum(info.questID)
      local objs = id and pc(QL.GetQuestObjectives, id)
      for _, o in ipairs(type(objs) == 'table' and objs or {}) do
        local txt = safe(o.text)
        if safe(o.type) == 'item' and type(txt) == 'string' then
          local name = txt:gsub('^%d+%s*/%s*%d+%s+', '')
          name = name:gsub(':%s*%d+%s*/%s*%d+$', '')
          name = name:gsub('%s+$', '')
          if name ~= '' then
            t[name:lower()] = { title = safe(info.title) or '?', have = safeNum(o.numFulfilled), need = safeNum(o.numRequired) }
          end
        end
      end
    end
  end
  qiCache, qiAt = t, GetTime()
  return t
end
-- jmeno itemu vs. text cile questu: cil byva v mnozne cisle ("Gnoll Paws" vs item "Gnoll Paw")
local function qiLookup(n)
  local t = G.questItems()
  n = n:lower()
  return t[n] or t[n .. 's'] or t[n .. 'es'] or t[(n:gsub('y$', 'ies'))] or t[(n:gsub('fe?$', 'ves'))]
end
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
function G.questNeed(link)
  local n = type(link) == 'string' and link:match('%[(.-)%]')
  if not n then return nil end
  local q = qiLookup(n)
  if q then return q end
  -- item tridy Quest (hra ho tak oznacuje) - i kdyz ho nejde sparovat s cilem v logu
  local gi = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local classID = gi and select(6, pc(gi, link))
  if safeNum(classID) == QUEST_CLASS then return { title = 'quest item' } end
end
-- quest item podle hry (bag + slot): spolehlivejsi nez jmeno
local function bagQuest(bag, slot, link)
  local q = G.questNeed(link)
  if q then return q end
  local f = C_Container and C_Container.GetContainerItemQuestInfo
  local qi = f and pc(f, bag, slot)
  if type(qi) == 'table' and (safeBool(qi.isQuestItem) or safeNum(qi.questID)) then
    local id = safeNum(qi.questID)
    local title = id and C_QuestLog and C_QuestLog.GetTitleForQuestID and safe(pc(C_QuestLog.GetTitleForQuestID, id))
    return { title = title or 'quest item' }
  end
end

-- batohy (0-4, 5 = reagent bag) + banka, kdyz je otevrena (-1 hlavni banka, -3 reagent banka, 6-16 bankovni
-- tasky / zalozky; neexistujici id vrati 0 slotu)
local BANK_IDS = { -1, -3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local BANKSET = {}
for _, b in ipairs(BANK_IDS) do BANKSET[b] = true end
function G.isBankBag(bag) return BANKSET[bag] == true end
function G.bagIds()
  local t = { 0, 1, 2, 3, 4, 5 }
  if G.bank then for _, b in ipairs(BANK_IDS) do t[#t + 1] = b end end
  return t
end
local upCache, upAt = nil, -99
function G.upgrades(force)
  if not force and upCache and GetTime() - upAt < 3 then return upCache end
  local list = {}
  local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  G.lastAll = {}
  G.sellMap = {}
  G.sellByLink = {}
  G.giftMap = {}
  G.questMap = {}
  G.questByLink = {}
  if not (getNum and getInfo) then return list end
  local lvl = safeNum(UnitLevel('player')) or 60
  local specLabel = (G.SPECS[G.spec()] or {}).label or 'tvuj spec'
  local bankUps = {}
  for _, bag in ipairs(G.bagIds()) do
    local inBank = G.isBankBag(bag)
    for slot = 1, safeNum(pc(getNum, bag)) or 0 do
      local info = pc(getInfo, bag, slot)
      local link = type(info) == 'table' and safe(info.hyperlink)
      local key = bag .. ':' .. slot
      local value = type(link) == 'string' and not safeBool(info.hasNoValue)
      local sell, gift
      -- seda vec (junk) = na prodej
      if value and safeNum(info.quality) == 0 then sell = 'seda vec (junk)' end
      -- materialy a recepty pro profese, ktere nemas
      if value and not sell then sell = G.tradeWhy(link, bag, slot) end
      if type(link) == 'string' and equipLocOf(link) and SLOTS[equipLocOf(link)] then
        local st, blocked, req, fl = G.parse(tipData('bag', bag, slot, link))
        fl = fl or {}
        local why
        if not st then why = 'nejde precist'
        elseif blocked then why = 'neumis nosit'
        elseif req and req > lvl then why = 'od lvl ' .. req end
        local pct, oldLink, eqSlot, new, old, partner
        if not why then
          pct, oldLink, eqSlot, new, old, partner = G.compare(link, st)
          if not pct then why = 'uz mas na sobe' end
        end
        G.lastAll[#G.lastAll + 1] = { link = link, pct = pct, why = why, est = fl.est, unk = fl.unk }
        -- na prodej: neumis nosit, nebo neni vylepseni (budouci "od lvl X" a neznamy proc nechame)
        if value and not sell then
          local oldName = oldLink and oldLink:match('%[(.-)%]') or '?'
          if st and blocked then
            sell = fl.classes and ('jen pro: ' .. fl.classes) or 'tvoje trida to nosit neumi'
          elseif not why and pct <= 0.02 and not fl.unk then
            if old and old > 0 and new < old * 0.15 then sell = ('pro %s skoro bez uzitku (spatne staty)'):format(specLabel)
            elseif pct < -0.02 then sell = ('horsi nez %s (%d %%)'):format(oldName, math.floor(pct * 100 - 0.5))
            else sell = 'stejne jako ' .. oldName end
          end
        end
        -- partak v parte by to vyuzil (a jde to predat) -> neprodavat, tooltip rekne komu
        if st and not fl.bound and G.peerUps and not (not why and pct and pct > 0.03) then
          local pu = G.peerUps(link, st, req, fl)[1]
          if pu then sell, gift = nil, pu.name end
        end
        if not why then
          if pct > 0.03 and new > 1 then
            local u = { link = link, id = safeNum(info.itemID), pct = pct, old = oldLink, slot = eqSlot, bag = bag, bslot = slot,
              partner = partner, boe = fl.boe and not fl.bound, unk = fl.unk }
            -- z banky nejde nasadit klikem: jen sipka, ne tip v panelu
            if inBank then bankUps[#bankUps + 1] = u else list[#list + 1] = u end
          end
        end
      end
      -- material / recept pro profesi partaka
      if type(link) == 'string' and not gift and G.matPeers then
        local mp = G.matPeers(link, function() return tipData('bag', bag, slot, link) end)[1]
        if mp then gift = mp.name end
      end
      if gift then G.giftMap[key] = gift sell = nil end
      -- potrebujes na quest: neprodavat, vykricnik
      local qn = type(link) == 'string' and bagQuest(bag, slot, link)
      if qn then G.questMap[key] = qn sell = nil G.giftMap[key] = nil G.questByLink[link] = qn end
      if sell then G.sellMap[key] = sell G.sellByLink[link] = sell end
    end
  end
  table.sort(list, function(a, b) return a.pct > b.pct end)
  upCache, upAt = list, GetTime()
  G.upMap = {}
  for _, u in ipairs(list) do G.upMap[u.bag .. ':' .. u.bslot] = u end
  for _, u in ipairs(bankUps) do G.upMap[u.bag .. ':' .. u.bslot] = u end
  return list
end

-- duvod prodeje pro tooltip (podle tlacitka v batohu, jinak podle odkazu)
function G.sellWhy(tt, link)
  if not G.sellMap then pcall(G.upgrades) end
  if G.questNeed(link) or (G.questByLink and G.questByLink[link]) then return nil end
  local ok, owner = pcall(tt.GetOwner, tt)
  if ok and owner and owner.GetID then
    -- jen tlacitka batohu (ne sloty postavy: tam GetID = cislo slotu)
    local okB, bag = pcall(function()
      if owner.GetBagID then return owner:GetBagID() end
      local par = owner:GetParent()
      local pn = par and par:GetName()
      if pn and pn:find('^ContainerFrame') then return par:GetID() end
    end)
    local slot = owner:GetID()
    local w = okB and bag and slot and G.sellMap and G.sellMap[bag .. ':' .. slot]
    if w then return w end
  end
  return G.sellByLink and G.sellByLink[link]
end

------------------------------------------------------------------------------------------
-- Profese: materialy / recepty, ktere nevyuzijes
------------------------------------------------------------------------------------------
local function inParty(name)
  if not UnitInParty then return true end
  local ok, r = pcall(UnitInParty, name)
  if not ok then return true end
  r = safeBool(r)
  return r ~= false
end
local PROFMAT = {
  Cloth = { 'Tailoring', 'First Aid' }, Leather = { 'Leatherworking' },
  -- ruda: Mining ji tavi na pruty (Smelting) -> pro hornika to neni zbytecny material
  ['Metal & Stone'] = { 'Mining', 'Blacksmithing', 'Engineering', 'Jewelcrafting' }, Herb = { 'Alchemy', 'Inscription' },
  Cooking = { 'Cooking' }, Meat = { 'Cooking' }, Enchanting = { 'Enchanting' }, Parts = { 'Engineering' },
  Devices = { 'Engineering' }, Explosives = { 'Engineering' }, Jewelcrafting = { 'Jewelcrafting' },
}
local profCache, profAt = nil, -99
local function myProfs()
  if profCache and GetTime() - profAt < 30 then return profCache end
  local t, any = {}, false
  if GetProfessions and GetProfessionInfo then
    any = true
    local list = { pc(GetProfessions) }
    for i = 1, 6 do
      local idx = safeNum(list[i])
      local n = idx and safe(pc(GetProfessionInfo, idx))
      if type(n) == 'string' then t[n] = true end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    any = true
    for i = 1, safeNum(pc(GetNumSkillLines)) or 0 do
      local n, hdr = pc(GetSkillLineInfo, i)
      n = safe(n)
      if type(n) == 'string' and not safeBool(hdr) then t[n] = true end
    end
  end
  profCache, profAt = any and t or nil, GetTime()
  return profCache
end
local function itemInfo(link)
  local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if not f then return nil end
  local _, typ, sub, loc, _, cls = pc(f, link)
  return safe(typ), safe(sub), safe(loc), safeNum(cls)
end
-- kdo z party (s addonem) ma nekterou z profesi -> { {name, prof}, ... }
G.peerProfs = {}
function G.profPeers(list)
  local out, now = {}, GetTime()
  for name, pp in pairs(G.peerProfs) do
    if now - pp.at < 900 and inParty(name) then
      for _, p in ipairs(list) do
        if pp.set[p] then out[#out + 1] = { name = name, prof = p } break end
      end
    end
  end
  return out
end
-- tooltip: material / recept, ktery vyuzije partak
function G.matPeers(link, data)
  local typ, sub, _, cls = itemInfo(link)
  if type(data) == 'function' and (cls == 9 or typ == 'Recipe') then data = data() end
  if cls == 7 or typ == 'Trade Goods' or typ == 'Tradeskill' then
    local need = sub and PROFMAT[sub]
    return need and G.profPeers(need) or {}
  end
  if (cls == 9 or typ == 'Recipe') and type(data) == 'table' and type(data.lines) == 'table' then
    for _, l in ipairs(data.lines) do
      local t = safe(l.leftText)
      local p = type(t) == 'string' and t:match('^Requires ([%a ]+) %(%d+%)')
      if p then return G.profPeers({ p }) end
    end
  end
  return {}
end
function G.tradeWhy(link, bag, slot)
  local typ, sub, _, cls = itemInfo(link)
  local pr = myProfs()
  if not pr then return nil end
  if cls == 7 or typ == 'Trade Goods' or typ == 'Tradeskill' then
    local need = sub and PROFMAT[sub]
    if not need then return nil end
    for _, p in ipairs(need) do if pr[p] then return nil end end
    if G.profPeers(need)[1] then return nil end
    return ('material pro %s - tu profesi nemas (na AH vic)'):format(table.concat(need, ' / '))
  end
  if cls == 9 or typ == 'Recipe' then
    local d = tipData('bag', bag, slot, link)
    if type(d) ~= 'table' or type(d.lines) ~= 'table' then return nil end
    for _, l in ipairs(d.lines) do
      local t = safe(l.leftText)
      if type(t) == 'string' and isRed(l.leftColor) then
        if t == 'Already known' then return 'recept uz umis' end
        local p = t:match('^Requires ([%a ]+) %(%d+%)')
        if p and not pr[p] and G.profPeers({ p })[1] then return nil end
        if p and not pr[p] then return 'recept pro ' .. p .. ' - tu profesi nemas (na AH vic)' end
        if t:find('^Classes:') then return 'recept pro jinou tridu' end
      end
    end
  end
  return nil
end

------------------------------------------------------------------------------------------
-- Parta: addony si posilaji, co kdo ma na sobe (skore slotu) -> "Cherri +12 %" v tooltipu
-- zprava: G^TRIDA^spec^lvl^obourucka(0/1)^slot:skore,slot:skore,...
------------------------------------------------------------------------------------------
G.peers = {}
local ARMOR = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }
local MAXARMOR = { MAGE = 1, PRIEST = 1, WARLOCK = 1, DRUID = 2, ROGUE = 2, MONK = 2, DEMONHUNTER = 2,
  HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, DEATHKNIGHT = 4, EVOKER = 3 }
local WEAP = {}
for cls, s in pairs({
  MAGE = 'Staves,One-Handed Swords,Daggers,Wands',
  WARLOCK = 'Staves,One-Handed Swords,Daggers,Wands',
  PRIEST = 'Staves,One-Handed Maces,Daggers,Wands',
  DRUID = 'Staves,One-Handed Maces,Two-Handed Maces,Daggers,Fist Weapons,Polearms,Idols',
  PALADIN = 'One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Shields,Librams',
  WARRIOR = 'One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Shields,Bows,Guns,Crossbows,Thrown',
  HUNTER = 'One-Handed Axes,Two-Handed Axes,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown',
  ROGUE = 'One-Handed Maces,One-Handed Swords,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown',
  SHAMAN = 'One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,Staves,Daggers,Fist Weapons,Shields,Totems',
}) do
  WEAP[cls] = {}
  for w in s:gmatch('[^,]+') do WEAP[cls][w] = true end
end
local function canUse(cls, lvl, link, loc, fl)
  if fl.classes then
    local ok = false
    for c in fl.classes:gmatch('[^,]+') do
      local k = c:gsub('%s', '')
      if k:upper() == cls then ok = true end
    end
    if not ok then return false end
  end
  local typ, sub = itemInfo(link)
  if typ == 'Armor' then
    if loc == 'INVTYPE_CLOAK' or sub == 'Miscellaneous' or not sub then return true end
    local a = ARMOR[sub]
    if a then
      local m = MAXARMOR[cls]
      if type(m) == 'table' then m = (lvl >= 40) and m[2] or m[1] end
      return m == nil or a <= m
    end
    return WEAP[cls] == nil or WEAP[cls][sub] == true      -- stity, libramy, idoly, totemy
  elseif typ == 'Weapon' then
    return WEAP[cls] == nil or WEAP[cls][sub] == true
  end
  return true
end
-- komu z party je item vylepsenim -> { {name, pct, req, empty}, ... } (nejvetsi prvni)
function G.peerUps(link, st, req, fl)
  local out = {}
  local loc = equipLocOf(link)
  local slots = loc and SLOTS[loc]
  if not slots then return out end
  if loc == 'INVTYPE_WEAPON' then slots = { 16 } end
  local now = GetTime()
  for name, p in pairs(G.peers) do
    if now - p.at < 900 and inParty(name) and canUse(p.cls, p.lvl, link, loc, fl or {}) then
      local new = G.score(st, G.weightsFor(p.spec, p.lvl))
      local old
      if loc == 'INVTYPE_2HWEAPON' then old = (p.sc[16] or 0) + (p.sc[17] or 0)
      elseif (slots[1] == 16 or slots[1] == 17) and p.two then old = nil       -- vs obourucka: nesrovnavat
      else
        for _, s in ipairs(slots) do
          local v = p.sc[s] or 0
          if old == nil or v < old then old = v end
        end
      end
      if old and new > 0.5 then
        local pct = old > 0 and (new - old) / old or 1
        if pct > 0.02 then
          out[#out + 1] = { name = name, pct = pct, empty = old <= 0, req = (req and req > p.lvl) and req or nil }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.pct > b.pct end)
  return out
end
function G.recv(name, msg)
  local f = {}
  for v in (msg .. '^'):gmatch('([^%^]*)%^') do f[#f + 1] = v end
  if f[2] == 'P' then
    local set = {}
    for pr in (f[3] or ''):gmatch('[^,]+') do set[pr] = true end
    G.peerProfs[name] = { set = set, at = GetTime() }
    upCache = nil
    return
  end
  local old = G.peers[name]
  local p = { cls = f[2], spec = f[3], lvl = tonumber(f[4]) or 60, two = f[5] == '1', sc = {}, at = GetTime() }
  for s, v in (f[6] or ''):gmatch('(%d+):([%d%.]+)') do p.sc[tonumber(s)] = tonumber(v) end
  G.peers[name] = p
  upCache = nil
  -- novy partak: poslat mu i nase
  if not old or GetTime() - old.at > 120 then G.shareSoon(1) end
end
local function fmt1(x)
  local s = ('%.1f'):format(x or 0)
  s = s:gsub('%.0$', '')
  return s
end
function G.share()
  if not (IsInGroup and IsInGroup()) or not (ns.Duo and ns.Duo.rawSend) then return end
  local s = G.spec()
  if s == 'custom' or not G.SPECS[s] then s = CLASS_DEFAULT[ns.class] or 'generic' end
  local lvl = safeNum(UnitLevel('player')) or 60
  local w = G.weightsFor(s, lvl)
  G.invalidate()
  local eq = equipped()
  local parts = {}
  for slot = 1, 18 do
    local e = eq[slot]
    if e then parts[#parts + 1] = slot .. ':' .. fmt1(G.score(e.st, w)) end
  end
  local mh = eq[16]
  local msg = ('G^%s^%s^%d^%s^%s'):format(ns.class or '?', s, lvl, (mh and mh.loc == 'INVTYPE_2HWEAPON') and '1' or '0',
    table.concat(parts, ','))
  pcall(ns.Duo.rawSend, msg:sub(1, 250))
  -- profese (pro materialy / recepty)
  local pr = myProfs()
  if pr then
    local names = {}
    for n in pairs(pr) do if n:find('^%a[%a ]*$') then names[#names + 1] = n end end
    pcall(ns.Duo.rawSend, ('G^P^' .. table.concat(names, ',')):sub(1, 250))
  end
end
local shareAt, sharePend = -99, false
function G.shareSoon(delay)
  if sharePend or not C_Timer then return end
  sharePend = true
  C_Timer.After(math.max(delay or 2, shareAt + 5 - GetTime()), function()
    sharePend = false
    shareAt = GetTime()
    pcall(G.share)
  end)
end
local sf = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_EQUIPMENT_CHANGED', 'GROUP_ROSTER_UPDATE', 'PLAYER_LEVEL_UP', 'PLAYER_ENTERING_WORLD' }) do
  pcall(sf.RegisterEvent, sf, e)
end
sf:SetScript('OnEvent', function() G.shareSoon(3) end)

function G.report()
  local s = G.spec()
  ns.say(('Gear: vahy %s   (/cm gear frost, arcane, fire, destro, ret, prot, holy, resto, balance, feral, auto)'):format(
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
-- nastavit vahy bez vypisu (okno nastaveni); vraci true, kdyz se zmenily
function G.applySpec(arg)
  if arg == 'auto' or arg == '' or arg == nil then ns.db.gearSpec = nil
  elseif arg == 'custom' and ns.db.gearWeights then ns.db.gearSpec = 'custom'
  elseif G.SPECS[arg] then ns.db.gearSpec = arg
  else return false end
  G.invalidate() upCache = nil
  if C_Timer and G.refreshBags then C_Timer.After(0.1, function() pcall(G.refreshBags) end) end
  return true
end
function G.setSpec(arg)
  if not G.applySpec(arg) then G.report() return end
  G.report()
end

-- zmena gearu / batohu -> prepocitat
local f = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_EQUIPMENT_CHANGED', 'BAG_UPDATE_DELAYED', 'PLAYER_LEVEL_UP', 'MERCHANT_SHOW', 'MERCHANT_CLOSED',
  'BANKFRAME_OPENED', 'BANKFRAME_CLOSED', 'PLAYERBANKSLOTS_CHANGED', 'PLAYERREAGENTBANKSLOTS_CHANGED',
  'QUEST_ACCEPTED', 'QUEST_REMOVED', 'QUEST_TURNED_IN' }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript('OnEvent', function(_, ev)
  if ev == 'MERCHANT_SHOW' then G.merchant = true elseif ev == 'MERCHANT_CLOSED' then G.merchant = false end
  if ev == 'BANKFRAME_OPENED' then G.bank = true elseif ev == 'BANKFRAME_CLOSED' then G.bank = false end
  if ev == 'BANKFRAME_OPENED' and C_Timer then C_Timer.After(0.6, function() pcall(G.refreshBags) end) end
  G.invalidate() upCache = nil bbCache = nil qiCache = nil
  if C_Timer and G.refreshBags then C_Timer.After(0.2, function() pcall(G.refreshBags) end) end
end)

------------------------------------------------------------------------------------------
-- Zelena sipka v rohu itemu v batohu (jako Pawn): vylepseni pro tebe
------------------------------------------------------------------------------------------
local ARROW = 'Interface\\AddOns\\ClaudeMaster\\Textures\\UpgradeArrow'   -- sipky z addonu Pawn (CC BY-NC-ND, viz Textures)
local COIN_T = 'Interface\\MoneyFrame\\UI-GoldIcon'
local QUEST_T = 'Interface\\GossipFrame\\AvailableQuestIcon'
local GIFT_T = 'Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon'
local function mark(btn, on)
  if not btn then return end
  if on and not btn.cmUp then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetTexture(ARROW) t:SetSize(16, 16) t:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 1, -1)
    btn.cmUp = t
  end
  if btn.cmUp then btn.cmUp:SetShown(on and true or false) end
end
local function sellMark(btn, on)
  if not btn then return end
  if on and not btn.cmSell then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetTexture(COIN_T) t:SetSize(14, 14) t:SetPoint('TOPLEFT', btn, 'TOPLEFT', 2, -4)
    btn.cmSell = t
  end
  if btn.cmSell then btn.cmSell:SetShown(on and true or false) end
end
-- postavicka = hodi se partakovi v parte (radsi dat nez prodat)
local function giftMark(btn, on)
  if not btn then return end
  if on and not btn.cmGift then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetTexture(GIFT_T) t:SetSize(16, 16) t:SetPoint('TOPLEFT', btn, 'TOPLEFT', 1, -4)
    btn.cmGift = t
  end
  if btn.cmGift then btn.cmGift:SetShown(on and true or false) end
end
-- vykricnik = item na quest (neprodavat)
local function questMark(btn, on)
  if not btn then return end
  if on and not btn.cmQuest then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetTexture(QUEST_T) t:SetSize(16, 16) t:SetPoint('TOPLEFT', btn, 'TOPLEFT', 1, -4)
    btn.cmQuest = t
  end
  if btn.cmQuest then btn.cmQuest:SetShown(on and true or false) end
end
-- tlacitka itemu z batohu jinych addonu: jednou za cas projit vsechny framy (EnumerateFrames)
local other, otherAt = setmetatable({}, { __mode = 'k' }), -99
local function isBlizzBag(b)
  local p = b:GetParent()
  local n = p and p.GetName and p:GetName()
  return type(n) == 'string' and (n:find('^ContainerFrame') or n == 'BankFrame' or n:find('^BankPanel')) ~= nil
end
function G.otherButtons(force)
  local now = GetTime()
  if (force or now - otherAt > 5) and EnumerateFrames then
    otherAt = now
    local f = EnumerateFrames()
    local n = 0
    while f and n < 20000 do
      n = n + 1
      if not other[f] and not (f.IsForbidden and f:IsForbidden()) then
        local ok, yes = pcall(function()
          return type(f.GetBagID) == 'function' and f:IsObjectType('Button') and not isBlizzBag(f)
        end)
        if ok and yes then other[f] = true end
      end
      f = EnumerateFrames(f)
    end
  end
  return other
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
  local show = G.merchant or G.bank   -- mince / postavicka jen u vendora nebo v bance (vykricnik vzdy)
  local function upd(b, forceBag)
    local okB, bag = pcall(function()
      if forceBag then return forceBag end
      if b.GetBagID then return b:GetBagID() end
      if b.GetBankTabID then return b:GetBankTabID() end
      return b:GetParent() and b:GetParent():GetID()
    end)
    bag = okB and bag or nil
    local okS, slot = pcall(function() return b.GetContainerSlotID and b:GetContainerSlotID() or b:GetID() end)
    slot = okS and slot or nil
    local key = bag and slot and (bag .. ':' .. slot)
    local up = key and map[key] ~= nil
    mark(b, up)
    sellMark(b, show and key and not up and G.sellMap and G.sellMap[key])
    giftMark(b, show and key and not up and G.giftMap and G.giftMap[key])
    questMark(b, key and not up and G.questMap and G.questMap[key])
  end
  eachButton(_G.ContainerFrameCombinedBags, upd)
  for i = 1, 13 do eachButton(_G['ContainerFrame' .. i], upd) end
  -- batohy jinych addonu (GW2 UI apod.): tlacitka z ContainerFrameItemButtonTemplate maji GetBagID
  local okO, ob = pcall(G.otherButtons)
  for b in pairs(okO and ob or {}) do
    if b:IsVisible() then
      local okB, bag = pcall(b.GetBagID, b)
      if okB and type(bag) == 'number' and (bag >= 0 and bag <= 5 or G.bank) then pcall(upd, b) end
    end
  end
  -- banka: novy panel (zalozky) nebo stara okna BankFrameItem1..28 (= bag -1)
  if G.bank then
    local bp = _G.BankPanel
    if bp and bp:IsShown() and bp.EnumerateValidItems then pcall(function() for _, b in bp:EnumerateValidItems() do upd(b) end end) end
    for i = 1, 36 do
      local b = _G['BankFrameItem' .. i]
      if not b then break end
      if b:IsVisible() then upd(b, -1) end
    end
  end
end
-- prekreslit, kdyz se batoh otevre / zmeni (hook = bez taintu)
local function hookFrame(fr)
  if fr and not fr.cmHooked then
    fr.cmHooked = true
    if fr.UpdateItems then hooksecurefunc(fr, 'UpdateItems', function() pcall(G.refreshBags) end) end
    fr:HookScript('OnShow', function() if C_Timer then C_Timer.After(0.05, function() pcall(G.refreshBags) end) end end)
  end
end
local function soon() if C_Timer then C_Timer.After(0.15, function() pcall(G.otherButtons, true) pcall(G.refreshBags) end) end end
for _, fn in ipairs({ 'ToggleAllBags', 'OpenAllBags', 'ToggleBackpack', 'OpenBackpack', 'ToggleBag', 'OpenBag' }) do
  if type(_G[fn]) == 'function' then hooksecurefunc(fn, soon) end
end
-- batoh jineho addonu je otevreny: obcas prekreslit (jeho tlacitka se recykluji)
local tickAcc = 0
local tk = CreateFrame('Frame')
tk:SetScript('OnUpdate', function(_, el)
  tickAcc = tickAcc + el
  if tickAcc < 1.5 then return end
  tickAcc = 0
  if InCombatLockdown() or not ns.db or ns.db.gearTips == false then return end
  for b in pairs(other) do
    if b:IsVisible() then pcall(G.refreshBags) return end
  end
end)
local hk = CreateFrame('Frame')
hk:RegisterEvent('PLAYER_LOGIN')
hk:SetScript('OnEvent', function()
  pcall(hookFrame, _G.ContainerFrameCombinedBags)
  for i = 1, 13 do pcall(hookFrame, _G['ContainerFrame' .. i]) end
  pcall(hookFrame, _G.BankFrame)
  pcall(hookFrame, _G.BankPanel)
end)

------------------------------------------------------------------------------------------
-- Automaticke nasazeni lepsiho kusu (volba v /cm config -> Veci a questy)
--  * jen mimo boj, ne pri castu, ne mrtvy; jeden kus za druhym
--  * jen kdyz je lepsi aspon o nastavena % a nema neznamy efekt ("Chance on hit" apod.)
--  * BoE (navaze se nasazenim) jen kdyz to hrac povoli - pak potvrdi i dotaz hry
------------------------------------------------------------------------------------------
local tried, pendingBind = {}, 0
local function canAuto()
  local db = ns.db
  if not db or not db.autoEquip or db.gearTips == false then return false end
  if InCombatLockdown() or ns.inCombat() then return false end
  if safeBool(pc(UnitIsDeadOrGhost, 'player')) then return false end
  if UnitCastingInfo and safe(pc(UnitCastingInfo, 'player')) then return false end
  if UnitChannelInfo and safe(pc(UnitChannelInfo, 'player')) then return false end
  if CursorHasItem and CursorHasItem() then return false end
  return true
end
function G.autoEquip()
  if not canAuto() then return end
  local db = ns.db
  local thr = (db.autoEquipPct or 5) / 100
  local now = GetTime()
  for k, t in pairs(tried) do if now - t > 60 then tried[k] = nil end end
  local ok, list = pcall(G.upgrades, true)
  if not ok or type(list) ~= 'table' then return end
  for _, u in ipairs(list) do
    local key = u.link .. '@' .. tostring(u.slot)
    if u.pct >= thr and not u.unk and (not u.boe or db.autoEquipBoE) and u.slot and not tried[key] then
      tried[key] = now
      if u.boe then pendingBind = now end
      local okE = pcall(EquipItemByName, u.link, u.slot)
      if okE then
        ns.say(('Nasazeno: %s%s (+%d %%)'):format(u.link, u.old and (' misto ' .. u.old) or '', math.floor(u.pct * 100 + 0.5)))
        -- jednorucka / stit misto obouruckly: nasadit i parak
        if u.partner and C_Timer then
          local other = (u.slot == 16) and 17 or 16
          C_Timer.After(0.4, function() if canAuto() then pcall(EquipItemByName, u.partner, other) end end)
        end
      end
      if C_Timer then C_Timer.After(1.5, function() pcall(G.autoEquip) end) end   -- dalsi kus
      return
    end
  end
end
local aeQueued = false
local function queueAuto(delay)
  if aeQueued or not (ns.db and ns.db.autoEquip) or not C_Timer then return end
  aeQueued = true
  C_Timer.After(delay or 1, function() aeQueued = false pcall(G.autoEquip) end)
end
G.queueAuto = queueAuto
local ae = CreateFrame('Frame')
for _, e in ipairs({ 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED', 'PLAYER_LEVEL_UP', 'PLAYER_ENTERING_WORLD',
  'EQUIP_BIND_CONFIRM', 'EQUIP_BIND_TRADEABLE_CONFIRM' }) do pcall(ae.RegisterEvent, ae, e) end
ae:SetScript('OnEvent', function(_, ev, a1)
  if ev == 'EQUIP_BIND_CONFIRM' or ev == 'EQUIP_BIND_TRADEABLE_CONFIRM' then
    -- dotaz "navaze se" jen na nase vlastni nasazeni BoE kusu (a jen kdyz to hrac povolil)
    if ns.db and ns.db.autoEquip and ns.db.autoEquipBoE and GetTime() - pendingBind < 3 and EquipPendingItem then
      pendingBind = 0
      pcall(EquipPendingItem, a1)
      if StaticPopup_Hide then pcall(StaticPopup_Hide, 'EQUIP_BIND') pcall(StaticPopup_Hide, 'EQUIP_BIND_TRADEABLE') end
    end
    return
  end
  queueAuto(ev == 'PLAYER_ENTERING_WORLD' and 5 or (ev == 'PLAYER_LEVEL_UP' and 2 or 1))
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
    -- parta: quest, ktery partak nema -> sdilet (klik)
    if not util and not c.inCombat and ns.Quests and ns.Quests.shareHint then
      local ok, h = pcall(ns.Quests.shareHint)
      if ok and h then util = h end
    end
    return plan, util
  end
end

------------------------------------------------------------------------------------------
-- Odmena za quest: sipka na nejlepsi vylepseni, jinak mince na nejdrazsi item (na prodej)
------------------------------------------------------------------------------------------
local COIN = 'Interface\\MoneyFrame\\UI-GoldIcon'
local function badge(btn, tex)
  if not btn then return end
  local icon = btn.Icon or btn.icon or (btn.GetName and btn:GetName() and _G[btn:GetName() .. 'IconTexture']) or btn
  if not btn.cmBadge then
    local t = btn:CreateTexture(nil, 'OVERLAY', nil, 7)
    t:SetSize(18, 18)
    t:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', 3, -3)
    btn.cmBadge = t
  end
  btn.cmBadge:SetShown(tex ~= nil)
  if tex then btn.cmBadge:SetTexture(tex) end
end
local function rewardButtons()
  local out = {}
  local rf = _G.QuestInfoRewardsFrame or (_G.QuestInfoFrame and _G.QuestInfoFrame.rewardsFrame)
  if rf and rf.RewardButtons then
    for _, b in ipairs(rf.RewardButtons) do out[#out + 1] = b end
  else
    for i = 1, 10 do
      local b = _G['QuestInfoRewardsFrameQuestInfoItem' .. i] or _G['QuestInfoItem' .. i]
      if b then out[#out + 1] = b end
    end
  end
  return out
end
function G.questRewards()
  if not ns.db or ns.db.gearTips == false then return end
  local btns = rewardButtons()
  for _, b in ipairs(btns) do badge(b, nil) end
  local n = safeNum(pc(GetNumQuestChoices)) or 0
  if n < 2 then return end
  local best, bestPct, rich, richPrice = nil, 0.02, nil, -1
  for i = 1, n do
    local link = safe(pc(GetQuestItemLink, 'choice', i))
    if type(link) == 'string' then
      local d = C_TooltipInfo and C_TooltipInfo.GetQuestItem and pc(C_TooltipInfo.GetQuestItem, 'choice', i)
      if type(d) ~= 'table' then d = tipData(nil, nil, nil, link) end
      local st, blocked = G.parse(d)
      if st and not blocked then
        local pct = G.compare(link, st)
        if pct and pct > bestPct then best, bestPct = i, pct end
      end
      local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
      local price = safeNum(select(11, pc(f, link))) or 0
      if price > richPrice then rich, richPrice = i, price end
    end
  end
  local pick, tex = best, ARROW
  if not pick then pick, tex = rich, COIN end
  if not pick then return end
  for _, b in ipairs(btns) do
    local isChoice = (b.type == nil or b.type == 'choice') and b:IsShown()
    if isChoice and b.GetID and b:GetID() == pick then badge(b, tex) end
  end
end
if hooksecurefunc and _G.QuestInfo_Display then
  hooksecurefunc('QuestInfo_Display', function()
    if C_Timer then C_Timer.After(0.1, function() pcall(G.questRewards) end) end
  end)
end

------------------------------------------------------------------------------------------
-- Need / Greed: hned ukaz, zda je to vylepseni (radek do chatu + sipka u okna hodu)
------------------------------------------------------------------------------------------
local function rollFrames()
  local out = {}
  local c = _G.GroupLootContainer
  if c and c.rollFrames then for _, fr in pairs(c.rollFrames) do out[#out + 1] = fr end end
  for i = 1, 4 do local fr = _G['GroupLootFrame' .. i] if fr then out[#out + 1] = fr end end
  return out
end
local function onRoll(rollID)
  if not ns.db or ns.db.gearTips == false then return end
  local link = safe(pc(GetLootRollItemLink, rollID))
  if type(link) ~= 'string' then return end
  local loc = equipLocOf(link)
  if not (loc and SLOTS[loc]) then return end
  local d = C_TooltipInfo and C_TooltipInfo.GetLootRollItem and pc(C_TooltipInfo.GetLootRollItem, rollID)
  if type(d) ~= 'table' then d = tipData(nil, nil, nil, link) end
  local st, blocked, req, fl = G.parse(d)
  if not st then return end
  local pct, oldLink = G.compare(link, st)
  local lvl = safeNum(UnitLevel('player')) or 60
  local txt, tex
  if blocked then txt = '|cff888888neumis nosit - Greed|r'
  elseif pct and pct > 0.02 then
    tex = ARROW
    txt = ('%s |cff40ff60+%d %%|r vs %s - |cff40ff60Need|r'):format(UP, math.floor(pct * 100 + 0.5),
      oldLink and oldLink:match('%[(.-)%]') or 'prazdny slot')
    if req and req > lvl then txt = txt .. (' |cffffcc00(od lvl %d)|r'):format(req) end
  elseif pct then
    txt = ('%s |cffff6060%d %%|r - Greed'):format(DOWN, math.floor(pct * 100 - 0.5))
  else return end
  -- parta s addonem: komu jinemu je to vylepsenim (o hod se jeste nehraje, Soulbound neresime)
  local ok, ups = pcall(G.peerUps, link, st, req, fl or {})
  if ok and ups and ups[1] then
    local mine = (not blocked and pct and pct > 0.02) and pct or 0
    for i, p in ipairs(ups) do
      if i > 2 then break end
      local s = p.empty and ('|cff66ccff%s|r |cff40ff60prazdny slot|r'):format(p.name)
        or ('|cff66ccff%s|r |cff40ff60+%d %%|r'):format(p.name, math.floor(p.pct * 100 + 0.5))
      if p.req then s = s .. (' |cffffcc00(od lvl %d)|r'):format(p.req) end
      txt = txt .. '\n' .. UP .. ' ' .. s
    end
    local best = ups[1]
    if best.pct > mine * 1.5 + 0.02 then
      txt = txt .. ('\n|cffffcc00Vic se hodi: %s - zvaz Greed / Pass|r'):format(best.name)
    end
  end
  local shown = false
  for _, fr in ipairs(rollFrames()) do
    if fr.cmUp and fr.rollID == rollID then fr.cmUp:Hide() end
    -- bublina vedle okna hodu (jako Pawn), zmizi s oknem
    if fr:IsShown() and fr.rollID == rollID then
      if not fr.cmTip then
        local t = CreateFrame('Frame', nil, fr, 'BackdropTemplate')
        t:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 2 })
        t:SetBackdropColor(0.05, 0.04, 0.02, 0.92) t:SetBackdropBorderColor(1, 0.8, 0.2, 0.9)
        t:SetPoint('LEFT', fr, 'RIGHT', 6, 0)
        t.text = t:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        t.text:SetPoint('CENTER') t.text:SetJustifyH('LEFT')
        fr.cmTip = t
      end
      fr.cmTip.text:SetText('|cff66ccffClaudeMaster|r\n' .. txt)
      fr.cmTip:SetSize(math.max(140, fr.cmTip.text:GetStringWidth() + 20), fr.cmTip.text:GetStringHeight() + 16)
      fr.cmTip:Show()
      shown = true
    elseif fr.cmTip and not fr:IsShown() then
      fr.cmTip:Hide()
    end
  end
  if not shown then ns.say(link .. ' ' .. txt) end   -- okno hodu jsme nenasli: aspon do chatu
  if tex then
    for _, fr in ipairs(rollFrames()) do
      if fr:IsShown() and fr.rollID == rollID then
        local ic = fr.IconFrame or fr.Icon or fr
        if not fr.cmUp then
          local t = fr:CreateTexture(nil, 'OVERLAY', nil, 7)
          t:SetSize(20, 20) t:SetPoint('BOTTOMRIGHT', ic, 'BOTTOMRIGHT', 4, -4)
          fr.cmUp = t
        end
        fr.cmUp:SetTexture(tex) fr.cmUp:Show()
      elseif fr.cmUp and fr.rollID ~= rollID and not fr:IsShown() then
        fr.cmUp:Hide()
      end
    end
  end
end
local rf = CreateFrame('Frame')
pcall(rf.RegisterEvent, rf, 'START_LOOT_ROLL')
rf:SetScript('OnEvent', function(_, _, rollID)
  -- okno hodu se vytvori az po udalosti: chvili pockat
  if C_Timer then C_Timer.After(0.3, function() pcall(onRoll, rollID) end) else pcall(onRoll, rollID) end
end)

------------------------------------------------------------------------------------------
-- U vendora: automaticka oprava, prodej sedych veci (junk) a tlacitko "prodat oznacene"
-- /cm prodej on|off, /cm oprava on|off
------------------------------------------------------------------------------------------
local JUNK = 'seda vec (junk)'
local selling = false
-- castka s ikonkami zlata / stribra / medi
local function money(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local function ic(n) return '|TInterface\\MoneyFrame\\UI-' .. n .. 'Icon:0:0:2:0|t' end
  local out = {}
  if g > 0 then out[#out + 1] = g .. ic('Gold') end
  if s > 0 then out[#out + 1] = s .. ic('Silver') end
  if cu > 0 or #out == 0 then out[#out + 1] = cu .. ic('Copper') end
  return table.concat(out, ' ')
end

-- prodat veci z G.sellMap (jen batohy 0-5); onlyJunk = jen sede
function G.sellMarked(onlyJunk)
  if selling or not G.merchant then return end
  pcall(G.upgrades, true)
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local use = C_Container and C_Container.UseContainerItem or UseContainerItem
  if not (getInfo and use) then return end
  local todo = {}
  for key, why in pairs(G.sellMap or {}) do
    local bag, slot = key:match('^(%-?%d+):(%d+)$')
    bag, slot = tonumber(bag), tonumber(slot)
    if bag and bag >= 0 and bag <= 5 and (why == JUNK or not onlyJunk) then
      local info = pc(getInfo, bag, slot)
      local link = type(info) == 'table' and safe(info.hyperlink)
      if type(link) == 'string' and not safeBool(info.isLocked) then
        todo[#todo + 1] = { bag = bag, slot = slot, link = link,
          price = (select(11, pc(GetItemInfo, link)) or 0) * (safeNum(info.stackCount) or 1) }
      end
    end
  end
  if #todo == 0 then
    if not onlyJunk then ns.say('Neni nic oznaceneho k prodeji') end
    return
  end
  selling = true
  local total, n, i = 0, 0, 0
  local function step()
    i = i + 1
    local t = todo[i]
    if not t or not G.merchant then
      selling = false
      if n > 0 then ns.say(('Prodano %d %s za %s'):format(n, n == 1 and 'vec' or 'veci', money(total))) end
      return
    end
    local info = pc(getInfo, t.bag, t.slot)
    -- vec se mezitim nepohnula?
    if type(info) == 'table' and safe(info.hyperlink) == t.link then
      pc(use, t.bag, t.slot)
      total, n = total + (safeNum(t.price) or 0), n + 1
    end
    C_Timer.After(0.15, step)
  end
  step()
end

local function repair()
  if not (CanMerchantRepair and pc(CanMerchantRepair)) then return end
  local cost, can = pc(GetRepairAllCost)
  cost = safeNum(cost) or 0
  if cost <= 0 or not can then return end
  if (safeNum(GetMoney()) or 0) < cost then ns.say('Na opravu nemas dost penez (' .. money(cost) .. ')') return end
  pc(RepairAllItems, false)
  ns.say('Opraveno za ' .. money(cost))
end

local sellBtn
local function updateBtn()
  if not sellBtn then return end
  local n = 0
  for key in pairs(G.sellMap or {}) do
    local bag = tonumber(key:match('^(%-?%d+):'))
    if bag and bag >= 0 and bag <= 5 then n = n + 1 end
  end
  sellBtn.count:SetText(n > 0 and tostring(n) or '')
  sellBtn:SetAlpha(n > 0 and 1 or 0.4)
end
local function makeBtn()
  if sellBtn or not MerchantFrame then return end
  local b = CreateFrame('Button', nil, MerchantFrame)
  b:SetSize(28, 28)
  b:SetPoint('TOPRIGHT', MerchantFrame, 'TOPRIGHT', -40, -28)
  local ic = b:CreateTexture(nil, 'ARTWORK') ic:SetAllPoints() ic:SetTexture('Interface\\Icons\\INV_Misc_Coin_01')
  b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square', 'ADD')
  b.count = b:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
  b.count:SetPoint('BOTTOMRIGHT', -1, 2)
  b:SetScript('OnClick', function() G.sellMarked(false) C_Timer.After(1, updateBtn) end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:AddLine('ClaudeMaster: prodat oznacene')
    GameTooltip:AddLine('Proda vsechno s minci v batohu (duvod je v tooltipu itemu).', 1, 1, 1, true)
    GameTooltip:AddLine('Sede veci se prodavaji samy.', 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  sellBtn = b
end

local mf = CreateFrame('Frame')
pcall(mf.RegisterEvent, mf, 'MERCHANT_SHOW')
mf:SetScript('OnEvent', function()
  local db = ns.db or {}
  C_Timer.After(0.3, function()
    if not G.merchant then return end
    if db.autoRepair ~= false then pcall(repair) end
    pcall(makeBtn)
    if db.autoSell ~= false then pcall(G.sellMarked, true) end
    C_Timer.After(1.5, function() pcall(updateBtn) end)
  end)
end)

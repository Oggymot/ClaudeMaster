-- ClaudeMaster: kempy (WoW Forever).
-- Hra nema pro kempy API a tooltip polozeneho vybaveni ukazuje jen nazev. Bonusy jsou az v buffu
-- "Camp Benefits" ("Lodestone: Melee Attack Power increased by 67. Faction Banner: Spirit ...").
-- Addon si proto pamatuje, co ktere vybaveni dava (db.campItems), a:
--  * u ohne (buff "Campfire Nearby") ukaze okenko: co kemp dava a jestli se ti to hodi (podle vah statu)
--  * v tooltipu polozeneho vybaveni, ktere uz zna, napise jeho bonus a jestli se ti hodi
local ADDON, ns = ...
local pc, safe, safeNum = ns.pc, ns.safe, ns.safeNum

local C = {}
ns.Camp = C

-- slovo ve statu -> klic vah z Gear.lua
local STATS = {
  { 'all stats', 'all' }, { 'all attributes', 'all' }, { 'experience', 'xp' }, { ' xp', 'xp' },
  { 'melee attack power', 'ap' }, { 'ranged attack power', 'ap' }, { 'attack power', 'ap' },
  { 'spell power', 'sp' }, { 'spell damage', 'sp' }, { 'healing', 'heal' },
  { 'strength', 'str' }, { 'agility', 'agi' }, { 'stamina', 'sta' }, { 'intellect', 'int' }, { 'spirit', 'spi' },
  { 'armor', 'armor' }, { 'spell critical', 'spcrit' }, { 'critical', 'crit' }, { 'spell hit', 'sphit' }, { 'hit', 'hit' },
  { 'mana', 'mp5' }, { 'health', 'sta' }, { 'dodge', 'dodge' }, { 'defense', 'def' },
}
local function statOf(text)
  local low = text:lower()
  local val = tonumber(low:match('by (%d+)') or low:match('(%d+)'))
  for _, s in ipairs(STATS) do
    if low:find(s[1], 1, true) then return s[2], val end
  end
  return nil, val
end
-- jak moc se ti bonus hodi: 2 = hodi, 1 = trochu, 0 = k nicemu, nil = nevim
local function worth(text)
  local key = statOf(text)
  if key == 'all' then return 2 end
  if key == 'xp' then return (safeNum(pc(UnitLevel, 'player')) or 60) < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) and 2 or 0 end
  if not key or not (ns.Gear and ns.Gear.weights) then return nil end
  local w = ns.Gear.weights()
  local v = w[key]
  if key == 'mp5' then v = w.mp5 or (w.int and w.int * 2) end
  if key == 'sp' and (w.sp or 0) == 0 then v = w.heal end
  v = v or 0
  if v >= 0.45 then return 2 elseif v >= 0.04 then return 1 end
  return 0
end
C.worth = worth
-- vybaveni, ktere addon zna i bez predchoziho setkani (bonus neni v "Camp Benefits")
-- Camp Tent: da rested XP navic, pak buff "Boosted Rest" = dalsi az za hodinu
local KNOWN = { ['Camp Tent'] = 'rested experience navic (jednou za hodinu)' }
C.tentUntil = 0
local function tentText()
  local left = C.tentUntil - GetTime()
  if left > 0 then return ('rested XP ze stanu uz mas - dalsi za %d min'):format(math.ceil(left / 60)), 0 end
  local lvl, max = safeNum(pc(UnitLevel, 'player')) or 60, GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
  if lvl >= max then return 'rested experience - na max levelu k nicemu', 0 end
  return KNOWN['Camp Tent'], 2
end
local function effOf(name)
  if name == 'Camp Tent' then return (tentText()) end
  return (ns.db and ns.db.campItems and ns.db.campItems[name]) or KNOWN[name]
end
local WCOL = { [2] = '|cff40ff60', [1] = '|cffffd200', [0] = '|cff888888' }
local WTXT = { [2] = 'hodi se ti', [1] = 'trochu', [0] = 'k nicemu' }

-- buffy hrace: je ohen blizko? jake bonusy mam?
local function auraTip(i, a)
  local TI = C_TooltipInfo
  local d
  if TI and TI.GetUnitBuffByAuraInstanceID and a and a.auraInstanceID then
    d = pc(TI.GetUnitBuffByAuraInstanceID, 'player', a.auraInstanceID)
  end
  if type(d) ~= 'table' and TI and TI.GetUnitAura then d = pc(TI.GetUnitAura, 'player', i, 'HELPFUL') end
  if type(d) ~= 'table' or type(d.lines) ~= 'table' then return nil end
  local out = {}
  for _, l in ipairs(d.lines) do
    local t = safe(l.leftText)
    if type(t) == 'string' then out[#out + 1] = t end
  end
  return table.concat(out, ' ')
end
function C.scan()
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  local st = { near = false, benefits = nil }
  if not get then return st end
  for i = 1, 40 do
    local ok, a = pcall(get, 'player', i, 'HELPFUL')
    if not ok or type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) == 'string' then
      if n == 'Campfire Nearby' or n:find('Campfire') then st.near = true end
      if n == 'Boosted Rest' then
        local exp = safeNum(a.expirationTime)
        C.tentUntil = (exp and exp > 0) and exp or (GetTime() + 3600)
        st.tent = true
      end
      -- stan (bonus XP) a jine kempove buffy mimo "Camp Benefits"
      if n ~= 'Camp Benefits' and (n:find('Tent') or n:find('Camp')) and not n:find('Campfire') then
        local id = safeNum(a.spellId)
        local d = id and C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, id))
        if type(d) ~= 'string' or d == '' then d = auraTip(i, a) end
        if type(d) == 'string' and d ~= '' then
          st.extra = st.extra or {}
          st.extra[#st.extra + 1] = { item = n:find('Tent') and 'Camp Tent' or n, eff = d:gsub('%s*%d+ minutes? remaining.*$', '') }
        end
      end
      if n == 'Camp Benefits' then
        local txt = auraTip(i, a)
        if txt then
          local list = {}
          -- "Gained the following camp benefits: Lodestone: Melee Attack Power increased by 67. Faction Banner: ..."
          local body = txt:match('benefits:%s*(.-)%s*%d+ minutes? remaining') or txt:match('benefits:%s*(.*)$') or txt
          for item, eff in body:gmatch("([%a' %-]+):%s*([^%.]+)%.") do
            item = item:gsub('^%s+', ''):gsub('%s+$', '')
            if item ~= '' and not item:lower():find('benefits') then list[#list + 1] = { item = item, eff = eff } end
          end
          st.benefits = list
          st.left = txt:match('(%d+) minutes? remaining')
        end
      end
    end
  end
  if st.extra then
    st.benefits = st.benefits or {}
    for _, e in ipairs(st.extra) do st.benefits[#st.benefits + 1] = e end
  end
  return st
end
-- zapamatovat, co ktere vybaveni dava
local function learn(list)
  if not (ns.db and list) then return end
  ns.db.campItems = ns.db.campItems or {}
  for _, b in ipairs(list) do ns.db.campItems[b.item] = b.eff end
end

------------------------------------------------------------------------------------------
-- Okenko u ohne
------------------------------------------------------------------------------------------
local frame
local function makeFrame()
  local f = CreateFrame('Frame', 'ClaudeMasterCamp', UIParent, 'BackdropTemplate')
  f:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
  local T = ns.THEME or { bg = { 0.05, 0.05, 0.08 }, border = { 0.3, 0.3, 0.4, 1 }, title = { 1, 0.8, 0.4 } }
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.92) f:SetBackdropBorderColor(1, 0.6, 0.2, 0.9)
  f:SetFrameStrata('MEDIUM')
  f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag('LeftButton') f:SetClampedToScreen(true)
  f:SetScript('OnDragStart', f.StartMoving)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.campPoint = { p, rp, x, y }
  end)
  f.icon = f:CreateTexture(nil, 'ARTWORK') f.icon:SetSize(18, 18) f.icon:SetPoint('TOPLEFT', 8, -7)
  f.icon:SetTexture('Interface\\Icons\\Spell_Fire_Fire')
  f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal') f.title:SetPoint('LEFT', f.icon, 'RIGHT', 6, 0)
  f.title:SetText('Kemp')
  f.text = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  f.text:SetPoint('TOPLEFT', 10, -30) f.text:SetJustifyH('LEFT') f.text:SetSpacing(2)
  local x = CreateFrame('Button', nil, f, 'UIPanelCloseButton') x:SetSize(20, 20) x:SetPoint('TOPRIGHT', 2, 2)
  x:SetScript('OnClick', function() f:Hide() C.closedAt = GetTime() end)
  local pt = ns.db and ns.db.campPoint
  if pt then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  elseif ns.UI and ns.UI.frame then f:SetPoint('BOTTOMRIGHT', ns.UI.frame, 'TOPLEFT', -8, 4)
  else f:SetPoint('CENTER', -250, 0) end
  return f
end

local lastSig
function C.update()
  if not ns.db or ns.db.campTip == false then if frame then frame:Hide() end return end
  if InCombatLockdown() or ns.inCombat() then if frame then frame:Hide() end return end
  local st = C.scan()
  if st.benefits then learn(st.benefits) end
  if not st.near then if frame then frame:Hide() end lastSig = nil return end
  if C.closedAt and GetTime() - C.closedAt < 600 then return end   -- zavreno krizkem: 10 min klid
  local lines, good, bad = {}, 0, 0
  if st.tent or C.tentUntil > GetTime() then
    lines[#lines + 1] = '|cff888888Camp Tent: ' .. (tentText()) .. '|r'
  end
  if st.benefits and #st.benefits > 0 then
    lines[#lines + 1] = '|cffffd200Mas z kempu' .. (st.left and (' (' .. st.left .. ' min)') or '') .. ':|r'
    for _, b in ipairs(st.benefits) do
      local w = worth(b.eff)
      if w == 2 then good = good + 1 elseif w == 0 then bad = bad + 1 end
      lines[#lines + 1] = ('%s%s|r: %s%s'):format(WCOL[w] or '|cffffffff', b.item, b.eff,
        w and (' - ' .. WTXT[w]) or '')
    end
    if bad > 0 and good == 0 then
      lines[#lines + 1] = '|cffff7070Tenhle kemp ti skoro nic neda - vyplati se vlastni kemp.|r'
    end
  else
    lines[#lines + 1] = '|cffffd200U ohne:|r sedni si, at ziskas bonusy (Camp Benefits).'
    lines[#lines + 1] = '|cff9aa6b8Najed mysi na vybaveni kempu - co addon zna, rekne v tooltipu.|r'
  end
  local sig = table.concat(lines, '\n')
  if not frame then frame = makeFrame() end
  if sig ~= lastSig then
    lastSig = sig
    frame.text:SetText(sig)
    frame:SetSize(math.max(220, frame.text:GetStringWidth() + 24), frame.text:GetStringHeight() + 40)
  end
  frame:Show()
end

------------------------------------------------------------------------------------------
-- Tooltip vybaveni kempu: co dava (pokud uz ho addon videl) a jestli se ti hodi
------------------------------------------------------------------------------------------
-- tooltip objektu ve svete se pri dalsim najeti jen prepise (OnShow znovu neprijde) -> hak na sestaveni
-- tooltipu (TooltipDataProcessor, kazde sestaveni); OnShow jen jako zaloha pro starsi klienty
local function campLine(tt, name)
  if not ns.db or ns.db.campTip == false then return end
  if type(name) ~= 'string' or tt:IsForbidden() then return end
  local eff = effOf(name)
  if not eff or tt.cmCamp == name then return end
  tt.cmCamp = name
  local w = worth(eff)
  if name == 'Camp Tent' then w = select(2, tentText()) end
  tt:AddLine(('|cff66ccffClaudeMaster:|r %s%s|r%s'):format(WCOL[w] or '|cffffffff', eff, w and (' - ' .. WTXT[w]) or ''),
    1, 1, 1, true)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
  pcall(TooltipDataProcessor.AddTooltipPostCall, TooltipDataProcessor.AllTypes, function(tt, data)
    if tt ~= GameTooltip then return end
    local l = type(data) == 'table' and type(data.lines) == 'table' and data.lines[1]
    pcall(campLine, tt, l and safe(l.leftText))
  end)
end
if GameTooltip then
  GameTooltip:HookScript('OnTooltipCleared', function(tt) tt.cmCamp = nil end)
  GameTooltip:HookScript('OnHide', function(tt) tt.cmCamp = nil end)
  -- zaloha: objekt ve svete (tooltip se prepisuje bez OnShow) - kontrola 5x za sekundu
  local acc = 0
  GameTooltip:HookScript('OnUpdate', function(tt, el)
    acc = acc + el
    if acc < 0.2 then return end
    acc = 0
    if tt.cmCamp or not ns.db then return end
    local fs = _G[tt:GetName() .. 'TextLeft1']
    local name = fs and safe(fs:GetText())
    if type(name) == 'string' and effOf(name) then
      pcall(campLine, tt, name)
      tt:Show()
    end
  end)
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'UNIT_AURA', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'PLAYER_ENTERING_WORLD' }) do
  pcall(ev.RegisterEvent, ev, e)
end
local pend = false
ev:SetScript('OnEvent', function(_, e, unit)
  if e == 'UNIT_AURA' and unit ~= 'player' then return end
  if e == 'PLAYER_REGEN_DISABLED' then if frame then frame:Hide() end return end
  if pend or not C_Timer then return end
  pend = true
  C_Timer.After(0.5, function() pend = false pcall(C.update) end)
end)

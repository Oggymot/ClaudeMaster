-- ClaudeMaster: zobrazeni
-- [ velka ikona = ted ] [ mana bar                    ]
--                       [ potom ] [ potom ]   [ item ]
-- ---------------------------------------------------
-- Duvod doporuceni
-- Moby / cil / stavy
local ADDON, ns = ...
if not ns.enabled then
  -- trida zatim bez rotace: aspon /cm dump a /cm sonda, at muzu pripravit podporu
  SLASH_CLAUDEMASTER1 = '/cm'
  SLASH_CLAUDEMASTER2 = '/claudemaster'
  SlashCmdList.CLAUDEMASTER = function(msg)
    local cmd = (msg or ''):lower():match('^(%S*)')
    local arg = (msg or ''):lower():match('^%S*%s*(.-)%s*$')
    if cmd == 'dump' then ns.fullDump()
    elseif cmd == 'sonda' or cmd == 'probe' then ns.apiProbe()
    elseif cmd == 'gear' and ns.Gear then ns.Gear.setSpec(arg)
    elseif cmd == 'vahy' and ns.Gear then ns.Gear.setWeights(arg)
    else ns.say(tostring(ns.class) .. ' zatim neumim radit. Funguje: /cm dump, /cm sonda, /cm gear, /cm vahy') end
  end
  return
end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local UI = {}
ns.UI = UI

local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local BAR = 'Interface\\TargetingFrame\\UI-StatusBar'

-- rozmery
local PAD, GAP = 8, 8
local MAIN, SMALL, SPACING = 52, 34, 4
local RIGHT_W = 172                              -- mana bar; pod nim dve "potom" ikony a vpravo item ikona
local WIDTH = PAD + MAIN + GAP + RIGHT_W + PAD
local MANA_H = 12
local TEXT_W = WIDTH - PAD * 2

-- barvy podle classy: mag = mrazive modra, warlock = fialova
local T = (ns.class == 'PALADIN') and {
  a1 = { 1, 0.78, 0.3, 0.95 }, a2 = { 1, 0.9, 0.6, 0.15 }, bg = { 0.08, 0.065, 0.04 }, border = { 0.45, 0.36, 0.2, 0.9 },
  title = { 1, 0.85, 0.5 }, icon = 'Interface\\Icons\\Spell_Holy_HolyBolt', ui = { 1, 0.8, 0.4 },
} or (ns.class == 'DRUID') and {
  a1 = { 1, 0.49, 0.04, 0.95 }, a2 = { 1, 0.75, 0.45, 0.15 }, bg = { 0.07, 0.05, 0.03 }, border = { 0.45, 0.3, 0.12, 0.9 },
  title = { 1, 0.7, 0.35 }, icon = 'Interface\\Icons\\Spell_Nature_Regeneration', ui = { 1, 0.6, 0.2 },
} or (ns.class == 'WARLOCK') and {
  a1 = { 0.62, 0.32, 1, 0.95 }, a2 = { 0.88, 0.6, 1, 0.15 }, bg = { 0.06, 0.035, 0.09 }, border = { 0.34, 0.22, 0.48, 0.9 },
  title = { 0.8, 0.6, 1 }, icon = 'Interface\\Icons\\Spell_Shadow_ShadowBolt', ui = { 0.68, 0.45, 1 },
} or {
  a1 = { 0.25, 0.65, 1, 0.9 }, a2 = { 0.6, 0.9, 1, 0.15 }, bg = { 0.04, 0.05, 0.08 }, border = { 0.22, 0.28, 0.38, 0.9 },
  title = { 0.55, 0.82, 1 }, icon = 'Interface\\Icons\\Spell_Frost_FrostBolt02', ui = { 0.35, 0.75, 1 },
}
ns.THEME = T

local COLORS = {
  go = { 0.25, 1, 0.4 }, wait = { 1, 0.8, 0.15 }, urgent = { 1, 0.2, 0.2 }, next = { 0.35, 0.5, 0.75 },
  item = { 0.75, 0.45, 1 }, hint = { 0.5, 0.5, 0.5 }, empty = { 0.18, 0.2, 0.25 },
}

------------------------------------------------------------------------------------------
-- Ikona
------------------------------------------------------------------------------------------
local function makeIcon(parent, size, withGlow)
  local b = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
  b:SetSize(size, size)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
  b:SetBackdropColor(0, 0, 0, 0.6)
  b:SetBackdropBorderColor(unpack(COLORS.empty))
  b.tex = b:CreateTexture(nil, 'ARTWORK')
  b.tex:SetPoint('TOPLEFT', 2, -2) b.tex:SetPoint('BOTTOMRIGHT', -2, 2)
  b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if withGlow then
    -- mekka zare kolem hlavni ikony
    b.glow = b:CreateTexture(nil, 'BACKGROUND')
    b.glow:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
    b.glow:SetBlendMode('ADD')
    b.glow:SetPoint('CENTER') b.glow:SetSize(size * 1.9, size * 1.9)
    b.glow:SetAlpha(0)
  end
  b.cd = CreateFrame('Cooldown', nil, b, 'CooldownFrameTemplate')
  b.cd:SetPoint('TOPLEFT', 2, -2) b.cd:SetPoint('BOTTOMRIGHT', -2, 2)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  if b.cd.SetSwipeColor then b.cd:SetSwipeColor(0, 0, 0, 0.65) end
  local over = CreateFrame('Frame', nil, b)
  over:SetAllPoints() over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
  b.key = over:CreateFontString(nil, 'OVERLAY')
  b.key:SetFont(FONT, math.max(9, math.floor(size * 0.24)), 'OUTLINE')
  b.key:SetPoint('TOPRIGHT', -3, -3)
  b.key:SetTextColor(0.9, 0.9, 0.9)
  b.timer = over:CreateFontString(nil, 'OVERLAY')
  b.timer:SetFont(FONT, math.max(11, math.floor(size * 0.38)), 'THICKOUTLINE')
  b.timer:SetPoint('CENTER', 0, -1)
  b.label = over:CreateFontString(nil, 'OVERLAY')
  b.label:SetFont(FONT, math.max(7, math.floor(size * 0.2)), 'OUTLINE')
  b.label:SetPoint('BOTTOM', 0, 3)
  return b
end

local function setCooldown(b, name, kind)
  if kind == 'item' or not ns.known(name) then b.cd:Clear() return end
  local id = ns.id(name)
  -- Forever: i v boji jde predat "durationObject" primo hre
  if C_Spell and C_Spell.GetSpellCooldownDuration and b.cd.SetCooldownFromDurationObject then
    local d = pc(C_Spell.GetSpellCooldownDuration, id, true)
    if d ~= nil and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then return end
  end
  local cd = C_Spell and pc(C_Spell.GetSpellCooldown, id)
  if type(cd) == 'table' then
    local s, du = safeNum(cd.startTime), safeNum(cd.duration)
    if s and du then b.cd:SetCooldown(s, du) return end
  end
  local t = ns.cdUntil[name]
  if t and t > GetTime() then b.cd:SetCooldown(t - ns.cdFor(name), ns.cdFor(name)) else b.cd:Clear() end
end

-- prazdny slot: tlumeny ctverecek, aby rozlozeni neposkakovalo
local function clear(b)
  b.tex:SetTexture(nil)
  b.key:SetText('') b.timer:SetText('') b.label:SetText('')
  b.cd:Clear()
  b:SetBackdropBorderColor(unpack(COLORS.empty))
  b:SetAlpha(0.45)
  if b.glow then b.glow:SetAlpha(0) end
end

local function fill(b, a, role, waitLeft)
  if not a then clear(b) return end
  b:SetAlpha(1)
  local icon, key
  if a.kind == 'item' then
    icon = ns.itemIcon(a.item)
    key = ns.binds['item:' .. tostring(a.item)]
  else
    icon = a.icon or ns.icon(a.name)
    key = a.key or ns.binds[a.name]
  end
  b.tex:SetTexture(icon)
  b.key:SetText(key or '')
  setCooldown(b, a.name, a.kind)
  local col, label = nil, ''
  if role == 'main' then
    if a.urgent then col = COLORS.urgent
    elseif a.kind == 'wait' or a.kind == 'hint' then col = COLORS.wait
    elseif waitLeft and waitLeft > ns.queueLead() then col = COLORS.wait
    else col = COLORS.go end
    b.timer:SetText((waitLeft and waitLeft > 0.05 and a.kind ~= 'wait') and ('%.1f'):format(waitLeft) or '')
    if b.glow then
      b.glow:SetVertexColor(col[1], col[2], col[3])
      b.glow:SetAlpha(col == COLORS.wait and 0.25 or 0.6)
    end
    if a.batch then label = 'BATCH' elseif a.rank then label = 'R' .. a.rank elseif a.learned then label = '|cff88ccffTVOJE|r' end
  elseif role == 'util' then
    col = a.urgent and COLORS.urgent or (a.kind == 'hint' and COLORS.hint or COLORS.item)
    label = a.kind == 'item' and 'ITEM' or (a.kind == 'hint' and 'TIP' or 'CD')
    b.timer:SetText('')
  else
    col = COLORS.next
    b.timer:SetText('')
    if a.batch then label = 'BATCH' elseif a.rank then label = 'R' .. a.rank end
  end
  b:SetBackdropBorderColor(col[1], col[2], col[3], 1)
  b.label:SetText(label)
  b.tex:SetDesaturated(role == 'util' and a.kind == 'hint')
end

------------------------------------------------------------------------------------------
-- Klikani (mimo boj)
------------------------------------------------------------------------------------------
-- Panel ukotvime levym hornim rohem (kdyz se meni vyska, ikona se nehne) a tlacitko na nej.
function UI.reanchor()
  local f = UI.frame
  if not f or InCombatLockdown() then return end
  local l, t = f:GetLeft(), f:GetTop()
  if not l or not t then return end
  f:ClearAllPoints()
  f:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l, t)
  ns.db.point = { 'TOPLEFT', 'BOTTOMLEFT', l, t }
  for key, b in pairs(UI.clicks or {}) do
    local icon = f[key]
    local il, it = icon and icon:GetLeft(), icon and icon:GetTop()
    b:SetScale(f:GetScale())
    b:ClearAllPoints()
    if il and it then b:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', il, it) end
    if icon then b:SetSize(icon:GetWidth(), icon:GetHeight()) end
    b:SetShown(f:IsShown())
  end
end

local lastSig = {}
UI.clickNames, UI.slotAct = {}, {}
function UI.setClick(key, a)
  ns.phase = 'setClick'
  local b = UI.clicks and UI.clicks[key]
  local test = InCombatLockdown() and ns.db.clickTest
  if not b or (InCombatLockdown() and not test) then return end
  if test and UI.ctest.done then return end   -- vysledek uz vime, dal hru nezahlcovat
  local typ, val, unit, label
  if a and a.kind == 'item' and a.item then
    typ, val, label = 'item', 'item:' .. a.item, (ns.Bags.items[a.item] and ns.Bags.items[a.item].name) or 'predmet'
    unit = a.unit
    if a.unit then label = label .. ' -> ' .. (safe(pc(UnitName, a.unit)) or a.unit) end
  elseif a and a.trade and a.trade.name and a.trade.item then
    typ, val, label = 'macro', '/target ' .. a.trade.name, ('poslat %s: %s (otevre obchod)'):format(a.trade.name, a.trade.what or 'item')
  elseif a and a.macro then
    typ, val, label = 'macro', a.macro, a.macroLabel or 'klik'
  elseif a and (a.kind == 'spell' or a.kind == 'hint') and a.name and ns.known(a.name) then
    typ, val, unit, label = 'spell', (ns.S[a.name] and ns.S[a.name].realName) or a.name, a.unit, a.name
    if a.rank and ns.rankId(a.name, a.rank) then val = ns.rankId(a.name, a.rank) label = a.name .. ' (rank ' .. a.rank .. ')' end
    if a.unit and a.unit ~= 'player' then label = label .. ' -> ' .. (safe(pc(UnitName, a.unit)) or a.unit) end
  end
  local sig = tostring(typ) .. '|' .. tostring(val) .. '|' .. tostring(unit) .. '|' .. tostring(a and a.slot)
  if sig == lastSig[key] then return end
  lastSig[key] = sig
  if test and not typ then return end          -- test: zkouset jen skutecnou akci
  if test then UI.ctest.done = true end        -- jen jeden pokus za boj (kazdy blok = hlaska)
  -- "cm-type" je zadana akce; samotne "type" prepina zabezpeceny state driver (v boji = nic)
  local okA = pcall(function()
    b:SetAttribute('cm-type', typ)
    b:SetAttribute('type', typ)
    b:SetAttribute('spell', typ == 'spell' and val or nil)
    b:SetAttribute('item', typ == 'item' and val or nil)
    b:SetAttribute('unit', unit)
    b:SetAttribute('target-slot', (typ == 'item' and a.slot) or nil)
    b:SetAttribute('macrotext', typ == 'macro' and val or nil)
  end)
  b.cmTrade = (typ == 'macro' and a and a.trade) or nil
  if test and typ then
    -- test: opravdu se zmena v boji ulozila?
    local now = typ == 'spell' and b:GetAttribute('spell') or b:GetAttribute('item')
    local ok = okA and now == val and b:GetAttribute('type') == typ
    ns.say(ok and ('|cff66ee77Test klikani v boji: zmena PROSLA|r (%s = %s). Zkus kliknout na ikonu.'):format(key, tostring(label))
      or '|cffff5555Test klikani v boji: hra zmenu ZABLOKOVALA|r - v boji klik opravdu nejde. Test vypnut.')
    if not ok then
      -- test sam vypnout; po boji vratit bezpecne vypinani tlacitek v boji
      ns.db.clickTest = false
      UI.ctestRestore = true
      return
    end
  end
  UI.clickNames[key] = label
  if key == 'main' then UI.clickName = label end
end
-- Na zacatku boje tlacitko "vypneme" (v boji uz to nepujde zmenit)
-- Na zacatku boje na tlacitko nesahame (to by hra zablokovala). Vypne ho state driver.
-- obchod otevreny po kliknuti na tip: vlozit item (potvrzeni Trade nechame na hraci)
do
  local tf = CreateFrame('Frame')
  tf:RegisterEvent('TRADE_SHOW')
  tf:SetScript('OnEvent', function()
    local p = UI.pendingTrade
    UI.pendingTrade = nil
    if not p or GetTime() - p.at > 15 or InCombatLockdown() then return end
    local getNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getInfo = C_Container and C_Container.GetContainerItemInfo
    local pick = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
    if not (getNum and getInfo and pick and ClickTradeButton) then return end
    for bag = 0, 4 do
      for slot = 1, (safeNum(pc(getNum, bag)) or 0) do
        local info = pc(getInfo, bag, slot)
        if type(info) == 'table' and safeNum(info.itemID) == p.item then
          if pcall(pick, bag, slot) and pcall(ClickTradeButton, 1) then
            ns.say('Item je v obchodu - potvrd Trade.')
          else
            if ClearCursor then ClearCursor() end
            ns.say('Item se nepovedlo vlozit, pretahni ho do obchodu sam.')
          end
          return
        end
      end
    end
  end)
end
UI.ctest = {}
-- po neuspesnem testu vratit vypinani tlacitek v boji (state driver), jakmile boj skonci
do
  local rf = CreateFrame('Frame')
  rf:RegisterEvent('PLAYER_REGEN_ENABLED')
  rf:SetScript('OnEvent', function()
    if not UI.ctestRestore or InCombatLockdown() then return end
    UI.ctestRestore = nil
    for _, b in pairs(UI.clicks or {}) do RegisterStateDriver(b, 'cmcombat', '[combat] in; out') end
  end)
end
function UI.combatStart()
  UI.ctest.done = nil
  wipe(lastSig)
  wipe(UI.clickNames)
  UI.clickName = nil
end

-- tooltip ikony: co to je, proc, a co udela klik
local function slotTip(self)
  local key = self.cmKey
  local a = UI.slotAct[key]
  if not a then return end
  GameTooltip:SetOwner(self, 'ANCHOR_TOP')
  local title = a.name
  if a.kind == 'item' and a.item and ns.Bags.items[a.item] then title = ns.Bags.items[a.item].name or title end
  if title == 'TARGET' then title = a.trade and 'Poslat partakovi' or 'Tip' end
  GameTooltip:AddLine(title or 'ClaudeMaster', T.title[1], T.title[2], T.title[3])
  if a.reason and a.reason ~= title then GameTooltip:AddLine(a.reason, 1, 1, 1, true) end
  local cn = UI.clickNames[key]
  if cn and not InCombatLockdown() then
    GameTooltip:AddLine('Klikni: ' .. cn, 0.55, 0.85, 1)
  elseif InCombatLockdown() and (a.kind == 'item' or ns.known(a.name)) then
    GameTooltip:AddLine('V boji klik nejde (hra nedovoli) - pouzij klavesu', 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

-- Klikaci tlacitko pres ikonu (jen mimo boj; v boji hra addonum menit akci nedovoli).
-- Samostatny ramec pod UIParent, aby panel samotny nebyl "chraneny" a slo ho v boji menit.
local function makeClick(key)
  local btn = CreateFrame('Button', 'ClaudeMasterClick' .. (key == 'main' and '' or key), UIParent,
    'SecureActionButtonTemplate,SecureHandlerStateTemplate')
  btn.cmKey = key
  -- v boji hra sama (zabezpecene) vypne akci tlacitka, po boji ji vrati
  btn:SetAttribute('_onstate-cmcombat', [[
    if newstate == 'in' then
      self:SetAttribute('type', nil)
    else
      self:SetAttribute('type', self:GetAttribute('cm-type'))
    end
  ]])
  if RegisterStateDriver and not ns.db.clickTest then RegisterStateDriver(btn, 'cmcombat', '[combat] in; out') end
  local sz = key == 'main' and MAIN or SMALL
  btn:SetSize(sz, sz)
  btn:SetScale(ns.db.scale or 1)
  btn:SetFrameStrata('MEDIUM')
  btn:SetFrameLevel(UI.frame:GetFrameLevel() + 20)
  -- jen jedna faze kliknuti (podle nastaveni hry), jinak by se akce spustila dvakrat
  local down = GetCVarBool and GetCVarBool('ActionButtonUseKeyDown')
  btn:RegisterForClicks(down and 'AnyDown' or 'AnyUp')
  btn:SetScript('PostClick', function(self)
    local t = self.cmTrade
    if not t or InCombatLockdown() then return end
    UI.pendingTrade = { item = t.item, at = GetTime() }
    pcall(InitiateTrade, t.unit)
  end)
  btn:SetScript('OnEnter', slotTip)
  btn:SetScript('OnLeave', function() GameTooltip:Hide() end)
  -- pres ikony jde panel i tahnout (jinak by ho tlacitka zakryla)
  btn:RegisterForDrag('LeftButton')
  btn:SetScript('OnDragStart', function()
    if not ns.db.locked and not InCombatLockdown() then UI.frame:StartMoving() end
  end)
  btn:SetScript('OnDragStop', function()
    UI.frame:StopMovingOrSizing()
    UI.reanchor()
  end)
  return btn
end

------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------
function UI.build()
  if UI.frame then return end
  local db = ns.db
  if db.compact == nil then db.compact = (ns.class == 'WARLOCK') end   -- warlock: jen ikony
  -- warlock v kompaktnim rezimu: bez mana baru, vse v jedne rade (hlavni ikona jako ostatni)
  UI.slim = db.compact and ns.class == 'WARLOCK'
  if UI.slim then
    MAIN, MANA_H = SMALL, 0
    RIGHT_W = SMALL * 3 + SPACING + GAP
    WIDTH = PAD + MAIN + GAP + RIGHT_W + PAD
    TEXT_W = WIDTH - PAD * 2
  end
  local f = CreateFrame('Frame', 'ClaudeMasterFrame', UIParent, 'BackdropTemplate')
  UI.frame = f
  f:SetSize(WIDTH, 120)
  f:SetScale(db.scale or 1)
  f:SetMovable(true) f:SetClampedToScreen(true)
  f:EnableMouse(not db.locked)
  f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', function(self)
    if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
  end)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    UI.reanchor()
  end)
  local p = db.point
  f:SetPoint(p[1], UIParent, p[2], p[3], p[4])

  if C_Timer then C_Timer.After(0, UI.reanchor) end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.82)
  f:SetBackdropBorderColor(unpack(T.border))

  -- mrazivy prouzek nahore
  f.accent = f:CreateTexture(nil, 'BORDER')
  f.accent:SetTexture(WHITE)
  f.accent:SetPoint('TOPLEFT', 1, -1) f.accent:SetPoint('TOPRIGHT', -1, -1) f.accent:SetHeight(2)
  if f.accent.SetGradient and CreateColor then
    f.accent:SetGradient('HORIZONTAL', CreateColor(unpack(T.a1)), CreateColor(unpack(T.a2)))
  else f.accent:SetVertexColor(T.a1[1], T.a1[2], T.a1[3], 0.8) end

  f.main = makeIcon(f, MAIN, true)
  f.main:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD, -PAD)

  local rx = PAD + MAIN + GAP
  -- mana: hodnoty jdou primo do StatusBaru, takze bar je presny i kdyz je mana skryta
  local mb = CreateFrame('Frame', nil, f, 'BackdropTemplate')
  mb:SetPoint('TOPLEFT', f, 'TOPLEFT', rx, -PAD)
  mb:SetSize(RIGHT_W, MANA_H)
  mb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  mb:SetBackdropColor(0, 0, 0, 0.7)
  mb:SetBackdropBorderColor(0, 0, 0, 1)
  f.mana = CreateFrame('StatusBar', nil, mb)
  f.mana:SetPoint('TOPLEFT', 1, -1) f.mana:SetPoint('BOTTOMRIGHT', -1, 1)
  f.mana:SetStatusBarTexture(BAR)
  f.mana:SetStatusBarColor(0.2, 0.5, 1)
  f.mana:SetMinMaxValues(0, 1) f.mana:SetValue(1)
  f.mana.text = f.mana:CreateFontString(nil, 'OVERLAY')
  f.mana.text:SetFont(FONT, 9, 'OUTLINE')
  f.mana.text:SetPoint('CENTER', 0, 0)

  local iy = -(PAD + MANA_H + (MAIN - MANA_H - SMALL))   -- zarovnat spodek s hlavni ikonou
  f.n1 = makeIcon(f, SMALL)
  f.n1:SetPoint('TOPLEFT', f, 'TOPLEFT', rx, iy)
  f.n2 = makeIcon(f, SMALL)
  f.n2:SetPoint('LEFT', f.n1, 'RIGHT', SPACING, 0)
  f.util = makeIcon(f, SMALL)
  f.util:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -PAD, iy)
  -- sipka mezi "ted" a "potom"
  -- klikaci tlacitka nad vsemi ctyrmi ikonami
  UI.clicks = {}
  for _, key in ipairs({ 'main', 'n1', 'n2', 'util' }) do UI.clicks[key] = makeClick(key) end
  UI.click = UI.clicks.main
  f.arrow = f:CreateFontString(nil, 'OVERLAY')
  f.arrow:SetFont(FONT, 10, 'OUTLINE')
  f.arrow:SetPoint('RIGHT', f.n1, 'LEFT', -1, 0)
  f.arrow:SetTextColor(0.5, 0.6, 0.75)
  f.arrow:SetText('>')

  -- oddelovac
  f.sep = f:CreateTexture(nil, 'ARTWORK')
  f.sep:SetTexture(WHITE)
  f.sep:SetVertexColor(0.3, 0.38, 0.5, 0.45)
  f.sep:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD, -(PAD + MAIN + 6))
  f.sep:SetSize(TEXT_W, 1)

  f.reason = f:CreateFontString(nil, 'OVERLAY')
  f.reason:SetFont(FONT, 12, 'OUTLINE')
  f.reason:SetPoint('TOPLEFT', f.sep, 'BOTTOMLEFT', 0, -6)
  f.reason:SetWidth(TEXT_W) f.reason:SetJustifyH('LEFT') f.reason:SetJustifyV('TOP')
  f.reason:SetWordWrap(true) f.reason:SetSpacing(1)

  -- kompaktni rezim: kratky text vpravo od ikon (pull, ready check) misto pod nimi
  f.side = f:CreateFontString(nil, 'OVERLAY')
  f.side:SetFont(FONT, 10, 'OUTLINE')
  f.side:SetPoint('TOPLEFT', f, 'TOPRIGHT', 6, -PAD)
  f.side:SetWidth(170) f.side:SetJustifyH('LEFT') f.side:SetJustifyV('TOP')
  f.side:SetWordWrap(true) f.side:SetSpacing(1)
  f.side:SetShadowOffset(1, -1) f.side:SetShadowColor(0, 0, 0, 1)

  f.info = f:CreateFontString(nil, 'OVERLAY')
  f.info:SetFont(FONT, 10, 'OUTLINE')
  f.info:SetPoint('TOPLEFT', f.reason, 'BOTTOMLEFT', 0, -5)
  f.info:SetWidth(TEXT_W) f.info:SetJustifyH('LEFT') f.info:SetJustifyV('TOP')
  f.info:SetWordWrap(true) f.info:SetSpacing(2)
  f.info:SetTextColor(0.72, 0.8, 0.92)

  clear(f.main) clear(f.n1) clear(f.n2) clear(f.util)
  f.pulse = 0
  if not db.shown then f:Hide() end
end

local SEP = '  |cff556070-|r  '
-- kazda skupina na vlastnim radku: moby / cil / stavy
-- co vime o mobovi: jen to dulezite (kouzli cim, utika - jiste, ne odhad)
-- (ikonky: skola kouzel, utek, leceni, CC, patrola - bez textu)
function UI.mobText(c)
  local m = c.mob
  local I = ns.ico
  local p = {}
  -- questovy mob: vykricnik + kolik jeste
  local q = c.hostile and ns.Quests and ns.Quests.mobNeed and ns.Quests.mobNeed('target')
  if q then p[#p + 1] = I('quest') .. (q.have and q.need and ('|cffffd100%d/%d|r'):format(q.have, q.need) or '') end
  if not m then return #p > 0 and table.concat(p, ' ') or nil end
  if m.caster then p[#p + 1] = I(m.school and ns.ICON[m.school] and m.school or 'arcane') end
  local d = m.db
  if d and #d.heal > 0 then p[#p + 1] = I('heal') end
  if d and #d.cc > 0 then p[#p + 1] = I('cc') end
  if m.flees and not m.fleeGuess then p[#p + 1] = I('flee') end
  if d and d.patrol and not c.inCombat then p[#p + 1] = I('patrol') end
  return #p > 0 and table.concat(p, ' ') or nil
end
local function infoLines(c)
  local lines = {}
  local e = c.enemies
  if (c.inCombat or e.combat > 0) and (e.combat > 1 or (e.cc or 0) > 0 or e.onMe > 1) then
    -- meče = moby v boji, stit = na tobe, ovce = v CC
    local I = ns.ico
    local t = ('%s |cffffffff%d|r'):format(I('swords'), e.combat)
    if e.onMe > 0 then t = t .. ('   %s |cffff7070%d|r'):format(I('onme'), e.onMe) end
    if (e.cluster or 0) >= 2 and e.cluster ~= e.onMe then t = t .. ('   |cff9aa6b8pohromade %d|r'):format(e.cluster) end
    if (e.cc or 0) > 0 then t = t .. ('   %s |cffc080ff%d|r'):format(I('sheep'), e.cc) end
    lines[#lines + 1] = t
  end
  -- mimo boj: staci mana na dalsi boj?
  if not c.inCombat and c.manaKnown and ns.Mem then
    local need, specific = ns.Mem.needMana(c.hostile and ns.Immune.tname or nil, c.group)
    -- jen kdyz mana nestaci (jinak zbytecny radek)
    if need and c.mana < need * 1.15 + 0.05 then
      lines[#lines + 1] = ('|cffff7070Na %s boj ~%d%% many (mas %d%%)|r'):format(specific and 'tento' or 'dalsi',
        math.floor(need * 100 + 0.5), math.floor(c.mana * 100))
    end
  end
  if ns.Afflict and ns.Afflict.infoLines then pcall(ns.Afflict.infoLines, c, lines) end
  -- co cil kouzli a jestli stoji za preruseni
  if c.tCasting and c.tCastPrio then
    local col = (c.tCastPrio >= 3 and '|cffff5555') or (c.tCastPrio == 2 and '|cffffcc00') or '|cff8a93a3'
    local word = (c.tCastPrio >= 3 and 'PRERUS') or (c.tCastPrio == 2 and 'vyplati se prerusit') or 'levne, interrupt si drz'
    lines[#lines + 1] = ('Kouzli: %s%s|r (%s)'):format(col, c.tCastName or '?', word)
  end
  -- duo: partak s addonem
  local plist = ns.Duo and ns.Duo.peerList and ns.Duo.peerList() or {}
  if plist[1] and c.inCombat and ns.Duo.encounter then
    lines[#lines + 1] = '|cffffcc00Boss: hra blokuje zpravy, s partaky nic nesdilime|r'
  elseif c.inCombat then
    -- kazdy partak, kteremu neco chybi (nejslabsi prvni, nejvys 3): ikona tridy + HP (barevne) + mana (modre)
    local need = {}
    for _, peer in ipairs(plist) do
      if (peer.hp and peer.hp < 70) or (peer.mana and peer.mana < 0.3) or peer.drink then need[#need + 1] = peer end
    end
    table.sort(need, function(a, b) return (a.hp or 100) < (b.hp or 100) end)
    for i, peer in ipairs(need) do
      if i > 3 then break end
      local col = (peer.hp and peer.hp < 35 and '|cffff5555') or (peer.hp and peer.hp < 60 and '|cffffcc00') or '|cff66ee77'
      local hp = peer.hp and (col .. peer.hp .. '%|r') or '?'
      local m = peer.mana and ('  |cff6fa8ff' .. math.floor(peer.mana * 100) .. '%|r') or ''
      lines[#lines + 1] = ('%s %s  %s%s%s'):format(ns.classIco(peer.cls), peer.name, hp, m, peer.drink and ('  ' .. ns.ico('drink')) or '')
    end
  end
  if ns.class == 'WARLOCK' and c.instance and c.ssKnown ~= nil and ns.Warlock and ns.Warlock.ssKnown then
    lines[#lines + 1] = c.ssOn and ('Soulstone: |cff9a7cffna ' .. c.ssOn .. '|r')
      or '|cffffcc00Soulstone: nikdo|r'
  end
  if c.group and c.inCombat and ns.Party and ns.Party.kickState then
    local ks = ns.Party.kickState()
    if ks.others then
      local p = {}
      for _, k in ipairs(ks.list) do
        local col = k.ready and ((ks.nextUp == k) and '|cff66ee77' or '|cffcfd8e3') or '|cff8a93a3'
        p[#p + 1] = col .. (k.me and 'ty' or k.name) .. (k.ready and '' or (' ' .. math.ceil(k.left) .. 's')) .. '|r'
      end
      lines[#lines + 1] = 'Interrupty: ' .. table.concat(p, ' ')
    end
  end
  if c.hostile and c.inCombat then
    local t
    if c.thp then
      if c.thpExact then t = ('Cil |cffffffff%d%%|r'):format(math.floor(c.thp))
      else t = ('Cil |cffffffff%d-%d%%|r'):format(c.thpLo or 0, c.thpHi or 100) end
    else t = 'Cil ?' end
    if c.elite then t = t .. ' |cffffd100elite|r' end
    if c.tankUp and c.threatPct then
      local tp = math.floor(c.threatPct)
      t = t .. SEP .. (tp >= 85 and '|cffff5555' or (tp >= 60 and '|cffffcc00' or '|cff9aa6b8')) .. 'threat ' .. tp .. '%|r'
    end
    if c.ttd then t = t .. SEP .. (c.ttd < 1 and '|cffffffffpadne kazdou chvili|r' or ('padne za |cffffffff%ds|r'):format(math.floor(c.ttd + 0.5)))
    elseif c.ttdMem then t = t .. SEP .. ('padne za ~%ds'):format(math.floor(c.ttdMem)) end
    local mt = UI.mobText(c)
    if mt then t = t .. SEP .. mt end
    lines[#lines + 1] = t
  end
  if c.hostile then
    -- mimo boj: co vime o mobovi samostatne (v boji je to na radku s cilem)
    local mt = not c.inCombat and UI.mobText(c)
    if mt then lines[#lines + 1] = '|cff9aa6b8Mob:|r ' .. mt end
    -- kiting (solo, mob na tobe): kdy je co pripravene
    if ns.class == 'MAGE' and c.inCombat and not c.group and c.aggro and (c.near or c.frozen > 0 or c.novaAgo < 12) then
      local function cdt(n)
        if not ns.known(n) then return nil end
        local l = ns.cdLeft(n)
        return n:gsub('Frost ', ''):gsub('Cone of Cold', 'Cone') .. ' ' .. (l > 0.5 and ('%ds'):format(math.ceil(l)) or '|cff66ee77ok|r')
      end
      local k = {}
      if c.frozen > 0 then k[#k + 1] = ('led %.1fs'):format(c.frozen) end
      for _, n in ipairs({ 'Frost Nova', 'Cone of Cold', 'Blink' }) do local x = cdt(n) if x then k[#k + 1] = x end end
      lines[#lines + 1] = '|cff7fd8ffKite: ' .. table.concat(k, ' | ') .. '|r'
    end
    if c.imm then
      local im = ns.Immune.describe(c.imm)
      if #im > 0 then lines[#lines + 1] = '|cffff8a8aImunni: ' .. table.concat(im, ', ') .. '|r' end
    end
  end
  -- parta s tankem: kdo drzi kolik mobu, kdy AoE
  if c.inCombat and c.tankUp then
    local t = ('|cff9ad0ffTank %s|r drzi |cffffffff%d|r'):format(c.tankName or '?', c.tankMobs or 0)
    local w = (ns.db.aoeDelay or 3) - (c.pullAge or 0)
    if (c.enemies.cluster or 0) >= ns.db.aoe then
      t = t .. SEP .. (w > 0 and ('AoE za %ds'):format(math.ceil(w)) or '|cff66ee77AoE ok|r')
    end
    if c.enemies.skull and c.mark ~= 8 then t = t .. SEP .. '|cffff7070lebka!|r' end
    lines[#lines + 1] = t
  end
  if ns.Engine.infoLine then
    local w = ns.Engine.infoLine(c)
    if w then lines[#lines + 1] = w end
  end
  local st = {}
  if c.hostile and c.frozen > 0 then st[#st + 1] = ('|cff7fd8ffZmrazen %.1fs|r'):format(c.frozen) end
  if c.fof and c.fof > 0 then st[#st + 1] = ('|cff7fd8ffFoF %d|r'):format(c.fof) end
  if c.barrierUp then st[#st + 1] = '|cff99c8ffBarrier|r' end
  if c.php and c.inCombat and c.php < 75 then
    local col = c.hpLow35 and '|cffff4444' or (c.hpLow50 and '|cffffcc00' or '|cff66ee77')
    st[#st + 1] = col .. 'HP ~' .. math.floor(c.php) .. '%|r'
  end
  if #st > 0 then lines[#lines + 1] = table.concat(st, SEP) end
  local out = table.concat(lines, '\n')
  if ns.db.debug and c.hostile then
    local function cd(n) return ns.known(n) and ('%.0f'):format(ns.cdLeft(n)) or '-' end
    out = out .. ('\n|cff8a8a8athreat:%s/%s near:%s aggro:%s tt:%s tank:%s nova:%s coc:%s IL:%s FB:%s glowIL:%s|r'):format(
      tostring(c.threat and math.floor(c.threat)), tostring(c.threatStatus),
      tostring(c.near), tostring(c.aggro), tostring(c.tt), tostring(c.tanking),
      cd('Frost Nova'), cd('Cone of Cold'), cd('Ice Lance'), cd('Fire Blast'), tostring(ns.glowing('Ice Lance')))
  end
  return out
end

function UI.update(c, plan, util)
  local f = UI.frame
  if not f or not ns.db.shown then return end
  local db = ns.db

  -- mana (warlock v kompaktnim rezimu ji nepotrebuje videt)
  local manaBox = f.mana:GetParent()
  local hideMana = db.compact and ns.class == 'WARLOCK'
  if manaBox and manaBox:IsShown() == hideMana then manaBox:SetShown(not hideMana) end
  local okC, cur = pcall(UnitPower, 'player', 0)
  local okM, mx = pcall(UnitPowerMax, 'player', 0)
  if okC and okM and cur ~= nil and mx ~= nil then
    pcall(f.mana.SetMinMaxValues, f.mana, 0, mx)
    pcall(f.mana.SetValue, f.mana, cur)
  end
  if not c.manaKnown then
    f.mana.text:SetText('mana ?')
    f.mana:SetStatusBarColor(0.45, 0.4, 0.7)
  else
    if c.manaExact then f.mana.text:SetText(('%d%%'):format(math.floor(c.mana * 100 + 0.5)))
    else f.mana.text:SetText(('%d-%d%%'):format(c.manaLo or 0, c.manaHi or 100)) end
    if c.mana < db.wandMana + 0.07 then f.mana:SetStatusBarColor(0.85, 0.25, 0.3)
    elseif c.mana < db.conserveMana then f.mana:SetStatusBarColor(0.55, 0.35, 0.95)
    else f.mana:SetStatusBarColor(0.2, 0.5, 1) end
  end

  local main = plan[1]
  local waitLeft = main and (main.wait or 0) or 0
  fill(f.main, main, 'main', waitLeft)
  fill(f.n1, plan[2], 'next')
  fill(f.n2, plan[3], 'next')
  fill(f.util, util, 'util')
  UI.slotAct.main, UI.slotAct.n1, UI.slotAct.n2, UI.slotAct.util = main, plan[2], plan[3], util
  if not c.inCombat or db.clickTest then
    UI.setClick('main', main)
    UI.setClick('n1', plan[2])
    UI.setClick('n2', plan[3])
    UI.setClick('util', util)
    if UI.clickName then f.main.label:SetText('|cff88ccffKLIK|r') end
  end
  f.arrow:SetShown(plan[2] ~= nil)

  -- zvuk: jen kdyz se nalehave doporuceni objevi (ne porad dokola)
  local urgentNow = (main and main.urgent and main.name) or (util and util.urgent and util.name) or nil
  if urgentNow and urgentNow ~= UI.lastUrgent and db.sound and GetTime() - (UI.lastSound or 0) > 3 then
    UI.lastSound = GetTime()
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, 'Master')
  end
  UI.lastUrgent = urgentNow
  -- pulzovani pri nalehave akci
  if main and main.urgent then
    f.pulse = f.pulse + 0.35
    local a = 0.55 + 0.45 * math.abs(math.sin(f.pulse))
    f.main:SetAlpha(a)
    if f.main.glow then f.main.glow:SetAlpha(a) end
  end

  local txt = ''
  if db.showReason then
    if main then
      txt = '|cffffffff' .. (main.reason or main.name) .. '|r'
      if util and util.urgent then txt = '|cffff5555' .. util.reason .. '|r\n' .. txt end
    elseif not c.inCombat then txt = '|cff88ee99Vse pripraveno|r' end
  end
  -- kompaktni rezim: jen ikony (duvod je v tooltipu hlavni ikony)
  UI.lastReason = main and (main.reason or main.name) or nil
  if db.compact then txt = '' end
  -- pred pullem: jeden radek pod hlavni radou = hodnoceni pullu (jen kdyz je co rict) + ready check
  -- (kompaktne vpravo od ikon)
  local sideTxt = ''
  if not c.inCombat and c.hostile then
    local extra = {}
    if ns.Tactics and ns.Tactics.pullText then
      local okP, ptxt = pcall(ns.Tactics.pullText, c)
      if okP and ptxt then extra[#extra + 1] = ptxt end
    end
    if ns.Duo and ns.Duo.ready then
      local rdy, rtxt = ns.Duo.ready(c, db.compact)
      if rtxt then extra[#extra + 1] = rtxt end
    end
    if #extra > 0 and db.compact then
      sideTxt = table.concat(extra, '\n')
    elseif #extra > 0 then
      local e = table.concat(extra, '   ')
      txt = (txt ~= '' and (txt .. '\n' .. e)) or e
    end
  end
  f.side:SetText(sideTxt)
  f.reason:SetText(txt)
  local info = (db.showInfo and not db.compact) and infoLines(c) or ''
  f.info:SetText(info)

  -- vyska podle obsahu
  local h = PAD + MAIN
  if txt ~= '' or info ~= '' then h = h + 6 + 1 end
  if txt ~= '' then h = h + 6 + f.reason:GetStringHeight() end
  if info ~= '' then h = h + 5 + f.info:GetStringHeight() end
  h = h + PAD
  if math.abs((f.lastH or 0) - h) > 0.5 then f:SetHeight(h) f.lastH = h end
  f.sep:SetShown(txt ~= '' or info ~= '')

  -- viditelnost: v boji/s cilem plne, jinak tlumene (zamcene a necinne = skryte)
  local active = c.inCombat or c.hostile or main ~= nil or util ~= nil
  local idleA = (db.locked or db.hideIdle) and 0 or 0.5
  -- schovane okno jde najet mysi (at jde posunout / otevrit)
  if idleA == 0 and not db.locked and f:IsMouseOver() then idleA = 0.5 end
  f:SetAlpha(active and 1 or idleA)
end

------------------------------------------------------------------------------------------
-- Shrnuti po boji (na strane, mysi "pruhledne", samo zmizi; v boji se hned schova)
------------------------------------------------------------------------------------------
local SUM_W, SP, TG = 248, 8, 4
local TILE_W = (SUM_W - SP * 2 - TG * 3) / 4
local function gradeColor(v)
  if not v then return 0.6, 0.65, 0.75 end
  if v >= 0.75 then return 0.35, 0.95, 0.5 end
  if v >= 0.5 then return 1, 0.82, 0.25 end
  return 1, 0.42, 0.38
end
local function makeTile(parent, title)
  local t = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
  t:SetSize(TILE_W, 34)
  t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  t:SetBackdropColor(0.09, 0.11, 0.16, 0.85)
  t:SetBackdropBorderColor(0.18, 0.23, 0.32, 0.9)
  t.val = t:CreateFontString(nil, 'OVERLAY')
  t.val:SetFont(FONT, 13, 'OUTLINE')
  t.val:SetPoint('TOP', 0, -4)
  t.lab = t:CreateFontString(nil, 'OVERLAY')
  t.lab:SetFont(FONT, 8, 'OUTLINE')
  t.lab:SetPoint('BOTTOM', 0, 4)
  t.lab:SetTextColor(0.55, 0.62, 0.72)
  t.lab:SetText(title)
  return t
end

local function buildSummary()
  if UI.sum then return UI.sum end
  local s = CreateFrame('Frame', 'ClaudeMasterSummary', UIParent, 'BackdropTemplate')
  UI.sum = s
  s:SetSize(SUM_W, 80)
  s:EnableMouse(false)
  s:SetFrameStrata('LOW')
  s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  s:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.86)
  s:SetBackdropBorderColor(unpack(T.border))
  -- mrazivy prouzek nahore (stejne jako hlavni panel)
  s.accent = s:CreateTexture(nil, 'BORDER')
  s.accent:SetTexture(WHITE)
  s.accent:SetPoint('TOPLEFT', 1, -1) s.accent:SetPoint('TOPRIGHT', -1, -1) s.accent:SetHeight(2)
  if s.accent.SetGradient and CreateColor then
    s.accent:SetGradient('HORIZONTAL', CreateColor(unpack(T.a1)), CreateColor(unpack(T.a2)))
  else s.accent:SetVertexColor(T.a1[1], T.a1[2], T.a1[3], 0.8) end
  -- hlavicka
  s.icon = s:CreateTexture(nil, 'ARTWORK')
  s.icon:SetSize(16, 16) s.icon:SetPoint('TOPLEFT', SP, -SP)
  s.icon:SetTexture(T.icon)
  s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  s.title = s:CreateFontString(nil, 'OVERLAY')
  s.title:SetFont(FONT, 12, 'OUTLINE')
  s.title:SetPoint('LEFT', s.icon, 'RIGHT', 6, 0)
  s.title:SetTextColor(unpack(T.title))
  s.title:SetText('Po boji')
  s.sub = s:CreateFontString(nil, 'OVERLAY')
  s.sub:SetFont(FONT, 10, 'OUTLINE')
  s.sub:SetPoint('RIGHT', s, 'TOPRIGHT', -SP, -SP - 8)
  s.sub:SetTextColor(0.7, 0.76, 0.86)
  -- dlazdice
  s.tiles = {}
  for i, title in ipairs({ 'KOUZLA', 'SHODA', 'MANA', 'NECINNOST' }) do
    local t = makeTile(s, title)
    t:SetPoint('TOPLEFT', s, 'TOPLEFT', SP + (i - 1) * (TILE_W + TG), -(SP + 16 + 7))
    s.tiles[i] = t
  end
  -- prouzek shody s doporucenim
  s.barBg = s:CreateTexture(nil, 'ARTWORK')
  s.barBg:SetTexture(WHITE) s.barBg:SetVertexColor(0.12, 0.14, 0.2, 1)
  s.barBg:SetPoint('TOPLEFT', s.tiles[1], 'BOTTOMLEFT', 0, -5)
  s.barBg:SetSize(SUM_W - SP * 2, 3)
  s.bar = s:CreateTexture(nil, 'OVERLAY')
  s.bar:SetTexture(WHITE)
  s.bar:SetPoint('TOPLEFT', s.barBg, 'TOPLEFT', 0, 0)
  s.bar:SetHeight(3)
  -- tipy
  s.sep = s:CreateTexture(nil, 'ARTWORK')
  s.sep:SetTexture(WHITE) s.sep:SetVertexColor(0.3, 0.38, 0.5, 0.4)
  s.sep:SetPoint('TOPLEFT', s.barBg, 'BOTTOMLEFT', 0, -7)
  s.sep:SetSize(SUM_W - SP * 2, 1)
  s.tips = s:CreateFontString(nil, 'OVERLAY')
  s.tips:SetFont(FONT, 10, 'OUTLINE')
  s.tips:SetPoint('TOPLEFT', s.sep, 'BOTTOMLEFT', 0, -6)
  s.tips:SetWidth(SUM_W - SP * 2) s.tips:SetJustifyH('LEFT') s.tips:SetWordWrap(true) s.tips:SetSpacing(3)
  s.tips:SetTextColor(0.8, 0.85, 0.93)
  s:Hide()
  s:SetScript('OnUpdate', function(self, el)
    self.left = (self.left or 0) - el
    if self.left <= 0 then self:Hide() return end
    self:SetAlpha(math.min(1, self.left / 3, (25 - self.left) * 2))
  end)
  return s
end

function UI.showSummary(r)
  local f = UI.frame
  if not f or not r then return end
  local s = buildSummary()
  s:ClearAllPoints()
  -- vedle panelu: vpravo, kdyz je misto, jinak vlevo
  local right = (f:GetRight() or 0) * f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  if right + SUM_W + 10 < UIParent:GetWidth() then s:SetPoint('TOPLEFT', f, 'TOPRIGHT', 6, 0)
  else s:SetPoint('TOPRIGHT', f, 'TOPLEFT', -6, 0) end
  s:SetScale(f:GetScale())

  local sub = ('|cffffffff%d s|r'):format(math.floor(r.dur + 0.5))
  if r.kills > 0 then sub = sub .. ('   |cff9aa6b8zabito|r |cffffffff%d|r'):format(r.kills) end
  s.sub:SetText(sub)

  local gr, gg, gb = gradeColor(r.follow)
  local idleBad = r.idle > math.max(3, r.dur * 0.12)
  local vals = {
    { tostring(r.casts), 1, 1, 1 },
    { r.follow and (math.floor(r.follow * 100 + 0.5) .. '%') or '-', gr, gg, gb },
    { ('%d%%'):format(math.floor(r.mana * 100 + 0.5)), 0.45, 0.7, 1 },
    { ('%.0f s'):format(r.idle), idleBad and 1 or 0.85, idleBad and 0.45 or 0.9, idleBad and 0.4 or 0.95 },
  }
  for i, v in ipairs(vals) do
    s.tiles[i].val:SetText(v[1])
    s.tiles[i].val:SetTextColor(v[2], v[3], v[4])
  end
  local w = (SUM_W - SP * 2) * math.max(0.02, math.min(1, r.follow or 0))
  s.bar:SetWidth(w)
  s.bar:SetVertexColor(gr, gg, gb, 0.9)
  s.bar:SetShown(r.follow ~= nil)

  local l = {}
  for i = 1, math.min(4, #r.tips) do l[#l + 1] = '|cff66b8ff\226\128\162|r ' .. r.tips[i] end
  if #l == 0 and r.follow and r.follow >= 0.75 and not idleBad then l[1] = '|cff66ee77\226\128\162|r Pekne odehrano' end
  s.tips:SetText(table.concat(l, '\n'))
  local hasTips = #l > 0
  s.sep:SetShown(hasTips) s.tips:SetShown(hasTips)
  local h = SP + 16 + 7 + 34 + 5 + 3 + SP
  if hasTips then h = h + 7 + 1 + 6 + s.tips:GetStringHeight() end
  s:SetHeight(h)
  s.left = 25
  s:SetAlpha(0)
  s:Show()
end
function UI.hideSummary() if UI.sum then UI.sum:Hide() end end

------------------------------------------------------------------------------------------
-- Makra: utok, ktery sam vybere dalsiho nepritele, a (warlock) vsechny DoTy na jedno tlacitko.
-- Addon za tebe cil menit nesmi (hra to dovoli jen po zmacknuti klavesy), makro ano.
------------------------------------------------------------------------------------------
local function makeMacro(name, body)
  local idx = safeNum(pc(GetMacroIndexByName, name)) or 0
  if idx > 0 then
    local ok = pcall(EditMacro, idx, name, 'INV_MISC_QUESTIONMARK', body)
    return ok and 'upraveno' or 'nepovedlo se upravit'
  end
  local _, nChar = pc(GetNumMacros)
  if (safeNum(nChar) or 0) >= (MAX_CHARACTER_MACROS or 18) then return 'neni misto (smaz nejake makro postavy)' end
  local ok = pcall(CreateMacro, name, 'INV_MISC_QUESTIONMARK', body, true)
  return ok and 'vytvoreno' or 'nepovedlo se vytvorit'
end

function UI.makeMacros()
  if InCombatLockdown() then ns.say('makra az po boji') return end
  local TGT = '/targetenemy [noharm][dead]\n'
  local list = {}
  local attacks = ns.class == 'WARLOCK' and { 'Shadow Bolt', 'Searing Pain' }
    or ns.class == 'PALADIN' and { 'Judgement', 'Crusader Strike', 'Holy Strike', 'Exorcism' }
    or ns.class == 'DRUID' and { 'Wrath', 'Moonfire', 'Starfire', 'Maul', 'Claw' }
    or { 'Frostbolt', 'Ice Lance', 'Fire Blast' }
  local start = ns.class == 'PALADIN' and '/startattack\n' or ''   -- melee: zaroven zapne auto attack
  for _, sp in ipairs(attacks) do
    if ns.known(sp) then list[#list + 1] = { 'CM ' .. sp, '#showtooltip\n' .. TGT .. start .. '/cast ' .. sp } end
  end
  -- ovce na focus: prvni zmacknuti si moba "zapamatuje" (focus), dalsi ho ovci znovu i kdyz mas jiny cil
  if ns.known('Polymorph') then
    list[#list + 1] = { 'CM Ovce', '#showtooltip Polymorph\n/focus [mod:shift][@focus,noexists][@focus,dead][@focus,noharm]\n/cast [@focus,harm,nodead] Polymorph; Polymorph' }
  end
  -- znacky: na moba pod mysi, jinak na cil (makro je secure, funguje i v boji)
  list[#list + 1] = { 'CM Lebka', '/tm [@mouseover,harm,nodead][] 8' }
  list[#list + 1] = { 'CM Mesic', '/tm [@mouseover,harm,nodead][] 5' }
  if ns.class == 'WARLOCK' and ns.Warlock then
    local seq = {}
    local curse = ns.Warlock.macroCurse()
    if curse then seq[#seq + 1] = curse end
    for _, sp in ipairs({ 'Immolate', 'Bane of Agony', 'Corruption', 'Siphon Life' }) do if ns.known(sp) then seq[#seq + 1] = sp end end
    if #seq >= 2 then
      list[#list + 1] = { 'CM DoTy', '#showtooltip\n' .. TGT .. '/castsequence reset=target/combat ' .. table.concat(seq, ', ') }
    end
  end
  for _, m in ipairs(list) do ns.say(('Makro |cffffffff%s|r: %s'):format(m[1], makeMacro(m[1], m[2]))) end
  ns.say('Otevri /macro (zalozka postavy) a pretahni makra na listu misto puvodnich kouzel.')
  ns.say('Utok bez cile / na mrtvolu sam vybere dalsiho nepritele.')
  if ns.class == 'WARLOCK' then ns.say('CM DoTy: kazde zmacknuti posle dalsi DoT (curse, Immolate, ...), na novem cili zacne znovu.') end
  if ns.known('Polymorph') then ns.say('CM Ovce: ovci cil a zapamatuje si ho (focus); dalsi zmacknuti ho prodlouzi i s jinym cilem. Shift = novy focus.') end
  ns.say('CM Lebka / CM Mesic: znacka na moba pod mysi (nebo cil) - v dungeonu jen podle znacek vidi partak stejne moby.')
end

------------------------------------------------------------------------------------------
-- Prikazy
------------------------------------------------------------------------------------------
local function status()
  local known = {}
  for _, n in ipairs(ns.SPELLS) do if ns.known(n) then known[#known + 1] = n end end
  ns.say('Znam kouzla: ' .. table.concat(known, ', '))
  local nb = 0 for _ in pairs(ns.binds) do nb = nb + 1 end
  local m, exact, lo, hi = ns.mana()
  local mtxt = exact and ('primo %d%%'):format(math.floor(m * 100)) or (m and ('sonda %d-%d%% (rezim %s)'):format(lo, hi, tostring(ns.manaProbe.mode)) or 'NEZNAMA')
  ns.say(('Zkratky: %d | mana: %s | UnitPower citelny: %s, UnitPowerMax: %s')
    :format(nb, mtxt, tostring(safeNum(pc(UnitPower, 'player', 0)) ~= nil), tostring(safeNum(pc(UnitPowerMax, 'player', 0)))))
  ns.say(('Sondy funguji: mana %s, HP cil %s, HP hrac %s, meritko %s | hpScale: %s | Cooldown Manager: %s')
    :format(tostring(ns.manaProbe.ok), tostring(ns.targetProbe.ok), tostring(ns.playerProbe.ok), tostring(ns.scaleProbe.ok),
      tostring(ns.db.hpScale), C_CooldownViewer and 'ano' or 'ne'))
  local php, pex = ns.healthPct('player')
  ns.say(('Tvoje HP: %s'):format(php and ((pex and 'primo ' or 'pasmo ~') .. math.floor(php) .. '%') or 'NEZNAME'))
  local uh, uhp = pc(UnitHealth, 'player'), pc(UnitHealthPercent, 'player')
  ns.say(('UnitHealth: %s | UnitHealthPercent: %s'):format(ns.issecret(uh) and 'skryte' or tostring(uh),
    ns.issecret(uhp) and 'skryte' or tostring(uhp)))
  local learned = {}
  for k, v in pairs(ns.db.cdLearned) do learned[#learned + 1] = k .. '=' .. v end
  ns.say('Naucene cooldowny: ' .. table.concat(learned, ', '))
end

local HELP = {
  '/cm - zobrazit/skryt',
  '/cm lock | unlock - zamknout/odemknout (tahnout mysi)',
  '/cm scale 1.2 - velikost',
  '/cm aoe 3 - od kolika mobu doporucovat AoE',
  '/cm drink 55 - pit mimo boj pod X % many',
  '/cm gem 70 - mana gem v boji pod X % many',
  '/cm wand 8 - wand pod X % many',
  '/cm barrier - zap/vyp Ice Barrier pred pullem',
  '/cm reason | info - zap/vyp texty',
  '/cm compact - jen ikony bez textu (duvod v tooltipu)',
  '/cm talents - co addon vycetl z talentu',
  '/cm dump - ulozi talenty, spelly, itemy a staty do souboru (po /reload)',
  '/cm sdilej - sdilet partakum questy, ktere nemaji (vidi to jejich addon)',
  '/cm gear [spec] - lepsi gear z batohu (vahy: frost/arcane/destro/ret/prot/holy/resto/balance/feral), /cm vahy str=1 ... vlastni',
  '/cm macro - vytvori makra: utok sam vybere dalsiho nepritele' .. (ns.class == 'WARLOCK' and ', DoTy na jedno tlacitko' or ''),
  '/cm status - co addon zjistil (pro ladeni)',
  '/cm rescan - znovu nacist kouzla a zkratky',
  '/cm bags - co addon poznal v inventari',
  '/cm spells - vypis celeho spellbooku (co addon zna a co ne)',
  '/cm items - nerozpoznane pouzitelne veci (pro ladeni)',
  '/cm immune - naucene imunity mobu (/cm immune reset = smazat vse)',
  '/cm immune frost/fire/arcane/nova/poly - oznacit cil jako imunni',
  '/cm config - okno s nastavenim',
  '/cm summary - ukazat posledni shrnuti boje',
  '/cm duo - stav vymeny dat s partakem (mag + warlock)',
  '/cm zmeny - co hra zmenila na kouzlech (patch) od minule',
  '/cm questy [zona|razeni|info] - questy pod minimapou: jen z aktualni oblasti, razeni podle vzdalenosti',
  '/cm bug [poznamka] - ulozit poslednich 30 s (co addon videl a radil), po /reload poslat',
  '/cm learn - co se addon naucil z tveho hrani (reset = zapomenout, off/on)',
  '/cm mobs reset - smazat pamet mobu',
  '/cm sound - zap/vyp zvuk u nalehavych veci',
  '/cm reset - vratit pozici',
}
if ns.class == 'WARLOCK' then
  table.insert(HELP, '/cm pet auto/imp/voidwalker/succubus/felhunter - ktery pet')
  table.insert(HELP, '/cm curse auto|agony|elements|shadow|weakness|tongues|doom - ktera curse')
  table.insert(HELP, '/cm talents - prectene talenty a proc je filler takovy')
  table.insert(HELP, '/cm filler auto/shadowbolt/searing - hlavni kouzlo')
end

SLASH_CLAUDEMASTER1 = '/cm'
SLASH_CLAUDEMASTER2 = '/claudemaster'
SlashCmdList.CLAUDEMASTER = function(msg)
  local db = ns.db
  if not db then return end
  local cmd, arg = (msg or ''):lower():match('^%s*(%S*)%s*(.-)%s*$')
  local num = tonumber(arg)
  if cmd == '' then
    db.shown = not db.shown
    if UI.frame and not InCombatLockdown() then UI.frame:SetShown(db.shown) UI.reanchor() end
    ns.say(db.shown and 'zobrazeno' or 'skryto (/cm pro zobrazeni)')
  elseif cmd == 'lock' or cmd == 'unlock' then
    db.locked = cmd == 'lock'
    if UI.frame then UI.frame:EnableMouse(not db.locked) end
    ns.say(db.locked and 'zamceno' or 'odemceno - tahni levym tlacitkem')
  elseif cmd == 'scale' and num then
    db.scale = math.max(0.5, math.min(3, num))
    if UI.frame and not InCombatLockdown() then UI.frame:SetScale(db.scale) UI.reanchor() end
  elseif cmd == 'aoe' and num then db.aoe = math.max(2, math.floor(num)) ns.say('AoE od ' .. db.aoe .. ' mobu')
  elseif cmd == 'drink' and num then db.drinkMana = num / 100 ns.say('pit pod ' .. num .. ' %')
  elseif cmd == 'gem' and num then db.gemMana = num / 100 ns.say('gem pod ' .. num .. ' %')
  elseif cmd == 'wand' and num then db.wandMana = num / 100 ns.say('wand pod ' .. num .. ' %')
  elseif cmd == 'barrier' then db.prebarrier = not db.prebarrier ns.say('Ice Barrier pred pullem: ' .. (db.prebarrier and 'zap' or 'vyp'))
  elseif cmd == 'macro' or cmd == 'makra' or cmd == 'makro' then UI.makeMacros()
  elseif cmd == 'compact' then db.compact = not db.compact ns.say('kompaktni: ' .. (db.compact and 'zap' or 'vyp') .. (ns.class == 'WARLOCK' and ' (velikost okna se zmeni po /reload)' or ''))
  elseif cmd == 'reason' then db.showReason = not db.showReason
  elseif cmd == 'info' then db.showInfo = not db.showInfo
  elseif cmd == 'debug' then db.debug = not db.debug ns.say('debug: ' .. tostring(db.debug))
  elseif cmd == 'status' then status()
  elseif cmd == 'config' or cmd == 'options' or cmd == 'nastaveni' then
    if ns.Options then ns.Options.toggle() end
  elseif cmd == 'sonda' or cmd == 'probe' then
    if ns.apiProbe then ns.apiProbe() end
  elseif cmd == 'test' then
    if ns.Plates and ns.Plates.test then ns.Plates.test() end
  elseif cmd == 'questy' or cmd == 'quests' then
    if ns.Quests then ns.Quests.toggle(arg) end
  elseif cmd == 'duo' then
    if ns.Duo then ns.Duo.status() end
  elseif cmd == 'sdilej' or cmd == 'share' then
    if ns.Quests and ns.Quests.shareAll then ns.Quests.shareAll() end
  elseif cmd == 'zmeny' or cmd == 'patch' then
    if arg == 'reset' then ns.db.patchLog = {} ns.say('zaznam zmen smazan') else ns.showPatchLog() end
  elseif cmd == 'klikboj' or cmd == 'clicktest' then
    -- pokus: zkusit menit klikaci tlacitka i v boji (hra by to mela blokovat)
    if InCombatLockdown() then ns.say('prepnout az po boji') return end
    db.clickTest = not db.clickTest
    for _, b in pairs(UI.clicks or {}) do
      if db.clickTest then UnregisterStateDriver(b, 'cmcombat')
      else RegisterStateDriver(b, 'cmcombat', '[combat] in; out') end
    end
    ns.say('test klikani v boji: ' .. (db.clickTest and 'ZAP - jdi do boje, addon napise vysledek' or 'vyp'))
  elseif cmd == 'bug' then
    if ns.Bug then ns.Bug.save(arg) end
  elseif cmd == 'summary' then
    if db.lastFight then UI.showSummary(db.lastFight) else ns.say('zatim zadny boj') end
  elseif cmd == 'learn' then
    if arg == 'reset' then db.learnData = {} ns.say('uceni smazano')
    elseif arg == 'off' or arg == 'on' then db.learn = arg == 'on' ns.say('uceni: ' .. arg)
    else ns.Mem.report() end
  elseif cmd == 'mobs' and arg == 'reset' then
    db.mobs, db.memGlobal = {}, nil ns.say('pamet mobu smazana')
  elseif cmd == 'pet' and ns.class == 'WARLOCK' then
    local map = { imp = 'Imp', voidwalker = 'Voidwalker', vw = 'Voidwalker', succubus = 'Succubus', felhunter = 'Felhunter', auto = 'auto' }
    db.lockPet = map[arg] or 'auto' ns.say('pet: ' .. db.lockPet)
  elseif cmd == 'talents' or cmd == 'talenty' then
    if ns.class == 'WARLOCK' and ns.Warlock then pcall(ns.Warlock.refresh) ns.Warlock.report()
    else
      pcall(ns.scanTalents) ns.talentReport()
      if ns.talentsRead then
        local function on(n) return (ns.talent(n) or 0) > 0 and '|cff66ee77ano|r' or '|cffff7070ne|r' end
        ns.say(('Vyuziva: Fingers of Frost %s, Frostbite %s, Improved Blizzard %s, Missile Barrage %s, Ice Barrier %s%s')
          :format(on('Fingers of Frost'), on('Frostbite'), on('Improved Blizzard'), on('Missile Barrage'), on('Ice Barrier'),
            ns.barrierBuff and ' (+mrazivy dmg - drzi ho porad)' or ''))
      end
    end
  elseif cmd == 'filler' and ns.class == 'WARLOCK' then
    local map = { shadowbolt = 'Shadow Bolt', sb = 'Shadow Bolt', searing = 'Searing Pain', sp = 'Searing Pain',
      incinerate = 'Incinerate', auto = 'auto' }
    db.lockFiller = map[arg] or 'auto' ns.say('filler: ' .. db.lockFiller)
  elseif cmd == 'curse' and ns.class == 'WARLOCK' then
    local map = { agony = ns.known('Bane of Agony') and 'Bane of Agony' or 'Curse of Agony', elements = 'Curse of the Elements',
      exhaustion = 'Curse of Exhaustion', none = 'none', shadow = 'Curse of Shadow',
      weakness = 'Curse of Weakness', tongues = 'Curse of Tongues', recklessness = 'Curse of Recklessness', doom = 'Curse of Doom', auto = 'auto' }
    db.lockCurse = map[arg] or 'auto' ns.say('curse: ' .. db.lockCurse)
  elseif cmd == 'seal' and ns.class == 'PALADIN' then
    local map = { crusader = 'Seal of the Crusader', righteousness = 'Seal of Righteousness', wisdom = 'Seal of Wisdom',
      command = 'Seal of Command', light = 'Seal of Light', justice = 'Seal of Justice', auto = 'auto' }
    db.palSeal = map[arg] or 'auto'
    ns.say('seal: ' .. db.palSeal .. '   (/cm seal auto/righteousness/crusader/wisdom/command/light)')
  elseif cmd == 'druid' and ns.class == 'DRUID' then
    db.druidSpec = (arg == 'resto' or arg == 'balance' or arg == 'feral') and arg or nil
    ns.say('druid: ' .. (db.druidSpec or ('auto (podle talentu: ' .. tostring(ns.Druid and ns.Druid.spec() or 'zatim nic') .. ')'))
      .. '   (/cm druid resto/balance/feral/auto)')
  elseif cmd == 'gear' and ns.Gear then ns.Gear.setSpec(arg)
  elseif cmd == 'vahy' and ns.Gear then ns.Gear.setWeights(arg)
  elseif cmd == 'sound' then db.sound = not db.sound ns.say('zvuk: ' .. (db.sound and 'zap' or 'vyp'))
  elseif cmd == 'dump' then
    ns.fullDump()
  elseif cmd == 'spells' then
    ns.dumpSpells()
  elseif cmd == 'blocked' then
    local l = db.blocked or {}
    if #l == 0 then ns.say('zadne zablokovane akce') end
    for _, line in ipairs(l) do ns.say(line) end
  elseif cmd == 'immune' then
    if arg == 'reset' then db.immune = {} ns.say('naucene imunity smazany') return end
    -- rucni oznaceni aktualniho cile
    local MANUAL = { frost = { nil, 'frost' }, mraz = { nil, 'frost' }, fire = { nil, 'fire' }, ohen = { nil, 'fire' },
      arcane = { nil, 'arcane' }, shadow = { nil, 'shadow' }, stin = { nil, 'shadow' }, nova = { 'Frost Nova' }, root = { 'Frost Nova' }, poly = { 'Polymorph' },
      polymorph = { 'Polymorph' } }
    if MANUAL[arg] then
      ns.Immune.refreshTarget()
      local mob = ns.Immune.tname
      if not mob then ns.say('nejdriv si vyber cil') return end
      local m = MANUAL[arg]
      if m[2] then
        ns.db.immune = ns.db.immune or {}
        local e = ns.db.immune[mob] or { schools = {}, spells = {} }
        ns.db.immune[mob] = e
        e.schools[m[2]] = true
        ns.say(('%s: oznaceno jako imunni na %s'):format(mob, ns.Immune.SCHOOL_CZ[m[2]]))
      else
        ns.Immune.learn(mob, m[1], nil, 'rucne')
      end
      return
    end
    if arg == 'clear' then
      ns.Immune.refreshTarget()
      if ns.Immune.tname and db.immune then db.immune[ns.Immune.tname] = nil ns.say(ns.Immune.tname .. ': imunity smazany') end
      return
    end
    local n = 0
    for mob, e in pairs(db.immune or {}) do
      local parts = {}
      for sc in pairs(e.schools) do parts[#parts + 1] = ns.Immune.SCHOOL_CZ[sc] or sc end
      for sp in pairs(e.spells) do parts[#parts + 1] = sp end
      ns.say(mob .. ': ' .. table.concat(parts, ', '))
      n = n + 1
    end
    if n == 0 then ns.say('zatim zadne naucene imunity') end
    local st = ns.Immune.stat
    ns.say(('Detekce: combat log %s - zprav %d (skrytych %d) | portret cile - zprav %d (skrytych %d)'):format(
      ns.Immune.cleuOK and 'registrovan' or 'vypnuty (Forever ho zakazuje)', st.cleu, st.cleuSecret, st.uc, st.ucSecret))
    ns.say('Rucne na cil: /cm immune frost | fire | arcane | nova | poly   (/cm immune clear = smazat u cile)')
  elseif cmd == 'items' then
    ns.Bags.scan()
    local list = ns.Bags.list('other')
    ns.say(('Nerozpoznane veci s efektem "Use:" (%d):'):format(#list))
    for _, it in ipairs(list) do
      ns.say(('%s x%d  ->  %s'):format(it.name, it.count, tostring(it.spell)))
    end
  elseif cmd == 'bags' then
    ns.Bags.scan()
    local LABELS = { water = 'Piti', food = 'Jidlo', gem = 'Mana gem', hpot = 'Healing pot', mpot = 'Mana pot',
      stone = 'Healthstone', scroll = 'Scrolly', elixir = 'Elixiry', bandage = 'Obvazy', imbue = 'Imbue zbrane',
      nuke = 'Utocne scrolly', antiElem = 'Proti elementalum', defense = 'Obrana', buffFood = 'Jidlo s buffem' }
    for _, k in ipairs({ 'water', 'food', 'buffFood', 'gem', 'hpot', 'mpot', 'stone', 'defense', 'scroll', 'imbue',
      'nuke', 'antiElem', 'elixir', 'bandage' }) do
      local names = {}
      for _, it in ipairs(ns.Bags.list(k)) do names[#names + 1] = it.name .. ' x' .. it.count end
      ns.say(LABELS[k] .. ': ' .. (#names > 0 and table.concat(names, ', ') or '-'))
    end
  elseif cmd == 'rescan' then
    if ns.inCombat() then ns.say('az po boji') else ns.scanSpells() ns.say('nacteno') end
  elseif cmd == 'reset' then
    db.point = { 'CENTER', 'CENTER', 0, -190 }
    if UI.frame and not InCombatLockdown() then
      UI.frame:ClearAllPoints() UI.frame:SetPoint('CENTER', UIParent, 'CENTER', 0, -190) UI.reanchor()
    end
  else
    for _, l in ipairs(HELP) do ns.say(l) end
  end
end

-- ClaudeMaster: pomucky, ktere hra dovoli jen "bezpecne" (secure) nebo mimo sdileni dat
--  1) lista se znackami (lebka / mesic / smazat) - klik = znacka na cil; v dungeonu jedina sdilena identita moba
--  2) boss encounter: hra blokuje zpravy mezi addony -> smazat sdilena data, at nematou
--  3) tooltip nepritele: co si addon o mobovi pamatuje (kouzli cim, utika, preruseni nefunguje...)
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local AS = {}
ns.Assist = AS

------------------------------------------------------------------------------------------
-- 1) Lista se znackami
------------------------------------------------------------------------------------------
-- /tm = /targetmarker; makro je secure, takze funguje i v boji (addon sam SetRaidTarget nesmi)
local MARKS = {
  { key = 'Skull', idx = 8, icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8', tip = 'Lebka: tohohle bijeme prvni' },
  { key = 'Moon', idx = 5, icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_5', tip = 'Mesic: ovce (Polymorph)' },
  { key = 'Clear', idx = 0, icon = 'Interface\\Buttons\\UI-GroupLoot-Pass-Up', tip = 'Smazat znacku z cile' },
}
local SIZE = 20

local function savePos(f)
  local p, _, rp, x, y = f:GetPoint(1)
  ns.db.markPos = { p, rp, x, y }
end

function AS.buildBar()
  if AS.bar or InCombatLockdown() then return end
  local bar = CreateFrame('Frame', 'ClaudeMasterMarks', UIParent)
  AS.bar = bar
  bar:SetSize(#MARKS * (SIZE + 2) + 2, SIZE + 4)
  bar:SetFrameStrata('MEDIUM')
  local pos = ns.db.markPos
  if pos then
    bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  elseif ns.UI and ns.UI.frame and ns.UI.frame:GetLeft() then
    bar:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', ns.UI.frame:GetLeft(), ns.UI.frame:GetBottom() - 4)
  else
    bar:SetPoint('CENTER', UIParent, 'CENTER', 0, -200)
  end
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  for i, m in ipairs(MARKS) do
    local b = CreateFrame('Button', 'ClaudeMasterMark' .. m.key, bar, 'SecureActionButtonTemplate')
    b:SetSize(SIZE, SIZE)
    b:SetPoint('LEFT', bar, 'LEFT', 2 + (i - 1) * (SIZE + 2), 0)
    b:RegisterForClicks('AnyUp')
    b:SetAttribute('useOnKeyDown', false)
    b:SetAttribute('type', 'macro')
    b:SetAttribute('macrotext', ('/tm %d'):format(m.idx))
    local t = b:CreateTexture(nil, 'ARTWORK')
    t:SetAllPoints()
    t:SetTexture(m.icon)
    b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square', 'ADD')
    b:SetScript('OnEnter', function(self)
      GameTooltip:SetOwner(self, 'ANCHOR_TOP')
      GameTooltip:AddLine(m.tip, 1, 1, 1)
      GameTooltip:AddLine('Klik = znacka na cil. Shift + tahni = presunout listu.', 0.7, 0.7, 0.7, true)
      GameTooltip:AddLine(('Klavesa: makro "/click ClaudeMasterMark%s"'):format(m.key), 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    -- presun: shift + tahni (jen mimo boj)
    b:RegisterForDrag('LeftButton')
    b:SetScript('OnDragStart', function()
      if IsShiftKeyDown() and not InCombatLockdown() then bar:StartMoving() end
    end)
    b:SetScript('OnDragStop', function()
      bar:StopMovingOrSizing()
      savePos(bar)
    end)
  end
  AS.applyVisibility()
end

-- viditelnost ridi hra sama (state driver funguje i v boji): jen ve skupine a kdyz je zapnuta
function AS.applyVisibility()
  if not AS.bar or InCombatLockdown() then return end
  if ns.db.markBar == false then
    UnregisterStateDriver(AS.bar, 'visibility')
    AS.bar:Hide()
  else
    RegisterStateDriver(AS.bar, 'visibility', '[group] show; hide')
  end
end

------------------------------------------------------------------------------------------
-- 2) Boss encounter: zpravy mezi addony nefunguji
------------------------------------------------------------------------------------------
local function wipeShared()
  local PL = ns.Plates
  if PL then
    wipe(PL.peerT) wipe(PL.peerA)
    for i = #PL.sheep, 1, -1 do if PL.sheep[i].from then table.remove(PL.sheep, i) end end
  end
  if ns.Duo then wipe(ns.Duo.claims or {}) ns.Duo.ccClaim = nil end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'ENCOUNTER_START', 'ENCOUNTER_END', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED' }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript('OnEvent', function(_, e)
  if e == 'ENCOUNTER_START' then
    if ns.Duo then ns.Duo.encounter = GetTime() end
    wipeShared()
  elseif e == 'ENCOUNTER_END' then
    if ns.Duo then ns.Duo.encounter = nil end
  elseif e == 'PLAYER_ENTERING_WORLD' then
    if ns.Duo then ns.Duo.encounter = nil end
    if C_Timer then C_Timer.After(1, function() pcall(AS.buildBar) end) else pcall(AS.buildBar) end
  elseif e == 'PLAYER_REGEN_ENABLED' then
    pcall(AS.buildBar)
    pcall(AS.applyVisibility)
  end
end)

------------------------------------------------------------------------------------------
-- 3) Tooltip nepritele: pamet addonu
------------------------------------------------------------------------------------------
local SCHOOL = { fire = 'ohnem', frost = 'mrazem', shadow = 'stinem' }
local function addMobLines(tt, unit)
  if ns.db.tipMob == false or type(unit) ~= 'string' then return end
  if safeBool(pc(UnitCanAttack, 'player', unit)) ~= true or safeBool(pc(UnitIsPlayer, unit)) == true then return end
  local name = safe(pc(UnitName, unit))
  if type(name) ~= 'string' then return end   -- v instanci muze byt jmeno skryte
  local lines = {}
  local m = ns.Mem and ns.Mem.info and ns.Mem.info(name, safe(pc(UnitCreatureType, unit)), IsInGroup and IsInGroup())
  if m then
    if m.caster then lines[#lines + 1] = 'kouzli' .. (SCHOOL[m.school] and (' ' .. SCHOOL[m.school]) or '') end
    if m.flees and not m.fleeGuess then lines[#lines + 1] = '|cffffcc00utika|r' end
    if m.nb and m.nb > 0 and m.ttd then lines[#lines + 1] = ('~%d s na zabiti'):format(math.floor(m.ttd + 0.5)) end
  end
  local casts = ns.db.mobCasts and ns.db.mobCasts[name]
  if casts then
    local heal, cc = {}, {}
    for sp, k in pairs(casts) do
      if k == 'heal' then heal[#heal + 1] = sp elseif k == 'CC' then cc[#cc + 1] = sp end
    end
    if #heal > 0 then lines[#lines + 1] = '|cff66ee77leci:|r ' .. table.concat(heal, ', ') end
    if #cc > 0 then lines[#lines + 1] = '|cffff7070CC:|r ' .. table.concat(cc, ', ') end
  end
  local nk = {}
  if casts and ns.db.noKick then
    for sp in pairs(casts) do if ns.db.noKick[sp] then nk[#nk + 1] = sp end end
  end
  if #nk > 0 then lines[#lines + 1] = '|cff999999nejde prerusit:|r ' .. table.concat(nk, ', ') end
  -- naucene imunity (jen to, co jsme sami zjistili)
  local e = ns.db.immune and ns.db.immune[name]
  if e and ns.Immune and ns.Immune.describe then
    local ok, im = pcall(ns.Immune.describe, { schools = e.schools or {}, spells = e.spells or {} })
    if ok and type(im) == 'table' and #im > 0 then lines[#lines + 1] = '|cffff7070imunni:|r ' .. table.concat(im, ', ') end
  end
  if #lines == 0 then return end
  tt:AddLine('|cff4fa3ffClaudeMaster:|r ' .. table.concat(lines, ', '), 0.85, 0.85, 0.85, true)
  tt:Show()
end

local function onTip(tt)
  if tt ~= GameTooltip then return end
  local ok, _, unit = pcall(tt.GetUnit, tt)
  if not ok then return end
  unit = safe(unit)
  if type(unit) ~= 'string' then
    if safeBool(pc(UnitExists, 'mouseover')) == true then unit = 'mouseover' else return end
  end
  pcall(addMobLines, tt, unit)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, onTip)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript('OnTooltipSetUnit') then
  GameTooltip:HookScript('OnTooltipSetUnit', onTip)
end

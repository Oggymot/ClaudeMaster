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
  if not ns.db.markBarOn then
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
local LBL = { 0.55, 0.62, 0.72 }   -- barva popisku vlevo
-- radky "popisek  hodnota" (vlastni pozorovani + databaze, bez duplicit)
local function addMobLines(tt, unit)
  if ns.db.tipMob == false or type(unit) ~= 'string' then return end
  if safeBool(pc(UnitCanAttack, 'player', unit)) ~= true or safeBool(pc(UnitIsPlayer, unit)) == true then return end
  local name = safe(pc(UnitName, unit))
  if type(name) ~= 'string' then return end   -- v instanci muze byt jmeno skryte
  local order, vals = {}, {}
  local function put(label, v)
    if not v or v == '' then return end
    if not vals[label] then vals[label] = {} order[#order + 1] = label end
    for _, x in ipairs(vals[label]) do if x == v then return end end
    vals[label][#vals[label] + 1] = v
  end
  local rec = ns.MobDB and ns.MobDB.forUnit(unit)
  local m = ns.Mem and ns.Mem.info and ns.Mem.info(name, safe(pc(UnitCreatureType, unit)), IsInGroup and IsInGroup())
  -- pozor: vlastnosti, na ktere se hodi myslet pred pullem
  if rec and (rec.rank == 1 or rec.rank == 2) then put('Pozor', '|cffffcc00elite|r') end
  if rec and rec.rank == 3 then put('Pozor', '|cffff5555boss|r') end
  if m and m.flees and not m.fleeGuess then put('Pozor', '|cffffcc00utika|r') end
  if rec and #rec.summon > 0 then put('Pozor', 'privolava pomoc') end
  if m and m.caster then put('Kouzli', SCHOOL[m.school] or 'ano') end
  -- leceni a CC (naucene + databaze)
  local casts = ns.db.mobCasts and ns.db.mobCasts[name]
  for sp, k in pairs(casts or {}) do
    if k == 'heal' then put('Leci', sp) elseif k == 'CC' then put('CC', sp) end
  end
  for _, sp in ipairs(rec and rec.heal or {}) do put('Leci', sp) end
  for _, sp in ipairs(rec and rec.cc or {}) do put('CC', sp) end
  for sp in pairs(casts or {}) do if ns.db.noKick and ns.db.noKick[sp] then put('Neprerusis', sp) end end
  -- imunity: naucene + databaze
  local e = ns.db.immune and ns.db.immune[name]
  if e and ns.Immune and ns.Immune.describe then
    local ok, im = pcall(ns.Immune.describe, { schools = e.schools or {}, spells = e.spells or {} })
    if ok and type(im) == 'table' then for _, x in ipairs(im) do put('Imunni', x) end end
  end
  if rec then
    local CZ = ns.MobDB.CZ
    for sc in pairs(rec.immSchool) do put('Imunni', CZ[sc]) end
    if rec.immPoly then put('Imunni', 'ovce') end
    if rec.immFear then put('Imunni', 'fear') end
    if rec.immRoot then put('Imunni', 'root') end
    if rec.immStun then put('Imunni', 'stun') end
    for sc in pairs(rec.res) do if not rec.immSchool[sc] then put('Odolny', CZ[sc]) end end
  end
  if m and m.nb and m.nb > 0 and m.ttd then put('Zabiti', ('~%d s'):format(math.floor(m.ttd + 0.5))) end
  local money = rec and rec.id and ns.MobDB.money and ns.MobDB.money(rec.id)
  if money and money.avg > 0 then
    put('Penize', ('~%s |cff888888(%s - %s)|r'):format(ns.MobDB.coin(money.avg), ns.MobDB.coin(money.min), ns.MobDB.coin(money.max)))
  end
  local lv = safeNum(pc(UnitLevel, unit))
  local drops, off = nil, nil
  if rec then drops, off = ns.MobDB.dropRows(rec, lv and lv > 0 and lv or nil) end
  if #order == 0 and not drops then return end
  local COL = { Pozor = 'ffffcc00', Leci = 'ff66ee77', CC = 'ffff7070', Imunni = 'ffff7070', Neprerusis = 'ff999999' }
  for _, label in ipairs(order) do
    local v = table.concat(vals[label], ', ')
    if COL[label] and not v:find('|c') then v = ('|c%s%s|r'):format(COL[label], v) end
    tt:AddDoubleLine(label, v, LBL[1], LBL[2], LBL[3], 1, 1, 1)
  end
  if drops then
    tt:AddLine(off and ('Drop |cff777777(%s lvl %d-%d)|r'):format(rec.fdb and 'databaze' or 'classic', rec.dlmin or rec.lmin, rec.dlmax or rec.lmax)
      or (rec.fdb and 'Drop |cff777777(ForeverDB)|r' or 'Drop'), LBL[1], LBL[2], LBL[3])
    for _, d in ipairs(drops) do tt:AddDoubleLine('  ' .. d[1], d[2], 1, 1, 1, 0.65, 0.65, 0.65) end
  end
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

-- ClaudeMaster: znacky u jmenovek nepratel (jmenovky samotne nemenime, jen k nim lepime vlastni ramecek)
-- Hra (Midnight/Forever) nedovoli porovnat "cil spoluhrace" se jmenovkou (slozene tokeny), proto:
--  * kazdy addon zna jen SVUJ cil (UnitIsUnit target vs jmenovka je povolene) a moby, ktere ho bijou (threat)
--  * posila je parťákovi jako identitu moba: GUID (venku), creature ID, raid znacka (v dungeonu je GUID skryte)
--  * parťák identitu porovna se svymi jmenovkami
-- Znacky: kdo moba bije (pismena), na koho utoci (>TY / >jmeno), CC ovce (i od parťáka, s odpoctem),
-- ramecek pri kouzle, ktere stoji za preruseni, a warlockovy DoTy.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local PL = { over = {}, peerT = {}, peerA = {}, sheep = {}, lastSend = 0, lastMsg = '' }
ns.Plates = PL
local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local CC_ICON = { Polymorph = 'Interface\\Icons\\Spell_Nature_Polymorph', Seduction = 'Interface\\Icons\\Spell_Shadow_MindSteal',
  Fear = 'Interface\\Icons\\Spell_Shadow_Possession', Banish = 'Interface\\Icons\\Spell_Shadow_Cripple' }

local function classHex(u)
  local _, cls = UnitClass(u)
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if not c then return 'ffffffff' end
  return ('ff%02x%02x%02x'):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end
local function is(a, b) return safeBool(pc(UnitIsUnit, a, b)) == true end
local function plateUnit(pl) return pl.namePlateUnitToken or (pl.UnitFrame and pl.UnitFrame.unit) end
-- jmenovky drzime podle udalosti hry (objevi se / zmizi), ne prohledavanim vsech ramcu
PL.units = {}
PL.combatOf = {}
local function getPlates()
  local out = {}
  if not PL.seeded then
    -- jmenovky, ktere uz byly videt pred nactenim addonu (/reload)
    PL.seeded = true
    local p = C_NamePlate and C_NamePlate.GetNamePlates and pc(C_NamePlate.GetNamePlates)
    for _, pl in ipairs(type(p) == 'table' and p or {}) do
      local u = pl.namePlateUnitToken or (pl.UnitFrame and pl.UnitFrame.unit)
      if u then PL.units[u] = true end
    end
  end
  if next(PL.units) == nil then
    local p = C_NamePlate and C_NamePlate.GetNamePlates and pc(C_NamePlate.GetNamePlates)
    return type(p) == 'table' and p or out
  end
  for u in pairs(PL.units) do
    local pl = C_NamePlate.GetNamePlateForUnit and pc(C_NamePlate.GetNamePlateForUnit, u)
    if pl then out[#out + 1] = pl else PL.units[u] = nil end
  end
  return out
end
do
  local ev = CreateFrame('Frame')
  pcall(ev.RegisterEvent, ev, 'NAME_PLATE_UNIT_ADDED')
  pcall(ev.RegisterEvent, ev, 'NAME_PLATE_UNIT_REMOVED')
  pcall(ev.RegisterEvent, ev, 'PLAYER_REGEN_DISABLED')
  ev:SetScript('OnEvent', function(_, e, u)
    if e == 'PLAYER_REGEN_DISABLED' then PL.fightAt = GetTime() return end
    u = safe(u)
    if type(u) ~= 'string' then return end
    if e == 'NAME_PLATE_UNIT_ADDED' then
      PL.units[u] = true
      PL.combatOf[u] = safeBool(pc(UnitAffectingCombat, u)) == true
    else
      PL.units[u] = nil
      PL.combatOf[u] = nil
    end
  end)
end
-- mob blizko, ktery byl v klidu, se behem boje pridal (social aggro / patrola)
local function checkJoined(u, inCombat)
  local now = safeBool(pc(UnitAffectingCombat, u)) == true
  local was = PL.combatOf[u]
  PL.combatOf[u] = now
  if not (inCombat and now and was == false) then return end
  if GetTime() - (PL.fightAt or 0) < 2 then return end   -- zacatek pullu: vsichni najednou
  if is(u, 'target') or ns.close(u) == false then return end
  PL.joined = { at = GetTime(), name = safe(pc(UnitName, u)) }
end

------------------------------------------------------------------------------------------
-- Identita moba: GUID / creature ID / raid znacka. Textove: "g/n/m"
------------------------------------------------------------------------------------------
local function idOf(u)
  local g = safe(pc(UnitGUID, u))
  if type(g) ~= 'string' then g = nil end
  local n = g and g:match('^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-') or nil
  local m = safeNum(pc(GetRaidTargetIndex, u))
  if not (g or m) then return nil end
  return { g = g, n = n, m = m }
end
local function idStr(id) return (id.g or '') .. '/' .. (id.n or '') .. '/' .. (id.m or '') end
local function idParse(s)
  if type(s) ~= 'string' then return nil end
  local g, n, m = s:match('^([^/]*)/([^/]*)/([^/]*)$')
  if not g then return nil end
  local id = { g = g ~= '' and g or nil, n = n ~= '' and n or nil, m = tonumber(m) }
  if not (id.g or id.m or id.n) then return nil end
  return id
end
-- shoda: GUID presne, nebo stejna raid znacka, nebo creature ID, kdyz je takovy mob u mne jen jeden
local npcCount = {}
local function match(u, id, myId)
  if not id then return false end
  myId = myId or idOf(u)
  if not myId then return false end
  if id.g and myId.g and id.g == myId.g then return true end
  if id.m and myId.m and id.m == myId.m then return true end
  if id.n and myId.n and id.n == myId.n and npcCount[id.n] == 1 then return true end
  return false
end
PL.idOf, PL.match = idOf, match

------------------------------------------------------------------------------------------
-- Zpravy: X^T=<id>^H=<hp cile>^A=<id>,<id>   P^<id>^<sekund>^<kouzlo>
------------------------------------------------------------------------------------------
local function send(msg)
  if ns.Duo and ns.Duo.rawSend then return ns.Duo.rawSend(msg) end
end
local function tanksMe(u)
  -- jen threat (porovnani "cil moba = ja" pres slozeny token hra nedovoli)
  if not UnitDetailedThreatSituation then return false end
  return safeBool(pc(UnitDetailedThreatSituation, 'player', u)) == true
end

local function sendState()
  if not (ns.Duo and ns.Duo.peer and ns.Duo.peer()) then return end
  local parts = { 'X' }
  local tid = UnitExists('target') and safeBool(pc(UnitCanAttack, 'player', 'target')) == true and idOf('target')
  parts[#parts + 1] = 'T=' .. (tid and idStr(tid) or '')
  local hp = tid and ns.healthPct('target')
  parts[#parts + 1] = 'H=' .. (hp and math.floor(hp) or '')
  local a = {}
  if ns.inCombat() then
    for _, pl in ipairs(getPlates()) do
      local u = plateUnit(pl)
      if u and #a < 5 and safeBool(pc(UnitCanAttack, 'player', u)) == true and tanksMe(u) then
        local id = idOf(u)
        if id then a[#a + 1] = idStr(id) end
      end
    end
  end
  parts[#parts + 1] = 'A=' .. table.concat(a, ',')
  local sl, sh = ns.sheepLeft and ns.sheepLeft()
  local sid = sl and sh and sh.guid and idOf('target')
  if sl and sh and not (sid and sid.g == sh.guid) then sid = PL.mySheepId end
  if sl and sid then
    PL.mySheepId = sid
    parts[#parts + 1] = ('S=%s~%d'):format(idStr(sid), math.floor(sl))
  else
    parts[#parts + 1] = 'S='
  end
  local msg = table.concat(parts, '^')
  if #msg > 250 then msg = msg:sub(1, 250) end
  local now = GetTime()
  if msg ~= PL.lastMsg and now - PL.lastSend > 0.4 or now - PL.lastSend > 2.5 then
    PL.lastMsg, PL.lastSend = msg, now
    send(msg)
  end
end

-- ovce: mag ji hned posle (GUID + delka), at ji parťák vidi na stejnem mobovi
function PL.sendSheep(unit, dur, spell)
  local id = idOf(unit or 'target')
  PL.mySheepId = id
  if id then send(('P^%s^%d^%s'):format(idStr(id), math.floor(dur or 50), spell or 'Polymorph')) end
end

function PL.recv(name, msg)
  local kind = msg:sub(1, 1)
  local f = {}
  for v in (msg .. '^'):gmatch('([^%^]*)%^') do f[#f + 1] = v end
  local now = GetTime()
  if kind == 'X' then
    local t, h, a, sh = nil, nil, {}, false
    for i = 2, #f do
      local k, v = f[i]:match('^(%a)=(.*)$')
      if k == 'T' then t = idParse(v)
      elseif k == 'H' then h = tonumber(v)
      elseif k == 'A' then for s in v:gmatch('[^,]+') do local id = idParse(s) if id then a[#a + 1] = id end end
      elseif k == 'S' then
        local is_, left = v:match('^(.-)~(%d+)$')
        sh = { id = idParse(is_), left = tonumber(left) }
      end
    end
    -- ovce parťáka: zprava je autoritativni (zadna = probudila se)
    for i = #PL.sheep, 1, -1 do if PL.sheep[i].from == name then table.remove(PL.sheep, i) end end
    if sh and sh.id and sh.left then
      PL.sheep[#PL.sheep + 1] = { id = sh.id, untilT = now + sh.left, from = name }
    end
    PL.peerT[name] = { id = t, hp = h, at = now }
    PL.peerA[name] = { ids = a, at = now }
  elseif kind == 'P' then
    local id = idParse(f[2])
    for i = #PL.sheep, 1, -1 do if PL.sheep[i].from == name then table.remove(PL.sheep, i) end end
    if id then PL.sheep[#PL.sheep + 1] = { id = id, untilT = now + (tonumber(f[3]) or 50), spell = f[4], from = name } end
  end
end

-- parťákuv cil (identita + HP), cerstvy do 4 s
function PL.peerTarget()
  local now = GetTime()
  for nm, t in pairs(PL.peerT) do if now - t.at < 4 then return t, nm end end
end
-- sdilena ovce na tomto mobovi? vraci zbyvajici cas
function PL.sharedCC(u)
  local now = GetTime()
  local myId
  for i = #PL.sheep, 1, -1 do
    local s = PL.sheep[i]
    if s.untilT <= now then table.remove(PL.sheep, i)
    else
      myId = myId or idOf(u)
      if match(u, s.id, myId) then return s.untilT - now, s end
    end
  end
end
-- ns.isCC doplnit o sdilenou ovci (cil = ovce od parťáka -> nebit)
do
  local orig = ns.isCC
  if orig then
    ns.isCC = function(u)
      local a, g = orig(u)
      if a then return a, g end
      if PL.sharedCC(u) then return true, g end
      return false, g
    end
  end
end

------------------------------------------------------------------------------------------
-- Ramecek u jmenovky
------------------------------------------------------------------------------------------
local function make(plate)
  local hb = plate.UnitFrame and (plate.UnitFrame.healthBar or plate.UnitFrame.HealthBar) or plate
  local o = CreateFrame('Frame', nil, plate)
  o:SetAllPoints(hb)
  o:SetFrameStrata('HIGH')
  -- kdo ho bije: pismena tesne vlevo od health baru, svisle na stred
  o.who = o:CreateFontString(nil, 'OVERLAY')
  o.who:SetFont(FONT, 12, 'OUTLINE')
  o.who:SetPoint('RIGHT', hb, 'LEFT', -4, 0)
  o.who:SetJustifyH('RIGHT')
  -- na koho jde: pod barem vlevo
  o.aggro = o:CreateFontString(nil, 'OVERLAY')
  o.aggro:SetFont(FONT, 10, 'OUTLINE')
  o.aggro:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', 0, -2)
  o.dots = o:CreateFontString(nil, 'OVERLAY')
  o.dots:SetFont(FONT, 10, 'OUTLINE')
  o.dots:SetPoint('LEFT', o.aggro, 'RIGHT', 4, 0)
  o.dots:SetTextColor(0.75, 0.5, 1)
  -- CC (ovce): vlevo od pismen
  -- questovy mob (mas ho zabit / dropuje questovy item): maly zluty vykricnik nad pravym koncem
  -- health baru (vpravo vedle baru je ukazatel levelu, vlevo nahore debuffy)
  o.quest = o:CreateTexture(nil, 'OVERLAY')
  o.quest:SetSize(11, 11)
  o.quest:SetPoint('BOTTOMRIGHT', hb, 'TOPRIGHT', 0, 1)
  o.quest:SetTexture('Interface\\GossipFrame\\AvailableQuestIcon')
  o.quest:Hide()
  o.cc = o:CreateTexture(nil, 'OVERLAY')
  o.cc:SetSize(18, 18)
  o.cc:SetPoint('RIGHT', o.who, 'LEFT', -3, 0)
  o.cc:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  o.ccq = o:CreateFontString(nil, 'OVERLAY')
  o.ccq:SetFont(FONT, 12, 'OUTLINE')
  o.ccq:SetPoint('CENTER', o.cc, 'CENTER', 0, 0)
  o.kick = {}
  for i = 1, 4 do
    local t = o:CreateTexture(nil, 'OVERLAY')
    t:SetTexture(WHITE)
    o.kick[i] = t
  end
  local k = o.kick
  k[1]:SetPoint('BOTTOMLEFT', hb, 'TOPLEFT', -3, 0) k[1]:SetPoint('BOTTOMRIGHT', hb, 'TOPRIGHT', 3, 0) k[1]:SetHeight(2)
  k[2]:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', -3, 0) k[2]:SetPoint('TOPRIGHT', hb, 'BOTTOMRIGHT', 3, 0) k[2]:SetHeight(2)
  k[3]:SetPoint('TOPRIGHT', hb, 'TOPLEFT', 0, 2) k[3]:SetPoint('BOTTOMRIGHT', hb, 'BOTTOMLEFT', 0, -2) k[3]:SetWidth(2)
  k[4]:SetPoint('TOPLEFT', hb, 'TOPRIGHT', 0, 2) k[4]:SetPoint('BOTTOMLEFT', hb, 'BOTTOMRIGHT', 0, -2) k[4]:SetWidth(2)
  return o
end
local function overlayFor(plate)
  local o = PL.over[plate]
  if not o then
    local ok, res = pcall(make, plate)
    if not ok then return nil end
    o = res
    PL.over[plate] = o
  end
  return o
end
local function clear(o)
  o.who:SetText('') o.aggro:SetText('') o.dots:SetText('')
  o.cc:Hide() o.ccq:Hide() o.ccq:SetText('')
  if o.quest then o.quest:Hide() end
  for i = 1, 4 do o.kick[i]:Hide() end
end

local function castPrioOf(u)
  local r = { pc(UnitCastingInfo, u) }
  local notInt, sid = r[8], r[9]
  if not ns.isSet(r[1]) then
    r = { pc(UnitChannelInfo, u) }
    if not ns.isSet(r[1]) then return nil end
    notInt, sid = r[7], r[8]
  end
  if safeBool(notInt) == true then return nil end
  local nm = safe(r[1])
  if type(nm) == 'string' and ns.db.noKick and ns.db.noKick[nm] then return nil end
  if not ns.castPrio then return 2 end
  local st, en = safeNum(r[4]), safeNum(r[5])
  return (ns.castPrio(type(nm) == 'string' and nm or nil, safeNum(sid), (st and en) and (en - st) or nil))
end

local DOTS = { 'Corruption', 'Bane of Agony', 'Immolate', 'Curse of Agony', 'Siphon Life', 'Bane of Doom' }
local function myDots(u, g)
  local W = ns.Warlock
  if not (W and W.dots) then return 0 end
  local keys = {}
  if g then keys[#keys + 1] = g end
  if is(u, 'target') then keys[#keys + 1] = 't' .. ns.T.token end
  local now, n, seen = GetTime(), 0, {}
  for _, k in ipairs(keys) do
    local d = W.dots[k]
    if d then
      for _, nm in ipairs(DOTS) do
        local e = d[nm]
        if e and not e.other and e.untilT > now and not seen[nm] then seen[nm] = true n = n + 1 end
      end
    end
  end
  return n
end

------------------------------------------------------------------------------------------
-- Hlavni smycka (5x za sekundu)
------------------------------------------------------------------------------------------
local function update()
  if ns.db.plates == false then
    for _, o in pairs(PL.over) do clear(o) end
    return
  end
  local plates = getPlates()
  local inCombat = ns.inCombat()
  local grouped = IsInGroup and IsInGroup()
  local seen = {}
  local peerT, peerName = PL.peerTarget()
  local peerUnit = ns.Duo and ns.Duo.peer and ns.Duo.peer()
  peerUnit = peerUnit and peerUnit.unit
  local myHex = classHex('player')
  local myL = (safe(pc(UnitName, 'player')) or '?'):sub(1, 1)
  -- kolik jmenovek ma jaky creature ID (shoda podle druhu jen kdyz je jediny)
  wipe(npcCount)
  local ids = {}
  for _, pl in ipairs(plates) do
    local u = plateUnit(pl)
    if u then
      local id = idOf(u)
      ids[pl] = id or false
      if id and id.n then npcCount[id.n] = (npcCount[id.n] or 0) + 1 end
    end
  end
  local want = ns.Tactics and ns.Tactics.ccWanted
  if want and GetTime() - want.at > 1 then want = nil end
  local now = GetTime()
  for _, pl in ipairs(plates) do
    local u = plateUnit(pl)
    if u and safeBool(pc(UnitCanAttack, 'player', u)) == true and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true then
      pcall(checkJoined, u, inCombat)
      local o = overlayFor(pl)
      if o then
        seen[o] = true
        clear(o)
        local myId = ids[pl] or nil
        -- questovy mob (sedy = tagnuty cizim hracem: polopruhledne)
        if o.quest and ns.Quests and ns.Quests.mobNeed and ns.Quests.mobNeed(u) then
          o.quest:SetAlpha(safeBool(pc(UnitIsTapDenied, u)) == true and 0.35 or 1)
          o.quest:Show()
        end
        -- kdo ho bije: ja (muj cil) + parťák (jeho cil ze zpravy)
        if grouped then
          local who = {}
          if is(u, 'target') then who[#who + 1] = ('|c%s%s|r'):format(myHex, myL) end
          if peerT and peerT.id and match(u, peerT.id, myId) then
            who[#who + 1] = ('|c%s%s|r'):format(peerUnit and classHex(peerUnit) or 'ffffffff', (peerName or '?'):sub(1, 1))
          end
          if #who > 0 then o.who:SetText(table.concat(who, ' ')) end
        end
        -- na koho utoci: ja (threat), parťák (jeho zprava)
        local mobIn = safeBool(pc(UnitAffectingCombat, u)) == true or inCombat
        if mobIn then
          local st = grouped and safeNum(pc(UnitThreatSituation, 'player', u))
          if tanksMe(u) then
            o.aggro:SetText('|cffff4040>TY|r')
          elseif st == 1 then
            -- mas vic threatu nez ten, koho bije: za chvili pujde po tobe
            o.aggro:SetText('|cffff9900!TY|r')
          else
            for nm, a in pairs(PL.peerA) do
              if now - a.at < 4 then
                for _, id in ipairs(a.ids) do
                  if match(u, id, myId) then o.aggro:SetText('|cffffcc33>' .. nm .. '|r') break end
                end
              end
            end
          end
        end
        -- CC: vlastni ovce nebo sdilena od parťáka (s odpoctem)
        local left = PL.sharedCC(u)
        local own = ns.isCC and ns.isCC(u) == true
        if own or left then
          o.cc:SetTexture(CC_ICON.Polymorph) o.cc:SetAlpha(1) o.cc:Show()
          if not left then
            local sl, sh = ns.sheepLeft and ns.sheepLeft()
            if sl and (not sh.guid or (myId and sh.guid == myId.g)) then left = sl end
          end
          if left then
            o.ccq:SetText(left <= 5 and ('|cffff5555%d|r'):format(math.ceil(left)) or tostring(math.ceil(left))) o.ccq:Show()
          end
        elseif want and mobIn and myId and myId.m == 5 then
          -- planovana ovce jen na mesici (znacku vidi oba stejne)
          o.cc:SetTexture(CC_ICON[want.spell] or CC_ICON.Polymorph)
          o.cc:SetAlpha(0.5) o.cc:Show() o.ccq:SetText('?') o.ccq:Show()
        end
        -- preruseni
        local pr = castPrioOf(u)
        if pr and pr >= 2 then
          local r, g, b = 1, 0.15, 0.15
          if pr == 2 then r, g, b = 1, 0.6, 0.1 end
          for i = 1, 4 do o.kick[i]:SetVertexColor(r, g, b, 0.95) o.kick[i]:Show() end
        end
      end
    end
  end
  for _, o in pairs(PL.over) do if not seen[o] then clear(o) end end
  if grouped and not (ns.Duo and ns.Duo.encounter) then pcall(sendState) end
end

if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(0.2, function()
    local ok, err = pcall(update)
    if not ok and ns.db and ns.db.debug then ns.say('plates: ' .. tostring(err)) end
  end)
end

------------------------------------------------------------------------------------------
-- /cm test: co hra prozradi (pro ladeni sdileni)
------------------------------------------------------------------------------------------
local function show(v)
  if v == nil then return '|cffff5555skryte/nil|r' end
  return '|cff66ee77' .. tostring(v) .. '|r'
end
function PL.test()
  ns.say(('Test (v boji: %s, cil: %s)'):format(tostring(ns.inCombat()), tostring(safe(pc(UnitName, 'target')))))
  local g = safe(pc(UnitGUID, 'target'))
  ns.say('  GUID cile: ' .. (type(g) == 'string' and ('|cff66ee77' .. g .. '|r') or '|cffff5555skryte|r'))
  local tk = UnitDetailedThreatSituation and safeBool(pc(UnitDetailedThreatSituation, 'player', 'target'))
  ns.say('  threat: tankuju cil: ' .. show(tk))
  ns.say('  znacka cile: ' .. show(safeNum(pc(GetRaidTargetIndex, 'target'))))
  local t, nm = PL.peerTarget()
  if t then
    ns.say(('  cil partaka (%s): %s, HP %s, shoda s mym cilem: %s'):format(nm, t.id and idStr(t.id) or 'zadny',
      tostring(t.hp), tostring(t.id and match('target', t.id) or false)))
  else
    ns.say('  zpravy o cili od partaka: zadne')
  end
  ns.say(('  sdilene ovce: %d'):format(#PL.sheep))
end

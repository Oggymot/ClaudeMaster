-- ClaudeMaster: okno s nastavenim (/cm config nebo tlacitko u minimapy)
-- Vlevo zalozky (Panel, Boj, Parta, Build, Veci a questy, Pamet), vpravo posuvny obsah.
-- Kazda volba ma tooltip s vysvetlenim. Build = smer talentu + vahy gearu (+ spec druida).
local ADDON, ns = ...
if not ns.enabled then return end

local O = {}
ns.Options = O

local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local W, H = 600, 480          -- okno
local NAV = 148                -- sirka leve listy
local CW = W - NAV - 44        -- sirka obsahu

local function th() return ns.THEME end
local function accent(a) local c = th().ui return c[1], c[2], c[3], a or 1 end

local function label(parent, text, size, r, g, b, flags)
  local fs = parent:CreateFontString(nil, 'OVERLAY')
  fs:SetFont(FONT, size or 11, type(flags) == 'string' and flags or '')
  fs:SetShadowOffset(1, -1) fs:SetShadowColor(0, 0, 0, 0.9)
  fs:SetTextColor(r or 0.88, g or 0.9, b or 0.95)
  fs:SetJustifyH('LEFT')
  fs:SetText(text or '')
  return fs
end
local function backdrop(f, bg, border, edge)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
  f:SetBackdropColor(unpack(bg)) f:SetBackdropBorderColor(unpack(border))
end
local function tip(f, title, text)
  if not text and not title then return end
  f:HookScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    if title then GameTooltip:AddLine(title, 1, 1, 1) end
    if text then GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  f:HookScript('OnLeave', function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------------------------
-- Prvky
------------------------------------------------------------------------------------------
local function checkbox(parent, text, desc, get, set)
  local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
  b:SetSize(CW, 22)
  b.box = CreateFrame('Frame', nil, b, 'BackdropTemplate')
  b.box:SetSize(16, 16) b.box:SetPoint('LEFT', 0, 0)
  backdrop(b.box, { 0, 0, 0, 0.55 }, { 0.35, 0.4, 0.5, 1 })
  b.mark = b.box:CreateTexture(nil, 'OVERLAY')
  b.mark:SetTexture('Interface\\Buttons\\UI-CheckBox-Check')
  b.mark:SetPoint('TOPLEFT', -3, 3) b.mark:SetPoint('BOTTOMRIGHT', 3, -3)
  b.text = label(b, text, 12) b.text:SetPoint('LEFT', b.box, 'RIGHT', 8, 0) b.text:SetPoint('RIGHT', 0, 0)
  b.text:SetWordWrap(false)
  b.hl = b:CreateTexture(nil, 'BACKGROUND') b.hl:SetAllPoints() b.hl:SetColorTexture(1, 1, 1, 0.04) b.hl:Hide()
  b:SetScript('OnEnter', function() b.hl:Show() b.box:SetBackdropBorderColor(accent()) end)
  b:SetScript('OnLeave', function() b.hl:Hide() b.box:SetBackdropBorderColor(0.35, 0.4, 0.5, 1) end)
  function b.refresh()
    local on = get() and true or false
    b.mark:SetShown(on)
    b.box:SetBackdropColor(on and 0.1 or 0, on and 0.12 or 0, on and 0.16 or 0, 0.6)
    b.text:SetTextColor(on and 0.95 or 0.7, on and 0.95 or 0.72, on and 0.97 or 0.76)
  end
  b:SetScript('OnClick', function()
    set(not get()) b.refresh()
    if PlaySound and SOUNDKIT then pcall(PlaySound, get() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
  end)
  tip(b, text, desc)
  b.refresh()
  return b
end

local function slider(parent, text, desc, minV, maxV, step, get, set, fmt)
  local h = CreateFrame('Frame', nil, parent)
  h:SetSize(CW, 38) h:EnableMouse(true)
  h.text = label(h, text, 12) h.text:SetPoint('TOPLEFT', 0, -2)
  local ar, ag, ab = accent()
  h.val = label(h, '', 12, ar, ag, ab) h.val:SetPoint('TOPRIGHT', 0, -2) h.val:SetJustifyH('RIGHT')
  local s = CreateFrame('Slider', nil, h, 'BackdropTemplate')
  s:SetOrientation('HORIZONTAL')
  s:SetPoint('TOPLEFT', 0, -20) s:SetPoint('TOPRIGHT', 0, -20) s:SetHeight(10)
  backdrop(s, { 0, 0, 0, 0.55 }, { 0.3, 0.34, 0.42, 1 })
  s.fill = s:CreateTexture(nil, 'ARTWORK') s.fill:SetTexture(WHITE)
  s.fill:SetPoint('TOPLEFT', 1, -1) s.fill:SetPoint('BOTTOMLEFT', 1, 1) s.fill:SetVertexColor(accent(0.35))
  s:SetThumbTexture(WHITE)
  local t = s:GetThumbTexture()
  t:SetSize(8, 16) t:SetVertexColor(accent())
  s:SetMinMaxValues(minV, maxV) s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  local busy = false
  local function show(v)
    h.val:SetText((fmt or '%s'):format(v))
    local w = s:GetWidth() - 2
    if w and w > 0 then s.fill:SetWidth(math.max(1, w * (v - minV) / (maxV - minV))) end
  end
  function h.refresh()
    busy = true s:SetValue(get()) show(get()) busy = false
  end
  s:SetScript('OnValueChanged', function(_, v)
    v = math.floor(v / step + 0.5) * step
    show(v)
    if busy then return end
    set(v)
  end)
  s:SetScript('OnMouseWheel', function(_, d) s:SetValue(math.max(minV, math.min(maxV, s:GetValue() + d * step))) end)
  s:SetScript('OnSizeChanged', function() show(get()) end)
  tip(h, text, desc) tip(s, text, desc)
  h.refresh()
  return h
end

-- vyber z moznosti: [<] hodnota [>]
local function choice(parent, text, desc, opts, get, set)
  local h = CreateFrame('Frame', nil, parent)
  h:SetSize(CW, 26) h:EnableMouse(true)
  h.text = label(h, text, 12) h.text:SetPoint('LEFT', 0, 0)
  local box = CreateFrame('Button', nil, h, 'BackdropTemplate')
  box:SetSize(170, 22) box:SetPoint('RIGHT', 0, 0)
  backdrop(box, { 0, 0, 0, 0.55 }, { 0.3, 0.34, 0.42, 1 })
  box.val = label(box, '', 12, 1, 1, 1) box.val:SetPoint('CENTER') box.val:SetJustifyH('CENTER')
  box:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  local function arrow(side, tex)
    local a = box:CreateTexture(nil, 'OVERLAY')
    a:SetTexture(tex) a:SetSize(18, 18) a:SetPoint(side, side == 'LEFT' and 1 or -1, 0) a:SetVertexColor(accent())
  end
  arrow('LEFT', 'Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up') arrow('RIGHT', 'Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up')
  local function list() return type(opts) == 'function' and opts() or opts end
  local function idx()
    local cur, l = get() or 'auto', list()
    for i, o in ipairs(l) do if o[1] == cur then return i end end
    return 1
  end
  function h.refresh() local l = list() box.val:SetText(l[idx()] and l[idx()][2] or '?') end
  box:SetScript('OnClick', function(self, btn)
    local l = list()
    local x = GetCursorPosition() / self:GetEffectiveScale()
    local back = btn == 'RightButton' or x < self:GetLeft() + self:GetWidth() * 0.3
    local i = idx() + (back and -1 or 1)
    if i > #l then i = 1 elseif i < 1 then i = #l end
    set(l[i][1]) h.refresh()
  end)
  box:SetScript('OnEnter', function() box:SetBackdropBorderColor(accent()) end)
  box:SetScript('OnLeave', function() box:SetBackdropBorderColor(0.3, 0.34, 0.42, 1) end)
  tip(h, text, desc) tip(box, text, (desc and (desc .. '\n\n') or '') .. '|cff888888Klik = dalsi, pravy klik (nebo leva cast) = predchozi.|r')
  h.refresh()
  return h
end

local function button(parent, text, w, onClick, desc)
  local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
  b:SetSize(w or 150, 24)
  backdrop(b, { accent(0.12) }, { accent(0.5) })
  b.text = label(b, text, 11, 1, 1, 1) b.text:SetPoint('CENTER') b.text:SetJustifyH('CENTER')
  b:SetScript('OnEnter', function() b:SetBackdropColor(accent(0.28)) b:SetBackdropBorderColor(accent(0.9)) end)
  b:SetScript('OnLeave', function() b:SetBackdropColor(accent(0.12)) b:SetBackdropBorderColor(accent(0.5)) end)
  b:SetScript('OnClick', function() onClick(b) end)
  tip(b, text, desc)
  return b
end

------------------------------------------------------------------------------------------
-- Stranka = posuvny obsah s rozvrzenim pod sebe
------------------------------------------------------------------------------------------
local function newPage(host)
  local sf = CreateFrame('ScrollFrame', nil, host)
  sf:SetAllPoints()
  local c = CreateFrame('Frame', nil, sf)
  c:SetSize(CW, 10)
  sf:SetScrollChild(c)
  local p = { sf = sf, c = c, y = 0, items = {}, flow = {} }
  -- posuvnik (jen ukazatel; kolecko mysi)
  local bar = sf:CreateTexture(nil, 'OVERLAY') bar:SetTexture(WHITE) bar:SetWidth(3) bar:SetVertexColor(accent(0.5))
  local function upd()
    local view, full = sf:GetHeight(), c:GetHeight()
    if full <= view + 1 then bar:Hide() return end
    local hh = math.max(20, view * view / full)
    local off = sf:GetVerticalScroll() / (full - view) * (view - hh)
    bar:ClearAllPoints() bar:SetPoint('TOPRIGHT', sf, 'TOPRIGHT', 14, -off) bar:SetHeight(hh) bar:Show()
  end
  sf:EnableMouseWheel(true)
  sf:SetScript('OnMouseWheel', function(_, d)
    local max = math.max(0, c:GetHeight() - sf:GetHeight())
    sf:SetVerticalScroll(math.max(0, math.min(max, sf:GetVerticalScroll() - d * 40)))
    upd()
  end)
  sf:SetScript('OnShow', function() sf:SetVerticalScroll(0) upd() end)
  p.upd = upd
  -- rozvrzeni pod sebe; skryte prvky a prazdne poznamky misto nezaberou
  function p.layout()
    local y, first = 0, true
    for _, it in ipairs(p.flow) do
      local w = it.w
      if w:IsShown() and w:GetHeight() > 1 then
        y = y - (first and 0 or it.gap)
        first = false
        w:ClearAllPoints()
        w:SetPoint('TOPLEFT', c, 'TOPLEFT', it.indent or 0, y)
        y = y - w:GetHeight()
      end
    end
    p.y = y
    c:SetHeight(-y + 10)
  end
  function p.add(w, gap, indent)
    if indent then w:SetWidth(CW - indent) end
    p.flow[#p.flow + 1] = { w = w, gap = gap or 6, indent = indent }
    p.items[#p.items + 1] = w
    p.layout()
    return w
  end
  function p.section(text, sub)
    local f = CreateFrame('Frame', nil, c)
    f:SetSize(CW, 22)
    local t = label(f, text, 13, unpack(th().title)) t:SetPoint('TOPLEFT', 0, 0)
    local line = f:CreateTexture(nil, 'ARTWORK') line:SetTexture(WHITE) line:SetHeight(1)
    line:SetPoint('TOPLEFT', 0, -18) line:SetPoint('TOPRIGHT', 0, -18) line:SetVertexColor(accent(0.3))
    if sub then
      local s = label(f, sub, 10, 0.6, 0.62, 0.68) s:SetPoint('TOPLEFT', 0, -24) s:SetWidth(CW) s:SetWordWrap(true)
      s:SetSpacing(2)
      f:SetHeight(24 + math.ceil(s:GetStringHeight()) + 2)
    end
    return p.add(f, 18)
  end
  function p.note(text, size)
    local f = CreateFrame('Frame', nil, c)
    local t = label(f, text, size or 11, 0.65, 0.67, 0.72) t:SetPoint('TOPLEFT') t:SetWidth(CW) t:SetWordWrap(true)
    f.fs = t
    function f.fit()   -- vyska podle textu (prazdny = 0, v rozvrzeni se preskoci)
      local txt = t:GetText()
      f:SetHeight((txt and txt ~= '') and math.max(12, t:GetStringHeight() + 2) or 1)
    end
    f:SetWidth(CW) f.fit()
    return p.add(f, 4)
  end
  function p.row(...)
    local f = CreateFrame('Frame', nil, c)
    local x, y = 0, 0
    for _, b in ipairs({ ... }) do
      if x > 0 and x + b:GetWidth() > CW then x, y = 0, y - 30 end   -- nevejde se -> dalsi radek
      b:SetParent(f) b:ClearAllPoints() b:SetPoint('TOPLEFT', x, y) x = x + b:GetWidth() + 8
    end
    f:SetSize(CW, 24 - y)
    return p.add(f, 10)
  end
  function p.refresh()
    for _, w in ipairs(p.items) do if w.refresh then pcall(w.refresh) end end
    for _, it in ipairs(p.flow) do if it.w.fit then it.w.fit() end end
    p.layout()
    upd()
  end
  return p
end

------------------------------------------------------------------------------------------
-- Akce sdilene s /cm
------------------------------------------------------------------------------------------
function O.togglePanel(on)
  local db = ns.db
  if on == nil then on = not db.shown end
  db.shown = on
  if ns.UI.frame and not InCombatLockdown() then ns.UI.frame:SetShown(db.shown) ns.UI.reanchor() end
end
local function questsUpd() if ns.Quests then ns.Quests.last = 0 pcall(ns.Quests.update) end end

------------------------------------------------------------------------------------------
-- Stranky
------------------------------------------------------------------------------------------
local PAGES = {}

PAGES[#PAGES + 1] = { key = 'panel', name = 'Panel', icon = 'Interface\\Icons\\INV_Misc_Spyglass_02', build = function(p, db)
  p.section('Panel s doporucenim', 'Okno s ikonou, co castit, manou a duvodem.')
  p.add(checkbox(p.c, 'Zobrazit panel', 'Skryje / zobrazi cely panel (stejne jako /cm).',
    function() return db.shown end, function(v) O.togglePanel(v) end))
  p.add(checkbox(p.c, 'Zamknout panel', 'Zamceny panel nejde tahat mysi.',
    function() return db.locked end, function(v) db.locked = v if ns.UI.frame then ns.UI.frame:EnableMouse(not v) end end))
  p.add(checkbox(p.c, 'Mimo boj schovat, kdyz neni co delat', 'Panel se ukaze sam, jakmile ma co doporucit nebo zacne boj.',
    function() return db.hideIdle end, function(v) db.hideIdle = v end))
  p.add(slider(p.c, 'Velikost panelu', 'Zvetseni celeho panelu. Meni se jen mimo boj.', 0.6, 2, 0.05,
    function() return db.scale end, function(v)
      db.scale = v
      if ns.UI.frame and not InCombatLockdown() then ns.UI.frame:SetScale(v) ns.UI.reanchor() end
    end, '%.2f x'), 10)

  p.section('Co panel ukazuje')
  p.add(checkbox(p.c, 'Kompaktni: jen ikony', 'Bez textu pod ikonami, duvod je v tooltipu ikony.'
    .. (ns.class == 'WARLOCK' and '\nU warlocka se velikost okna zmeni po /reload.' or ''),
    function() return db.compact end, function(v) db.compact = v end))
  p.add(checkbox(p.c, 'Text doporuceni', 'Kratka veta, proc addon radi prave tohle kouzlo.',
    function() return db.showReason end, function(v) db.showReason = v end))
  p.add(checkbox(p.c, 'Info radky (moby, cil, stavy)', 'Kolik mobu, co ma cil, imunity, aggro...',
    function() return db.showInfo end, function(v) db.showInfo = v end))
  p.add(checkbox(p.c, 'Zvuk u nalehavych veci', 'Kratky zvuk, kdyz je potreba rychle reagovat (prerusit, utect, lecit).',
    function() return db.sound end, function(v) db.sound = v end))
  p.add(checkbox(p.c, 'Shrnuti po boji', 'Po boji ukaze, co slo dobre a co zlepsit.',
    function() return db.summary end, function(v) db.summary = v end))
  if ns.class == 'DRUID' then
    p.add(checkbox(p.c, 'Threat metr v bear forme', 'Lista nad panelem: jak blizko je dalsi clen party k tvemu aggru.',
      function() return db.threatBar ~= false end, function(v) db.threatBar = (not v) and false or nil end))
  end

  p.section('Tlacitko u minimapy')
  p.add(checkbox(p.c, 'Zobrazit tlacitko u minimapy', 'Levy klik = nastaveni, pravy klik = panel. Tazenim ho posunes po okraji minimapy.',
    function() return not (db.minimap and db.minimap.hide) end,
    function(v) db.minimap = db.minimap or {} db.minimap.hide = not v O.updateMinimap() end))

  p.section('Nastroje')
  p.row(button(p.c, 'Vratit panel na misto', 160, function()
    db.point = { 'CENTER', 'CENTER', 0, -190 }
    if ns.UI.frame and not InCombatLockdown() then
      ns.UI.frame:ClearAllPoints() ns.UI.frame:SetPoint('CENTER', UIParent, 'CENTER', 0, -190) ns.UI.reanchor()
    end
  end, 'Panel se vrati doprostred pod postavu.'),
  button(p.c, 'Vytvorit makra', 140, function() if ns.UI.makeMacros then ns.UI.makeMacros() end end,
    'Vytvori makra, kterymi castis doporucene kouzlo jednim tlacitkem (/cm makra).'))
end }

PAGES[#PAGES + 1] = { key = 'combat', name = 'Boj a mana', icon = 'Interface\\Icons\\Ability_DualWield', build = function(p, db)
  local function pct(key) return function() return math.floor((db[key] or 0) * 100 + 0.5) end, function(v) db[key] = v / 100 end end
  p.section('Boj')
  p.add(slider(p.c, 'AoE od kolika mobu', 'Od kolika mobu v boji addon radi plosna kouzla.', 2, 6, 1,
    function() return db.aoe end, function(v) db.aoe = v end, '%d mobu'))
  p.add(slider(p.c, 'Healing potion / healthstone pod', 'Pri kolika % zivotu addon pripomene potion nebo healthstone.', 10, 60, 5,
    function() return db.potionHP or 30 end, function(v) db.potionHP = v end, '%d %% HP'))
  if ns.class == 'MAGE' then
    p.add(checkbox(p.c, 'Ice Barrier pred pullem', 'Mimo boj pripomene Ice Barrier, at jdes do boje se stitem.',
      function() return db.prebarrier end, function(v) db.prebarrier = v end), 8)
  end

  p.section('Mana', 'Kdy pit, setrit a sahat po wandu nebo mana gemu.')
  local g, s = pct('drinkMana') p.add(slider(p.c, 'Pit mimo boj pod', 'Mimo boj doporuci piti, kdyz mas mene many.', 20, 90, 5, g, s, '%d %%'))
  g, s = pct('conserveMana') p.add(slider(p.c, 'Setrit manou pod', 'Pod touto hranici addon voli levnejsi kouzla a nedela AoE na par mobu.', 10, 60, 5, g, s, '%d %%'))
  g, s = pct('wandMana') p.add(slider(p.c, 'Wand pod', 'Na dorazeni wandem, kdyz dochazi mana (0 = nikdy).', 0, 30, 1, g, s, '%d %%'))
  if ns.class == 'MAGE' then
    g, s = pct('gemMana') p.add(slider(p.c, 'Mana gem v boji pod', 'V boji pouzit mana gem pod touto hranici.', 20, 90, 5, g, s, '%d %%'))
  end

  if ns.class == 'WARLOCK' then
    p.section('Warlock')
    p.add(choice(p.c, 'Pet', 'Ktereho demona addon doporuci privolat.', { { 'auto', 'automaticky' }, { 'Imp', 'Imp' },
      { 'Voidwalker', 'Voidwalker' }, { 'Succubus', 'Succubus' }, { 'Felhunter', 'Felhunter' } },
      function() return db.lockPet end, function(v) db.lockPet = v end))
    p.add(choice(p.c, 'Curse', 'Kterou curse drzet na cili. Automaticky: Elements, kdyz je v parte mag, jinak Agony.',
      { { 'auto', 'automaticky' }, { 'Curse of the Elements', 'Elements' }, { 'Curse of Recklessness', 'Recklessness' },
        { 'Curse of Weakness', 'Weakness' }, { 'Curse of Exhaustion', 'Exhaustion' }, { 'Curse of Shadow', 'Shadow' },
        { 'Curse of Tongues', 'Tongues' }, { 'Curse of Doom', 'Doom' }, { 'none', 'zadna (jen Bane)' } },
      function() return db.lockCurse end, function(v) db.lockCurse = v end))
    p.add(choice(p.c, 'Hlavni kouzlo (filler)', 'Automaticky = to, co podle talentu a spell poweru dava nejvic za sekundu castu.',
      { { 'auto', 'automaticky' }, { 'Shadow Bolt', 'Shadow Bolt' }, { 'Searing Pain', 'Searing Pain' }, { 'Incinerate', 'Incinerate' } },
      function() return db.lockFiller end, function(v) db.lockFiller = v if ns.Warlock then pcall(ns.Warlock.refresh) end end))
    p.add(checkbox(p.c, 'Multi-DoT na dalsi moby', 'Radit DoTy i na moby kolem (s tabem).',
      function() return db.multiDot ~= false end, function(v) db.multiDot = v end), 8)
    p.add(slider(p.c, 'Drzet aspon soul shardu', 'Shadowburn / Soul Fire jen nad timto poctem.', 0, 10, 1,
      function() return db.shardKeep end, function(v) db.shardKeep = v end, '%d'))
    p.add(checkbox(p.c, 'Hlidat soul shardy nad maximum', 'Mimo boj se nad panelem ukaze tlacitko "Zahodit X soul shardu" (hra mazani '
      .. 'dovoli jen na klik). Totez prikazem /cm shardy.',
      function() return db.shardTrim ~= false end, function(v) db.shardTrim = v
        if ns.Warlock and ns.Warlock.updateShardButton then pcall(ns.Warlock.updateShardButton) end end), 8)
    p.add(slider(p.c, 'Maximum soul shardu', 'Nad timto poctem addon nabidne shardy zahodit.', 1, 40, 1,
      function() return db.shardMax or 10 end, function(v) db.shardMax = v
        if ns.Warlock and ns.Warlock.updateShardButton then pcall(ns.Warlock.updateShardButton) end end, '%d'), 6, 24)
    p.add(slider(p.c, 'Drain Soul na dorazeni do', 'Dokud nemas tolik shardu, dorazej Drain Soulem.', 0, 20, 1,
      function() return db.shardWant end, function(v) db.shardWant = v end, '%d'))
  elseif ns.class == 'PALADIN' then
    p.section('Paladin')
    p.add(choice(p.c, 'Seal', 'Automaticky: Righteousness, pri nedostatku many Wisdom.',
      { { 'auto', 'automaticky' }, { 'Seal of Righteousness', 'Righteousness' }, { 'Seal of the Crusader', 'Crusader' },
        { 'Seal of Wisdom', 'Wisdom' }, { 'Seal of Command', 'Command' }, { 'Seal of Light', 'Light' }, { 'Seal of Justice', 'Justice' } },
      function() return db.palSeal end, function(v) db.palSeal = v end))
  end
end }

PAGES[#PAGES + 1] = { key = 'party', name = 'Parta', icon = 'Interface\\Icons\\Ability_Warrior_BattleShout', build = function(p, db)
  p.section('Parta s tankem', 'Aby sis nebral aggro: chvili pockat po pullu a AoE az pozdeji.')
  p.add(slider(p.c, 'Pockat na tanka po pullu', 'Kolik sekund po pullu nechat tanka nabrat aggro, nez zacnes.', 0, 4, 0.5,
    function() return db.tankWait end, function(v) db.tankWait = v end, '%.1f s'))
  p.add(slider(p.c, 'AoE az po', 'AoE kouzla az po tolika sekundach boje. Uci se samo: kdyz strhnes aggro, prodlouzi se.', 0, 8, 0.5,
    function() return db.aoeDelay end, function(v) db.aoeDelay = v end, '%.1f s'))
  p.section('Znacky a jmenovky')
  p.add(checkbox(p.c, 'Znacky u jmenovek nepratel', 'Kdo bije koho, na koho mob jde, CC a co prerusit.',
    function() return db.plates ~= false end, function(v) db.plates = v end))
  p.add(checkbox(p.c, 'Lista se znackami ve skupine', 'Mala lista: lebka = zabit prvni, mesic = CC, smazat znacky.',
    function() return db.markBarOn == true end, function(v) db.markBarOn = v if ns.Assist then pcall(ns.Assist.applyVisibility) end end))
  p.add(checkbox(p.c, 'Pamet moba v tooltipu', 'V tooltipu nepritele: co si addon pamatuje (imunity, kouzla, utek).',
    function() return db.tipMob ~= false end, function(v) db.tipMob = v end))
end }

------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------
local function buildCard(parent)
  local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
  b:SetSize(CW, 56)
  backdrop(b, { 0, 0, 0, 0.35 }, { 0.25, 0.28, 0.34, 1 })
  b.radio = b:CreateTexture(nil, 'ARTWORK') b.radio:SetSize(14, 14) b.radio:SetPoint('TOPLEFT', 10, -10)
  b.radio:SetTexture(WHITE)
  b.dot = b:CreateTexture(nil, 'OVERLAY') b.dot:SetSize(8, 8) b.dot:SetPoint('CENTER', b.radio) b.dot:SetTexture(WHITE)
  b.title = label(b, '', 13, 1, 1, 1) b.title:SetPoint('TOPLEFT', 32, -9)
  b.tag = label(b, '', 10, 0.5, 0.9, 0.5) b.tag:SetPoint('LEFT', b.title, 'RIGHT', 8, 0)
  b.prog = label(b, '', 11, 0.75, 0.78, 0.85) b.prog:SetPoint('TOPRIGHT', -10, -10) b.prog:SetJustifyH('RIGHT')
  b.desc = label(b, '', 10, 0.62, 0.64, 0.7) b.desc:SetPoint('TOPLEFT', 32, -27) b.desc:SetPoint('RIGHT', -10, 0)
  b.desc:SetWordWrap(true)
  b:SetScript('OnEnter', function() if not b.sel then b:SetBackdropBorderColor(accent(0.6)) end end)
  b:SetScript('OnLeave', function() if not b.sel then b:SetBackdropBorderColor(0.25, 0.28, 0.34, 1) end end)
  function b.set(sel)
    b.sel = sel
    b.dot:SetShown(sel)
    b.radio:SetVertexColor(sel and 0.15 or 0.08, sel and 0.15 or 0.08, sel and 0.18 or 0.1, 1)
    b.dot:SetVertexColor(accent())
    b:SetBackdropColor(sel and th().ui[1] * 0.18 or 0, sel and th().ui[2] * 0.18 or 0, sel and th().ui[3] * 0.18 or 0, sel and 0.6 or 0.35)
    b:SetBackdropBorderColor(sel and th().ui[1] or 0.25, sel and th().ui[2] or 0.28, sel and th().ui[3] or 0.34, 1)
  end
  return b
end

PAGES[#PAGES + 1] = { key = 'build', name = 'Build', icon = 'Interface\\Icons\\INV_Misc_Book_11', build = function(p, db)
  local T = ns.Talents
  p.section('Smer talentu', 'Podle buildu addon radi talenty (tooltip v okne talentu + chat pri volnem bodu) a hodnoti gear.')
  local cards, cardKeys = {}, {}
  local MAXC = 5
  for i = 1, MAXC do
    local cd = buildCard(p.c)
    cd:SetScript('OnClick', function()
      if not T then return end
      local k = cardKeys[i]
      T.select(k ~= 'auto' and k or nil)
      p.refresh()
    end)
    cards[i] = cd
    p.add(cd, i == 1 and 6 or 4)
  end
  local warn = p.note('', 11)
  warn.fs:SetTextColor(1, 0.65, 0.3)

  p.section('Dalsi body podle vybraneho buildu')
  local nextLines = {}
  for i = 1, 3 do
    local f = CreateFrame('Frame', nil, p.c) f:SetSize(CW, 34)
    f.icon = f:CreateTexture(nil, 'ARTWORK') f.icon:SetSize(26, 26) f.icon:SetPoint('TOPLEFT', 0, -2)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.name = label(f, '', 12, 1, 0.85, 0.3) f.name:SetPoint('TOPLEFT', 34, -1)
    f.why = label(f, '', 10, 0.7, 0.72, 0.78) f.why:SetPoint('TOPLEFT', 34, -16) f.why:SetWidth(CW - 34)
    f.why:SetWordWrap(true) f.why:SetSpacing(1)
    nextLines[i] = f
    p.add(f, 4)
  end
  local none = p.note('', 11)

  p.row(button(p.c, 'Ulozit moje talenty', 150, function()
    if T and T.saveCustom() then T.select('custom') ns.say('Tvoje talenty ulozeny jako vlastni build.')
    else ns.say('Nemas zadne talenty k ulozeni.') end
    p.refresh()
  end, 'Ulozi talenty, ktere mas ted, jako vlastni build. Hodi se, kdyz si build skladas sam, nebo pred prestavbou u trenera.'),
  button(p.c, 'Smazat vlastni', 120, function()
    if db.talentBuild == 'custom' then T.select(nil) end
    db.customBuild = nil p.refresh()
  end, 'Smaze ulozeny vlastni build.'),
  button(p.c, 'Vypsat do chatu', 130, function() if T then T.say(true) end end, 'Dalsi 3 body do chatu (/cm talent).'))

  p.section('Vahy statu pro gear', 'Podle ceho se hodnoti itemy (sipky v batohu a tooltipu). Automaticky = podle buildu.')
  local CLASS_SPECS = { MAGE = { 'frost', 'fire', 'arcane' }, WARLOCK = { 'destro', 'affli', 'demo' },
    PALADIN = { 'ret', 'prot', 'holy' }, DRUID = { 'balance', 'feral', 'resto' },
    SHAMAN = { 'shhybrid', 'shresto', 'shele', 'shenh' }, HUNTER = { 'hunter' } }
  p.add(choice(p.c, 'Vahy', 'Vlastni vahy nastavis prikazem /cm vahy str=1 sta=0.5 ...', function()
    local o = { { 'auto', 'automaticky' } }
    for _, k in ipairs(CLASS_SPECS[ns.class] or {}) do
      local s = ns.Gear and ns.Gear.SPECS[k]
      if s then o[#o + 1] = { k, s.label } end
    end
    if db.gearWeights then o[#o + 1] = { 'custom', 'vlastni' } end
    return o
  end, function() return db.gearSpec or 'auto' end, function(v) if ns.Gear then ns.Gear.applySpec(v) end end))

  local nf = { refresh = function()
    if not T then return end
    pcall(ns.scanTalents)
    local list, cur, auto = T.list(), db.talentBuild, T.autoKey()
    cardKeys[1] = 'auto'
    for i, k in ipairs(list) do cardKeys[i + 1] = k end
    for i = 1, MAXC do
      local cd, k = cards[i], cardKeys[i]
      if i > #list + 1 then cd:Hide()
      else
        cd:Show()
        local b = k == 'auto' and T.get(auto) or T.get(k)
        if k == 'auto' then
          cd.title:SetText('Automaticky')
          cd.desc:SetText('Podle toho, kam davas body. Ted: ' .. (b and b.label or '?') .. '.')
          cd.tag:SetText('')
        else
          cd.title:SetText(b.label)
          cd.desc:SetText(b.desc or '')
          cd.tag:SetText(k == auto and (T.mainBand() and 'podle talentu' or 'vychozi') or '')
        end
        local have, total = T.progress(k == 'auto' and auto or k)
        cd.prog:SetText(total > 0 and ('%d / %d bodu'):format(have, total) or '')
        cd.set((k == 'auto' and cur == nil) or k == cur)
      end
    end
    -- jiny smer, nez kam mas body -> potreba prestavet talenty
    local key = T.buildKey()
    local off = T.offBuild(key)
    if off >= 3 and key ~= auto then
      warn.fs:SetText(('Mas %d bodu mimo tento build. Pro zmenu smeru si u trenera resetuj talenty - addon ti pak poradi body jeden po druhem.'):format(off))
    elseif off >= 3 then
      warn.fs:SetText(('%d bodu mas mimo build - nevadi, addon radi jen dalsi body.'):format(off))
      warn.fs:SetTextColor(0.6, 0.62, 0.68)
    else warn.fs:SetText('') end
    if key ~= auto then warn.fs:SetTextColor(1, 0.65, 0.3) end
    local nx = T.next(3)
    for i, f in ipairs(nextLines) do
      local r = nx[i]
      if r then
        local tex = r.e and r.e.spellId and C_Spell and C_Spell.GetSpellTexture and ns.safe(ns.pc(C_Spell.GetSpellTexture, r.e.spellId))
        f.icon:SetTexture(tex or 'Interface\\Icons\\INV_Misc_QuestionMark')
        f.name:SetText(('%s  |cffaaaaaa%d/%d|r%s'):format(r.name, r.cur, r.target, r.can and '  |cff55ee66- muzes hned|r' or ''))
        f.why:SetText(r.why)
        f:SetHeight(math.max(32, 18 + math.ceil(f.why:GetStringHeight()) + 2))
        f:Show()
      else f:Hide() end
    end
    if not ns.talentsRead then none.fs:SetText('Talenty se nepodarilo precist - otevri jednou okno talentu (N).')
    elseif #nx == 0 then none.fs:SetText('Build mas kompletni.')
    else none.fs:SetText(('Volne body: %d'):format(T.freePoints())) end
  end }
  p.items[#p.items + 1] = nf
end }

PAGES[#PAGES + 1] = { key = 'items', name = 'Veci a questy', icon = 'Interface\\Icons\\INV_Misc_Bag_08', build = function(p, db)
  p.section('Obchodnik')
  p.add(checkbox(p.c, 'Automaticky opravit', 'U obchodnika, ktery umi opravovat, opravi vybaveni.',
    function() return db.autoRepair ~= false end, function(v) db.autoRepair = (not v) and false or nil end))
  p.add(checkbox(p.c, 'Automaticky prodat sede veci', 'U obchodnika proda sedy junk. Ostatni oznacene veci prodas minci na okne obchodnika.',
    function() return db.autoSell ~= false end, function(v) db.autoSell = (not v) and false or nil end))
  p.section('Vybaveni', 'Addon hodnoti itemy podle vah statu tveho buildu (zalozka Build).')
  p.add(checkbox(p.c, 'Sipky a hodnoceni v batohu a tooltipu', 'Zelena sipka = lepsi pro tebe, v tooltipu o kolik %.',
    function() return db.gearTips ~= false end, function(v) db.gearTips = (not v) and false or nil
      if ns.Gear and ns.Gear.refreshBags then pcall(ns.Gear.refreshBags) end end))
  p.add(checkbox(p.c, 'Automaticky nasazovat lepsi veci', 'Mimo boj nasadi lepsi kus z batohu a napise do chatu, co vymenil. '
    .. 'Veci s neznamym efektem (Chance on hit apod.) necha na tobe.',
    function() return db.autoEquip end, function(v) db.autoEquip = v if v and ns.Gear and ns.Gear.queueAuto then ns.Gear.queueAuto(0.2) end end))
  p.add(slider(p.c, 'Jen kdyz je lepsi aspon o', 'Mala zlepseni nech byt - zabrani zbytecnemu prehazovani.', 1, 25, 1,
    function() return db.autoEquipPct or 5 end, function(v) db.autoEquipPct = v end, '%d %%'), 8, 24)
  p.add(checkbox(p.c, 'Nasazovat i BoE (navaze se)', 'Veci "Binds when equipped" se nasazenim navazou na postavu a uz je neprodas '
    .. 'na aukci ani nedas partakovi. Vypnuto = takove veci jen oznaci sipkou.',
    function() return db.autoEquipBoE end, function(v) db.autoEquipBoE = v end), 6, 24)

  p.add(checkbox(p.c, 'Pripominat Find Herbs / Find Minerals', 'Kdyz sledovani bylin nebo rud na minimape neni zapnute '
    .. '(typicky po smrti), ukaze se tip - klik ho zapne. Pravy klik na tip = skryt na 30 min.',
    function() return db.trackHint ~= false end, function(v) db.trackHint = (not v) and false or nil end), 12)
  p.add(checkbox(p.c, 'Kempy: co kemp dava a jestli se ti hodi', 'U ohne ukaze okenko s bonusy kempu (Camp Benefits) a u kazdeho, '
    .. 'jestli se ti hodi podle vah statu. V tooltipu vybaveni kempu napise jeho bonus, kdyz ho addon uz nekdy videl.',
    function() return db.campTip ~= false end, function(v) db.campTip = (not v) and false or nil
      if ns.Camp then pcall(ns.Camp.update) end end), 12)
  p.section('Questy pod minimapou')
  p.add(checkbox(p.c, 'Jen questy z aktualni oblasti', 'Seznam ukaze jen questy z mista, kde jsi.',
    function() return db.questZone == true end, function(v) db.questZone = v questsUpd() end))
  p.add(checkbox(p.c, 'Radit podle vzdalenosti', 'Nejblizsi quest nahore.',
    function() return db.questSort == true end, function(v) db.questSort = v questsUpd() end))
  p.add(checkbox(p.c, 'Varovat pred odletem', 'Pri otevreni mapy letu napise, ktere questy v teto oblasti jeste zbyva odevzdat '
    .. 'nebo dokoncit (potrebuje addon ForeverDB).',
    function() return db.routeWarn ~= false end, function(v) db.routeWarn = (not v) and false or nil end))
  p.row(button(p.c, 'Trasa questu', 130, function() if ns.Route then ns.Route.toggle() end end,
    'Poradi zastavek s nejkratsi cestou, navazujici questy a questy po ceste (/cm trasa). Potrebuje addon ForeverDB.'))
  p.row(button(p.c, 'Zobrazit / skryt questy', 170, function() if ns.Quests then ns.Quests.toggle('') end end, '/cm questy'),
    button(p.c, 'Sdilet questy s partou', 170, function() if ns.Quests and ns.Quests.shareAll then ns.Quests.shareAll() end end, '/cm sdilej'))
end }

PAGES[#PAGES + 1] = { key = 'explore', name = 'Pruzkumnik', icon = 'Interface\\Icons\\INV_Misc_Map_01', build = function(p, db)
  p.section('Pruzkumnik', 'Hledani a chytre filtry nad databazi ForeverDB. Klik na vysledek = sipka na mape.')
  local status = p.note('', 11)
  local function setStatus(t) status.fs:SetText(t or '') status.fit() p.layout() end
  -- hledani s lupou
  local eb = CreateFrame('EditBox', nil, p.c, 'BackdropTemplate')
  eb:SetSize(CW, 28) eb:SetAutoFocus(false)
  eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  eb:SetBackdropColor(0, 0, 0, 0.55) eb:SetBackdropBorderColor(0.3, 0.34, 0.42, 1)
  eb:SetFont(FONT, 12, '') eb:SetTextInsets(28, 8, 0, 0) eb:SetTextColor(1, 1, 1)
  local mag = eb:CreateTexture(nil, 'ARTWORK')
  mag:SetTexture('Interface\\Common\\UI-Searchbox-Icon') mag:SetSize(14, 14) mag:SetPoint('LEFT', 9, -1) mag:SetVertexColor(0.7, 0.75, 0.85)
  eb.hint = label(eb, 'Hledat quest, NPC nebo item...   |cff667080z:tanaris = questy v oblasti|r', 11, 0.5, 0.52, 0.58)
  eb.hint:SetPoint('LEFT', 28, 0)
  eb:SetScript('OnEditFocusGained', function() eb:SetBackdropBorderColor(accent()) end)
  eb:SetScript('OnEditFocusLost', function() eb:SetBackdropBorderColor(0.3, 0.34, 0.42, 1) end)
  p.add(eb, 8)
  -- filtry (aktivni zvyrazneny)
  local filters, active = {}, nil
  local function paint(b)
    if b == active then b:SetBackdropColor(accent(0.45)) b:SetBackdropBorderColor(accent(1))
    else b:SetBackdropColor(accent(0.12)) b:SetBackdropBorderColor(accent(0.5)) end
  end
  local function activate(b) active = b for _, f in ipairs(filters) do paint(f) end end
  -- hlavicka vysledku
  local head = CreateFrame('Frame', nil, p.c) head:SetSize(CW, 22)
  head.t = label(head, '', 11, 0.75, 0.78, 0.85) head.t:SetPoint('BOTTOMLEFT', 2, 5)
  local back = button(head, '< Zpet', 64, function() end, 'Zpet na predchozi seznam.')
  back:SetHeight(18) back:SetPoint('BOTTOMRIGHT', 0, 3) back:Hide()
  local line = head:CreateTexture(nil, 'ARTWORK') line:SetTexture(WHITE) line:SetHeight(1)
  line:SetPoint('BOTTOMLEFT') line:SetPoint('BOTTOMRIGHT') line:SetVertexColor(accent(0.35))
  -- radky vysledku (karty)
  local rows, RH = {}, 34
  local stack, cur = {}, nil
  local show
  local function view(list, what, push)
    if push and cur then stack[#stack + 1] = cur else if not push then stack = {} end end
    cur = { list = list, what = what }
    show(list, what)
  end
  back:SetScript('OnClick', function()
    local prev = table.remove(stack)
    if prev then cur = prev show(prev.list, prev.what) end
  end)
  function show(list, what)
    back:SetShown(#stack > 0)
    local n = 0
    for _, l in ipairs(list or {}) do if l.title then n = n + 1 end end
    head.t:SetText(what and ('|cffffffff%s|r   |cff8a93a6%d vysledku|r'):format(what, n) or '')
    local odd = false
    for i, r in ipairs(rows) do
      local l = list and list[i]
      r.p, r.link, r.tipText, r.open = nil, nil, nil, nil
      r.arrow:Hide()
      if not l then r:Hide()
      elseif l.head then
        r:SetHeight(24) r.kind = 'head'
        r.icon:Hide() r.sub:SetText('') r.right:SetText('') r.right2:SetText('') r.bar:Hide() r.bg:Hide() r.stripe:Hide()
        r.title:ClearAllPoints() r.title:SetPoint('BOTTOMLEFT', 2, 4)
        r.title:SetText(l.head) r.title:SetTextColor(accent())
        odd = false r:Show()
      elseif not l.title then
        r:SetHeight(26) r.kind = 'msg'
        r.icon:Hide() r.sub:SetText('') r.right:SetText('') r.right2:SetText('') r.bar:Hide() r.bg:Hide() r.stripe:Hide()
        r.title:ClearAllPoints() r.title:SetPoint('LEFT', 8, 0) r.title:SetText(l.text or '') r.title:SetTextColor(1, 1, 1)
        r:Show()
      else
        r:SetHeight(RH) r.kind = 'item'
        odd = not odd
        r.bg:Show() r.bg:SetColorTexture(1, 1, 1, odd and 0.035 or 0.012)
        r.stripe:Hide()
        r.icon:SetTexture(l.icon or 'Interface\\Icons\\INV_Misc_QuestionMark') r.icon:Show()
        r.title:ClearAllPoints() r.title:SetPoint('TOPLEFT', 36, -4) r.title:SetText(l.title) r.title:SetTextColor(1, 1, 1)
        r.sub:SetText(l.sub or '')
        r.right:SetText(l.right or '') r.right2:SetText(l.right2 or '')
        local rw = math.max(r.right:GetStringWidth(), r.right2:GetStringWidth())
        local tw = CW - 48 - rw - 10 - (l.open and 12 or 0)
        r.title:SetWidth(tw) r.sub:SetWidth(tw)
        if l.bar then r.bar:SetWidth(math.max(2, CW * math.min(1, l.bar))) r.bar:Show() else r.bar:Hide() end
        r.p, r.link, r.tipText, r.open = l.p, l.link, l.tip, l.open
        r.arrow:SetShown(l.open ~= nil)
        if l.open then r.right:SetPoint('TOPRIGHT', -20, -4) r.right2:SetPoint('BOTTOMRIGHT', -20, 4)
        else r.right:SetPoint('TOPRIGHT', -8, -4) r.right2:SetPoint('BOTTOMRIGHT', -8, 4) end
        r:Show()
      end
    end
    p.layout()
    p.sf:SetVerticalScroll(0)
    p.upd()
  end
  local function ready()
    local R = ns.Route
    if R and R.DB() then return true end
    if not (R and R.available()) then
      setStatus('|cffff8855Tahle funkce potrebuje addon ForeverDB - nainstaluj ho vedle ClaudeMasteru.|r') return false
    end
    ns.say('Nacitam ForeverDB (chvili to muze seknout)...')
    local ok, why = R.load()
    if not ok then setStatus('|cffff8855ForeverDB se nepodarilo nacist: ' .. tostring(why) .. '|r') return false end
    setStatus('')
    return true
  end
  -- z jinych oken (trasa questu): ukaz seznam / detail
  O.exploreShow = function(list, what)
    if not list or not ready() then return end
    activate(nil)
    view(list, what or '')
  end
  local pend
  eb:SetScript('OnTextChanged', function(self)
    eb.hint:SetShown(self:GetText() == '')
    if pend or not C_Timer then return end
    pend = true
    C_Timer.After(0.4, function()
      pend = false
      local t = eb:GetText()
      if #t >= 3 and ready() then activate(nil) view(ns.Explore.search(t), 'Hledani: ' .. t) end
    end)
  end)
  eb:SetScript('OnEscapePressed', eb.ClearFocus)
  eb:SetScript('OnEnterPressed', eb.ClearFocus)
  local function filter(text, w, what, fn, desc)
    local b
    b = button(p.c, text, w, function()
      if not ready() then return end
      activate(b)
      view(fn(function(list) if active == b and cur and cur.what == what then cur.list = list show(list, what) end end), what)
    end, desc)
    b:HookScript('OnLeave', function() paint(b) end)
    filters[#filters + 1] = b
    return b
  end
  p.row(filter('Kde levelit', 110, 'Kde levelit', function() return ns.Explore.leveling() end,
      'Oblasti s nejvic questy pro tvuj level a kolik XP daji.'),
    filter('Dropy pro tebe', 120, 'Dropy pro tebe', function(cb) return ns.Explore.drops(cb) end,
      'Zelene a lepsi itemy z mobu tveho levelu, ktere jsou pro tebe vylepsenim (podle vah gearu). Pocita se par vterin.'),
    filter('Blizko', 80, 'Blizko', function() return ns.Explore.nearby() end, 'Questy k vzeti a rare moby pobliz.'),
    filter('Moje questy', 100, 'Moje questy', function() return ns.Explore.active() end,
      'Questy v logu: hotove k odevzdani nahore, pak rozpracovane podle vzdalenosti. Klik = detail (cile, retez, co odemkne).'),
    button(p.c, 'Trasa questu', 110, function() if ns.Route then ns.Route.toggle() end end, 'Okno s trasou questu (/cm trasa).'))
  p.add(checkbox(p.c, 'Data ForeverDB v tooltipech', 'Dropy mobu, penize a itemy zacinajici quest z ForeverDB. Addon si z databaze jednou udela malou cache (po prihlaseni, jen pri nove verzi ForeverDB) - cela databaze se pak drzi v pameti jen pri pouziti Pruzkumnika / trasy.',
    function() return db.fdbAuto ~= false end, function(v) db.fdbAuto = v end), 8)
  p.add(head, 6)
  for i = 1, 30 do
    local r = CreateFrame('Button', nil, p.c)
    r:SetSize(CW, RH)
    r.bg = r:CreateTexture(nil, 'BACKGROUND') r.bg:SetAllPoints()
    r.stripe = r:CreateTexture(nil, 'ARTWORK') r.stripe:SetTexture(WHITE) r.stripe:SetWidth(2)
    r.stripe:SetPoint('TOPLEFT') r.stripe:SetPoint('BOTTOMLEFT') r.stripe:SetVertexColor(accent(1))
    r.icon = r:CreateTexture(nil, 'ARTWORK') r.icon:SetSize(26, 26) r.icon:SetPoint('LEFT', 5, 0) r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.title = label(r, '', 12) r.title:SetWordWrap(false)
    r.sub = label(r, '', 10, 0.55, 0.59, 0.67) r.sub:SetPoint('BOTTOMLEFT', 36, 4) r.sub:SetWordWrap(false)
    r.right = label(r, '', 11) r.right:SetPoint('TOPRIGHT', -8, -4) r.right:SetJustifyH('RIGHT')
    r.right2 = label(r, '', 10, 0.55, 0.59, 0.67) r.right2:SetPoint('BOTTOMRIGHT', -8, 4) r.right2:SetJustifyH('RIGHT')
    r.bar = r:CreateTexture(nil, 'BACKGROUND', nil, 1) r.bar:SetTexture(WHITE)
    r.bar:SetPoint('TOPLEFT', 0, 0) r.bar:SetPoint('BOTTOMLEFT', 0, 0) r.bar:SetVertexColor(1, 0.82, 0, 0.07)
    r.hl = r:CreateTexture(nil, 'HIGHLIGHT') r.hl:SetAllPoints() r.hl:SetColorTexture(1, 1, 1, 0.07)
    r.arrow = label(r, '>', 14, 0.55, 0.6, 0.7) r.arrow:SetPoint('RIGHT', -6, 0) r.arrow:Hide()
    r:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    r:SetScript('OnClick', function(self, btn)
      if btn ~= 'RightButton' and self.open then
        local list, what = self.open()
        view(list, what or '', true)
        return
      end
      if self.p and ns.Route then
        local t = (self.title:GetText() or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        ns.Route.waypoint(self.p, t)
      end
    end)
    r:SetScript('OnEnter', function(self)
      if self.kind ~= 'item' then return end
      self.stripe:Show()
      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      if self.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
      else GameTooltip:AddLine(self.title:GetText() or '', 1, 1, 1, true) GameTooltip:AddLine(self.sub:GetText() or '', 0.7, 0.7, 0.7, true) end
      if self.tipText then GameTooltip:AddLine(self.tipText, 0.8, 0.8, 0.8, true) end
      if self.open then GameTooltip:AddLine('Klik = detail' .. (self.p and ', pravy klik = sipka na mape' or ''), 0.55, 0.85, 1)
      elseif self.p then GameTooltip:AddLine('Klik = sipka na mape', 0.55, 0.85, 1) end
      GameTooltip:Show()
    end)
    r:SetScript('OnLeave', function(self) self.stripe:Hide() GameTooltip:Hide() end)
    r:Hide()
    rows[i] = r
    p.add(r, 0)
  end
  if not (ns.Route and ns.Route.available()) then
    setStatus('|cffff8855Pruzkumnik potrebuje addon ForeverDB (data o questech, NPC a dropech). Zbytek addonu funguje i bez nej.|r')
  else
    head.t:SetText('|cff8a93a6Zvol filtr nebo zacni psat.|r')
  end
end }

PAGES[#PAGES + 1] = { key = 'memory', name = 'Pamet a uceni', icon = 'Interface\\Icons\\INV_Misc_Note_05', build = function(p, db)
  p.section('Uceni z hrani', 'Addon si pamatuje, jak hrajes, a podle toho upravuje rady (nerusive, v shrnuti po boji).')
  p.add(checkbox(p.c, 'Ucit se z meho hrani', 'Napr. kdyz strhnes aggro, priste doporuci AoE pozdeji.',
    function() return db.learn end, function(v) db.learn = v end))
  p.row(button(p.c, 'Co se naucil', 130, function() if ns.Mem then ns.Mem.report() end end, 'Vypise do chatu (/cm learn).'),
    button(p.c, 'Posledni shrnuti', 140, function()
      if db.lastFight then ns.UI.showSummary(db.lastFight) else ns.say('zatim zadny boj') end
    end, 'Znovu ukaze shrnuti posledniho boje.'))
  p.section('Smazat data', 'Nevratne - addon se pak uci znovu od zacatku.')
  p.row(button(p.c, 'Zapomenout uceni', 140, function() db.learnData = {} ns.say('uceni smazano') end),
    button(p.c, 'Smazat pamet mobu', 150, function() db.mobs, db.memGlobal = {}, nil ns.say('pamet mobu smazana') end),
    button(p.c, 'Smazat imunity', 120, function() db.immune = {} ns.say('naucene imunity smazany') end))
  p.section('Ladeni')
  p.add(checkbox(p.c, 'Ladici vypisy (debug)', 'Do chatu pise podrobnosti o rozhodovani. Jen pro hledani chyb.',
    function() return db.debug end, function(v) db.debug = v end))
  p.row(button(p.c, 'Ulozit vypis (dump)', 150, function() ns.fullDump() end, 'Ulozi vse potrebne k doladeni do SavedVariables (/cm dump).'),
    button(p.c, 'Znovu nacist kouzla', 150, function()
      if ns.inCombat() then ns.say('az po boji') else ns.scanSpells() ns.say('nacteno') end
    end, '/cm rescan'))
end }

------------------------------------------------------------------------------------------
-- Okno
------------------------------------------------------------------------------------------
local function build()
  if O.frame then return O.frame end
  local db = ns.db
  local T = th()
  local f = CreateFrame('Frame', 'ClaudeMasterOptions', UIParent, 'BackdropTemplate')
  O.frame = f
  -- ulozena velikost (roztahuje se za roh vpravo dole)
  W = math.max(520, math.min(1100, db.optW or W))
  H = math.max(360, math.min(900, db.optH or H))
  CW = W - NAV - 44
  f:SetSize(W, H)
  f:SetPoint('CENTER')
  f:SetFrameStrata('DIALOG')
  f:SetToplevel(true)
  f:SetMovable(true) f:EnableMouse(true) f:SetClampedToScreen(true)
  backdrop(f, { T.bg[1], T.bg[2], T.bg[3], 0.97 }, T.border)
  tinsert(UISpecialFrames, 'ClaudeMasterOptions')   -- zavira se klavesou Esc

  -- hlavicka (tahani okna)
  local head = CreateFrame('Frame', nil, f, 'BackdropTemplate')
  head:SetPoint('TOPLEFT', 1, -1) head:SetPoint('TOPRIGHT', -1, -1) head:SetHeight(40)
  backdrop(head, { T.ui[1] * 0.15, T.ui[2] * 0.15, T.ui[3] * 0.15, 0.9 }, { 0, 0, 0, 0 })
  head:EnableMouse(true) head:RegisterForDrag('LeftButton')
  head:SetScript('OnDragStart', function() f:StartMoving() end)
  head:SetScript('OnDragStop', function() f:StopMovingOrSizing() end)
  local ic = head:CreateTexture(nil, 'ARTWORK') ic:SetSize(26, 26) ic:SetPoint('LEFT', 10, 0)
  ic:SetTexture(T.icon) ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local title = label(head, 'ClaudeMaster', 15, unpack(T.title)) title:SetPoint('LEFT', ic, 'RIGHT', 10, 6)
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and ns.pc(C_AddOns.GetAddOnMetadata, ADDON, 'Version'))
    or (GetAddOnMetadata and ns.pc(GetAddOnMetadata, ADDON, 'Version')) or ''
  local CLASS_CZ = { MAGE = 'Mag', WARLOCK = 'Warlock', PALADIN = 'Paladin', DRUID = 'Druid', SHAMAN = 'Shaman', HUNTER = 'Hunter' }
  local sub = label(head, ('Nastaveni  -  %s  -  v%s'):format(CLASS_CZ[ns.class] or ns.class, ns.safe(ver) or '?'), 10, 0.6, 0.62, 0.68)
  sub:SetPoint('LEFT', ic, 'RIGHT', 10, -8)
  local line = f:CreateTexture(nil, 'ARTWORK') line:SetTexture(WHITE) line:SetHeight(1)
  line:SetPoint('TOPLEFT', head, 'BOTTOMLEFT') line:SetPoint('TOPRIGHT', head, 'BOTTOMRIGHT') line:SetVertexColor(accent(0.5))
  local close = CreateFrame('Button', nil, head)
  close:SetSize(24, 24) close:SetPoint('RIGHT', -8, 0)
  close.t = label(close, 'x', 20, 0.7, 0.7, 0.75) close.t:SetPoint('CENTER', 0, 1)
  close:SetScript('OnEnter', function() close.t:SetTextColor(1, 0.4, 0.4) end)
  close:SetScript('OnLeave', function() close.t:SetTextColor(0.7, 0.7, 0.75) end)
  close:SetScript('OnClick', function() f:Hide() end)

  -- leva lista
  local nav = CreateFrame('Frame', nil, f, 'BackdropTemplate')
  nav:SetPoint('TOPLEFT', 1, -42) nav:SetPoint('BOTTOMLEFT', 1, 1) nav:SetWidth(NAV)
  backdrop(nav, { 0, 0, 0, 0.25 }, { 0, 0, 0, 0 })
  local sep = f:CreateTexture(nil, 'ARTWORK') sep:SetTexture(WHITE) sep:SetWidth(1)
  sep:SetPoint('TOPLEFT', nav, 'TOPRIGHT') sep:SetPoint('BOTTOMLEFT', nav, 'BOTTOMRIGHT') sep:SetVertexColor(accent(0.25))
  local foot = label(nav, '/cm help - prikazy', 9, 0.45, 0.47, 0.52) foot:SetPoint('BOTTOMLEFT', 10, 8)

  -- obsah
  local host = CreateFrame('Frame', nil, f)
  host:SetPoint('TOPLEFT', nav, 'TOPRIGHT', 18, -14) host:SetPoint('BOTTOMRIGHT', -24, 12)

  local tabs, pages = {}, {}
  local function select(key)
    db.optTab = key
    for _, pg in ipairs(PAGES) do
      local on = pg.key == key
      local tb = tabs[pg.key]
      tb.sel:SetShown(on) tb.bar:SetShown(on)
      tb.text:SetTextColor(on and 1 or 0.72, on and 1 or 0.74, on and 1 or 0.8)
      if on then
        if not pages[key] then
          pages[key] = newPage(host)
          local ok, err = pcall(pg.build, pages[key], db)
          if not ok then ns.say('chyba v nastaveni (' .. pg.name .. '): ' .. tostring(err)) end
        end
        pages[key].sf:Show() pages[key].refresh()
      elseif pages[pg.key] then pages[pg.key].sf:Hide() end
    end
  end
  for i, pg in ipairs(PAGES) do
    local tb = CreateFrame('Button', nil, nav)
    tb:SetSize(NAV, 34) tb:SetPoint('TOPLEFT', 0, -8 - (i - 1) * 36)
    tb.sel = tb:CreateTexture(nil, 'BACKGROUND') tb.sel:SetAllPoints() tb.sel:SetColorTexture(accent(0.16))
    tb.hl = tb:CreateTexture(nil, 'HIGHLIGHT') tb.hl:SetAllPoints() tb.hl:SetColorTexture(1, 1, 1, 0.05)
    tb.bar = tb:CreateTexture(nil, 'ARTWORK') tb.bar:SetPoint('TOPLEFT') tb.bar:SetPoint('BOTTOMLEFT') tb.bar:SetWidth(3)
    tb.bar:SetColorTexture(accent())
    tb.icon = tb:CreateTexture(nil, 'ARTWORK') tb.icon:SetSize(20, 20) tb.icon:SetPoint('LEFT', 12, 0)
    tb.icon:SetTexture(pg.icon) tb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tb.text = label(tb, pg.name, 12) tb.text:SetPoint('LEFT', tb.icon, 'RIGHT', 9, 0)
    tb:SetScript('OnClick', function() select(pg.key) end)
    tabs[pg.key] = tb
  end
  f.select = select

  -- roztahovani: tah za roh; obsah se po pusteni prestavi na novou sirku. Dvojklik = puvodni velikost.
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(520, 360, 1100, 900)
  elseif f.SetMinResize then f:SetMinResize(520, 360) f:SetMaxResize(1100, 900) end
  local function rebuild()
    W, H = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
    db.optW, db.optH = W, H
    CW = W - NAV - 44
    for k, pg in pairs(pages) do pg.sf:Hide() pages[k] = nil end
    select(db.optTab or PAGES[1].key)
  end
  local grip = CreateFrame('Button', nil, f)
  grip:SetSize(16, 16) grip:SetPoint('BOTTOMRIGHT', -2, 2) grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
  grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
  grip:SetScript('OnMouseDown', function() f:StartSizing('BOTTOMRIGHT') end)
  grip:SetScript('OnMouseUp', function() f:StopMovingOrSizing() rebuild() end)
  grip:SetScript('OnDoubleClick', function() f:SetSize(600, 480) rebuild() end)
  tip(grip, 'Velikost okna', 'Tahni za roh. Dvojklik = puvodni velikost.')
  f:SetScript('OnShow', function()
    local k = db.optTab
    local ok = false
    for _, pg in ipairs(PAGES) do if pg.key == k then ok = true end end
    select(ok and k or PAGES[1].key)
  end)
  f:Hide()
  return f
end

function O.toggle(tab)
  if not ns.db then return end
  local f = build()
  if tab then ns.db.optTab = tab end
  if f:IsShown() and not tab then f:Hide() else f:Hide() f:Show() end
end

------------------------------------------------------------------------------------------
-- Tlacitko u minimapy: levy klik = nastaveni, pravy = panel, tahem po okraji
------------------------------------------------------------------------------------------
local function placeMinimap(b)
  local a = math.rad((ns.db.minimap and ns.db.minimap.angle) or 215)
  local x, y = math.cos(a), math.sin(a)
  local r = (Minimap:GetWidth() / 2) + 5
  local shape = GetMinimapShape and GetMinimapShape() or 'ROUND'
  if shape == 'SQUARE' then
    -- ctvercova minimapa: po obvodu ctverce
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m * 0.92, y / m * 0.92
  end
  b:ClearAllPoints()
  b:SetPoint('CENTER', Minimap, 'CENTER', x * r, y * r)
end

function O.updateMinimap()
  local db = ns.db
  if not db or not Minimap then return end
  db.minimap = db.minimap or {}
  local b = O.mini
  if not b then
    b = CreateFrame('Button', 'ClaudeMasterMinimapButton', Minimap)
    O.mini = b
    b:SetSize(31, 31) b:SetFrameStrata('MEDIUM') b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    b:RegisterForClicks('LeftButtonUp', 'RightButtonUp') b:RegisterForDrag('LeftButton')
    local bg = b:CreateTexture(nil, 'BACKGROUND') bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background')
    bg:SetSize(20, 20) bg:SetPoint('TOPLEFT', 7, -5)
    local icon = b:CreateTexture(nil, 'ARTWORK') icon:SetTexture(th().icon) icon:SetSize(18, 18) icon:SetPoint('TOPLEFT', 7, -6)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    b.icon = icon
    local border = b:CreateTexture(nil, 'OVERLAY') border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(53, 53) border:SetPoint('TOPLEFT')
    b:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    b:SetScript('OnClick', function(_, btn)
      if btn == 'RightButton' then
        O.togglePanel()
        ns.say(ns.db.shown and 'panel zobrazen' or 'panel skryt')
      else O.toggle() end
    end)
    b:SetScript('OnMouseDown', function() icon:SetPoint('TOPLEFT', 8, -7) end)
    b:SetScript('OnMouseUp', function() icon:SetPoint('TOPLEFT', 7, -6) end)
    b:SetScript('OnDragStart', function()
      b:LockHighlight()
      b:SetScript('OnUpdate', function()
        local mx, my = Minimap:GetCenter()
        local s = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / s, cy / s
        ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
        placeMinimap(b)
      end)
    end)
    b:SetScript('OnDragStop', function() b:SetScript('OnUpdate', nil) b:UnlockHighlight() end)
    b:SetScript('OnEnter', function(self)
      GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
      GameTooltip:AddLine('ClaudeMaster', unpack(th().title))
      local bl = ns.Talents and ns.Talents.build and ns.Talents.build()
      if bl then GameTooltip:AddLine('Build: ' .. bl.label, 0.8, 0.8, 0.8) end
      GameTooltip:AddLine(' ')
      GameTooltip:AddDoubleLine('Levy klik', 'nastaveni', 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine('Pravy klik', ns.db.shown and 'skryt panel' or 'zobrazit panel', 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine('Tahnout', 'posunout tlacitko', 1, 0.82, 0, 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  end
  placeMinimap(b)
  b:SetShown(not db.minimap.hide)
end

-- GW2 UI a jine addony meni velikost / tvar minimapy az po prihlaseni -> pozici prepocitat znovu
local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN')
ev:RegisterEvent('PLAYER_ENTERING_WORLD')
local hooked = false
ev:SetScript('OnEvent', function()
  pcall(O.updateMinimap)
  if C_Timer then
    C_Timer.After(2, function() pcall(O.updateMinimap) end)
    C_Timer.After(8, function() pcall(O.updateMinimap) end)
  end
  if not hooked and Minimap and Minimap.HookScript then
    hooked = true
    Minimap:HookScript('OnSizeChanged', function() if O.mini then pcall(placeMinimap, O.mini) end end)
  end
end)

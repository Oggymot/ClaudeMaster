-- ClaudeMaster: okno s nastavenim (/cm config)
local ADDON, ns = ...
if not ns.enabled then return end

local O = {}
ns.Options = O

local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local W = 300

local function label(parent, text, size, r, g, b)
  local fs = parent:CreateFontString(nil, 'OVERLAY')
  fs:SetFont(FONT, size or 11, 'OUTLINE')
  fs:SetTextColor(r or 0.85, g or 0.9, b or 1)
  fs:SetText(text)
  return fs
end

-- zaskrtavatko: vlastni (nezavisle na sablonach, ktere se mezi verzemi meni)
local function checkbox(parent, text, get, set)
  local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
  b:SetSize(W - 32, 18)
  b.box = CreateFrame('Frame', nil, b, 'BackdropTemplate')
  b.box:SetSize(14, 14) b.box:SetPoint('LEFT', 0, 0)
  b.box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b.box:SetBackdropColor(0, 0, 0, 0.6) b.box:SetBackdropBorderColor(0.35, 0.45, 0.6, 1)
  b.mark = b.box:CreateTexture(nil, 'OVERLAY')
  b.mark:SetTexture(WHITE) b.mark:SetPoint('TOPLEFT', 3, -3) b.mark:SetPoint('BOTTOMRIGHT', -3, 3)
  b.mark:SetVertexColor(unpack(ns.THEME.ui))
  b.text = label(b, text, 11) b.text:SetPoint('LEFT', b.box, 'RIGHT', 6, 0)
  function b.refresh() b.mark:SetShown(get() and true or false) end
  b:SetScript('OnClick', function() set(not get()) b.refresh() end)
  b.refresh()
  return b
end

-- posuvnik: vlastni
local function slider(parent, text, minV, maxV, step, get, set, fmt)
  local h = CreateFrame('Frame', nil, parent)
  h:SetSize(W - 32, 34)
  h.text = label(h, text, 11) h.text:SetPoint('TOPLEFT', 0, 0)
  h.val = label(h, '', 11, 1, 1, 1) h.val:SetPoint('TOPRIGHT', 0, 0)
  local s = CreateFrame('Slider', nil, h, 'BackdropTemplate')
  s:SetOrientation('HORIZONTAL')
  s:SetPoint('TOPLEFT', 0, -16) s:SetPoint('TOPRIGHT', 0, -16) s:SetHeight(12)
  s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  s:SetBackdropColor(0, 0, 0, 0.6) s:SetBackdropBorderColor(0.3, 0.38, 0.5, 1)
  s:SetThumbTexture(WHITE)
  local th = s:GetThumbTexture()
  th:SetSize(10, 14) th:SetVertexColor(unpack(ns.THEME.ui))
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local busy = false
  function h.refresh()
    busy = true
    s:SetValue(get())
    h.val:SetText((fmt or '%s'):format(get()))
    busy = false
  end
  s:SetScript('OnValueChanged', function(_, v)
    if busy then return end
    v = math.floor(v / step + 0.5) * step
    set(v)
    h.val:SetText((fmt or '%s'):format(get()))
  end)
  h.refresh()
  return h
end

-- prepinac: klik = dalsi moznost, pravy klik = predchozi
local function cycler(parent, text, opts, get, set)
  local h = CreateFrame('Frame', nil, parent)
  h:SetSize(W - 32, 20)
  h.text = label(h, text, 11) h.text:SetPoint('LEFT', 0, 0)
  local b = CreateFrame('Button', nil, h, 'BackdropTemplate')
  b:SetSize(130, 18) b:SetPoint('RIGHT', 0, 0)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b:SetBackdropColor(0, 0, 0, 0.6) b:SetBackdropBorderColor(unpack(ns.THEME.border))
  b.val = label(b, '', 11, 1, 1, 1) b.val:SetPoint('CENTER')
  b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  local function idx()
    local cur = get() or 'auto'
    for i, o in ipairs(opts) do if o[1] == cur then return i end end
    return 1
  end
  function h.refresh() b.val:SetText(opts[idx()][2]) end
  b:SetScript('OnClick', function(_, btn)
    local i = idx() + (btn == 'RightButton' and -1 or 1)
    if i > #opts then i = 1 elseif i < 1 then i = #opts end
    set(opts[i][1]) h.refresh()
  end)
  h.refresh()
  return h
end

local function build()
  if O.frame then return O.frame end
  local db = ns.db
  local f = CreateFrame('Frame', 'ClaudeMasterOptions', UIParent, 'BackdropTemplate')
  O.frame = f
  f:SetSize(W, 100)
  f:SetPoint('CENTER')
  f:SetFrameStrata('DIALOG')
  f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag('LeftButton') f:SetClampedToScreen(true)
  f:SetScript('OnDragStart', f.StartMoving) f:SetScript('OnDragStop', f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(ns.THEME.bg[1], ns.THEME.bg[2], ns.THEME.bg[3], 0.95) f:SetBackdropBorderColor(unpack(ns.THEME.border))
  tinsert(UISpecialFrames, 'ClaudeMasterOptions')   -- zavira se klavesou Esc

  local title = label(f, 'ClaudeMaster - nastaveni', 13, unpack(ns.THEME.title))
  title:SetPoint('TOPLEFT', 12, -10)
  local close = CreateFrame('Button', nil, f, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', 2, 2)

  local items = {}
  local function add(w, gap) items[#items + 1] = { w = w, gap = gap or 4 } end
  local function pct(key) return function() return math.floor((db[key] or 0) * 100 + 0.5) end, function(v) db[key] = v / 100 end end

  add(checkbox(f, 'Zamknout panel (nejde tahat)', function() return db.locked end,
    function(v) db.locked = v if ns.UI.frame then ns.UI.frame:EnableMouse(not v) end end), 10)
  if ns.class == 'MAGE' then
    add(checkbox(f, 'Ice Barrier pred pullem', function() return db.prebarrier end, function(v) db.prebarrier = v end))
  end
  add(checkbox(f, 'Zvuk u nalehavych veci', function() return db.sound end, function(v) db.sound = v end))
  add(checkbox(f, 'Shrnuti po boji', function() return db.summary end, function(v) db.summary = v end))
  add(checkbox(f, 'Mimo boj schovat okno, kdyz neni co delat', function() return db.hideIdle end, function(v) db.hideIdle = v end))
  add(checkbox(f, 'Znacky u jmenovek nepratel (kdo bije, na koho jde, CC, preruseni)', function() return db.plates ~= false end, function(v) db.plates = v end))
  add(checkbox(f, 'Lista se znackami ve skupine (lebka / mesic / smazat)', function() return db.markBarOn == true end,
    function(v) db.markBarOn = v if ns.Assist then ns.Assist.applyVisibility() end end))
  add(checkbox(f, 'Questy pod minimapou: jen z aktualni oblasti', function() return db.questZone == true end,
    function(v) db.questZone = v if ns.Quests then ns.Quests.last = 0 ns.Quests.update() end end))
  add(checkbox(f, 'Questy pod minimapou: radit podle vzdalenosti', function() return db.questSort == true end,
    function(v) db.questSort = v if ns.Quests then ns.Quests.last = 0 ns.Quests.update() end end))
  add(checkbox(f, 'V tooltipu nepritele: co si addon o mobovi pamatuje', function() return db.tipMob ~= false end, function(v) db.tipMob = v end))
  if ns.class == 'WARLOCK' then
    add(checkbox(f, 'Multi-DoT: radit DoTy i na dalsi moby (tab)', function() return db.multiDot ~= false end, function(v) db.multiDot = v end))
  end
  add(checkbox(f, 'Ucit se z meho hrani', function() return db.learn end, function(v) db.learn = v end))
  add(checkbox(f, 'Kompaktni: jen ikony (duvod v tooltipu)', function() return db.compact end, function(v) db.compact = v end))
  add(checkbox(f, 'Text doporuceni', function() return db.showReason end, function(v) db.showReason = v end))
  add(checkbox(f, 'Info radky (moby, cil, stavy)', function() return db.showInfo end, function(v) db.showInfo = v end))

  add(slider(f, 'AoE od kolika mobu', 2, 6, 1, function() return db.aoe end, function(v) db.aoe = v end, '%d'), 10)
  local g, s = pct('drinkMana') add(slider(f, 'Pit mimo boj pod (% many)', 20, 90, 5, g, s, '%d %%'))
  g, s = pct('gemMana') add(slider(f, 'Mana gem v boji pod (% many)', 20, 90, 5, g, s, '%d %%'))
  g, s = pct('wandMana') add(slider(f, 'Wand pod (% many)', 0, 30, 1, g, s, '%d %%'))
  g, s = pct('conserveMana') add(slider(f, 'Setrit manou pod (% many)', 10, 60, 5, g, s, '%d %%'))
  add(slider(f, 'Parta: pockat na tanka po pullu (s)', 0, 4, 0.5, function() return db.tankWait end,
    function(v) db.tankWait = v end, '%.1f s'))
  add(slider(f, 'Parta: AoE az po (s) - uci se samo', 0, 8, 0.5, function() return db.aoeDelay end,
    function(v) db.aoeDelay = v end, '%.1f s'))
  if ns.class == 'WARLOCK' then
    add(slider(f, 'Warlock: drz aspon shardu', 0, 10, 1, function() return db.shardKeep end, function(v) db.shardKeep = v end, '%d'))
    add(slider(f, 'Warlock: Drain Soul do (shardu)', 0, 20, 1, function() return db.shardWant end, function(v) db.shardWant = v end, '%d'))
    add(cycler(f, 'Warlock: pet', { { 'auto', 'automaticky' }, { 'Imp', 'Imp' }, { 'Voidwalker', 'Voidwalker' },
      { 'Succubus', 'Succubus' }, { 'Felhunter', 'Felhunter' } }, function() return db.lockPet end, function(v) db.lockPet = v end), 8)
    add(cycler(f, 'Warlock: curse', { { 'auto', 'automaticky' }, { 'Curse of the Elements', 'Elements' },
      { 'Curse of Recklessness', 'Recklessness' }, { 'Curse of Weakness', 'Weakness' }, { 'Curse of Exhaustion', 'Exhaustion' },
      { 'none', 'zadna (jen Bane)' } }, function() return db.lockCurse end, function(v) db.lockCurse = v end))
    add(cycler(f, 'Warlock: filler', { { 'auto', 'automaticky' }, { 'Shadow Bolt', 'Shadow Bolt' }, { 'Searing Pain', 'Searing Pain' },
      { 'Incinerate', 'Incinerate' } }, function() return db.lockFiller end,
      function(v) db.lockFiller = v if ns.Warlock then pcall(ns.Warlock.refresh) end end))
  end
  add(slider(f, 'Velikost panelu', 0.6, 2, 0.05, function() return db.scale end, function(v)
    db.scale = v
    if ns.UI.frame and not InCombatLockdown() then ns.UI.frame:SetScale(v) ns.UI.reanchor() end
  end, '%.2f'))

  local reset = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
  reset:SetSize(130, 22) reset:SetText('Zapomenout uceni')
  reset:SetScript('OnClick', function() db.learnData = {} ns.say('uceni smazano') end)
  local mobs = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
  mobs:SetSize(130, 22) mobs:SetText('Smazat pamet mobu')
  mobs:SetScript('OnClick', function() db.mobs, db.memGlobal = {}, nil ns.say('pamet mobu smazana') end)

  local y = -32
  for _, it in ipairs(items) do
    y = y - it.gap
    it.w:SetPoint('TOPLEFT', f, 'TOPLEFT', 16, y)
    y = y - it.w:GetHeight()
  end
  y = y - 12
  reset:SetPoint('TOPLEFT', f, 'TOPLEFT', 16, y)
  mobs:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -16, y)
  f:SetHeight(-y + 22 + 14)
  f.items = items
  f:SetScript('OnShow', function() for _, it in ipairs(items) do if it.w.refresh then it.w.refresh() end end end)
  f:Hide()
  return f
end

function O.toggle()
  if not ns.db then return end
  local f = build()
  f:SetShown(not f:IsShown())
end

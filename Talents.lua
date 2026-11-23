-- ClaudeMaster: radce pro talenty.
-- Build podle MythicSim (Forever) referencnich buildu; v tooltipu talentu napise, kolik bodu sem dat a proc,
-- u ostatnich proc ne a co ho zamyka (body ve vetvi, sipka). Pri volnem bodu napise do chatu, co vzit.
-- /cm talent = dalsi 3 doporucene body.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local T = {}
ns.Talents = T

-- { jmeno, cilovy pocet bodu, proc } v poradi priority (ktery volny talent brat driv)
local BUILDS = {
  ret = {
    label = 'Retribution (2H)',
    trees = { 'Holy', 'Protection', 'Retribution' },
    list = {
      { 'Benediction', 5, 'Instantni kouzla (Judgement, sealy, Consecration) stoji min many - vydrzis bez piti dele.' },
      { 'Conviction', 3, '+2 % krit za bod ke vsem utokum i kouzlum.' },
      { 'Improved Judgement', 2, 'Judgement o 1 s za bod casteji - je to tvuj hlavni damage.' },
      { 'Sanctified Judgement', 3, 'Judgement ti vraci cast many.' },
      { 'Pursuit of Justice', 2, 'Rychlejsi pohyb pesky i na koni - rychlejsi questovani.' },
      { 'Vindication', 2, 'Tvoje udery oslabi utok moba - dostavas mensi rany.' },
      { 'Two-Handed Weapon Specialization', 3, 'Mas 2H zbran: +2 % damage za bod (fyzicky i holy) a mene threatu.' },
      { 'Sacred Arbiter', 1, 'Holy Strike bije vic a obnovi Judgement na cili.' },
      { 'Vengeance', 3, 'Po kritu bijes silneji (stackuje se).' },
      { 'Champion of the Light', 5, 'Kouzla (Judgement, Exorcism, sealy) sili s Intellectem.' },
      { 'Unyielding Faith', 2, 'Vetsi odolnost proti fear a disorient.' },
      { 'Divine Strength', 5, '+2 % Strength za bod = silnejsi udery.' },
      { 'Improved Seals', 5, 'Sealy a Judgement bijou o 3 % za bod vic.' },
      { 'Holy Conduit', 2, 'Levnejsi Consecration, Exorcism, Holy Wrath a Hammer of Wrath.' },
      { 'Purifying Power', 2, 'Exorcism a Holy Wrath casteji.' },
      { 'Divine Intellect', 5, '+2 % Intellect za bod: vic many a s Champion of the Light i vic damage.' },
      { 'Reverence', 1, 'Cast regenerace many bezi i pri castovani.' },
    },
    no = {
      ['Seal of Command'] = 'Addon drzi Seal of Righteousness (podle simu lepsi), Command by nepouzival.',
      ['Deflection'] = 'Parry je obrana pro tanka - ty bijes.',
      ['Eye for an Eye'] = 'Vraci jen kousek damage, kdyz te nekdo kritne - malo.',
      ['Repentance'] = 'CC na par sekund - v PvE malo platne, body jinde daji vic damage.',
      ['Turn Evil'] = 'Jen vylepseni Turn Undead.',
      ['Unsealed Wrath'] = 'Funguje jen pri stridani sealu - addon drzi jeden seal.',
      ['Holy Shock'] = 'Dobre kouzlo, ale hluboko v Holy - prisel bys o body v Retribution.',
    },
    tree = {
      'Leceni. Jako Ret odsud ber jen Divine Strength, Improved Seals, Holy Conduit, Purifying Power a Reverence.',
      'Tankovani se stitem - s 2H zbrani zbytecne (vyjimka: Divine Intellect).',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
    },
  },
  resto = {
    label = 'Restoration',
    trees = { 'Balance', 'Feral', 'Restoration' },
    list = {
      { 'Heart of the Wild', 5, 'Vic Intellectu = vic many a silnejsi leceni.' },
      { "Nature's Focus", 5, 'Kdyz te mob bije, leceni se tolik nezdrzuje.' },
      { 'Reflection', 3, 'Cast regenerace many bezi i pri castovani - mene piti.' },
      { 'Naturalist', 5, 'Healing Touch se castuje rychleji, +2 % damage za bod.' },
      { 'Gift of Nature', 5, '+2 % za bod ke vsem lecenim.' },
      { 'Swiftmend', 1, 'Okamzite velke leceni (spotrebuje Rejuvenation/Regrowth) - nouzove tlacitko.' },
      { 'Improved Rejuvenation', 3, 'Rejuvenation leci vic - je to tvuj hlavni HoT.' },
      { "Nature's Swiftness", 1, 'Pristi Healing Touch / Regrowth / Wild Growth okamzite - zachrana umirajiciho.' },
      { 'Wild Growth', 1, 'Vrchol stromu: HoT na celou partu naraz.' },
      { 'Improved Regrowth', 5, 'Regrowth casteji kritne (vetsi leceni).' },
      { 'Bloom', 1, 'Leceni navic k tvym HoTum.' },
      { 'Living Spirit', 3, '+5 % Spirit za bod - rychlejsi regenerace many.' },
      { 'Tranquil Spirit', 5, 'Healing Touch a Tranquility stoji mene many.' },
      { 'Subtlety', 3, 'Leceni dela mene threatu - moby pujdou po tankovi, ne po tobe.' },
      { 'Improved Tranquility', 2, 'Tranquility dela mene threatu (az zbydou body).' },
      { 'Natural Shapeshifter', 3, 'Levnejsi premena do formy (az zbydou body).' },
    },
    no = {},
    tree = {
      'Damage kouzla (moonkin). Jako resto lecis - tady body chybi v leceni.',
      'Medved a kocka. Jako lecitel je nepotrebujes.',
      'Tenhle talent ti jako lecitel malo pomuze.',
    },
  },
}

function T.buildKey()
  if ns.db and ns.db.talentBuild and BUILDS[ns.db.talentBuild] then return ns.db.talentBuild end
  if ns.class == 'PALADIN' then return 'ret' end
  if ns.class == 'DRUID' then
    local sp = ns.Druid and ns.Druid.spec and ns.Druid.spec()
    if sp == nil or sp == 'resto' then return 'resto' end
  end
  return nil
end
function T.build() local k = T.buildKey() return k and BUILDS[k] end

-- talenty ze skenu (Core.lua): jmeno -> zaznam s nejvyssim rankem
local function byName()
  local t = {}
  for _, e in ipairs(ns.talentList or {}) do
    if e.name and (not t[e.name] or (e.rank or 0) > (t[e.name].rank or 0)) then t[e.name] = e end
  end
  return t
end
-- vetev podle sloupce (Forever: 3 stromy vedle sebe v jednom C_Traits strome)
local function band(x) x = x or 0 return x < 4000 and 1 or (x < 8000 and 2 or 3) end
local function spentIn(b)
  local n, seen = 0, {}
  for _, e in ipairs(ns.talentList or {}) do
    if band(e.x) == b and not seen[e.node] then seen[e.node] = true n = n + (e.rank or 0) end
  end
  return n
end

function T.freePoints()
  local cfg = ns.talentCfg
  if cfg and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo then
    local info = pc(C_Traits.GetConfigInfo, cfg)
    local tree = type(info) == 'table' and type(info.treeIDs) == 'table' and info.treeIDs[1]
    local cur = tree and pc(C_Traits.GetTreeCurrencyInfo, cfg, tree, false)
    if type(cur) == 'table' and type(cur[1]) == 'table' then return safeNum(cur[1].quantity) or 0 end
  end
  if UnitCharacterPoints then return safeNum(pc(UnitCharacterPoints, 'player')) or 0 end
  return 0
end

local function nodeInfo(node)
  if not (node and ns.talentCfg and C_Traits and C_Traits.GetNodeInfo) then return nil end
  local ni = pc(C_Traits.GetNodeInfo, ns.talentCfg, node)
  return type(ni) == 'table' and ni or nil
end

-- muzu ted koupit bod? true / false / nil (nevime)
local function canBuy(e)
  local ni = nodeInfo(e and e.node)
  if not ni then return nil end
  local c = safeBool(ni.canPurchaseRank)
  if c ~= nil then return c end
  if C_Traits.CanPurchaseRank and e.entry then
    c = safeBool(pc(C_Traits.CanPurchaseRank, ns.talentCfg, e.node, e.entry))
    if c ~= nil then return c end
  end
  local a, m = safeBool(ni.isAvailable), safeBool(ni.meetsEdgeRequirements)
  if a == false or m == false then return false end
  return T.freePoints() > 0
end

-- proc je talent zamceny (seznam textu)
function T.lockWhy(e)
  local out = {}
  local ni = nodeInfo(e and e.node)
  if not ni then return out end
  for _, cid in ipairs(type(ni.conditionIDs) == 'table' and ni.conditionIDs or {}) do
    local ci = C_Traits.GetConditionInfo and pc(C_Traits.GetConditionInfo, ns.talentCfg, cid)
    if type(ci) == 'table' and safeBool(ci.isMet) == false then
      local need = safeNum(ci.spentAmountRequired)
      if need and need > 0 then
        out[#out + 1] = ('Potrebujes %d bodu v teto vetvi (mas %d).'):format(need, spentIn(band(e.x)))
      end
    end
  end
  if safeBool(ni.meetsEdgeRequirements) == false then
    -- ktery talent na nej ukazuje sipkou
    local seen = {}
    for _, o in ipairs(ns.talentList or {}) do
      if o.node and not seen[o.node] then
        seen[o.node] = true
        local oi = nodeInfo(o.node)
        for _, ed in ipairs(type(oi) == 'table' and type(oi.visibleEdges) == 'table' and oi.visibleEdges or {}) do
          if safeNum(ed.targetNode) == e.node and (o.rank or 0) < (o.max or 1) then
            out[#out + 1] = ('Nejdriv dej vsechny body do %s (%d/%d).'):format(o.name, o.rank or 0, o.max or 1)
          end
        end
      end
    end
  end
  if #out == 0 and T.freePoints() == 0 and (e.rank or 0) < (e.max or 1) then
    out[#out + 1] = 'Nemas volny bod (dalsi s dalsim levelem).'
  end
  return out
end

-- dalsi doporucene body: { {name, cur, target, why, can} ... }
function T.next(limit)
  local b = T.build()
  if not b then return {} end
  local tl = byName()
  local out, firstCan = {}, nil
  for _, it in ipairs(b.list) do
    local e = tl[it[1]]
    local cur = e and e.rank or 0
    if e and cur < it[2] then
      local can = canBuy(e)
      local r = { name = it[1], cur = cur, target = it[2], why = it[3], can = can, e = e }
      out[#out + 1] = r
      if can and not firstCan then firstCan = r end
    end
  end
  -- prvni, ktery jde koupit hned, dopredu
  if firstCan then
    for i, r in ipairs(out) do if r == firstCan then table.remove(out, i) break end end
    table.insert(out, 1, firstCan)
  end
  if limit then while #out > limit do table.remove(out) end end
  return out
end

------------------------------------------------------------------------------------------
-- Tooltip talentu
------------------------------------------------------------------------------------------
local function ownerIsTalentUI(owner)
  local f = owner
  for _ = 1, 12 do
    if not f then return false end
    local n = safe(pc(f.GetDebugName, f)) or safe(pc(f.GetName, f))
    if type(n) == 'string' and (n:find('Talent') or n:find('ClassTalent')) then return true end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end
local function nodeOfOwner(owner)
  if not owner then return nil end
  local n = owner.nodeID or (owner.GetNodeID and safeNum(pc(owner.GetNodeID, owner)))
  if not n and owner.GetNodeInfo then
    local ni = pc(owner.GetNodeInfo, owner)
    n = type(ni) == 'table' and safeNum(ni.ID)
  end
  return safeNum(n)
end

local busy = false
local function addAdvice(tt)
  if busy or not tt or tt:IsForbidden() then return end
  local b = T.build()
  if not b then return end
  local owner = tt:GetOwner()
  local node = nodeOfOwner(owner)
  local e
  if node then
    for _, x in ipairs(ns.talentList or {}) do if x.node == node then e = x break end end
  end
  if not e then
    if not ownerIsTalentUI(owner) then return end
    local fs = _G[tt:GetName() .. 'TextLeft1']
    local title = fs and safe(fs:GetText())
    if type(title) ~= 'string' then return end
    e = byName()[title]
  end
  if not e or tt.cmTalent == e.name then return end
  tt.cmTalent = e.name
  busy = true
  local rec
  for _, it in ipairs(b.list) do if it[1] == e.name then rec = it end end
  local nxt = T.next(1)[1]
  local function ic(path, s) return ('|T%s:%d:%d:0:0|t '):format(path, s or 14, s or 14) end
  local OK, NO, WAIT = 'Interface\\RAIDFRAME\\ReadyCheck-Ready', 'Interface\\RAIDFRAME\\ReadyCheck-NotReady',
    'Interface\\RAIDFRAME\\ReadyCheck-Waiting'
  local LOCK = 'Interface\\LFGFrame\\UI-LFG-ICON-LOCK'
  tt:AddLine(' ')
  tt:AddLine('|cff66ccffClaudeMaster|r |cff888888- ' .. b.label .. '|r')
  if rec then
    local cur = e.rank or 0
    if cur >= rec[2] then
      tt:AddLine(ic(OK) .. ('|cff00ff00Hotovo|r  %d/%d'):format(cur, rec[2]))
    elseif nxt and nxt.name == e.name and nxt.can then
      tt:AddLine(ic(OK) .. ('|cff00ff00Ted tohle|r  %d/%d'):format(cur, rec[2]))
    else
      tt:AddLine(ic(WAIT) .. ('|cffffd200Ber|r  %d/%d'):format(cur, rec[2]))
    end
    tt:AddLine('     ' .. rec[3], 0.9, 0.9, 0.9, true)
  else
    tt:AddLine(ic(NO) .. '|cffff6060Neber|r')
    tt:AddLine('     ' .. (b.no[e.name] or b.tree[band(e.x)]), 0.8, 0.8, 0.8, true)
    if nxt then
      local tex = nxt.e and nxt.e.spellId and C_Spell and C_Spell.GetSpellTexture and safe(pc(C_Spell.GetSpellTexture, nxt.e.spellId))
      tt:AddLine(' ')
      tt:AddLine('Lepsi:  ' .. (tex and ic(tex, 16) or '') .. ('|cff80ff80%s|r  %d/%d'):format(nxt.name, nxt.cur, nxt.target))
    end
  end
  -- zamky jen kdyz dava smysl: doporuceny talent, nebo skutecny zamek (vetev / sipka)
  if (e.rank or 0) < (e.max or 1) then
    local locks = T.lockWhy(e)
    local onlyNoPoint = #locks == 1 and locks[1]:find('^Nemas volny')
    if #locks > 0 and (rec or not onlyNoPoint) then
      tt:AddLine(' ')
      for _, w in ipairs(locks) do tt:AddLine(ic(LOCK, 12) .. w, 1, 0.6, 0.3, true) end
    end
  end
  tt:Show()
  busy = false
end

if GameTooltip then
  hooksecurefunc(GameTooltip, 'Show', function(tt) pcall(addAdvice, tt) busy = false end)
  GameTooltip:HookScript('OnTooltipCleared', function(tt) tt.cmTalent = nil end)
  GameTooltip:HookScript('OnHide', function(tt) tt.cmTalent = nil end)
end

------------------------------------------------------------------------------------------
-- Chat: volny bod -> co vzit;  /cm talent
------------------------------------------------------------------------------------------
function T.say(force)
  local b = T.build()
  if not b then
    if force then ns.say('Pro tuhle postavu/spec zatim nemam doporuceny build.') end
    return
  end
  local free = T.freePoints()
  if free <= 0 and not force then return end
  local list = T.next(3)
  if #list == 0 then
    if force then ns.say('Talenty: build ' .. b.label .. ' mas cely.') end
    return
  end
  ns.say(('Talenty (%s)%s:'):format(b.label, free > 0 and (', volne body: ' .. free) or ''))
  for i, r in ipairs(list) do
    ns.say(('  %d. |cffffd200%s|r %d/%d - %s'):format(i, r.name, r.cur, r.target, r.why))
  end
end

local tf = CreateFrame('Frame')
for _, ev in ipairs({ 'PLAYER_LEVEL_UP', 'PLAYER_ENTERING_WORLD' }) do pcall(tf.RegisterEvent, tf, ev) end
local said = false
tf:SetScript('OnEvent', function(_, ev)
  if ev == 'PLAYER_ENTERING_WORLD' and said then return end
  said = true
  if C_Timer then C_Timer.After(ev == 'PLAYER_LEVEL_UP' and 3 or 8, function() pcall(T.say, false) end) end
end)

function T.cmd(arg)
  if arg and BUILDS[arg] then ns.db.talentBuild = arg ns.say('Talent build: ' .. BUILDS[arg].label)
  elseif arg == 'auto' then ns.db.talentBuild = nil end
  T.say(true)
end

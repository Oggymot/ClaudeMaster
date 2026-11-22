-- ClaudeMaster: nemoci, jedy a nakazlive debuffy
--  * kdo v parte co ma (Disease / Poison / Curse / Magic) a kdo to umi vylecit
--  * nakazlive / vybusne debuffy (podle popisu kouzla): "odejdi od ostatnich" / "drz se od X dal"
--  * pamet: ktery mob co dava (debuffy, chain / AoE kouzla) -> varovani uz pred pullem
-- Pozn.: aury jdou na Forever cist hlavne mimo boj; v boji drzime posledni zjisteny stav.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local AF = { at = 0, state = nil, seenMe = {} }
ns.Afflict = AF

-- popis kouzla -> sireni / vybuch
local SPREAD_DESC = { 'nearby allies', 'nearby party', 'nearby friendly', 'nearby players', 'nearby targets', 'spreads', 'spread to',
  'jumps', 'contagious', 'infects', 'to all nearby', 'enemies within', 'allies within', 'players within', 'explodes', 'explode' }
local SPREAD_NAME = { 'Contagion', 'Contagious', 'Infect', 'Spore', 'Pestilence', 'Living Bomb', 'Plague Cloud' }
local descCache = {}
local function spreads(name, sid)
  if sid then
    local d = descCache[sid]
    if d == nil then
      d = C_Spell and C_Spell.GetSpellDescription and safe(pc(C_Spell.GetSpellDescription, sid)) or false
      if type(d) ~= 'string' or d == '' then d = false end
      descCache[sid] = d
    end
    if d then
      local dl = d:lower()
      for _, k in ipairs(SPREAD_DESC) do if dl:find(k, 1, true) then return true end end
      return false
    end
  end
  if type(name) == 'string' then
    for _, k in ipairs(SPREAD_NAME) do if name:find(k, 1, true) then return true end end
  end
  return false
end

-- kdo co umi vylecit
local CURE = {
  Disease = { PRIEST = 'Cure Disease', PALADIN = 'Purify', SHAMAN = 'Cure Disease' },
  Poison = { DRUID = 'Cure Poison', PALADIN = 'Purify', SHAMAN = 'Cure Poison' },
  Curse = { MAGE = 'Remove Lesser Curse', DRUID = 'Remove Curse' },
  Magic = { PRIEST = 'Dispel Magic', PALADIN = 'Cleanse' },
}
local TYPE_CZ = { Disease = 'nemoc', Poison = 'jed', Curse = 'kletba', Magic = 'magie' }
AF.TYPE_CZ = TYPE_CZ

local function readDebuffs(u)
  local out, hidden = {}, false
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return out, true end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, 'HARMFUL')
    if not ok or type(a) ~= 'table' then break end
    local n = safe(a.name)
    if type(n) ~= 'string' then hidden = true break end
    local sid = safeNum(a.spellId)
    out[#out + 1] = { name = n, sid = sid, type = safe(a.dispelName), icon = safe(a.icon), spread = spreads(n, sid) }
  end
  return out, hidden
end

local function curer(dtype, myCls)
  local t = CURE[dtype]
  if not t then return nil end
  if t[myCls] and ns.known(t[myCls]) then return 'ty', t[myCls] end
  for i = 1, 4 do
    local u = 'party' .. i
    if UnitExists(u) then
      local cls = select(2, UnitClass(u))
      if t[cls] then return safe(pc(UnitName, u)) or cls, t[cls], u end
    end
  end
end

-- Kazdych 0.5 s z kontextu
function AF.scan(c)
  local now = GetTime()
  if now - AF.at < 0.5 then return AF.state end
  AF.at = now
  local st = { list = {}, spreadMe = nil, spreadOther = nil, cure = nil, hidden = false }
  local units = { 'player', 'party1', 'party2', 'party3', 'party4' }
  local tname = ns.Immune and ns.Immune.tname
  for _, u in ipairs(units) do
    if UnitExists(u) and safeBool(pc(UnitIsDeadOrGhost, u)) ~= true then
      local deb, hidden = readDebuffs(u)
      if hidden then st.hidden = true end
      local who = (u == 'player') and 'ty' or (safe(pc(UnitName, u)) or u)
      for _, d in ipairs(deb) do
        if d.spread then
          if u == 'player' then st.spreadMe = st.spreadMe or d
          else st.spreadOther = st.spreadOther or { d = d, who = who, unit = u } end
        end
        if d.type and CURE[d.type] then
          local by, spell, byUnit = curer(d.type, ns.class)
          st.list[#st.list + 1] = { who = who, unit = u, d = d, by = by, spell = spell }
          if by == 'ty' and not st.cure then st.cure = { unit = u, who = who, spell = spell, d = d } end
        end
        -- pamet: novy debuff na mne, kdyz mlatim moba -> nejspis od neho
        if u == 'player' and c.inCombat and c.hostile and type(tname) == 'string' and (d.spread or d.type == 'Disease' or d.type == 'Poison') then
          ns.db.mobDebuffs = ns.db.mobDebuffs or {}
          local m = ns.db.mobDebuffs[tname] or {}
          ns.db.mobDebuffs[tname] = m
          if not m[d.name] and ns.Duo and ns.Duo.shareMob then
            ns.Duo.shareMob('D', tname, d.name, d.type or '', d.spread and '1' or '')
          end
          m[d.name] = { type = d.type, spread = d.spread or nil }
        end
      end
    end
  end
  AF.state = st
  return st
end

-- Co vime o mobovi pred pullem: nakazlive debuffy, chain kouzla, AoE kolem sebe
local CHAIN = { 'Chain Lightning', 'Chain Heal', 'Chain', 'Arcing' }
local PBAOE = { 'Thunder Clap', 'War Stomp', 'Frost Nova', 'Arcane Explosion', 'Whirlwind', 'Shockwave', 'Fire Nova', 'Holy Nova', 'Hellfire' }
function AF.mobWarn(mob)
  if type(mob) ~= 'string' then return nil end
  local md = ns.db.mobDebuffs and ns.db.mobDebuffs[mob]
  if md then
    for n, d in pairs(md) do if d.spread then return ('dava nakazlivy %s - stujte od sebe'):format(n), 'spread' end end
  end
  local mc = ns.db.mobCasts and ns.db.mobCasts[mob]
  if mc then
    for sp in pairs(mc) do
      for _, k in ipairs(CHAIN) do
        if sp:find(k, 1, true) and not sp:find('Heal', 1, true) then return ('umi %s (preskakuje) - stujte od sebe'):format(sp), 'chain' end
      end
    end
    for sp in pairs(mc) do
      for _, k in ipairs(PBAOE) do if sp:find(k, 1, true) then return ('umi %s kolem sebe - drz se dal'):format(sp), 'pbaoe' end end
    end
  end
  if md then
    for n, d in pairs(md) do
      if d.type == 'Disease' or d.type == 'Poison' then return ('dava %s (%s)'):format(n, TYPE_CZ[d.type]), 'dot' end
    end
  end
end

------------------------------------------------------------------------------------------
-- Napojeni na kontext a plan (obe classy)
------------------------------------------------------------------------------------------
local E = ns.Engine
local ANTIVENOM = { 19440, 6453, 6452 }   -- Powerful / Strong / Anti-Venom
if E and E.context and E.plan then
  local origCtx, origPlan = E.context, E.plan
  E.context = function(...)
    local c = origCtx(...)
    if c then
      local ok, st = pcall(AF.scan, c)
      c.afflict = ok and st or nil
      if c.hostile and not c.inCombat then c.mobWarn, c.mobWarnKind = AF.mobWarn(ns.Immune and ns.Immune.tname) end
    end
    return c
  end
  E.plan = function(c, ...)
    local plan, util = origPlan(c, ...)
    local st = c and c.afflict
    if not st then return plan, util end
    local busy = util and util.urgent
    -- nakazlive na mne: pryc od ostatnich
    if st.spreadMe and c.group and not busy then
      util = { name = 'TARGET', kind = 'hint', urgent = true, icon = st.spreadMe.icon or 'Interface\\Icons\\Spell_Shadow_CallofBone',
        reason = ('Mas nakazlivy debuff (%s): odejdi od ostatnich!'):format(st.spreadMe.name) }
      return plan, util
    end
    -- jed na mne: Anti-Venom (First Aid)
    if not util and st.list then
      for _, e in ipairs(st.list) do
        if e.unit == 'player' and e.d.type == 'Poison' then
          for _, id in ipairs(ANTIVENOM) do
            if (safeNum(pc(GetItemCount, id)) or 0) > 0 and ns.itemReady(id, 'antivenom', 60) then
              util = { name = 'item:' .. id, kind = 'item', item = id, reason = ('Jed (%s): Anti-Venom'):format(e.d.name) }
              break
            end
          end
          break
        end
      end
    end
    -- nakazlive na spoluhraci: drz se dal
    if not util and st.spreadOther then
      util = { name = 'TARGET', kind = 'hint', icon = st.spreadOther.d.icon or 'Interface\\Icons\\Spell_Shadow_CallofBone',
        reason = ('%s ma nakazlivy %s: drz se od nej dal'):format(st.spreadOther.who, st.spreadOther.d.name) }
    end
    -- umim vylecit (nemoc/jed/kletba/magie, kterou mam ve spellbooku)
    if not util and st.cure and ns.cdLeft(st.cure.spell) <= 0 then
      util = { name = st.cure.spell, kind = 'spell', unit = st.cure.unit,
        reason = ('%s na %s (%s): %s'):format(TYPE_CZ[st.cure.d.type] or st.cure.d.type, st.cure.who, st.cure.d.name, st.cure.spell) }
    end
    -- pred pullem: mob dava nakazlivy debuff / chain
    if not util and c.mobWarn and c.group and (c.mobWarnKind == 'spread' or c.mobWarnKind == 'chain') then
      util = { name = 'TARGET', kind = 'hint', icon = 'Interface\\Icons\\Spell_Nature_ChainLightning',
        reason = 'Pozor, tenhle mob ' .. c.mobWarn }
    end
    return plan, util
  end
end

-- Info radky (vola UI)
function AF.infoLines(c, lines)
  local st = c.afflict
  if st and st.list then
    local shown = 0
    for _, e in ipairs(st.list) do
      if shown >= 2 then break end
      local cure = e.by and (e.by == 'ty' and ('vylec: ' .. e.spell) or ('vylecit muze ' .. e.by)) or 'nikdo z vas neumi vylecit'
      lines[#lines + 1] = ('|cffb5e655%s|r na %s (%s): %s'):format(TYPE_CZ[e.d.type] or e.d.type, e.who, e.d.name, cure)
      shown = shown + 1
    end
  end
  if c.mobWarn then lines[#lines + 1] = '|cffffcc00Mob ' .. c.mobWarn .. '|r' end
end

-- ClaudeMaster: znalosti o mobech z databaze (MobData.lua, vmangos = classic 1.12)
-- Forever neni cisty classic, takze databaze je jen VYCHOZI ODHAD:
-- co addon sam ve hre zjisti (Immune.lua, Memory.lua, mobCasts), ma vzdy prednost.
-- Hledame podle jmena (venku citelne); v dungeonu hra jmeno i ID skryva -> databaze tam nepomuze.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum = ns.pc, ns.safe, ns.safeNum

local MD = { byName = nil, cache = {}, spellTag = nil }
ns.MobDB = MD

-- mechanic_immune_mask: bit = 1 << (mechanika - 1)
local MECH = { polymorph = 65536, fear = 16, root = 64, snare = 1024, stun = 2048, freeze = 4096, banish = 131072,
  silence = 256, charm = 1, sleep = 512, horror = 8388608 }
local SCH = { fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }
local SCHOOL_OF = { F = 'fire', R = 'frost', S = 'shadow', A = 'arcane', N = 'nature', H = 'holy', P = 'physical' }
local CZ = { fire = 'ohen', frost = 'mraz', shadow = 'stin', arcane = 'arcane', nature = 'priroda', holy = 'svetlo', physical = 'fyzicky' }
MD.CZ = CZ
local function has(mask, bit) return mask and bit and math.floor(mask / bit) % 2 == 1 end

local function index()
  if MD.byName then return end
  MD.byName = {}
  for id, s in pairs(ns.MOBDATA or {}) do
    local name = s:match('^([^|]*)')
    local l = MD.byName[name]
    if not l then l = {} MD.byName[name] = l end
    l[#l + 1] = id
  end
end

local function parse(id)
  local c = MD.cache[id]
  if c then return c end
  local s = ns.MOBDATA and ns.MOBDATA[id]
  if not s then return nil end
  local f = {}
  for v in (s .. '|'):gmatch('([^|]*)|') do f[#f + 1] = v end
  local r = { id = id, name = f[1], lmin = tonumber(f[2]), lmax = tonumber(f[3]), rank = tonumber(f[4]), ctype = tonumber(f[5]),
    mech = tonumber(f[6]) or 0, school = tonumber(f[7]) or 0, flee = f[9] == '1', cls = tonumber(f[10]), help = tonumber(f[11]),
    res = {}, spells = {}, heal = {}, cc = {}, summon = {}, dmgSchool = {} }
  for sc, v in (f[8] or ''):gmatch('(%a)(%d+)') do r.res[SCHOOL_OF[sc]] = tonumber(v) end
  for sp in (f[12] or ''):gmatch('[^;]+') do
    local tag, sc, cast, name = sp:match('^(%a):(%a)(%+?)(.+)$')
    if tag then
      local e = { tag = tag, school = SCHOOL_OF[sc], cast = cast == '+', name = name }
      r.spells[#r.spells + 1] = e
      if tag == 'h' then r.heal[#r.heal + 1] = name
      elseif tag == 'c' then r.cc[#r.cc + 1] = name
      elseif tag == 's' then r.summon[#r.summon + 1] = name
      elseif tag == 'd' and e.school ~= 'physical' then r.dmgSchool[e.school] = true end
    end
  end
  r.patrol = f[14] == '1'
  r.drops = {}
  for d in (f[13] or ''):gmatch('[^;]+') do
    local id, ch, kind, name = d:match('^(%d+)~([%d%.]+)~(%w)~(.+)$')
    if id then r.drops[#r.drops + 1] = { id = tonumber(id), chance = tonumber(ch), kind = kind, name = name } end
  end
  r.immPoly = has(r.mech, MECH.polymorph)
  r.immFear = has(r.mech, MECH.fear)
  r.immRoot = has(r.mech, MECH.root)
  r.immSnare = has(r.mech, MECH.snare)
  r.immStun = has(r.mech, MECH.stun)
  r.immBanish = has(r.mech, MECH.banish)
  r.immSchool = {}
  for nm, bit in pairs(SCH) do if has(r.school, bit) then r.immSchool[nm] = true end end
  MD.cache[id] = r
  return r
end

-- zaznam podle jmena; pri vic zaznamech se stejnym jmenem ten, jehoz level sedi
function MD.byNameLevel(name, level)
  if type(name) ~= 'string' then return nil end
  index()
  local l = MD.byName[name]
  if not l then return nil end
  if #l == 1 or not level then return parse(l[1]) end
  local best, bd
  for _, id in ipairs(l) do
    local r = parse(id)
    local d = 0
    if level < r.lmin then d = r.lmin - level elseif level > r.lmax then d = level - r.lmax end
    if not bd or d < bd then best, bd = r, d end
  end
  return best
end
function MD.forUnit(u)
  local name = safe(pc(UnitName, u))
  if type(name) ~= 'string' then return nil end
  local lv = safeNum(pc(UnitLevel, u))
  return MD.byNameLevel(name, lv and lv > 0 and lv or nil)
end

local SPELL_FIELD = '^' .. ('[^|]*|'):rep(11) .. '([^|]*)'   -- 12. pole = kouzla
-- typ kouzla podle jmena napric vsemi moby (pro prioritu preruseni)
function MD.tagOf(spell)
  if type(spell) ~= 'string' then return nil end
  if not MD.spellTag then
    MD.spellTag = {}
    for _, s in pairs(ns.MOBDATA or {}) do
      local sp = s:match(SPELL_FIELD)
      if sp then
        for tag, name in sp:gmatch('(%a):%a%+?([^;]+)') do
          if tag == 'h' or tag == 'c' or tag == 's' then MD.spellTag[name] = tag end
        end
      end
    end
  end
  return MD.spellTag[spell]
end

-- dropy pro tooltip: jmeno itemu z vlastni hry (presne a barevne), jinak z databaze
local QCOL = { ['2'] = 'ff1eff00', ['3'] = 'ff0070dd', ['4'] = 'ffa335ee', ['5'] = 'ffff8000', c = 'ffffffff', q = 'ffffd100' }
function MD.dropText(r, level)
  if not r or #r.drops == 0 then return nil end
  -- Forever moba preskaloval na jiny level: bezne dropy nesedi, questove itemy asi ano
  local off = level and r.lmin and (level < r.lmin - 3 or level > r.lmax + 3)
  local p = {}
  for _, d in ipairs(r.drops) do
    if not off or d.kind == 'q' then
      local nm = d.name
      local gi = C_Item and C_Item.GetItemInfo and safe(pc(C_Item.GetItemInfo, d.id)) or safe(pc(GetItemInfo, d.id))
      if type(gi) == 'string' and gi ~= '' then nm = gi end
      local ch = d.kind == 'q' and 'quest' or (d.chance >= 1 and ('%d%%'):format(math.floor(d.chance + 0.5)) or ('%.1f%%'):format(d.chance))
      p[#p + 1] = ('|c%s%s|r %s'):format(QCOL[d.kind] or 'ffffffff', nm, ch)
    end
  end
  if #p == 0 then return nil end
  local txt = table.concat(p, ', ')
  if off then txt = txt .. ('  |cff888888(classic lvl %d-%d, jinak se lisi)|r'):format(r.lmin, r.lmax) end
  return txt
end

-- dropy jako radky { jmeno (barevne), sance } + zda level nesedi
function MD.dropRows(r, level)
  if not r or #r.drops == 0 then return nil end
  local off = level and r.lmin and (level < r.lmin - 3 or level > r.lmax + 3)
  local rows = {}
  for _, d in ipairs(r.drops) do
    if not off or d.kind == 'q' then
      local nm = d.name
      local gi = C_Item and C_Item.GetItemInfo and safe(pc(C_Item.GetItemInfo, d.id)) or safe(pc(GetItemInfo, d.id))
      if type(gi) == 'string' and gi ~= '' then nm = gi end
      local ch = d.kind == 'q' and 'quest' or (d.chance >= 1 and ('%d %%'):format(math.floor(d.chance + 0.5)) or ('%.1f %%'):format(d.chance))
      rows[#rows + 1] = { ('|c%s%s|r'):format(QCOL[d.kind] or 'ffffffff', nm), ch }
    end
  end
  if #rows == 0 then return nil end
  return rows, off
end

-- kratky popis pro tooltip / info
function MD.describe(r)
  if not r then return nil end
  local p = {}
  if r.rank == 1 or r.rank == 2 then p[#p + 1] = '|cffffcc00elite|r' elseif r.rank == 3 then p[#p + 1] = '|cffff5555boss|r' end
  local imm = {}
  for sc in pairs(r.immSchool) do imm[#imm + 1] = CZ[sc] end
  if r.immPoly then imm[#imm + 1] = 'ovce' end
  if r.immFear then imm[#imm + 1] = 'fear' end
  if r.immRoot then imm[#imm + 1] = 'root' end
  if r.immStun then imm[#imm + 1] = 'stun' end
  table.sort(imm)
  if #imm > 0 then p[#p + 1] = '|cffff7070imunni:|r ' .. table.concat(imm, ', ') end
  local res = {}
  for sc, v in pairs(r.res) do if not r.immSchool[sc] then res[#res + 1] = CZ[sc] end end
  table.sort(res)
  if #res > 0 then p[#p + 1] = 'odolny: ' .. table.concat(res, ', ') end
  if #r.heal > 0 then p[#p + 1] = '|cff66ee77leci:|r ' .. table.concat(r.heal, ', ') end
  if #r.cc > 0 then p[#p + 1] = '|cffff7070CC:|r ' .. table.concat(r.cc, ', ') end
  if #r.summon > 0 then p[#p + 1] = 'privolava pomoc' end
  if r.flee then p[#p + 1] = '|cffffcc00utika|r' end
  if r.patrol then p[#p + 1] = 'patroluje' end
  return #p > 0 and table.concat(p, ', ') or nil
end

------------------------------------------------------------------------------------------
-- Napojeni (vlastni pozorovani maji prednost)
------------------------------------------------------------------------------------------
-- imunity: doplnit z databaze, co jsme se jeste nenaucili
if ns.Immune and ns.Immune.info then
  local orig = ns.Immune.info
  ns.Immune.info = function(...)
    local r = orig(...)
    local ok, d = pcall(MD.forUnit, 'target')
    if ok and d and r then
      for sc in pairs(d.immSchool) do if not r.schools[sc] then r.schools[sc] = 'db' end end
      if d.immPoly and not r.spells.Polymorph then r.spells.Polymorph = 'db' end
      if d.immFear and not r.spells.Fear then r.spells.Fear = 'db' r.spells.Seduction = r.spells.Seduction or 'db' end
      if d.immRoot and not r.spells['Frost Nova'] then r.spells['Frost Nova'] = 'db' end
      if d.immBanish and not r.spells.Banish then r.spells.Banish = 'db' end
      r.db = d
    end
    return r
  end
end

-- pamet moba: kouzli / utika z databaze, dokud nemame vlastni data
if ns.Mem and ns.Mem.info then
  local orig = ns.Mem.info
  ns.Mem.info = function(name, ctype, group)
    local r = orig(name, ctype, group)
    local d = type(name) == 'string' and MD.byNameLevel(name)
    if not (r and d) then return r end
    r.db = d
    if (r.n or 0) < 3 then
      if not r.caster and next(d.dmgSchool) then
        r.caster = true
        r.school = (d.dmgSchool.fire and 'fire') or (d.dmgSchool.frost and 'frost') or (d.dmgSchool.shadow and 'shadow') or nil
      end
      if d.flee and (not r.flees or r.fleeGuess) then r.flees, r.fleeGuess = true, nil end
      -- databaze vi, ze neutika (zadny skript na utek): zrusit odhad "humanoid asi utika"
      if not d.flee and r.fleeGuess then r.flees, r.fleeGuess = false, nil end
    end
    return r
  end
end

-- heal / CC moba (setreni interruptu)
if ns.mobCastInfo then
  local orig = ns.mobCastInfo
  ns.mobCastInfo = function(mob)
    local r = orig(mob)
    local d = MD.byNameLevel(mob)
    if d and (#d.heal > 0 or #d.cc > 0) then
      r = r or {}
      r.heal = r.heal or d.heal[1]
      r.cc = r.cc or d.cc[1]
    end
    return r
  end
end

-- priorita preruseni: databaze zna leceni / CC / privolani i u kouzel s nejasnym jmenem
if ns.castPrio then
  local orig = ns.castPrio
  ns.castPrio = function(name, sid, durMs)
    local p, why, kind = orig(name, sid, durMs)
    if (p or 0) < 3 then
      local t = MD.tagOf(name)
      if t == 'h' then return 3, 'leceni', 'heal'
      elseif t == 'c' then return 3, 'CC', 'CC'
      elseif t == 's' then return 3, 'privolava', 'summon' end
    end
    return p, why, kind
  end
end

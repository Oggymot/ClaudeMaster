-- ClaudeMaster: pamet a uceni.
-- 1) Pamet mobu podle jmena: jestli kouzli (a jakou skolou), jestli utika, jak dlouho se zabiji
--    a kolik many na nej padne. Uklada se pro postavu (ClaudeMasterDB.mobs).
-- 2) Statistika boje: co jsi castil oproti doporuceni, kolik casu jsi stal bez castu, mana.
-- 3) Uceni z tveho hrani: kdyz v nejake situaci doporuceni opakovane neberes a hrajes neco
--    jineho, zacne addon nabizet to, co hrajes ty (nikdy u nouzovych veci).
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local M = {}
ns.Mem = M

local function mobs() ns.db.mobs = ns.db.mobs or {} return ns.db.mobs end
local function learnDB() ns.db.learnData = ns.db.learnData or {} return ns.db.learnData end
-- Cas a mana se pocitaji zvlast pro solo ('s') a partu ('g'): v parte mob pada rychleji
-- a stoji te min many, takze by to kazilo odhady pro solo (a naopak).
local function bucket() return { n = 0, ttd = 0, mana = 0 } end
local function global()
  local g = ns.db.memGlobal
  if not g or not g.s then
    g = { s = bucket(), g = bucket() }
    local old = ns.db.memGlobal
    if old and (old.n or 0) > 0 then g.g = { n = old.n, ttd = old.ttd, mana = old.mana } end   -- starsi data byla z party
    ns.db.memGlobal = g
  end
  return g
end
local function mobBuckets(m)
  if not m.s then
    m.s, m.g = bucket(), bucket()
    if (m.n or 0) > 0 and m.ttd then m.g = { n = m.n, ttd = m.ttd, mana = m.mana or 0 } end
    m.ttd, m.mana = nil, nil
  end
  return m
end
-- klouzavy prumer: prvnich 10 vzorku plne, pak pomalu
local function avg(old, x, n) return old + (x - old) / math.min(n, 10) end

------------------------------------------------------------------------------------------
-- Pamet mobu
------------------------------------------------------------------------------------------
M.cur = nil          -- prave bojovany cil
M.stat = { started = 0, byDead = 0, byLow = 0, byEnd = 0 }   -- diagnostika (/cm learn)
M.fleeAt = {}        -- jmeno -> cas posledniho "utika" emote
M.fleeTok = {}       -- jmeno -> token cile, ktery utikal (kdyz to byl prave cil)

local function finishKill(cur, now)
  local name = cur.name
  local m = mobBuckets(mobs()[name] or { n = 0, caster = 0, flee = 0, fire = 0, frost = 0 })
  mobs()[name] = m
  m.n = m.n + 1
  local k = cur.group and 'g' or 's'
  local bk = m[k]
  bk.n = bk.n + 1
  bk.ttd = avg(bk.ttd, now - cur.start, bk.n)
  bk.mana = avg(bk.mana, cur.mana, bk.n)
  if cur.caster then m.caster = m.caster + 1 end
  if cur.fire then m.fire = m.fire + 1 end
  if cur.frost then m.frost = m.frost + 1 end
  if cur.fled then m.flee = m.flee + 1 end
  m.ctype = cur.ctype or m.ctype
  m.seen = time and time() or 0
  local g = global()[k]
  g.n = g.n + 1
  g.mana = avg(g.mana, cur.mana, g.n)
  g.ttd = avg(g.ttd, now - cur.start, g.n)
  if M.fight then M.fight.kills = M.fight.kills + 1 end
end

-- Co vime o mobovi (nil = nikdy jsme ho nezabili a nic se o nem neda rict)
function M.info(name, ctype, group)
  if type(name) ~= 'string' then return nil end
  local m = mobs()[name]
  local r = { n = m and m.n or 0, nb = 0, group = group }
  if m and m.n > 0 then
    mobBuckets(m)
    local bk = m[group and 'g' or 's']
    -- cas a mana jen ze stejneho rezimu (solo / parta)
    if bk.n > 0 then r.ttd, r.mana, r.nb = bk.ttd, bk.mana, bk.n end
    r.caster = m.caster / m.n >= 0.3
    if r.caster then r.school = (m.fire > m.frost and m.fire > 0 and 'fire') or (m.frost > 0 and 'frost') or nil end
    r.flees = m.n >= 2 and (m.flee / m.n >= 0.3) or (m.flee > 0)
  end
  -- humanoidi v classic pravidlech pri malo HP utikaji; dokud nevime jinak, pocitame s tim
  -- utika (vim to sam nebo od parťáka)
  if ns.db.mobFlees and ns.db.mobFlees[name] then r.flees, r.fleeGuess = true, nil end
  if not r.flees and (ctype or (m and m.ctype)) == 'Humanoid' and r.n < 3 then r.flees, r.fleeGuess = true, true end
  if M.fleeAt[name] and GetTime() - M.fleeAt[name] < 6 then r.fleeingNow = true end
  return r
end

-- Kolik many (0-1) obvykle stoji jeden boj s timto mobem (nebo prumerne)
function M.needMana(name, group)
  local k = group and 'g' or 's'
  local m = type(name) == 'string' and mobs()[name]
  if m then mobBuckets(m) if m[k].n >= 2 then return m[k].mana, true end end
  local g = global()[k]
  if g.n >= 3 then return g.mana, false end
  return nil
end

-- Utika: "%s attempts to run away in fear!"
local ef = CreateFrame('Frame')
pcall(ef.RegisterEvent, ef, 'CHAT_MSG_MONSTER_EMOTE')
ef:SetScript('OnEvent', function(_, _, text, who)
  text, who = safe(text), safe(who)
  if type(text) ~= 'string' or type(who) ~= 'string' then return end
  local t = text:lower()
  if t:find('run away') or t:find('flee') or t:find('in fear') then
    M.fleeAt[who] = GetTime()
    ns.db.mobFlees = ns.db.mobFlees or {}
    if not ns.db.mobFlees[who] and ns.Duo and ns.Duo.shareMob then ns.Duo.shareMob('F', who) end
    ns.db.mobFlees[who] = true
    local tn = safe(pc(UnitName, 'target'))
    M.fleeTok[who] = (tn == who and ns.T) and ns.T.token or nil
    if M.cur and M.cur.name == who then M.cur.fled = true end
  end
end)

------------------------------------------------------------------------------------------
-- Boj: statistika a porovnani s doporucenim
------------------------------------------------------------------------------------------
M.fight = nil
M.rec = nil          -- doporuceni, ktere bylo videt naposledy {name, key, learned, orig, urgent}

function M.startFight()
  M.fight = { start = GetTime(), casts = 0, judged = 0, followed = 0, idle = 0, mana = 0, kills = 0,
    dev = {}, fled = 0, learnedNew = {}, kicks0 = ns.Party and ns.Party.myKicks or 0 }
  M.idleSince = nil
end

-- Situace (pro uceni): v boji, u tebe, zmrazeny, AoE, malo many, parta, FoF
function M.sit(c)
  local s = ''
  if c.near then s = s .. 'n' end
  if (c.frozen or 0) > 0 then s = s .. 'f' end
  if c.enemies and (c.enemies.cluster or 0) >= c.db.aoe then s = s .. 'a' end
  if c.manaKnown and c.mana < c.db.conserveMana then s = s .. 'm' end
  if c.group then s = s .. 'g' end
  if (c.fof or 0) > 0 then s = s .. 'p' end
  if c.moving then s = s .. 'v' end
  return s
end
local SIT_TXT = { n = 'mob u tebe', f = 'zmrazeny cil', a = 'AoE', m = 'malo many', g = 'v parte', p = 'FoF', v = 'v pohybu' }
function M.sitText(s)
  local t = {}
  for ch in s:gmatch('.') do t[#t + 1] = SIT_TXT[ch] end
  return #t > 0 and table.concat(t, ', ') or 'bezny boj'
end

-- Kazdych 0.1 s z hlavni smycky
function M.tick(c, plan)
  local now = GetTime()
  local name = ns.Immune and ns.Immune.tname
  -- zacatek / zmena cile
  -- zmena cile: kdyz mel predchozi cil pred chvili skoro nula HP, nejspis padl
  if M.cur and not M.cur.done and M.cur.token ~= ns.T.token then
    if M.cur.lowAt and now - M.cur.lowAt < 3 then M.cur.done = true finishKill(M.cur, M.cur.lowAt) M.stat.byLow = M.stat.byLow + 1 end
    if not M.cur.done then M.cur = nil end
  end
  if c.hostile and c.inCombat and type(name) == 'string' then
    if not M.cur or M.cur.token ~= ns.T.token then
      M.cur = { name = name, token = ns.T.token, start = now, mana = 0, ctype = c.ctype, group = c.group }
      M.stat.started = M.stat.started + 1
    end
    local cur = M.cur
    if c.tLow10 then cur.lowAt = now end
    if c.group then cur.group = true end
    if c.tCasting then
      if c.tCastName and ns.noteMobCast then ns.noteMobCast(name, c.tCastName, c.tCastKind) end
      -- interrupt: kolikrat to stalo za to (heal/CC/silny spell), jednou na kazdy cast
      if M.fight and c.interruptible and (c.tCastPrio or 2) >= 2 and ns.tCastStart ~= M.lastKickCast then
        M.lastKickCast = ns.tCastStart
        M.fight.kickAsk = (M.fight.kickAsk or 0) + 1
      end
      cur.caster = true
      if c.tCastSchool == 'fire' then cur.fire = true elseif c.tCastSchool == 'frost' then cur.frost = true end
    end
  end
  -- cil padl (mrtvola zustava v cili)
  -- Forever muze "je mrtvy" skryvat, proto vic zpusobu
  if M.cur and not M.cur.done and M.cur.token == ns.T.token and UnitExists('target') then
    local dead = safeBool(pc(UnitIsDeadOrGhost, 'target')) == true or safeBool(pc(UnitIsDead, 'target')) == true
      or safeNum(pc(UnitHealth, 'target')) == 0
    if not dead and M.cur.lowAt and safeBool(pc(UnitCanAttack, 'player', 'target')) == false then dead = true end
    if dead then
      M.cur.done = true
      finishKill(M.cur, now)
      M.stat.byDead = M.stat.byDead + 1
    end
  end
  -- doporuceni, ktere hrac prave vidi
  local a = plan and plan[1]
  if a and c.inCombat then
    M.rec = { name = a.name, kind = a.kind, urgent = a.urgent, learned = a.learned, key = a.learnKey, orig = a.orig }
  else
    M.rec = nil
  end
  -- necinnost: v boji, s cilem, nic necastim a GCD je volny
  local F = M.fight
  -- parta s tankem: kdy jsi strhl aggro (mob prepnul na tebe)
  if F and c.inCombat and c.tankUp then
    F.tank = true
    local onMe = c.enemies.onMe or 0
    if onMe > 0 and (M.prevOnMe or 0) == 0 and (c.pullAge or 0) > 1 then
      F.aggroPulls = (F.aggroPulls or 0) + 1
      local lastAoE = math.max(ns.castAt.Blizzard or -99, ns.castAt.Flamestrike or -99, ns.castAt['Arcane Explosion'] or -99,
        ns.castAt['Rain of Fire'] or -99, ns.castAt.Hellfire or -99)
      if now - lastAoE < 5 then F.aoeAggro = (F.aoeAggro or 0) + 1 end
    end
  end
  M.prevOnMe = c.inCombat and (c.enemies.onMe or 0) or 0
  if F and c.inCombat then
    if c.hostile and not c.castName and (c.gcd or 0) <= 0 then
      M.idleSince = M.idleSince or now
    else
      if M.idleSince and now - M.idleSince > 0.6 then F.idle = F.idle + (now - M.idleSince - 0.6) end
      M.idleSince = nil
    end
  end
end

-- Hrac zacal castit / seslal instant (jednou na kouzlo)
function M.playerCast(name)
  local F = M.fight
  if not F or not ns.inCombat() then return end
  -- wand strili sam dokola: pocitat jen zacatek strelby
  local now = GetTime()
  if name == 'Shoot' then
    local again = M.lastShoot and now - M.lastShoot < 4
    M.lastShoot = now
    if again then return end
  end
  F.casts = F.casts + 1
  if name == 'Blizzard' or name == 'Flamestrike' or name == 'Arcane Explosion' or name == 'Rain of Fire' or name == 'Hellfire' then
    F.aoeCasts = (F.aoeCasts or 0) + 1
  end
  -- kouzla mimo GCD (Icy Veins, Cold Snap...) a predmety nejsou "misto" hlavniho doporuceni
  if ns.OFF_GCD[name] or not (ns.S[name] and ns.S[name].known) then return end
  local r = M.rec
  if not r or r.kind ~= 'spell' or r.urgent then return end
  F.judged = F.judged + 1
  local L
  if r.key then
    L = learnDB()[r.key] or { shown = 0, followed = 0, instead = {}, swapOk = 0 }
    learnDB()[r.key] = L
  end
  if r.learned then
    -- addon nabidl to, co obvykle hrajes ty
    if name == r.name then F.followed = F.followed + 1 if L then L.swapOk = L.swapOk + 1 end
    elseif L and name == r.orig then L.followed = L.followed + 1 L.shown = L.shown + 1 end
    return
  end
  if name == r.name then
    F.followed = F.followed + 1
    if L then L.shown = L.shown + 1 L.followed = L.followed + 1 end
  else
    local d = r.name .. '>' .. name
    F.dev[d] = (F.dev[d] or 0) + 1
    if L then
      L.shown = L.shown + 1
      L.instead[name] = (L.instead[name] or 0) + 1
    end
  end
end

-- mana za kazde kouzlo (z ceny kouzla, i kdyz je mana skryta)
function M.onCast(name)
  if not ns.inCombat() then return end
  local frac = ns.cost(name) / math.max(1, ns.manaMax())
  if M.fight then M.fight.mana = M.fight.mana + frac end
  if M.cur and not M.cur.done then M.cur.mana = M.cur.mana + frac end
end

------------------------------------------------------------------------------------------
-- Uceni: nahradit doporuceni tim, co v dane situaci hrajes ty
------------------------------------------------------------------------------------------
local MIN_SHOWN = 10
function M.swap(c, a)
  if not ns.db.learn or not a or a.urgent or a.kind ~= 'spell' or not c.inCombat then return a end
  local key = a.name .. '|' .. M.sit(c)
  a.learnKey = key
  local L = learnDB()[key]
  if not L or L.shown < MIN_SHOWN then return a end
  local miss = L.shown - L.followed
  if L.followed / L.shown > 0.3 then return a end
  local best, bn = nil, 0
  for n, k in pairs(L.instead) do if k > bn then best, bn = n, k end end
  if not best or bn < miss * 0.5 or not ns.known(best) then return a end
  if ns.cdLeft(best) > 0.3 then return a end
  if c.imm and ns.Immune.bad(c.imm, best) then return a end
  local b = { name = best, kind = 'spell', learned = true, orig = a.name, learnKey = key, at = a.at, wait = a.wait,
    reason = ('Podle tveho hrani: %s (misto %s)'):format(best, a.name) }
  if M.fight and not L.announced then
    L.announced = true
    M.fight.learnedNew[#M.fight.learnedNew + 1] = ('%s: hrajes %s misto %s - nabizim to tak'):format(M.sitText(M.sit(c)), best, a.name)
  end
  return b
end

------------------------------------------------------------------------------------------
-- Konec boje: shrnuti
------------------------------------------------------------------------------------------
function M.endFight()
  -- konec boje: cil, ktery mel pred chvili skoro nula HP, padl
  if M.cur and not M.cur.done and M.cur.lowAt and GetTime() - M.cur.lowAt < 8 then
    M.cur.done = true
    finishKill(M.cur, M.cur.lowAt)
    M.stat.byEnd = M.stat.byEnd + 1
  end
  local F = M.fight
  M.fight = nil
  if not F then return end
  local dur = GetTime() - F.start
  if M.idleSince then M.idleSince = nil end
  if dur < 6 or F.casts < 3 then return end
  local s = { dur = dur, casts = F.casts, kills = F.kills, mana = F.mana, idle = F.idle, tips = {} }
  s.follow = F.judged > 0 and (F.followed / F.judged) or nil
  -- tipy
  local tips = s.tips
  if F.idle > math.max(3, dur * 0.12) then
    tips[#tips + 1] = ('Stal jsi %.0f s bez castu - cast hned, jak dobehne GCD'):format(F.idle)
  end
  local devs = {}
  for k, n in pairs(F.dev) do devs[#devs + 1] = { k = k, n = n } end
  table.sort(devs, function(x, y) return x.n > y.n end)
  for i = 1, math.min(2, #devs) do
    if devs[i].n >= 2 then
      local rec, did = devs[i].k:match('^(.-)>(.*)$')
      tips[#tips + 1] = ('Misto %s jsi %dx dal %s'):format(rec, devs[i].n, did)
    end
  end
  -- dungeon: AoE a aggro. Kdyz AoE strhne aggro, priste pockame dele; kdyz ne, pomalu zkracujeme.
  if F.tank then
    local d = ns.db.aoeDelay or 3
    if (F.aoeAggro or 0) > 0 then
      ns.db.aoeDelay = math.min(8, d + 1)
      tips[#tips + 1] = ('AoE strhlo aggro - priste AoE az po %.1f s od pullu'):format(ns.db.aoeDelay)
    elseif (F.aoeCasts or 0) > 0 then
      ns.db.aoeDelay = math.max(1.5, d - 0.25)
    end
    if (F.aggroPulls or 0) > (F.aoeAggro or 0) then
      tips[#tips + 1] = ('Strhl jsi aggro %dx - bij cil tanka a nech ho chvili sbirat'):format(F.aggroPulls - (F.aoeAggro or 0))
    end
  end
  -- interrupty: kolik dulezitych castu cil dokoncil
  local kicked = ((ns.Party and ns.Party.myKicks) or 0) - (F.kicks0 or 0)
  local canKick = ns.known('Counterspell') or (UnitExists('pet') and safe(pc(UnitCreatureFamily, 'pet')) == 'Felhunter')
  if canKick and (F.kickAsk or 0) >= 2 and kicked < F.kickAsk then
    tips[#tips + 1] = ('Prerusit stalo za to %dx (heal/CC/silny spell), prerusil jsi %dx'):format(F.kickAsk, kicked)
  end
  for _, l in ipairs(F.learnedNew) do tips[#tips + 1] = '|cff88ccffNauceno:|r ' .. l end
  local need = M.needMana(nil, IsInGroup and IsInGroup())
  if need then s.need = need end
  ns.db.lastFight = s
  if ns.UI and ns.UI.showSummary and ns.db.summary then ns.UI.showSummary(s) end
end

-- /cm learn
function M.report()
  local n = 0
  for key, L in pairs(learnDB()) do
    if L.shown >= MIN_SHOWN and L.followed / L.shown <= 0.3 then
      local best, bn = nil, 0
      for nm, k in pairs(L.instead) do if k > bn then best, bn = nm, k end end
      local rec, sit = key:match('^(.-)|(.*)$')
      if best then
        ns.say(('%s (%s): hrajes %s (%d z %d)'):format(rec, M.sitText(sit or ''), best, bn, L.shown))
        n = n + 1
      end
    end
  end
  if n == 0 then ns.say('zatim nic nauceneho (potrebuju aspon 10 situaci, kde hrajes jinak)') end
  local count = 0 for _ in pairs(mobs()) do count = count + 1 end
  local G = global()
  ns.say(('Pamet: %d druhu mobu | solo: boj %.0f s, %.0f %% many (%d) | parta: boj %.0f s, %.0f %% many (%d)'):format(
    count, G.s.ttd, G.s.mana * 100, G.s.n, G.g.ttd, G.g.mana * 100, G.g.n))
  local st = M.stat
  ns.say(('Diagnostika: cil %s | sledovano %d, zabito podle smrti %d / malo HP+zmena cile %d / konec boje %d | smrt citelna: %s'):format(
    tostring(ns.Immune and ns.Immune.tname), st.started, st.byDead, st.byLow, st.byEnd,
    tostring(safeBool(pc(UnitIsDeadOrGhost, 'target')))))
end

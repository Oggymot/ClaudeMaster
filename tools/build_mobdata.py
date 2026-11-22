"""Build MobData.lua from the vmangos sqlite world DB.
usage: python -I build_mobdata.py <mangos.sqlite> <out.lua>
"""
import sqlite3, sys, re

db, out = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db)
c.row_factory = sqlite3.Row

# --- spells -------------------------------------------------------------------------------
spells = {}
for r in c.execute('select * from spell_template order by build'):
    spells[r['entry']] = r  # last build wins

HEAL_EFFECTS = {10, 136}          # HEAL, HEAL_PCT? (10 = heal)
HEAL_AURAS = {8}                  # periodic heal
CC_MECH = {1: 'charm', 2: 'disorient', 5: 'fear', 9: 'silence', 10: 'sleep', 12: 'stun', 13: 'freeze',
           14: 'knockout', 17: 'polymorph', 20: 'shackle', 24: 'horror', 7: 'root'}
CC_AURAS = {12: 'stun', 7: 'fear', 6: 'charm', 26: 'root', 27: 'silence', 95: 'sleep'}  # aura ids (approx)
DMG_EFFECTS = {2, 9}              # school damage, health leech
SUMMON_EFFECTS = {28, 41, 42, 56, 87, 88, 89, 90}
SCHOOLS = {0: 'P', 1: 'H', 2: 'F', 3: 'N', 4: 'R', 5: 'S', 6: 'A'}   # R = fRost
# castingTimeIndex -> ms (common vanilla values)
CAST_MS = {1: 0, 2: 250, 3: 500, 4: 1000, 5: 2000, 6: 5000, 7: 10000, 8: 20000, 9: 30000, 10: 1000, 11: 2000,
           12: 5000, 13: 180000, 14: 3000, 15: 4000, 16: 1500, 18: 2500, 19: 2500, 20: 2300, 22: 3500, 23: 1800,
           24: 1700, 25: 1200, 26: 4500}

def classify(sid):
    s = spells.get(sid)
    if not s or not s['name']:
        return None
    name = s['name']
    effs = [s['effect1'], s['effect2'], s['effect3']]
    auras = [s['effectApplyAuraName1'], s['effectApplyAuraName2'], s['effectApplyAuraName3']]
    mechs = [s['mechanic'], s['effectMechanic1'], s['effectMechanic2'], s['effectMechanic3']]
    cast = CAST_MS.get(s['castingTimeIndex'], 0)
    tag = None
    if any(e in HEAL_EFFECTS for e in effs) or any(a in HEAL_AURAS for a in auras):
        tag = 'h'
    else:
        for m in mechs:
            if m in CC_MECH:
                tag = 'c'
                break
        if not tag and any(a in CC_AURAS for a in auras):
            tag = 'c'
    if not tag and any(e in SUMMON_EFFECTS for e in effs):
        tag = 's'
    if not tag and any(e in DMG_EFFECTS for e in effs) or (not tag and any(a == 3 for a in auras)):
        tag = 'd'
    if not tag:
        tag = 'o'   # other (buff, debuff...)
    school = SCHOOLS.get(s['school'], 'P')
    return (name, tag, school, cast)

# --- flee + scripted casts (creature_ai) -----------------------------------------------------
scripts = {}
for r in c.execute('select id, command, datalong from creature_ai_scripts'):
    scripts.setdefault(r['id'], []).append((r['command'], r['datalong']))
flee, aiSpells = set(), {}
for r in c.execute('select creature_id, action1_script, action2_script, action3_script from creature_ai_events'):
    for a in (r['action1_script'], r['action2_script'], r['action3_script']):
        for cmd, dl in scripts.get(a, []):
            if cmd == 47:
                flee.add(r['creature_id'])
            elif cmd == 15 and dl:
                aiSpells.setdefault(r['creature_id'], set()).add(dl)

# --- spell lists ------------------------------------------------------------------------------
lists = {}
for r in c.execute('select * from creature_spells'):
    ids = [r['spellId_%d' % i] for i in range(1, 9) if r['spellId_%d' % i]]
    lists[r['entry']] = ids

# --- loot: questove itemy, vlastni dropy (zelene+), caste cloth/kuze ---------------------------
items = {}
for r in c.execute('select entry, name, quality, class, subclass from item_template order by patch'):
    items[r['entry']] = r
loot = {}
for r in c.execute('select entry, item, ChanceOrQuestChance ch, groupid g, mincountOrRef ref from creature_loot_template'):
    if r['ref'] < 0:
        continue   # odkaz na spolecnou tabulku (nahodne world dropy)
    loot.setdefault(r['entry'], []).append((r['item'], r['ch'], r['g']))

def drops(lootid):
    rows = loot.get(lootid)
    if not rows:
        return ''
    # v groupe: polozky s 0 % si deli zbytek do 100 %
    gsum, gzero = {}, {}
    for it, ch, g in rows:
        if g and ch == 0:
            gzero[g] = gzero.get(g, 0) + 1
        elif g and ch > 0:
            gsum[g] = gsum.get(g, 0) + ch
    out, seen = [], set()
    for it, ch, g in rows:
        i = items.get(it)
        if not i or it in seen:
            continue
        seen.add(it)
        if g and ch == 0:
            ch = (100 - gsum.get(g, 0)) / gzero[g]
        quest = ch < 0
        ch = abs(ch)
        cloth = i['class'] == 7 and re.search(r'(Cloth|Leather|Scraps)$', i['name']) and ch >= 10
        if quest:
            out.append((0, it, ch, 'q', i['name']))
        elif i['quality'] >= 2 and ch >= 0.5:
            out.append((1, it, ch, str(i['quality']), i['name']))
        elif cloth:
            out.append((2, it, ch, 'c', i['name']))
    out.sort(key=lambda x: (x[0], -x[2]))
    return ';'.join('%d~%s~%s~%s' % (it, ('%.1f' % ch).rstrip('0').rstrip('.'), fl, nm.replace(';', ',').replace('|', '/'))
                    for _, it, ch, fl, nm in out[:4])

# --- creatures --------------------------------------------------------------------------------
cre = {}
for r in c.execute('select * from creature_template order by patch'):
    cre[r['entry']] = r

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

rows = []
for e, r in sorted(cre.items()):
    name = r['name']
    if not name or r['type'] == 8:              # critters
        continue
    if r['level_max'] > 63 or r['level_min'] < 1:
        continue
    if r['npc_flags'] and r['rank'] == 0 and not r['spell_list_id']:   # vendors/trainers etc.
        continue
    if re.search(r'(Trigger|DND|\[|Dummy|Invisible|Visual|Bunny)', name):
        continue
    sids = set(lists.get(r['spell_list_id'], [])) | aiSpells.get(e, set())
    sp = []
    seen = set()
    for sid in sorted(sids):
        k = classify(sid)
        if not k or k[0] in seen or k[1] == 'o':
            continue
        seen.add(k[0])
        sp.append('%s:%s%s%s' % (k[1], k[2], '+' if k[3] >= 1000 else '', esc(k[0]).replace(';', ',')))
    res = []
    for sch, col in (('F', 'fire_res'), ('R', 'frost_res'), ('S', 'shadow_res'), ('A', 'arcane_res'), ('N', 'nature_res')):
        if (r[col] or 0) >= 75:
            res.append('%s%d' % (sch, r[col]))
    rows.append('[%d]="%s|%d|%d|%d|%d|%d|%d|%s|%s|%d|%d|%s|%s"' % (
        e, esc(name), r['level_min'], r['level_max'], r['rank'], r['type'],
        r['mechanic_immune_mask'] or 0, r['school_immune_mask'] or 0,
        ','.join(res), '1' if e in flee else '', r['unit_class'] or 0,
        int(r['call_for_help_range'] or 0), ';'.join(sp), esc(drops(r['loot_id']))))

with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- ClaudeMaster: data o mobech z vmangos world DB (GPL-2.0, https://github.com/vmangos/core)\n')
    f.write('-- Vygenerovano skriptem build_mobdata.py. Format: "jmeno|lvlMin|lvlMax|rank|typ|mechImm|schoolImm|odolnosti|utika|classa|pomoc|kouzla|dropy"\n')
    f.write('-- dropy: "itemID~sance~druh~jmeno" oddelene ";"  druh q=quest c=cloth/kuze 2-5=kvalita\n')
    f.write('-- kouzla: "tag:skola[+]jmeno" oddelene ";"  tag h=leci c=CC s=privolava d=dmg; + = kouzlo se castuje (jde prerusit)\n')
    f.write('local ADDON, ns = ...\n')
    f.write('ns.MOBDATA = {\n')
    for i in range(0, len(rows), 1):
        f.write(rows[i] + ',\n')
    f.write('}\n')
print(len(rows), 'mobs')

-- ClaudeMaster: radce pro talenty.
-- Buildy pro vsechny classy (3 smery + vlastni ulozeny); ret a resto podle MythicSim (Forever); v tooltipu talentu napise, kolik bodu sem dat a proc,
-- u ostatnich proc ne a co ho zamyka (body ve vetvi, sipka). Pri volnem bodu napise do chatu, co vzit.
-- /cm talent = dalsi 3 doporucene body.
local ADDON, ns = ...
if not ns.enabled then return end
local pc, safe, safeNum, safeBool = ns.pc, ns.safe, ns.safeNum, ns.safeBool

local T = {}
ns.Talents = T

-- { jmeno, cilovy pocet bodu, proc } v poradi priority (ktery volny talent brat driv).
-- Talent, ktery ve hre neexistuje, se preskoci; cil se zkrati na max. rank talentu ve hre.
-- band = hlavni vetev (1-3 zleva), gear = vahy statu v Gear.lua, druid = spec rotace druida.
-- sim = build overeny simulatorem (MythicSim); ostatni jsou pripravene podle klasickych buildu.
local BUILDS = {
  ------------------------------------------------------------------ PALADIN
  ret = {
    class = 'PALADIN', band = 3, gear = 'ret', sim = true,
    label = 'Retribution (2H)', desc = 'Dvourucni zbran, Judgement a sealy. Nejlepsi na questovani solo.',
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
  prot = {
    class = 'PALADIN', band = 2, gear = 'prot',
    label = 'Protection (tank)', desc = 'Stit, Holy Shield, Righteous Fury. Tankovani v dungeonech.',
    trees = { 'Holy', 'Protection', 'Retribution' },
    list = {
      { 'Redoubt', 5, 'Po zasahu blokujes stitem mnohem casteji.' },
      { 'Toughness', 5, '+armor z vybaveni = mensi rany.' },
      { 'Improved Righteous Fury', 3, 'Vic threatu - moby se od tebe nepohnou.' },
      { 'Precision', 3, '+1 % hit za bod: tvoje udery (a threat) netrefi vedle.' },
      { 'Shield Specialization', 3, 'Blok stitem ti vraci manu.' },
      { 'Anticipation', 5, '+defense: mene krit zasahu do tebe.' },
      { 'Blessing of Kings', 1, '+10 % ke vsem statum pro celou partu.' },
      { 'Improved Devotion Aura', 5, 'Vic armoru pro tebe i partu.' },
      { 'One-Handed Weapon Specialization', 5, 'Silnejsi udery s jednorucni zbrani (i holy damage = threat).' },
      { 'Holy Shield', 1, 'Blok + holy damage pri kazdem bloku - hlavni tankovaci kouzlo.' },
      { "Templar's Bulwark", 1, 'Absorbcni stit na nebezpecne chvile.' },
      { 'Hammer of the Righteous', 1, 'Uder do vice mobu - AoE threat.' },
      { 'Improved Holy Shield', 3, 'Holy Shield vydrzi dele a bije vic.' },
      { 'Blessing of Sanctuary', 1, 'Mene damage a holy damage pri bloku.' },
      { 'Divine Strength', 5, '+Strength = vic blokovane hodnoty a threatu.' },
      { 'Divine Intellect', 5, 'Vic many - tank s manou drzi aggro dele.' },
      { 'Benediction', 5, 'Levnejsi Judgement a sealy.' },
    },
    no = {},
    tree = {
      'Leceni. Jako tank odsud jen Divine Strength a Divine Intellect.',
      'Tvoje hlavni vetev, ale tenhle talent tankovi malo pomuze.',
      'Damage s 2H zbrani - tank ma stit (vyjimka: Benediction).',
    },
  },
  holy = {
    class = 'PALADIN', band = 1, gear = 'holy',
    label = 'Holy (lecitel)', desc = 'Holy Light, Flash of Light, Holy Shock. Leceni party.',
    trees = { 'Holy', 'Protection', 'Retribution' },
    list = {
      { 'Divine Intellect', 5, 'Vic many = delsi leceni bez piti.' },
      { 'Spiritual Focus', 5, 'Leceni se pri zasahu nezdrzuje.' },
      { 'Healing Light', 3, 'Holy Light a Flash of Light leci vic.' },
      { 'Illumination', 5, 'Krit leceni ti vrati manu.' },
      { 'Improved Lay on Hands', 2, 'Lay on Hands da navic armor a casteji.' },
      { 'Consecration', 1, 'AoE damage na pull, kdyz neni co lecit.' },
      { 'Divine Favor', 1, 'Jisty krit pristiho leceni - nouzove tlacitko.' },
      { 'Holy Power', 5, '+krit holy kouzel = vic Illumination many.' },
      { 'Sanctified Light', 3, 'Holy Light casteji kritne.' },
      { 'Holy Shock', 1, 'Okamzite leceni (nebo damage).' },
      { 'Improved Blessing of Wisdom', 2, 'Vic many z Blessing of Wisdom.' },
      { 'Holy Guidance', 5, 'Leceni sili s Intellectem.' },
      { 'Divine Illumination', 1, 'Polovicni cena kouzel na chvili.' },
      { 'Benediction', 5, 'Levnejsi instantni kouzla.' },
      { 'Improved Devotion Aura', 5, 'Vic armoru pro partu.' },
    },
    no = {},
    tree = {
      'Tvoje hlavni vetev, ale tenhle talent lecitelovi malo pomuze.',
      'Tankovani - jako lecitel odsud jen Improved Devotion Aura.',
      'Damage - jako lecitel odsud jen Benediction.',
    },
  },
  ------------------------------------------------------------------ DRUID
  resto = {
    class = 'DRUID', band = 3, gear = 'resto', druid = 'resto', sim = true,
    label = 'Restoration (lecitel)', desc = 'HoTy, Swiftmend, Wild Growth. Leceni party.',
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
  balance = {
    class = 'DRUID', band = 1, gear = 'balance', druid = 'balance',
    label = 'Balance (moonkin)', desc = 'Wrath, Starfire, Moonfire, Insect Swarm. Kouzelnik na dalku.',
    trees = { 'Balance', 'Feral', 'Restoration' },
    list = {
      { 'Improved Wrath', 5, 'Wrath se castuje rychleji - tvuj hlavni filler.' },
      { "Nature's Reach", 2, 'Delsi dosah kouzel - bezpecnejsi pull.' },
      { 'Improved Moonfire', 5, 'Moonfire bije vic a casteji kritne.' },
      { 'Vengeance', 5, 'Silnejsi krity kouzel.' },
      { 'Moonglow', 3, 'Levnejsi kouzla - mene piti.' },
      { "Nature's Grace", 1, 'Po kritu je pristi kouzlo rychlejsi.' },
      { 'Improved Starfire', 5, 'Starfire se castuje rychleji.' },
      { 'Moonfury', 5, '+damage Wrath, Starfire a Moonfire.' },
      { 'Moonkin Form', 1, 'Armor, krit pro partu a levnejsi kouzla.' },
      { 'Insect Swarm', 1, 'Dalsi DoT na cil.' },
      { 'Genesis', 5, 'DoTy a HoTy sili.' },
      { "Nature's Majesty", 2, '+krit Wrath a Starfire.' },
      { 'Eclipse', 3, 'Stridani Wrath/Starfire posiluje dalsi kouzlo.' },
      { "Nature's Splendor", 1, 'DoTy vydrzi dele.' },
      { 'Overgrowth', 1, 'Talent Foreveru z Balance - vem, az zbydou body.' },
      { 'Furor', 5, 'Mana/energie pri premene (z Restoration).' },
    },
    no = {},
    tree = {
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Medved a kocka - jako moonkin je nepotrebujes.',
      'Leceni - jako moonkin odsud jen Furor.',
    },
  },
  feral = {
    class = 'DRUID', band = 2, gear = 'feral', druid = 'feral',
    label = 'Feral (kocka / medved)', desc = 'Kocka na damage, medved na tankovani.',
    trees = { 'Balance', 'Feral', 'Restoration' },
    list = {
      { 'Ferocity', 5, 'Levnejsi Maul, Swipe, Claw, Rake - vic uderu.' },
      { 'Furor', 5, 'Rage/energie hned po premene.' },
      { 'Feral Instinct', 5, 'Vic threatu v medvedovi a lepsi plizeni kocky.' },
      { 'Thick Hide', 5, 'Vic armoru - mensi rany.' },
      { 'Sharpened Claws', 3, '+krit ve forme.' },
      { 'Feral Charge', 1, 'Skok k cili a preruseni kouzla.' },
      { 'Shredding Attacks', 2, 'Levnejsi Shred a Lacerate.' },
      { 'Predatory Strikes', 3, '+utok ve forme podle levelu.' },
      { 'Blood Frenzy', 2, 'Krit kocky = extra combo bod.' },
      { 'Savage Fury', 2, 'Silnejsi Claw, Rake, Maul, Swipe.' },
      { 'Heart of the Wild', 5, '+Strength v kocce, +Stamina v medvedovi.' },
      { 'Leader of the Pack', 1, '+krit pro celou partu.' },
      { 'Brutal Impact', 2, 'Delsi omraceni (Bash).' },
      { 'Primal Bite', 1, 'Talent Foreveru: silny uder ve forme.' },
      { 'Rend and Tear', 5, 'Silnejsi Maul a Shred na krvacejici cil.' },
      { 'Natural Instinct', 5, 'Talent Foreveru z Feral.' },
      { 'Predatory Discipline', 3, 'Talent Foreveru z Feral.' },
      { 'Natural Reaction', 3, 'Vic dodge v medvedovi.' },
      { 'Lacerate', 1, 'Krvaceni a threat v medvedovi.' },
      { 'Shifting Power', 1, 'Talent Foreveru z Feral.' },
    },
    no = {},
    tree = {
      'Kouzla na dalku - ve forme je nepouzijes.',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Leceni - jako feral odsud jen Furor.',
    },
  },
  ------------------------------------------------------------------ MAGE
  frost = {
    class = 'MAGE', band = 3, gear = 'frost',
    label = 'Frost', desc = 'Frostbolt, zpomaleni, Shatter s Frost Novou. Nejbezpecnejsi na questy i dungeony.',
    trees = { 'Arcane', 'Fire', 'Frost' },
    list = {
      { 'Improved Frostbolt', 5, 'Frostbolt se castuje rychleji - tvuj hlavni damage.' },
      { 'Ice Shards', 5, 'Silnejsi krity mrazivych kouzel.' },
      { 'Frostbite', 3, 'Sance zmrazit moba na miste - Shatter a bezpeci.' },
      { 'Elemental Precision', 3, 'Mene minuti - mene zbytecne utracene many.' },
      { 'Permafrost', 3, 'Zpomaleni vydrzi dele a zpomali vic.' },
      { 'Piercing Ice', 3, '+2 % mrazivy damage za bod.' },
      { 'Improved Blizzard', 3, 'Blizzard zpomaluje - AoE kiting.' },
      { 'Cold Snap', 1, 'Obnovi mrazive cooldowny (Nova, Ice Block, Barrier).' },
      { 'Frost Channeling', 3, 'Levnejsi mrazova kouzla.' },
      { 'Shatter', 5, 'Zmrazeny mob = +krit: Frost Nova + Frostbolt/Ice Lance.' },
      { 'Fingers of Frost', 3, 'Proc: pristi kouzlo jako na zmrazeneho moba (Ice Lance).' },
      { 'Ice Barrier', 1, 'Absorbcni stit - klidne castovani.' },
      { 'Arctic Reach', 2, 'Delsi dosah Frostboltu a Blizzardu.' },
      { 'Improved Frost Nova', 2, 'Frost Nova casteji.' },
      { "Winter's Chill", 5, 'Cil dostava vic mraziveho kritu.' },
      { 'Icy Veins', 1, 'Rychlejsi castovani na chvili.' },
      { 'Ice Block', 1, 'Nouzove: imunita na 10 s.' },
      { 'Improved Cone of Cold', 3, 'Silnejsi Cone of Cold na AoE.' },
      { 'Arcane Subtlety', 2, 'Mene threatu (z Arcane).' },
      { 'Arcane Focus', 3, 'Mene minuti (z Arcane).' },
      { 'Arcane Concentration', 5, 'Obcas kouzlo zdarma (z Arcane).' },
    },
    no = {},
    tree = {
      'Arcane - jako Frost odsud jen Arcane Subtlety, Arcane Focus a Arcane Concentration.',
      'Ohen - body tady chybi ve Frostu.',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
    },
  },
  fire = {
    class = 'MAGE', band = 2, gear = 'fire',
    label = 'Fire', desc = 'Fireball, Pyroblast, Ignite, Combustion. Nejvic damage, ale mene kontroly.',
    trees = { 'Arcane', 'Fire', 'Frost' },
    list = {
      { 'Improved Fireball', 5, 'Fireball se castuje rychleji.' },
      { 'Ignite', 5, 'Krit ohnem zapali cil - hodne damage navic.' },
      { 'Flame Throwing', 2, 'Delsi dosah ohnivych kouzel.' },
      { 'Improved Scorch', 3, 'Scorch zvysuje ohnivy damage na cili.' },
      { 'Incineration', 2, '+krit Scorch a Fire Blast.' },
      { 'Impact', 5, 'Ohniva kouzla obcas omraci.' },
      { 'Pyroblast', 1, 'Velky uvodni uder.' },
      { 'Burning Soul', 2, 'Ohniva kouzla se mene zdrzuji a delaji mene threatu.' },
      { 'Master of Elements', 3, 'Krit vraci manu.' },
      { 'Critical Mass', 3, '+krit ohnivych kouzel.' },
      { 'Blast Wave', 1, 'AoE uder a zpomaleni kolem tebe.' },
      { 'Fire Power', 5, '+2 % ohnivy damage za bod.' },
      { 'Combustion', 1, 'Krit na nekolik kouzel za sebou.' },
      { 'Improved Flamestrike', 3, 'Flamestrike casteji kritne.' },
      { 'Arcane Subtlety', 2, 'Mene threatu (z Arcane).' },
      { 'Arcane Focus', 3, 'Mene minuti (z Arcane).' },
      { 'Arcane Concentration', 5, 'Obcas kouzlo zdarma (z Arcane).' },
    },
    no = {},
    tree = {
      'Arcane - jako Fire odsud jen Arcane Subtlety, Arcane Focus a Arcane Concentration.',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Mraz - jako Fire body tady chybi.',
    },
  },
  arcane = {
    class = 'MAGE', band = 1, gear = 'arcane',
    label = 'Arcane', desc = 'Arcane Missiles, Missile Barrage, Arcane Power. Hodne many a velke vybuchy.',
    trees = { 'Arcane', 'Fire', 'Frost' },
    list = {
      { 'Arcane Focus', 5, 'Mene minuti arcane kouzel.' },
      { 'Arcane Subtlety', 2, 'Mene threatu.' },
      { 'Improved Arcane Missiles', 5, 'Arcane Missiles se nezdrzuji pri zasahu.' },
      { 'Arcane Concentration', 5, 'Obcas kouzlo zdarma.' },
      { 'Magic Absorption', 5, 'Odolnost a mana z odolanych kouzel.' },
      { 'Arcane Meditation', 3, 'Regenerace many i pri castovani.' },
      { 'Improved Arcane Explosion', 3, 'Arcane Explosion casteji kritne.' },
      { 'Presence of Mind', 1, 'Pristi kouzlo okamzite.' },
      { 'Arcane Mind', 5, 'Vic Intellectu = vic many.' },
      { 'Arcane Instability', 3, '+damage a krit vsech kouzel.' },
      { 'Missile Barrage', 3, 'Proc: rychle Arcane Missiles zdarma.' },
      { 'Arcane Power', 1, '+30 % damage na chvili.' },
      { 'Wand Specialization', 2, 'Silnejsi wand pri setreni many.' },
      { 'Improved Mana Shield', 2, 'Mana Shield stoji mene.' },
      { 'Improved Counterspell', 2, 'Counterspell i umlci.' },
      { 'Improved Frostbolt', 5, 'Rychlejsi Frostbolt (z Frost).' },
    },
    no = {},
    tree = {
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Ohen - jako Arcane body tady chybi.',
      'Mraz - jako Arcane odsud jen Improved Frostbolt.',
    },
  },
  ------------------------------------------------------------------ WARLOCK
  destro = {
    class = 'WARLOCK', band = 3, gear = 'destro',
    label = 'Destruction', desc = 'Searing Pain / Incinerate, Immolate, Conflagrate, Shadowburn. Rychly primy damage.',
    trees = { 'Affliction', 'Demonology', 'Destruction' },
    list = {
      { 'Bane', 5, 'Rychlejsi Shadow Bolt, Immolate a Soul Fire.' },
      { 'Devastation', 5, '+krit Destruction kouzel.' },
      { 'Cataclysm', 5, 'Levnejsi Destruction kouzla - mene Life Tapu.' },
      { 'Improved Searing Pain', 5, 'Searing Pain casteji kritne.' },
      { 'Agonizing Flames', 3, 'Talent Foreveru: +Destruction damage a krit Searing Pain.' },
      { 'Ruin', 5, 'Silnejsi krity Destruction kouzel.' },
      { 'Emberstorm', 5, '+2 % ohnivy damage za bod.' },
      { 'Improved Immolate', 5, 'Silnejsi uvodni uder Immolate.' },
      { 'Conflagrate', 1, 'Okamzity uder pres Immolate.' },
      { 'Shadow and Flame', 5, 'Talent Foreveru: Conflagrate nespotrebuje Immolate.' },
      { 'Shadowburn', 1, 'Okamzite dorazeni + soul shard.' },
      { 'Intensity', 2, 'Ohniva kouzla se mene zdrzuji pri zasahu.' },
      { 'Destructive Reach', 2, 'Delsi dosah a mene threatu.' },
      { 'Improved Shadow Bolt', 5, 'Shadow Bolt krit zvysi stinovy damage na cili.' },
      { 'Improved Corruption', 5, 'Okamzita Corruption (z Affliction).' },
      { 'Improved Life Tap', 2, 'Vic many z Life Tapu (z Affliction).' },
    },
    no = {},
    tree = {
      'Affliction - jako Destro odsud jen Improved Corruption a Improved Life Tap.',
      'Demoni - jako Destro body tady chybi.',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
    },
  },
  affli = {
    class = 'WARLOCK', band = 1, gear = 'affli',
    label = 'Affliction', desc = 'DoTy na vice mobu, Drain Life, Nightfall. Malo piti, skvele na questy.',
    trees = { 'Affliction', 'Demonology', 'Destruction' },
    list = {
      { 'Improved Corruption', 5, 'Okamzita Corruption - DoT bez castu.' },
      { 'Suppression', 5, 'Mene minuti DoTu a curse.' },
      { 'Improved Life Tap', 2, 'Vic many z Life Tapu.' },
      { 'Improved Curse of Agony', 3, 'Silnejsi Agony.' },
      { 'Improved Drain Soul', 2, 'Drain Soul vraci manu.' },
      { 'Fel Concentration', 5, 'Drain kouzla se nezdrzuji.' },
      { 'Nightfall', 2, 'Proc: okamzity Shadow Bolt zdarma.' },
      { 'Grim Reach', 2, 'Delsi dosah Affliction kouzel.' },
      { 'Siphon Life', 1, 'DoT, ktery te leci.' },
      { 'Shadow Mastery', 5, '+2 % stinovy damage za bod.' },
      { 'Amplify Curse', 1, 'Silnejsi curse.' },
      { 'Curse of Exhaustion', 1, 'Zpomaleni moba - kiting.' },
      { 'Improved Drain Life', 5, 'Silnejsi Drain Life.' },
      { 'Dark Pact', 1, 'Mana z peta.' },
      { 'Demonic Embrace', 5, 'Vic Stamina (z Demonology).' },
    },
    no = {},
    tree = {
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Demoni - jako Affliction odsud jen Demonic Embrace.',
      'Destruction - jako Affliction body tady chybi.',
    },
  },
  demo = {
    class = 'WARLOCK', band = 2, gear = 'demo',
    label = 'Demonology', desc = 'Silny pet (Voidwalker / Felguard), Soul Link. Nejodolnejsi solo.',
    trees = { 'Affliction', 'Demonology', 'Destruction' },
    list = {
      { 'Demonic Embrace', 5, 'Vic Stamina = vic HP pro Life Tap.' },
      { 'Fel Intellect', 5, 'Vic many tobe i petovi.' },
      { 'Improved Voidwalker', 3, 'Voidwalker vydrzi vic.' },
      { 'Fel Domination', 1, 'Rychle privolani peta v boji.' },
      { 'Fel Stamina', 5, 'Vic HP petovi.' },
      { 'Master Summoner', 2, 'Rychlejsi a levnejsi privolani.' },
      { 'Unholy Power', 5, 'Silnejsi utoky peta.' },
      { 'Improved Imp', 3, 'Silnejsi Imp.' },
      { 'Demonic Sacrifice', 1, 'Obetuj peta za silny buff.' },
      { 'Master Demonologist', 5, 'Buff podle peta.' },
      { 'Soul Link', 1, 'Cast damage jde na peta.' },
      { 'Demonic Brand', 3, 'Talent Foreveru z Demonology.' },
      { 'Improved Corruption', 5, 'Okamzita Corruption (z Affliction).' },
      { 'Improved Life Tap', 2, 'Vic many z Life Tapu (z Affliction).' },
    },
    no = {},
    tree = {
      'Affliction - jako Demo odsud jen Improved Corruption a Improved Life Tap.',
      'Tvoje hlavni vetev, ale tenhle talent ti malo pomuze.',
      'Destruction - jako Demo body tady chybi.',
    },
  },
}
T.BUILDS = BUILDS
local DEFAULT = { MAGE = 'frost', WARLOCK = 'destro', PALADIN = 'ret', DRUID = 'resto' }
local ORDER = { 'frost', 'fire', 'arcane', 'destro', 'affli', 'demo', 'ret', 'prot', 'holy', 'balance', 'feral', 'resto' }

-- vlastni build = ulozene talenty postavy (poradi: vetev s nejvic body, pak shora dolu)
function T.custom()
  local c = ns.db and ns.db.customBuild
  if type(c) ~= 'table' or type(c.list) ~= 'table' then return nil end
  local first = BUILDS[DEFAULT[ns.class] or ''] or {}
  c.class, c.no = ns.class, {}
  c.tree = { 'Neni v tvem ulozenem buildu.', 'Neni v tvem ulozenem buildu.', 'Neni v tvem ulozenem buildu.' }
  c.trees = first.trees or { '1', '2', '3' }
  return c
end
-- buildy pro moji classu (+ vlastni ulozeny)
function T.list()
  local out = {}
  for _, k in ipairs(ORDER) do if BUILDS[k].class == ns.class then out[#out + 1] = k end end
  if T.custom() then out[#out + 1] = 'custom' end
  return out
end
function T.get(k)
  if k == 'custom' then return T.custom() end
  return k and BUILDS[k]
end

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
T.band, T.spentIn = band, spentIn

-- vetev s nejvic body (nil = zadne body)
function T.mainBand()
  local best, bn = nil, 0
  for b = 1, 3 do local n = spentIn(b) if n > bn then best, bn = b, n end end
  return best
end
-- automaticky: druid podle specu rotace, ostatni podle vetve s nejvic body, jinak vychozi
function T.autoKey()
  if ns.class == 'DRUID' and ns.Druid and ns.Druid.spec then
    local sp = ns.Druid.spec()
    if sp and BUILDS[sp] then return sp end
  end
  local mb = T.mainBand()
  if mb then
    for k, b in pairs(BUILDS) do if b.class == ns.class and b.band == mb then return k end end
  end
  return DEFAULT[ns.class]
end
function T.buildKey()
  local k = ns.db and ns.db.talentBuild
  if k == 'custom' and T.custom() then return 'custom' end
  if k and BUILDS[k] and BUILDS[k].class == ns.class then return k end
  return T.autoKey()
end
function T.build() return T.get(T.buildKey()) end

-- vybrat build: talenty + vahy gearu + spec druida (nil = automaticky)
function T.select(k)
  local db = ns.db
  if k ~= nil and not T.get(k) then return end
  if k == nil and ns.class == 'DRUID' then db.druidSpec = nil end   -- auto: spec znovu podle talentu
  db.talentBuild = k
  local b = T.get(k or T.autoKey())
  if ns.class == 'DRUID' and k then db.druidSpec = b and b.druid or nil end
  if db.gearSpec ~= 'custom' and ns.Gear and ns.Gear.applySpec then pcall(ns.Gear.applySpec, (k and b and b.gear) or 'auto') end
end

-- ulozit soucasne talenty jako vlastni build
function T.saveCustom()
  pcall(ns.scanTalents)
  local seen, list = {}, {}
  for _, e in ipairs(ns.talentList or {}) do
    if (e.rank or 0) > 0 and e.name and not seen[e.name] then
      seen[e.name] = true
      list[#list + 1] = { e.name, e.rank, 'Ulozeno z tveho buildu.', b = band(e.x), y = e.y or 0 }
    end
  end
  if #list == 0 then return false end
  local mb = T.mainBand() or 1
  table.sort(list, function(a, b)
    if (a.b == mb) ~= (b.b == mb) then return a.b == mb end
    if a.b ~= b.b then return a.b < b.b end
    return a.y < b.y
  end)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = { it[1], it[2], it[3] } end
  ns.db.customBuild = { label = 'Vlastni (' .. date('%d.%m.') .. ')',
    desc = ('Tvoje talenty ulozene %s (%d talentu). Kdyz prestavis talenty, addon ti je poradi znovu.'):format(date('%d.%m.%Y'), #out),
    band = mb, gear = ns.Gear and ns.Gear.spec and ns.Gear.spec() or nil, list = out }
  return true
end

local function byNameMax()
  local tl = {}
  for _, e in ipairs(ns.talentList or {}) do
    if e.name and (not tl[e.name] or (e.rank or 0) > (tl[e.name].rank or 0)) then tl[e.name] = e end
  end
  return tl
end
-- kolik bodu mam mimo build (= kolik by se predelavalo u trenera)
function T.offBuild(k)
  local b = T.get(k or T.buildKey())
  if not b then return 0 end
  local want = {}
  for _, it in ipairs(b.list) do want[it[1]] = it[2] end
  local n = 0
  for name, e in pairs(byNameMax()) do n = n + math.max(0, (e.rank or 0) - (want[name] or 0)) end
  return n
end
-- kolik bodu build chce celkem (z talentu, ktere ve hre existuji) a kolik uz mam
function T.progress(k)
  local b = T.get(k or T.buildKey())
  if not b then return 0, 0 end
  local tl, have, total = byNameMax(), 0, 0
  for _, it in ipairs(b.list) do
    local e = tl[it[1]]
    if e then
      local tgt = math.min(it[2], e.max or it[2])
      total = total + tgt
      have = have + math.min(tgt, e.rank or 0)
    end
  end
  return have, total
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
  if T.freePoints() <= 0 then return false end   -- bez volneho bodu nic koupit nejde (API obcas tvrdi opak)
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
    local tgt = e and math.min(it[2], e.max or it[2]) or it[2]
    if e and cur < tgt then
      local can = canBuy(e)
      local r = { name = it[1], cur = cur, target = tgt, why = it[3], can = can, e = e }
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
    local tgt = math.min(rec[2], e.max or rec[2])
    if cur >= tgt then
      tt:AddLine(ic(OK) .. ('|cff00ff00Hotovo|r  %d/%d'):format(cur, tgt))
    elseif nxt and nxt.name == e.name and nxt.can then
      tt:AddLine(ic(OK) .. ('|cff00ff00Ted tohle|r  %d/%d'):format(cur, tgt))
    else
      tt:AddLine(ic(WAIT) .. ('|cffffd200Ber|r  %d/%d'):format(cur, tgt))
    end
    tt:AddLine('     ' .. rec[3], 0.9, 0.9, 0.9, true)
  else
    if b.sim or b.no[e.name] then tt:AddLine(ic(NO) .. '|cffff6060Neber|r')
    else tt:AddLine(ic(WAIT) .. '|cffff9933Mimo build|r') end
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
  local b = arg and arg ~= '' and T.get(arg)
  if b and b.class == ns.class then T.select(arg) ns.say('Build: ' .. b.label)
  elseif arg == 'auto' then T.select(nil) ns.say('Build: automaticky (' .. T.get(T.autoKey()).label .. ')')
  elseif arg == 'uloz' or arg == 'save' then
    if T.saveCustom() then T.select('custom') ns.say('Tvoje talenty ulozeny jako vlastni build.')
    else ns.say('Nemas zadne talenty k ulozeni.') end
  elseif arg and arg ~= '' then
    ns.say('Buildy: ' .. table.concat(T.list(), ', ') .. ', auto, uloz   (nebo /cm config -> Build)')
  end
  T.say(true)
end

# ClaudeMaster

Poradce pro **Mage**, **Warlock**, **Paladin**, **Druid**, **Shaman** a **Hunter** ve WoW Forever (Interface 16001).
Doporucuje, co castit, hlida manu, CC, preruseni, a pri hre ve dvou (mag + warlock) si addony
vymenuji data (cile, aggro, ovce, ready check).

## Instalace

- **WowUp:** *Get Addons* -> *Install from URL* -> vloz adresu tohoto repozitare.
- **Rucne:** stahni `ClaudeMaster-x.y.z.zip` z [Releases](../../releases) a rozbal do
  `World of Warcraft/_forever_/Interface/AddOns/`.

Prikazy: `/cm help`.

## Nastaveni

Tlacitko u minimapy (levy klik = nastaveni, pravy klik = panel, tahem ho posunes) nebo `/cm config`.
Zalozky: **Panel** (vzhled, velikost, kompaktni rezim), **Boj a mana**, **Parta** (cekani na tanka, AoE),
**Build**, **Veci a questy** (automaticke nasazovani lepsich veci, oprava, prodej, seznam questu), **Pamet a uceni**. Kazda volba ma tooltip s vysvetlenim.

**Build** = smer talentu a vahy statu pro gear. Pro kazdou classu jsou pripravene tri smery
(Mag: Frost / Fire / Arcane, Warlock: Destruction / Affliction / Demonology, Paladin: Retribution / Protection / Holy,
Druid: Balance / Feral / Restoration) a jde ulozit vlastni build z aktualnich talentu. Automaticky rezim bere vetev,
do ktere davas body. Pri zmene smeru addon ukaze, kolik bodu mas mimo build (reset u trenera) a radi dalsi body.

## Vydani nove verze

```
git tag v1.0.1
git push origin v1.0.1
```

GitHub Action postavi zip a vytvori Release; WowUp pak nabidne aktualizaci.

## Trasa questu (volitelne ForeverDB)

`/cm trasa` naplanuje poradi zastavek (odevzdat / splnit) s nejkratsi cestou, upozorni na navazujici questy
a nabidne questy po ceste. Okno jde zvetsit tahem za roh (kolecko = posun), v hlavicce je kompaktni rezim (K),
pruhledny rezim (T) a minimalizace do ikony (_), ktera po najeti ukaze trasu. Klik na navazujici quest
(nebo pravy klik na krok) otevre jeho detail v Pruzkumnikovi. Pod kroky "Splnit" jsou cile s pocty (jako seznam
questu ve hre) vc. postupu partaka; v kompaktnim rezimu je pocet za nazvem a cile v tooltipu. Potrebuje samostatny addon [ForeverDB](https://github.com/foreverfraddons/forever-db)
(GPL-3, data z QuestieDB, VMaNGOS, cMaNGOS, pfQuest a dalsich - viz jeho LICENSE-DATA). ClaudeMaster jeho data
nekopiruje, jen si ho na vyzadani nacte.

V nastaveni je i zalozka **Pruzkumnik**: hledani questu, NPC a itemu (`z:oblast` = questy v oblasti),
filtry *Kde levelit* (oblasti podle questu a XP pro tvuj level), *Dropy pro tebe* (zelene+ itemy z mobu
tveho levelu, ktere jsou vylepsenim) a *Blizko* (questy a rare moby pobliz). Klik na radek = sipka na mape.
Klik na oblast = seznam questu v ni, klik na quest = detail (zadavatel, misto plneni, odevzdani, odmeny,
reputace, cile, co je predtim, co quest odemkne a cely retez dal se souctem XP). Filtr *Moje questy* = quest log, klik na item = odkud pada, z jakeho questu je a kdo ho prodava. Pravy klik = sipka.

V trase jsou kroky bez cisel (s mezerou mezi kroky). Elitni, skupinove a dungeonove questy maji lebku;
kdyz jsi sam, zaradi se az na konec. Pod souctem XP je "do levelu": kolik XP chybi a kterym odevzdanim das level
(`^lvl` u kroku). U vzdalenych kroku v jine zone tooltip doporuci let (nejblizsi letiste u cile, upozorni na neobjevene -
addon si objevena letiste pamatuje pri otevreni mapy letu). U kroku "Splnit" tooltip ukaze, kde cil ziskat: nejblizsi
moby k zabiti a moby, ze kterych potrebny item pada (se sanci).

Filtr *Suroviny* v Pruzkumniku: byliny a rudy pobliz podle tveho skillu Herbalism / Mining (barvy jako u receptu)
a kde farmit materialy, ktere chybi do planu profese. Detail itemu ma i sekci *Kde farmit (tvuj level)*.

Questy s pouzitelnym itemem maji v trase male tlacitko (jako v seznamu questu hry) - klik = pouzit. Kvuli pravidlum
hry se s trasou s takovym tlacitkem v boji neda hybat ani ji zavrit (po boji zase jde).

V parte si addony posilaji quest log (pri zmene postupu do 1 s, i v boji), takze trasa je spolecna: zahrne i questy, ktere ma jen partak,
a u zastavky napise, kdo tam co odevzda nebo splni navic.

Kdyz je ForeverDB nainstalovana, addon si z ni udela malou cache (jen pri nove verzi ForeverDB; cela databaze
se v pameti drzi jen pri pouziti Pruzkumnika / trasy) a tooltip moba
ukazuje dropy podle Foreveru (vc. dat ze skutecnych killu) misto classic databaze; itemy, ktere zacinaji quest,
to napisou v tooltipu. Tooltip moba ukazuje i kolik penez z nej pada (prumer a rozsah ze skutecnych killu)
a v Pruzkumniku jde rozkliknout moba/NPC (boj, naucene imunity, penize, kde se spawnuje, dropy, questy).

Bez ForeverDB funguje zbytek addonu normalne, tyto funkce jen napisou, ze ForeverDB chybi.

## Levelovani profesi

U okna profese (Tailoring, Blacksmithing, Alchemy...) se ukaze panel ClaudeMasteru se zalozkami
**Prehled** (od kazde kategorie to nejdulezitejsi), **Plan** (levelovani), **Upgrady** (co si muzes vyrobit a je lepsi
nez tvoje vybaveni - i pro partaky s addonem), **Profit** (ziskove recepty: aukce / vendor minus material)
a **Recepty** (nove recepty pro tvuj skill):

- **tlacitko Vyrob** - vybere recept, ktery ted nejlip zvedne skill (oranzovy > zluty > zeleny, z tech nejlevnejsi),
  a jednim klikem vyrobi davku. Kdyz lepsi recept blokuje jen polotovar (napr. Bolt of Linen Cloth), vyrobi nejdriv ten.
  Kdyz recept behem davky zezelena a mas lepsi, vyroba se zastavi.
- **Pak** - dalsi recepty v poradi.
- **Chybi** - co chybi na nejlepsi recepty; klik na material = kde ho sehnat (Pruzkumnik, ForeverDB).
- **Trener** - upozorneni u stropu ranku a recepty, ktere se u trenera ted muzes naucit (podle pozadavku na skill).
- **Nakup u vendora** - material od vendora na nejlepsi recepty se ulozi; u obchodnika, ktery ho prodava, se ukaze
  tlacitko "Koupit vse" (jednim klikem koupi chybejici mnozstvi).

- **Cena za bod** - u receptu odhad ceny jednoho bodu skillu (vendor material za nakupni cenu, ostatni za prodejni,
  vlastni polotovary za cenu jejich materialu; zluty / zeleny recept podle sance na bod).
- **Plan** (tlacitko v hlavicce) - seznam receptu se zaskrtnutim a odhadem "zbyva ~N ks", nez recept zesedne
  (hranice barev z ForeverDB). Ze zaskrtnutych addon spocita nejlevnejsi postup az ke stropu ranku (useky skillu,
  kolik kusu ceho), material celkem a co chybi; vendor material z planu pak nabidne koupit u obchodnika.
- **Banka** - plan pocita i s tim, co mas v bance (hra si to pamatuje, staci banku jednou otevrit).
- **Aukce** - pri hledani itemu v aukci si addon zapamatuje nejnizsi cenu za kus (plan ji pak pouzije); u materialu z planu
  ukaze, kolik chybi a za kolik ho koupis z nejlevnejsich nabidek, u vyrobku porovna aukci (po 5% poplatku) s vendorem.
- **Cil skillu** - v planu tlacitka -5 / -1 / +1 / +5 / max: do kolika skillu plan pocitat.
- Panely (profese, vendor, aukce) se samy umisti tam, kde neprekryvaji jina otevrena okna.
- Panel jde presunout (tahem) a zvetsit (roh vpravo dole); dvojklik na roh = puvodni misto a velikost.
- **Polotovar z aukce** - u materialu, ktery plan vyrabi z surovin, porovna cenu hotoveho kusu v aukci se surovinami.

Kazdou davku spousti klik hrace (bez kliknuti vyrabet nejde). `/cm profese` vypise, co hra v okne profese vraci.

## Obchodnik, uklid, trener

- **Zasoby** - u obchodnika panel "Nakup": jidlo a piti pro tvuj level (piti jen pro manu), reagencie tridy
  (Ankh, Rune of Teleportation, svicky, seminka...) a munice lovce podle zbrane; jednim klikem koupi, co chybi.
- **Uklid batohu** - mince na okne obchodnika: tooltip ukaze, co prodat (sede, neumis nosit, horsi, itemy hotovych
  questu) a co zahodit (hotove questy, nejdou prodat); klik proda. `/cm uklid` vypise totez do chatu.
- **Trener tridy** - addon si u trenera zapamatuje kouzla, ktera jeste nemas; po levelu napise, co se muzes naucit
  a za kolik (`/cm trener`).

## Data o mobech

`MobData.lua` je vygenerovany z [vmangos](https://github.com/vmangos/core) world databaze (GPL-2.0)
skriptem `tools/build_mobdata.py` (imunity, kouzla, utek, odolnosti, dropy; classic 1.12).
Forever se od classicu muze lisit - addon databazi bere jen jako vychozi odhad,
vlastni pozorovani ve hre ma prednost.

## Credits

Upgrade/downgrade arrow textures (`Textures/`) are unmodified files from [Pawn](https://www.vgermods.com) by Vger-Azjol-Nerub, (c) Travis Spomer, CC BY-NC-ND 3.0.

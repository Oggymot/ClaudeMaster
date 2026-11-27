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

V parte si addony posilaji quest log, takze trasa je spolecna: zahrne i questy, ktere ma jen partak,
a u zastavky napise, kdo tam co odevzda nebo splni navic.

Kdyz je ForeverDB nainstalovana, addon si z ni udela malou cache (jen pri nove verzi ForeverDB; cela databaze
se v pameti drzi jen pri pouziti Pruzkumnika / trasy) a tooltip moba
ukazuje dropy podle Foreveru (vc. dat ze skutecnych killu) misto classic databaze; itemy, ktere zacinaji quest,
to napisou v tooltipu. Tooltip moba ukazuje i kolik penez z nej pada (prumer a rozsah ze skutecnych killu)
a v Pruzkumniku jde rozkliknout moba/NPC (boj, naucene imunity, penize, kde se spawnuje, dropy, questy).

Bez ForeverDB funguje zbytek addonu normalne, tyto funkce jen napisou, ze ForeverDB chybi.

## Levelovani profesi

U okna profese (Tailoring, Blacksmithing, Alchemy...) se ukaze panel ClaudeMasteru:

- **tlacitko Vyrob** - vybere recept, ktery ted nejlip zvedne skill (oranzovy > zluty > zeleny, z tech nejlevnejsi),
  a jednim klikem vyrobi davku. Kdyz lepsi recept blokuje jen polotovar (napr. Bolt of Linen Cloth), vyrobi nejdriv ten.
  Kdyz recept behem davky zezelena a mas lepsi, vyroba se zastavi.
- **Pak** - dalsi recepty v poradi.
- **Chybi** - co chybi na nejlepsi recepty; klik na material = kde ho sehnat (Pruzkumnik, ForeverDB).
- **Trener** - upozorneni u stropu ranku.

Kazdou davku spousti klik hrace (bez kliknuti vyrabet nejde). `/cm profese` vypise, co hra v okne profese vraci.

## Data o mobech

`MobData.lua` je vygenerovany z [vmangos](https://github.com/vmangos/core) world databaze (GPL-2.0)
skriptem `tools/build_mobdata.py` (imunity, kouzla, utek, odolnosti, dropy; classic 1.12).
Forever se od classicu muze lisit - addon databazi bere jen jako vychozi odhad,
vlastni pozorovani ve hre ma prednost.

## Credits

Upgrade/downgrade arrow textures (`Textures/`) are unmodified files from [Pawn](https://www.vgermods.com) by Vger-Azjol-Nerub, (c) Travis Spomer, CC BY-NC-ND 3.0.

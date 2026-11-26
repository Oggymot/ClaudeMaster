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

## Data o mobech

`MobData.lua` je vygenerovany z [vmangos](https://github.com/vmangos/core) world databaze (GPL-2.0)
skriptem `tools/build_mobdata.py` (imunity, kouzla, utek, odolnosti, dropy; classic 1.12).
Forever se od classicu muze lisit - addon databazi bere jen jako vychozi odhad,
vlastni pozorovani ve hre ma prednost.

## Credits

Upgrade/downgrade arrow textures (`Textures/`) are unmodified files from [Pawn](https://www.vgermods.com) by Vger-Azjol-Nerub, (c) Travis Spomer, CC BY-NC-ND 3.0.

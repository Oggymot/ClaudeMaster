# ClaudeMaster

Poradce pro **Frost Mage** a **Destruction Warlock** ve WoW Forever (Interface 16001).
Doporucuje, co castit, hlida manu, CC, preruseni, a pri hre ve dvou (mag + warlock) si addony
vymenuji data (cile, aggro, ovce, ready check).

## Instalace

- **WowUp:** *Get Addons* -> *Install from URL* -> vloz adresu tohoto repozitare.
- **Rucne:** stahni `ClaudeMaster-x.y.z.zip` z [Releases](../../releases) a rozbal do
  `World of Warcraft/_forever_/Interface/AddOns/`.

Prikazy: `/cm help`.

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

# Stance Studio

A BeamNG.drive tuning menu that works on every car, mod cars included. It covers stance, wheels and
performance parts in one place, with a key you choose.

## Features

- **Stance, on any car.** Ride height, camber, toe, wheel offset (track width), spring stiffness,
  damping and steering angle, per axle or linked.
  - Slam it lower than the game allows, down to scraping. The first 5 cm come from the springs,
    the rest from lowering the hub, so the suspension keeps its travel.
  - A ghost tire shows where the wheel will end up while you drag a slider, and the real ride
    height is measured after every change.
  - Quick looks: Flush, Track, Slammed, Hellaflush, Scraping, Drift lock, Lifted.
- **Visual wheel picker.** Every rim your car can fit, mod wheels included, shown as a real
  face-on render of the rim. Search and filter by size, and pick front, rear or both.
- **Performance parts, best first.** Engines, intakes, turbos, superchargers, exhausts, ECUs and
  so on, ranked by estimated power. Each part shows how much horsepower you gain (`+43 hp`) or
  lose (`−58 hp`) compared to what's on your car now, using the game's own engine math.
- **Tuning.** The car's own tuning settings as sliders, with search.
- **Your key.** Opens with **Alt+E** by default. Change it in the menu's Settings tab or under
  Options › Controls ("Stance Studio: open / close"). The menu is also in the pause menu under Mods.

Stance settings are saved with the vehicle config, so saved `.pc` files keep them.

## Install

1. Download `stancestudio.zip` from the [latest release](../../releases/latest).
2. Put the zip, without unpacking it, in your BeamNG mods folder:
   - Windows: `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`
   - Linux: `~/.local/share/BeamNG/BeamNG.drive/current/mods/`
3. Start the game, load a freeroam map and press **Alt+E**.

## Notes

- Made for BeamNG.drive 0.40. Singleplayer only for now. It is turned off in career mode.
- Wheel photos are taken once per rim: the first time you open the Wheels tab, a temporary copy of
  your car parks behind you and each rim is photographed on its own. It takes about a second per
  rim, keep the menu open until it is done. The photos are saved in
  `screenshots/stancestudio/rims/` in your user folder and shared between cars.
- Horsepower numbers are estimates of peak power. Nitrous is not counted.

## Building from source

`mod/` is the unpacked mod. `./build.sh` zips it into `dist/stancestudio.zip`.
For development, put a copy of `mod/` in `mods/unpacked/stancestudio/` in your BeamNG user folder.

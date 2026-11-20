# Stance Studio

A BeamNG.drive tuning menu that works on every car, mod cars included. It covers stance, wheels and
performance parts in one place, with a key you choose.

> **To open it for the first time, press `Alt + E`** in freeroam. The game also reminds you with a
> notification when a map loads, until you've opened it once.

## Features

- **Stance, on any car.** Ride height, camber, toe, wheel offset (track width), spring stiffness,
  damping and steering angle, per axle or linked.
  - Ride height goes from −250 to +200 mm on cars, SUVs and vans, and ±400 mm on pickups and
    heavy vehicles (4 t and up: box trucks, semis, buses). Extreme range in Settings allows
    ±500 mm on anything.
  - Slam it lower than the game allows, down to scraping. The first 5 cm come from the springs,
    the rest from lowering the hub, so the suspension keeps its travel.
  - Lift it like a lift kit: the first 10 cm come from the springs, anything higher drops the
    wheels on the hubs.
  - Wheels stay on. When a wheel is moved far on its hub, the beams that hold it are reinforced
    so they don't snap and drop the wheel.
  - A ghost tire shows where the wheel will end up while you drag a slider, and the real ride
    height is measured after every change.
  - Quick looks: Flush, Track, Slammed, Hellaflush, Scraping, Drift lock, Lifted.
- **Visual wheel picker.** Every rim your car can fit, mod wheels included, shown as a real
  face-on render of the rim. Search and filter by size, and pick front, rear or both.
- **Performance parts, best first.** Engines, intakes, turbos, superchargers, exhausts, ECUs and
  so on, ranked by estimated power. Each part shows how much horsepower you gain (`+43 hp`) or
  lose (`−58 hp`) compared to what's on your car now, using the game's own engine math.
- **Tuning.** The car's own tuning settings as sliders, with search.
- **Fun stuff (easter egg).** Scroll to the very bottom of Settings and turn on **Fun stuff** for a
  Fun tab, the JBeam edits people make for fun, right in the game:
  - **Engine:** an Indestructible engine toggle, no rev limiter, max RPM, and the torque curve as an
    RPM / torque table you can type in (with a 1,000,000 hp button). Turbo or supercharger boost in
    psi, pops & bangs, and the nitrous shot.
  - **Car:** weight, tire grip and brake power sliders, and an Unbreakable or Paper car toggle.
  - **World:** gravity (Earth, Moon, Mars, Jupiter, zero, upside down or custom) and slow motion.
  - **Advanced:** every other JBeam value of the car, with a slider.

  No game files are touched: the car changes are saved with its config, and Reset car to stock
  undoes them.
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

`tests/run.sh` runs the offline tests against `mod/`. It needs `luajit` and the game installed; set
`G` to the game folder if it is not in the default Steam location on Linux.
`tests/tools/audit_wheel_meshes.py` checks every vanilla vehicle for wheel meshes that would not
follow their wheel.

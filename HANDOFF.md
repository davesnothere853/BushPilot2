# Bush Pilot 2 — Handoff

Written 2026-10-12 for a fresh Claude session that has none of the earlier chat. Read this first, then `DESIGN_NOTES.txt` (the full numbered design log, entries 62–184, newest at the bottom) and `PROGRESS.md` (an older progress ledger).

**PRIVATE.** This package is the full source code plus the design notes. Dave does **not** want it shared. When he asks for something to send a friend, give him only the playable files: the exported `.exe`, the `.pck`, `libvoxel.windows.template_release.x86_64.dll` and the Player Guide. He once sent a source zip by mistake ("ya that was close i dont want to give that all away"), so take this seriously.

---

## 1. Overview

Bush Pilot 2 (BP2) is a single-player and co-op bush-flying survival sandbox, built by Dave ("Hammer") with Claude doing all the coding.

**Setting.** A late-1980s northern bush (an Alaska-like map; an Outback map is also selectable).

**What you do:**
- Fly freight, passengers, mail, skydivers, explosives and core samples between gravel strips.
- Mine a gold claim by hand and with machines: shovel, pick, pan, sluice, wash plant, excavator, dozer, loader, drift miner, timbered tunnels, rail and ore cars, pumps, generator and rope lights.
- Fell and buck trees with a chainsaw, haul logs, and build strips, cabins, hangars and camps.
- Drive trucks and machines with realistic suspension.
- Survive fire, crashes and weather. There is gore and dismemberment (it is optional).
- Fight other players with tools, a pistol and dynamite in co-op.

**Planes:** the Wolverine bush plane (high-wing taildragger), the Meadowlark biplane and the DC-3. Tundra tyres, skis and floats are available.

**Direction.** Dave's latest steer is *"think survival fps game … kinda where its headed towards"*: a console-style survival shooter on foot that is also a serious bush-flying sim.

**Engine.**
- Godot **4.7.2** (Steam build), Forward+ renderer, GDScript only.
- Physics at 120 Hz with physics interpolation.
- Terrain uses the **Zylann Voxel Tools 1.7 GDExtension** (`addons/zylann.voxel`).
- Autoload `Game` = `scripts/game.gd`. Main scene `main.tscn` → `scripts/main.gd` (~9,800 lines; the hub for nearly everything).

**Dave's machine.**
- Windows PC. Project at `C:\Users\davku\Documents\BushPilot2` (the master copy).
- Builds go to `Documents\BushPilot2_builds`.
- Controller: GameSir G7 Pro (Xbox layout).

---

## 2. How to run

### In the editor
1. Install Godot 4.7.2 (standard, not .NET).
2. Unzip this package and open `project.godot` from Godot's Project Manager.
   - The first open re-imports everything, which takes a few minutes and creates `.godot/`.
   - The `.fbx` motion-capture clips in `assets/characters/src` without a `.fbx.import` file are imported automatically.
3. Press F5 (main scene `main.tscn`).

**Voxel binaries.** Only the **Windows** binaries are included (`libvoxel.windows.editor.x86_64.dll` for the editor and `libvoxel.windows.template_release.x86_64.dll` for exports). To run on Linux or macOS, download **Voxel Tools 1.7 for Godot 4.4.1+** (GDExtension build, Zylann/godot_voxel releases on GitHub) and copy its `bin/` files into `addons/zylann.voxel/bin/`. `voxel.gdextension` already lists every platform.

### Testing co-op on one PC
Use two instances side by side:
1. Debug > Customize Run Instances.
2. Set 2 instances.
3. Give one the args `-- coop=host` and the other `-- coop=join`.

The host window opens on the right and the guest on the left. The guest joins 127.0.0.1 after 4 s.

To try co-op alone in one instance, use the console (F1 or `) and type `buddy`. This adds a fake second player, peer 990001, that runs through the real co-op code paths.

### Exporting the playable build
1. Project > Export > Windows Desktop preset > Export Project (release, no debug). Export templates 4.7.2 are installed on Dave's PC.
2. The preset `export_path` is `Desktop\Bush Pilot 2\Bush Pilot 2.exe`.
3. The `exclude_filter` keeps tools, tests, reference, `_rec`, `.txt`, `.md` and `.html` out of the `.pck`. The `.pck` is about 7 MB.
4. The exe icon (`icon.ico`) is embedded by Godot itself, no rcedit needed.
5. Ship three files together: `Bush Pilot 2.exe`, `Bush Pilot 2.pck` and `libvoxel.windows.template_release.x86_64.dll`, plus the Player Guide HTML.

Windows SmartScreen may warn; the player clicks More info > Run anyway.

### Useful console commands (F1 or `)
- `help` lists everything.
- Teleports: `goto strip|door|creek|pond|knoll|bog|pad|vein|forest` and `tp <strip>`.
- Items and cheats: `give <item> [n]`, `money`, `sandbox on|off`, `repair`, `fuel`.
- World: `weather`, `time`, `season`, `wind`.
- Co-op stand-in: `buddy [on|off|fly|land|ask|come|stay|fight|peace]`.
- Hands camera: `handcheck [item|aim|side|back|info|off]` (close-up camera on the hands for tool placement).
- Diagnostics: `perf`, `rumble` (controller test), `rec N` (records frames to `_rec/`).

Wait about 1.5 s after opening the console before typing; a second command typed quickly gets lost.

---

## 3. File map

```
project.godot          Godot project (name "Bush Pilot 2"; icon.png / icon.ico; autoload Game)
export_presets.cfg     Windows (and other) presets, exclude filter, icon
main.tscn              Main scene -> scripts/main.gd
testworld.tscn/.gd     Old proving-ground test scene (not the game)
icon.png / icon.ico    Game/exe icon: dusk mountain + yellow bush plane (tools/make_icon.py)
HANDOFF.md             This file
DESIGN_NOTES.txt       Full design log, numbered entries 62-184 + "NEXT SESSION" list (~line 1479)
PROGRESS.md            Older progress ledger / vision summary
FEATURES.txt           Feature list (older)
docs/player_guide.md   Source of "Bush Pilot 2 - Player Guide.html" (keys for KB+M and pad)
addons/zylann.voxel/   Voxel Tools 1.7 GDExtension (Windows binaries only in this package)
assets/characters/     pilot.scn (rigged Mixamo "mixamorig1_" skeleton, polyart Ch17 character),
                       src/*.fbx motion clips (idle, walking, running, jump, driving, get_in,
                       sit_down, sitting_idle, stand_up, falling, switch_high/low, + new:
                       pistol_aim, pistol_walk, pistol_shoot, throw, swing, hit_react,
                       pick_up, shovel_dig), src_poly/
assets/sounds/         Engine/ambience/etc. sounds
assets/vehicles/       Vehicle meshes (e.g. pickup made in Blender)
shaders/               Ground, water, vegetation, etc.
reference/             Target-look images Dave picked (polyart forest/valley/rain/deer)
tests/                 Headless/shot test scenes (build_pilot_poly.gd rebuilds pilot.scn)
tools/                 Blender/python helpers (polyart_pilot.py, make_icon.py, ...)
scripts/               All game code (~100 scripts), key ones below
```

### Key scripts

**Core**
- `main.gd`: the game hub. Flying, on-foot input, cameras, aim-down-sights (ADS), tools, the pistol and bullets, gore hooks, dynamite, controller handling and co-op launch args.
- `game.gd` (autoload): settings and saves (5 slots), options (gore, goals_on, rumble, sandbox), pending_join.
- `net.gd`: co-op.
  - ENet on UDP 24680 with UPnP.
  - RPCs: `_state`, `_world_is`, `_world_now`, `_hit`, `_dyn`, `_plane_shot`, `_ask`, `_granted`, `_give_back`.
  - Also the BUDDY stand-in, `shot_target`, `hit_player`, `blast_near` and `_apart_from`.
- `menu.gd`: pause menu (Start, Travel, Load & fuel, Save slots, New game, Season/weather/realism, Graphics, Controls, Co-op). Guests can't change world rows.
- `hud.gd`: gauges, key legend, getting-started list (X close box), ADS crosshair.
- `console.gd`: cheat and test console.

**Character and items**
- `pilot_rig.gd`: the rigged figure (used for the player, remote players, passengers and skydivers).
  - Runtime-loads the EXTRA clips from `assets/characters/src/*.fbx`.
  - `one_shot()` plays a clip once; the `aim` property switches to the aiming clips.
  - `_fit_carry` fits each tool to the palm in the idle pose.
- `on_foot.gd`: the walker controller.
- `gore.gd`: dismemberment, both on dead bodies and live (`sever_live`, `lost_live`, `restore_live`).
- `inventory.gd`: item table, CARRY table (how each item is held), `build_mesh` for item models, HOLSTER_XF.
- `inventory_ui.gd`: backpack and hotbar UI.
- `shovel.gd`: shovel model. `dynamite.gd`: lit stick physics.

**Planes**
- `plane.gd`, `plane_types.gd`, `engine*.gd` (flight model and engine sim; the "brains" carried over from Bush Pilot 1).
- Visuals: `plane_visual.gd`, `dc3_*.gd`, `biplane_*.gd`.
- `cockpit.gd`: clickable switches.

**World**
- `world.gd`, `terrain.gd`, `voxel_ground.gd`, `ground.gd`, `map_gen.gd`, `world_look.gd`, `vegetation.gd`, `flora.gd`, `water*.gd`, `wind.gd`, `fire.gd`, `birds.gd`.

**Work and machines**
- Mining: `prospect.gd`, `mining.gd`, `dig_site.gd`, `veins.gd`, `mine_rails.gd`, `tunneler.gd`, `tunnel_power.gd`.
- Machines: `dozer.gd`, `excavator.gd`, `loader.gd`, `forklift.gd`, `tug.gd`, `pickup_truck.gd`, `water_truck.gd`, `wheeled_body.gd`, `tracked_body.gd`, `vehicle_damage.gd`.
- Economy and building: `jobs.gd`, `cargo.gd`, `skydive.gd`, `fleet.gd`, `builds.gd`, `structures.gd`, `crafting.gd`.

---

## 4. Status (what works, verified on Dave's PC on 2026-10-12)

**Game loop.** The whole game is playable: flying, jobs, mining, logging, building, machines, saves, seasons and weather.

**Latest export.** `Desktop\Bush Pilot 2\Bush Pilot 2.exe` with the new icon. It launches to the menu and the office start with the new on-foot controller legend.

**Co-op**
- Two instances connect.
- The guest's plane is moved 18 m apart on join.
- The guest's menu can't change map, season, time or weather, or wipe saves.
- The host syncs the world every 3 s.
- A guest whose map or seed differs reloads and rejoins automatically.

**Buddy stand-in.** follow, ride, fly, orbit, land, fight, die and respawn.

**Combat**
- Tool fights, dynamite (thrown and placed, crater, debris).
- The pistol (holster on the right hip, ADS over the shoulder, crosshair).
- Live dismemberment.

**Tools in hand.** Placement of the pistol, shovel (shortened to 1.05 m) and pick was fixed and checked with `handcheck`.

**Motion clips.** Mixamo clips are in and the aim pose works.

---

## 5. In progress / not yet verified

1. **Send zip for Dave's friend.**
   - Dave asked: "now make new zip to send please when you get done".
   - The new icon build is exported to `Desktop\Bush Pilot 2\` (exe, pck, dll, guide).
   - I was clicking File Explorer > "…" > *Compress to ZIP file* on that folder when the session ended and the PC went offline.
   - **To do:** create `Desktop\Bush Pilot 2.zip` from that folder (it must contain only those 4 files) and confirm with Dave.
2. **Not play-tested yet:**
   - Bullet holes (decals).
   - Glass breaking.
   - Bullets damaging machines and planes.
   - The new on-foot pad layout (RT use, LT aim, L3 run toggle, LB/RB hotbar, View backpack).
   - The throw, swing and hit_react clips in play.
3. **Not tested:** real two-PC co-op over the internet (UPnP or port forward).
4. **Player Guide is out of date.**
   - `docs/player_guide.md` and the HTML predate the new on-foot pad layout.
   - Section 3 still says RT = run, LB = backpack, D-pad L/R = hotbar.
   - Update it to the layout in §8 and rebuild the HTML.
   - A Claude Docs copy ("Bush Pilot 2 Player Guide") exists in the old account with sections half-filled. It won't carry over, so treat the md as the source.
5. **Source backup.**
   - The newest dated source zip on the PC (`Documents\BushPilot2_builds\BushPilot2_build_2026-10-12_0628.zip`) predates design entries 182–184.
   - Make a new one (Godot: Project > Pack Project as ZIP) and keep it private.
6. **Frozen copy.**
   - "Bush Pilot 2 v1" is at `Documents\BushPilot2_v1\BushPilot2` (also `Documents\BushPilot2_v1.zip`). It is a separate game copy Dave asked for, like the first Bush Pilot.
   - Development continues in `Documents\BushPilot2`.

---

## 6. Known bugs and workarounds

**Editor and console**
- **The Godot editor overwrites scripts.** If a script is open in Godot's script editor while files are changed outside it, pressing F5 saves the editor's stale copy over your change.
  - Workaround: close the script tab (File > Close) before changing files outside the editor.
  - Afterwards, verify the file on disk (compare or grep).
- **Console drops fast input.** A second command typed quickly is lost. Wait about 1.5 s.

**Code gotchas**
- `main.world.terrain` is a RefCounted, not a Node. Don't type it as `Node`.
- GDScript can't negate a `Basis` in a const; put the minus sign on the Vector3.
- Setting a plane's `global_transform` gets undone. Move planes with `plane.pos = …; plane._snap_transform()`.

**Unfinished features**
- **3D relief chart** (`topo_map.gd`) draws nothing on foot. It's set aside; M shows the flat chart.
- **Rumble on the GameSir G7 Pro**: Dave felt none. The `rumble` console test was sent, but there's no answer yet. Check the GameSir app's vibration setting.
- **Co-op sharing is partial.** Only planes, pilots on foot, ride-along, control handoff, tool, gun and dynamite hits, and the world clock and weather are shared. Trucks, machines, digging, buildings, felled trees, jobs and money, fires and cargo are NOT shared.
- **Both players need the identical build.** RPC signatures must match.
- **Dozer** treadmills when pushing a full blade uphill (TODO: side-cast when climbing).

**Working on Dave's PC through computer use**
- File Explorer is click-only: no typing, right-click, drag or clipboard.
- Explorer's "…" menu offers Compress to ZIP and Extract all.
- New folders can be made by committing a file into them.
- File transfers to the PC are capped at about 30 MB.

---

## 7. Roadmap (Dave's list, roughly in priority order)

1. Finish and send the friend zip (§5.1). Play-test §5.2 with Dave.
2. Update the Player Guide for the survival pad layout, the holster and bullet holes.
3. Keep growing the **survival-FPS feel on foot**: more weapons and tools, hunger and cold are possible next steps. Ask Dave first.
4. **Deeper co-op:** share vehicles, digging and terrain edits, buildings, felled trees, jobs and money, fires.
5. Backlog:
   - helicopter
   - radial-engine bush plane
   - log building system
   - hangar doors and a stove
   - Git with LFS
   - fix the 3D relief chart
   - optional `.pck` encryption
6. Low priority (Dave: "dont worry so much about the tree growth yet"): **a burned forest regrows over time**, saplings first, then young trees.
7. Older checks still open:
   - tree collisions
   - loader power and lockers
   - fuel pools (console `spill`)
   - quick menu (LB)
   - weather fronts
   - save slots
   - goals ticking
   - gore in a real fatal crash
   - L3 tap to board

---

## 8. Design decisions (numbers and why)

### Controls and console feel
- **Full controller play is required** ("consider it a console game"). Every feature must work on a pad.
- **On-foot pad layout (survival-shooter):**

| Button | Action |
| --- | --- |
| RT | Use the item in hand (dig, swing, fire, pick up). Presses "interact" once past 60% and re-arms under 30%. |
| LT | Aim |
| L3 | Run toggle. It ends when you stop. At a plane door, L3 still gets in. |
| LB / RB | Previous / next hotbar slot |
| View | Backpack (View or B closes it) |
| D-pad left / up / down | Chart / headlamp / build |
| X | Pick up / interact |
| Y | Door / put down |
| A | Jump |
| B | Camera |

  - Keyboard on foot is unchanged: Shift runs, E uses, RMB aims.
  - Flying controls are unchanged: RT/LT throttle, LB quick menu.
- **Physical interaction over menus.** Reach, grab and carry. A pager instead of menus where possible.

### Pistol and bullets
- **Pistol timing:** 0.32 s between shots. The first press from the holster only draws the gun, which stays up for 1.5 s.
- **Accuracy:** hip-fire spread 0.045, aimed spread 0.004.
- **ADS:** FOV 66 → 36, camera over the right shoulder.
- **Damage:**
  - Head shot kills (1.5).
  - Body 0.28–0.38 of a health bar.
  - 20% chance to take a limb.
- **Hit zones:** head 1.62 m high, r 0.16; body 1.15, r 0.32; legs 0.55, r 0.26, plus range slack t×0.004. The voxel ground blocks shots.
- **Glass** (mesh named glass/window/windshield/screen, or a see-through material with alpha < 0.6) breaks into shards and the round carries on. Anything else stops the bullet.
- **Vehicles hit by bullets:** take body or engine damage. Planes take damage to the part struck (wing, aileron, tank, prop, tail, tyre, fuselage).
- **Bullet holes:** Decals 16 cm on ground, 9 cm on metal (with a bare-metal rim). They are parented to what they hit, and the newest 80 are kept.

### Tools, dynamite and gore
- **Tool damage** (fraction of a health bar, ±15%): pick .45, rail .35, shovel .30, timber .25, ladder .20, bottle .15, gold pan .12.
  - Reach 2.4 m, swing cooldown 0.9 s.
  - Pick, rail and shovel have a 22% chance to take a limb.
  - Knockback 0.6 m.
- **Dynamite:**
  - Placed on a face within 1.8 m, or at your feet: 8 s fuse.
  - Thrown: 12 m/s plus lob, 5.5 s fuse.
  - Blast: 2.2 m crater, 1.6 m voxel bite, 14 rock chunks, hurts within 9 m, fells trees within 3.5 m.
  - Within 5 m without killing: 75% chance to lose a limb.
  - In co-op every player's game simulates the same stick.
- **Gore** is on by default with an option to turn it off. No red balls on cut ends (Dave). Live dismemberment shrinks the bone and re-applies it after the animation mixer runs.

### Tools in hand
- Fitted in the **idle pose** at the real palm: 60% of the way from wrist to middle knuckle, 2 cm in.
- The pistol is fitted in the pistol_aim pose, and is holstered on the right hip unless aiming.
- The shovel is about 1.05 m (Dave: "too long and big"), carried blade-down.

### Co-op design
- **Each player flies their own plane** (Dave). The host owns the world: map, seed, season, time, weather, wind.
- The guest's own saves (money, planes, buildings) stay theirs.
- A guest's menu must not affect the host (Dave).
- Port UDP 24680. The host tries UPnP; otherwise forward the port.

### World, art and performance
- **Physics at 120 Hz with interpolation.** This was the fix for jitter, Dave's first priority.
- **Art:** polyart models with moody lighting (Dave likes polyart; target images in `reference/`).
  - **Every model is new for BP2** (no Bush Pilot 1 meshes). BP2 keeps BP1's *brains* (flight model, engine sim, dig math, machine logic) but not its looks.
- **Models of real kinds of things are based on real reference photos.** Find photos first, let Dave pick, then model. **No brand names** anywhere (generic names such as "Wolverine", "Meadowlark", a generic 9 mm service pistol).
- **Voxel ground** must be smooth, not blocky. You can dig very deep and make your own tunnels. Natural branching caves exist, about 7 systems.
- **Performance:**
  - The perf overlay updates 4×/s and probes scripts every 10 s; it was eating the frame before.
  - Far bird flocks are culled.
  - The on-foot HUD redraws at 20 Hz.
  - Result: 60 fps capped, GPU ~9.7 ms.

---

## 9. Rejected / set-aside ideas

- **The old Bush Pilot 1 island map.** Dave: he doesn't want the old map.
- **Old-game meshes and plants.** All remade.
- **Rendered far mountains and a random mini-map in the test square.** Dave disliked them; removed.
- **Procedural noise ground textures.** They didn't look good.
- **Blocky voxel terrain.** Rejected; must be smooth.
- **Red balls on gore stumps.** Removed.
- **The two "people on the airport" apron figures** (old blocky model). Removed (`world.gd` people = 0).
- **The old blocky passenger and skydiver model.** Replaced by PilotRig.
- **The 3D relief chart.** Set aside; it drew nothing on foot.
- **OceanPro ocean addon ($95).** On hold until a big coastal map; Dave's call.
- **Sharing the project or source zip with friends.** Never again; only the exe, pck, dll and guide.
- **Including design notes in anything sent out.** Dave: "no design notes".

---

## 10. Dave's preferences (how to work with him)

**Who he is**
- Dave, also "Hammer". Writes short, fast, typo-heavy messages; read for intent.
- Typical messages: "keep going", "sorry keep going", "just do whats need please".
- He expects autonomy: "you can use my computer the whole time". Work on his PC directly and verify in the running game.

**Standing rules**
- Install everything to the PC and **verify** it (launch it, look at it).
- **Keep `DESIGN_NOTES.txt` updated as you go**, in numbered entries. He wants notes kept "in case you get interrupted or the usage limit is hit".
- After each decent update, **auto-save a dated build zip** to `Documents\BushPilot2_builds` (`BushPilot2_build_YYYY-MM-DD_HHMM.zip`). Keep these private.
- **No brand names. Base models on real references.**
- **Console-game mindset.** Everything works on the controller.
- Show him results (screenshots or launching the game) rather than long explanations. Keep replies short.

**Never do**
- Never enter passwords; Dave logs in himself (e.g. Mixamo for animations, character Ch17).
- Never share source or notes outside.

**Practical**
- Dave was on paid usage credits (his plan reset was Oct 13, 7 PM). Don't waste effort, and pause to ask before big or expensive steps.
- His desktop gets cluttered with builds. Keep exactly one current playable folder, `Desktop\Bush Pilot 2`; Dave moved older copies into `Desktop\bushy` and "Bush Pilot 2 - old copies".

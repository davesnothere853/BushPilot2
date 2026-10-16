# Bush Pilot 2 — progress ledger

The scheduled "keep building" runs read this first. Keep it current.

## Vision (short form — full text in DESIGN_NOTES.txt §61)
BeamNG-physics bush plane game: bush piloting, gold mining, jobs. Full terrain
deformation everywhere. Late 80s / early 90s, pager instead of menus, own a
shipping company, start with a beater plane, Dead Stick-grade look.

## Current phase
Proving ground (Task #83): ~360 m square map in an empty void that looks like
the finished game. Everything judged by Dave from render shots on his phone.

## Done
- v0.3 FULL GAME ON THE SMALL MAP (2026-10-10): the whole old game (main,
  menus, saves, collisions, walker, cargo, jobs, fleet, skydive, mining
  claims, builds, prospect hand-mining, wash plant, excavator, dozer,
  cockpit, HUD, chart, lights, day/night) now runs with world = the small
  deformable map. world.gd builds ground.gd + ground_view + open plain +
  faceted mountains + Gerstner pond; old hangar/house/runway-light/windsock/
  apron/sale-plane builders reused at 'Proving Ground'. Two outlying strips
  on the plain (Bluff Camp, Willow Bar) so jobs/claims/skydive have places
  to go. prospect.gd digs/grades/piles straight into ground.gd (no tiles).
  New CLAIM CREEK carved knoll->pay pad->pond: pannable water, placer gold
  in its gravels, willows along it. Selftest: 0 problems. digtest full loop
  OK (dig/pan/sluice/washplant/excavator/sell). doztest GRADED OK pushing
  downhill (uphill full-blade push treadmills - TODO side-cast when climbing).
  crashtest + walktest OK.
- POLYART PILOT in game: tools/polyart_pilot.py (Blender) decimates the
  rigged pilot 24k->3.2k faces, palette vertex colours, vest->leather, hat
  off, skin weights kept -> tests/build_pilot_poly.gd rebuilds
  assets/characters/pilot.scn with all 12 animations. Verified animating.
- Voxel Tools 1.7 GDExtension downloaded (Dave's PC Downloads) and verified
  loading in Godot 4.7.2 (addons/zylann.voxel; not used by the game yet).
- v0.2 (2026-10-10): MOVING TRACKS - scripts/track_loop.gd (shoes as a
  MultiMesh running the real loop: ground run, up the sprocket, over the
  top, down the idler; advance() in metres, differential per side so turns
  counter-rotate). Wired into dozer.gd and excavator.gd drive(). Excavator
  is now IN the playable world at the cut: board it (G), look where to dig,
  E digs a bucket / dumps it, real ground deformation; dozer blade work as
  before. Boarding generalised to nearest machine.
- PLAYABLE BUILD v0.1 (2026-10-10): testworld.tscn/gd - walk the apron
  (first person, on_foot.gd), board the plane (G near it) and fly off 09/27
  with the full engine/flight sim, board the D8 at the cut and actually
  grade/push dirt into the real deformable ground, blade up/down with E,
  trees fall when pushed. Vegetation streams the REMADE card trees/shrubs
  in-game. Simple HUD readout (kt/ft/rpm/flaps). ESC releases the mouse,
  F11-equivalent via "fullscreen" action. Smoke-boots headless clean.
- Deciduous canopies densified + shrubs REMADE as card foliage
  (Meshes.shrub_cards); vegetation.gd now streams tree_cards/shrub_cards
  only (no old blob/cone models anywhere in BP2).
- UNIFIED DEFORMABLE GROUND BUILT AND PROVEN (2026-10-10): scripts/ground.gd
  (RefCounted; whole 360 m square one fine 0.5 m grid, 24 m chunk dirty
  marking, dig/level/deposit/_slump ported from dig_site.gd, geology layers
  turf/overburden/pay/bedrock with gold grade hot spots in the pay zone,
  save/load of changed cells only, full old-terrain API duck-type) +
  scripts/ground_view.gd (225 chunk meshes, global-grid normals = no seams,
  per-frame rebuild budget, void edge skirt). tests/ground_test.gd: ALL OK
  (seams, runway slope, void, pond, dig layers+gold, bedrock stop, deposit,
  level bench, 797 trees, save round-trip). Grid builds in 1.6 s.
- tests/pg_quick.gd now runs on the REAL ground: demo earthworks are real
  dig()/level()/deposit() calls (bladed road apron->pad with 8% ramp rule,
  bucket-bench pay cut, spoil cone). Shader shows dug layers by depth and
  heaped ground as loose spoil (UV.y signed: + dug, - heaped).
- FIRST LOOK RENDERED (2026-10-10): tests/pg_quick.gd builds the whole square
  analytically (QuickGround class = the zone plan + terrain duck-type for
  flora), with runway/apron/hangar/knoll/bog/pond/pay-cut zones, shader
  shaders/ground.gdshader (zone weights in COLOR, wet+dug in UV), edge skirt
  into the void, pond disc, hangar, parked Wolverine, D8 at the cut.
  3 shots sent to Dave (runway, cut, apron).
- TREES REMADE: switched to Meshes.tree_cards (the shelved needle-card
  builder) for ALL tree LODs + densified veg_textures frond/leaf painting
  (needles 0.75->1.7 px wide, 2.6x count; leaves bigger/denser). Cone trees
  are gone. Card surface MUST get CARD_SHADER with Tex.frond()/leaves() as
  surface 1 material - material_override flattens them back into cones.
- Project scaffolded at /home/claude/bushpilot2 (Godot 4.7.2, Forward+, 120 Hz,
  physics interpolation). project.godot written, main_scene=res://testworld.tscn.
- All brain scripts carried over from the old game and compile clean
  (tests/check.gd: 0 failures): plane, engine, gear, plane_types, plane_visual,
  cockpit, hud, meshkit, dent_mesh, pbr, fx, wind, debris, dozer, excavator,
  veg_meshes, vegetation, veg_textures, flora, terrain (constants/reference),
  game (autoload), liveries, aircraft_lights, dc3_shape, hotas, engine_model,
  float_visual, panel_layout. Shaders: veg, veg_cards, veg_far, panel,
  lookdev_ground (reference recipe).
- Everything above committed to Dave's PC at Documents\BushPilot2 (2026-10-10).

## RULE: new game, new models (DESIGN_NOTES 64)
Old-game meshes are placeholders only. Every model gets REMADE from real
reference photos before Dave judges it: plane visual first, then dozer,
hangar/props, excavator, pilot. Brains (physics/logic) stay.

## Next (in order) - CURRENT
1. VOXEL GROUND (smooth, Transvoxel, like 7DTD/Out of Ore): replace
   ground.gd internals with VoxelTerrain SDF; keep its API (height_at via
   raycast, dig/level/deposit via VoxelTool, layers by depth below the
   natural surface). Caves, deep digging, true mine later on top.
2. Real machine physics (DESIGN_NOTES 70).
3. Look pass (world_look.gd exists, not yet wired into world.gd's sky).

## Next (old list, superseded)
1. scripts/ground.gd — unified deformable ground (RefCounted, duck-types the
   old terrain API for plane/flora/vegetation) + scripts/ground_view.gd
   (chunked meshes) + shaders/ground.gdshader (game-quality, lookdev lessons:
   specular 0.08 base, roughness 0.72-0.97, saturated albedo, AGX-friendly).
2. testworld.tscn/gd — environment (overcast recipe from tests/look_shot.gd of
   the old project: AGX, fog 0.002, sun -16 deg warm 1.45, saturation 1.1),
   vegetation streaming, hangar on the apron, parked Wolverine, walkable/flyable.
3. tests/pg_shot.gd — headless render views (apron, runway threshold, knoll,
   bog, pond, dig crater demo) -> send PNGs to chat.
4. Machines: dozer + excavator spawned, their on_grade/on_spill/dig wired to
   ground.level/deposit/dig.
5. Judgment: Dave reviews shots; then art pass iterations.

## Zone plan (copied from storyboard)
Square 360x360 centred at origin, half=180. Runway 09/27 gravel 300x18 centred
(0,-130) heading 90. Apron+hangar south of it around (-30..40, -112..-75).
Rock knoll NE ~(125,-35) r~48 +14 m, bedrock shallow. Pay dirt zone ~(75,60)
r~40, pay_top 0.6-1.4 m, bedrock 2.5-4 m. Muskeg/bog south z>80. Pond ~(-105,105)
r~26 with sand ring. Rolling grass elsewhere. Outside the square: void (-60 m),
no water, nothing grows.

## Open bugs / rough edges (first-look verdicts)
- Shrubs still faceted blobs on sticks (pond view foreground). Try
  Meshes.lite=false fringes, or card-ify shrubs like the trees.
- pg_void overview: fog washes the square out at 400 m - closer camera or
  lower fog for that one view.
- Pond water is a plain disc; no shore blend. Water sim is a designed-later
  feature (DESIGN_NOTES 62) - just make the standing look nicer for now.
- Hangar is a plain gable box - good proportions, needs corrugation/wear pass.
- Apron-left has a big dark shadow rectangle (hangar shadow, sun ENE) - fine,
  but check it reads as shadow once ground detail increases.

## Dave's standing rules
Ask before building NEW features (scheduled runs: only continue this list).
Record every idea in DESIGN_NOTES.txt. Reference photos for models. Models must
look good and work with mechanics. Finish interrupted tests. No menus — world
interactions physical. Old game at Documents\BushPilot is reference only.


## v0.4 (2026-10-10) - smooth voxel ground, levers, shovel
- Smooth voxel ground (Voxel Tools LOD terrain, Transvoxel, 0.25 m voxels with
  mesh optimisation): mirrors every dig, collisions match, tunnels stay open
  (scripts/voxel_ground.gd, shaders/voxel_ground.gdshader). Falls back to the
  old heightmesh if the add-on is missing (or run with heightmesh=1).
- Excavator lever mode (Y toggles): ISO controls, bucket bites/drags/fills,
  dump where you open it (ground.cut_to). Easy mode (look + E) kept.
- Dozer blade raise/lower by hand (Shift/Ctrl, triggers, right stick).
- Real shovel: pick it up by the hangar, dig only with it in hand, Y sticks it in the ground.
- Contract loads never exceed what the plane can stow.
- Tests: selftest 0 problems, digtest (shovel + levers), doztest GRADED OK,
  tests/voxel_gen_test.tscn all PASS.
Next: walk into tunnels (walker on voxel collision underground), timber
supports, polyart look pass, machine physics (notes 70).

# usagi-geo-td

**Geometric roguelike tower defense** built entirely from primitive shapes on the
[Usagi](https://github.com/brettchalupa/usagi) engine. The engine core is Rust;
the game is Lua. There are no art assets: towers, enemies, bosses, route events,
affixes, and UI markers are all squares, circles, triangles, hexes, diamonds,
lines, and glow-friendly palette colors under a CRT/neon post-process.

Defend a fixed path through escalating roguelike waves, draft upgrades, reshape
the route between waves, mine charge from resource prisms, sign optional wave
contracts, build module resonance circuits, and carry meta-progression between
runs. The full design is in `docs/DESIGN.md`; the original roadmap and V2 arc are
shipped in `docs/ROADMAP.md` and `docs/roadmap_v2.md`.

## Play

Install Usagi once:

```bash
curl -fsSL https://usagiengine.com/install.sh | sh
```

Run from the repo root:

```bash
~/.usagi/bin/usagi dev .   # live reload; F5 resets state
~/.usagi/bin/usagi run .   # normal run
```

## Controls

- **Mouse**: place selected tower, click HUD/menus, inspect a tower in build phase
- **Right-click**: cancel selection, close inspect, exit sell mode
- **1 / 2 / 3 / 4 / 5 / 6**: Pellet / Splash / Frost / Rail / Flak / Drill
- **S**: sell mode
- **Space / Enter**: start wave; in combat, call the next wave early when allowed
- **F**: cycle 1x/2x combat speed
- **O**: orbital strike, a money-based emergency clear
- **D**: Discharge, spending stored charge for field-wide damage
- **Esc**: pause menu with quick comfort/settings toggles

## Shipped Features

- Fixed-path TD on five unlockable maps with map select, route previews, best-wave
  tracking, difficulty order, and layout validation.
- Six towers: Pellet, Splash, Frost, Rail, Flak, and Drill. Towers support
  air/ground targeting, per-tower targeting overrides, upgrades, and one geometry
  module socket.
- Twenty enemy JSON rows: fifteen normal enemies plus five boss-arena objects,
  covering flyers, splitters, armor, regen, shields, swarms, and aura emitters.
- Four cycling bosses plus the wave-25 Lattice final boss, with telegraphs, arena
  objects, shield batteries, Hydra heads, Specter anchors, Prism mirrors, and
  final-boss anchors.
- Roguelike upgrade drafts with Common/Uncommon/Rare behavior cards: pierce,
  ricochet, brittle, splash rings, flyer bursts, economy boosts, crit, range,
  rate, and more.
- Challenge modes: Standard, One Life, No Orbital, No Rail, Boss Rush, Flyer
  Swarm, Hardcore, and Draft Chaos.
- Route Draft 2.0 between waves: Loop, Shortcut, Braid, Split, Convergence, Prism,
  and Hold cards, all preserving the single-polyline route invariant.
- Resource prisms and Drills generate charge during combat. Charge fuels
  Discharge and module rerolls.
- Optional wave contracts: Enrage, Swarm, Blackout, and No Sell. Risk applies to
  the next wave; rewards pay only on clear.
- Tower resonance circuits from socketed geometry modules, including named
  behaviors such as Delta Chain, Orbit Field, Diamond Wake, and Green Vector.
- Enemy affixes from wave 8 onward: Mirrored, Armored Front, Veiled Pack,
  Overclock, Fracture, and Null Field, with visible affected-enemy geometry.
- Persistent meta systems: unlocks, mastery tree, meta-contract board, badges,
  bank shards, and deterministic local daily challenges.
- Share codes and replay snapshots for local bug reports and run verification,
  including route, contract, targeting, reroll, and timed active-ability decisions.
- Settings/accessibility: music/SFX volume, CRT toggle, screen-shake toggle,
  damage-number toggle, high-contrast palette, pause-menu quick toggles.
- MiniMax-generated multi-track soundtrack, procedural SFX, desktop/web CRT
  shaders, and a documented export checklist.

## Verification

Run from the repo root:

```bash
luajit tests/smoke.lua       # full headless suite: 1007 checks
luajit tools/map_lab.lua     # validate every layout + route variant
luajit tests/baseline.lua    # deterministic balance baseline, waves 1-30

# LuaJIT syntax gate; keep Lua syntax portable
for f in main.lua lib/*.lua scenes/*.lua tests/*.lua tools/*.lua; do
  luajit -bl "$f" /dev/null || echo "FAIL $f"
done
```

The smoke suite covers core combat, reports, cards, modifiers, auras, telegraphs,
modes, path mutation, route drafts, resources, contracts, resonance, affixes,
boss arenas, tactical UX, mastery, dailies, share codes, settings, replay, sim,
balance, and performance gates. `tests/baseline.lua` pins the standard balance
anchors; `tools/map_lab.lua` catches malformed route content before runtime.

## Project Layout

- `main.lua`: Usagi config, global `State`, scene dispatch, pause/settings hooks
- `lib/`: gameplay systems, simulation, metrics, settings, replay, share codes
- `scenes/`: menu, select, game, upgrade, route, contract, gameover
- `data/`: JSON content for enemies, towers, bosses, powerups, maps, affixes,
  contracts, resonance, mastery, and arenas
- `sfx/`, `music/`, `shaders/`: generated audio and CRT shader variants
- `tools/`: map lab and audio generation
- `tests/`: headless Usagi harness and per-system smoke suites
- `docs/`: design, roadmaps, export/release checklist, current state

## Development Notes

The game is deliberately data-driven: most content additions start with a JSON row
and a small Lua hook. Route changes must preserve the single-polyline invariant;
features that alter enemy/tower behavior should prefer derived fields over
mutating base definitions. `lib/sim.lua` and `lib/loop.lua` are shared by tests
and gameplay so balance, replay verification, and the real game do not drift.

Built with the [Usagi engine](https://github.com/brettchalupa/usagi).

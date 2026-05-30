# geo-td

**Geometric roguelike tower defense** — built entirely from primitive shapes on the
[Usagi](https://usagiengine.com) engine (Rust core, Lua game code). Defend a fixed path
across escalating, procedurally-scaled waves; every 5th wave is a cycling boss. Death banks
meta-currency for permanent unlocks. No art assets — towers, enemies, and bosses are squares,
circles, triangles, and hexagons in a 16-color palette, finished with a CRT / neon post-process.

## Play

Requires the [Usagi](https://usagiengine.com) engine (one-time install — adds `usagi` to
`~/.usagi/bin`; add that to your `PATH`):

```bash
curl -fsSL https://usagiengine.com/install.sh | sh
```

Then, from the repo root:

```bash
usagi dev .     # run with live reload (or: usagi run .)
```

### Controls
- **Mouse** — place the selected tower; click the sidebar buttons
- **1 / 2 / 3 / 4** — select tower (Pellet / Splash / Frost / Rail)
- **S** — sell mode, then click a tower
- **Space / Enter** or **START WAVE** — begin the next wave
- **Right-click** — cancel selection / exit sell mode
- **Esc** — pause menu (volume, fullscreen, CRT toggle, key remap)

## Features
- Fixed-path tower defense with mouse placement, range rings, and sell/refund
- Four towers with air/ground targeting — **flyers** ignore the path and beeline the core
- Ten enemy types: armor, regeneration, regenerating shields, splitters, swarms, flyers
- Four cycling bosses with distinct mechanics — shockwaves, shields, continuous adds, invulnerability windows
- Procedural waves with compounding difficulty tiers every 10 waves
- Roguelike meta-progression: bank currency between runs, permanent unlocks
- Common / Uncommon / Rare upgrade drafts between waves
- Procedurally-synthesized sound effects + ambient track, and a CRT / neon-glow shader

## Develop

```bash
luajit tests/smoke.lua        # headless simulation smoke test (no GUI needed)
python3 tools/gen_audio.py    # regenerate sfx/ and music/ from code
```

The game is data-driven: add an enemy, tower, boss, or upgrade by adding a row to the relevant
JSON file in `data/`.

## Layout
- `main.lua` — engine config + scene dispatch
- `lib/` — game systems (towers, enemies, bosses, waves, projectiles, fx, hud, …)
- `scenes/` — menu, game, upgrade, gameover
- `data/` — JSON content (enemies, towers, bosses, powerups, paths)
- `sfx/`, `music/`, `shaders/` — generated audio + post-process shaders
- `tools/gen_audio.py` — procedural audio generator
- `tests/smoke.lua` — headless verification harness

---

Built with the [Usagi engine](https://github.com/brettchalupa/usagi) (public domain).

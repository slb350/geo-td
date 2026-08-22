# Changelog

## 2026-08-22 — Adopt Usagi 1.3.0 features

Follow-on to the engine update below, applying the new API surface where it fits.

### Off-canvas cursor no longer drives hover (`input.mouse_over`)

`input.mouse()` keeps reporting a clamped position once the cursor leaves the
window or moves onto a letterbox bar, so hover previews stuck to the clamped
edge. `scenes/game.lua` now derives a `ui.hover_over` flag that gates the
ghost-tower preview, the hovered-tower range ring, the aura tooltip and
`ui.hover_valid`. Draw-time hover highlighting in the menu, select, route and
contract scenes goes through a new `ui.hover_pos()`, which returns a
far-off-screen point when the cursor is off the game area so every `in_rect`
test just fails. Click paths are unchanged: a click outside the window never
reaches the game.

### Effects fade instead of popping (trailing `alpha`)

Every `gfx` primitive takes an optional alpha as of 1.2.0; before that only
`text_ex` did, which is why damage numbers already faded while particles did
not. `fx` particles now fade over their life, and `ring` splash zones fade as
they spend their ticks — the code already computed the fraction and used it only
for radius, despite the comment claiming "a fading ring".

Boss telegraphs were deliberately left opaque. They exist to be legible, and
fading them would undercut the warning they carry.

### `gif_length = 12`

Raises F9 capture from the 5s default for trailer clips. Unverifiable headlessly
(it only manifests on an actual recording) and the engine is silent for both
unknown and malformed config keys, so `tests/smoke_config.lua` now pins the exact
frontmatter key set rather than a bare count.

`pixel_perfect` was evaluated and skipped: on a 2x-DPI display the v1.2.0 scaling
rework already lands on an integer scale (`fit 3x`), identical with the flag on
or off. Enabling it would only change resize/fullscreen behaviour to hard
letterboxing — a taste call worth making by eye, not by default.

### Test-file split

`tests/smoke_core.lua` crossed the 600-line soft limit, so its scene-layer block
moved to `tests/smoke_scenes.lua` (438 + 211 lines, both well under). It runs
second because it installs the shared scene globals the later suites reuse. Check
count is identical either side of the split, which is what proves nothing was
lost or duplicated.

### Verification

Smoke 1103/1103 (22 checks added, each mutation-verified: off-canvas ghost and
range-ring suppression, `hover_valid`, `ui.hover_pos` off-canvas, map-tile
highlight, particle and ring fade curves, typo'd/dropped/extra frontmatter keys).
All five export targets gated; the game and the exported bundle both boot clean
at 480x270.

## 2026-08-22 — Usagi engine 1.1.0 → 1.3.0

Updated the engine (`usagi update`) and re-synced the engine-managed files
(`usagi refresh`: `USAGI.md`, `meta/usagi.lua`, `.luarc.json`).

The API-stub diff across 1.1.1 / 1.2.0 / 1.3.0 is purely additive: no removed
functions and no changed signatures, so no call site needed migrating. New
surface:
an optional trailing `alpha` on every `gfx` draw call, `sfx.stop` /
`sfx.stop_all` / `sfx.is_playing`, `input.mouse_over`, `util.remap`, and
`gfx.text` accepting a non-string first argument.

### `_config()` → `main.lua` frontmatter

v1.3.0 deprecates the `_config()` function; the engine logs a warning when it is
present. Config now comes from a `usagi.conf` file or `-- key = value`
frontmatter comments atop `main.lua`.

We use frontmatter, because **`usagi export` does not copy `usagi.conf` into the
bundle**. A conf-configured export contains the config nowhere in its bytes and
boots at 320x180 instead of 480x270 with the save key reverted. On a live game
that orphans every player's localStorage save. `main.lua` is bundled, so
frontmatter survives; an exported bundle built that way boots at 480x270.
Verified on v1.3.0 and worth reporting upstream.

Guards added on both sides:

- `tests/smoke_config.lua`: new suite (12 checks). Parses `main.lua`'s leading
  comment block the way the engine does, pins `game_id`, asserts
  `game_width`/`game_height` equal `C.GAME_W`/`C.GAME_H` (the drift guard that
  moving off `_config()` would otherwise have cost), pins the key count so a
  stray `=` in prose can't inject config, rejects a returning `_config()`, and
  rejects a `usagi.conf` reappearing. Each check was mutation-verified against a
  deliberate break.
- `tools/stage_export.sh`: fails the export unless the save key is present both
  in the staged tree and in the produced artifact's bytes, anchored to the
  frontmatter line so prose quoting the key can't satisfy it. Zip artifacts are
  decompressed before scanning (a fused exe is Deflated, so raw bytes show
  nothing), both content gates now share one extraction, and `--target all`
  gates all five emitted artifacts instead of only the bundle.

### Removed the custom `shell.html`

It was frozen at the v1.0.0 default plus a `contextmenu` suppressor. A
whitespace-insensitive diff against a fresh v1.3.0 default export shows the
engine now ships that suppression itself, and that our copy had never picked up
the `?verbose=1` diagnostic hook added in v1.1.1. Removed the file and the
`--web-shell` flag; a fresh web export was verified to carry both.

### Corrections

- `usagi refresh` overwrites `.luarc.json` and drops the deliberate
  `lowercase-global` diagnostic (audit finding 5). Restored, and recorded as a
  post-refresh step.
- The Android notes recorded "no Usagi → LÖVE conversion path" as verified. It is
  wrong — `usagi loveify <SRC> <DST>` ports a project to Love2D 11.5.
  `docs/EXPORT.md` Option B revised.

### Verification

Smoke 1081/1081, `map_lab` all layouts + variants valid, `baseline.lua` balance
anchors unchanged (cordon still tops out wave 15-16 per map), StyLua + Luacheck
(83 files) + the LuaJIT syntax gate clean, `pre_commit.sh` green. Bundle and web
exports both pass the content and save-key gates; the exported bundle boots at
480x270 with no deprecation warning, and `usagi dev` / `usagi run` boot clean.

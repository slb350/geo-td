# Changelog

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

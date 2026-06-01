#!/usr/bin/env bash
# Staged, runtime-only export with a bundle-content gate.
#
# `usagi export <dir>` bundles the WHOLE project tree (USAGI.md), so a plain
# `usagi export .` ships tests/, tools/, the WAV masters, docs, and agent files
# inside the .usagi bundle. This stages a copy of ONLY the files the engine loads
# at runtime, exports the bundle from that staging root, then verifies the
# produced bundle contains no test/tool source -- so internal harness code can't
# leak into a shipped build.
#
# Runtime set (verified against the project: no sprites.png/font.png/shell.html;
# meta/ is LuaLS type-stubs, not loaded; tests/ tools/ docs/ music_src/ and the
# *.md / dotfiles are not runtime surface):
#   main.lua lib/ scenes/ data/ sfx/ music/ shaders/
#
# Usage:  bash tools/stage_export.sh [--target bundle|all|web|...]   (default: bundle)
# Output: artifact(s) land in ./export/ (the gitignored build dir) and PERSIST --
#         only the throwaway staging copy is cleaned up (with `trash` if present).
# Requires: the usagi binary + `strings`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USAGI="${USAGI_BIN:-$HOME/.usagi/bin/usagi}"
TARGET="${1:-bundle}"; TARGET="${TARGET#--target=}"; [[ "$TARGET" == "--target" ]] && TARGET="${2:-bundle}"

RUNTIME=(main.lua lib scenes data sfx music shaders)

# Only the staging copy is temporary; the export artifact persists in ./export/.
STAGE="$(mktemp -d)"
cleanup() { command -v trash >/dev/null 2>&1 && trash "$STAGE" 2>/dev/null || true; }
trap cleanup EXIT

echo "staging runtime-only tree -> $STAGE"
for item in "${RUNTIME[@]}"; do
  if [[ ! -e "$ROOT/$item" ]]; then echo "  ERROR: runtime item missing: $item" >&2; exit 1; fi
  cp -R "$ROOT/$item" "$STAGE/"
done

# Primary gate (authoritative -- the bundle is exactly this tree): the staging
# root must contain no test/tool surface.
if find "$STAGE" \( -name tests -o -name tools -o -name 'smoke*.lua' \
     -o -name 'baseline.lua' -o -name 'harness.lua' -o -name 'map_lab.lua' \) -print -quit | grep -q .; then
  echo "  ERROR: staging tree contains test/tool files -- runtime set is wrong" >&2; exit 1
fi
echo "  staged: ${RUNTIME[*]}"

OUTROOT="$ROOT/export"        # gitignored build-output dir; artifacts persist here
mkdir -p "$OUTROOT"
echo "exporting (--target $TARGET) -> $OUTROOT"
if [[ "$TARGET" == "bundle" ]]; then
  ARTIFACT="$OUTROOT/usagi-geo-td.usagi"
  "$USAGI" export "$STAGE" --target bundle -o "$ARTIFACT"
else
  "$USAGI" export "$STAGE" --target "$TARGET" -o "$OUTROOT"
  # Scan the portable .usagi if one was produced (e.g. by `all`); a single
  # platform zip has no loose .usagi -- the primary gate above already covers it.
  ARTIFACT="$(find "$OUTROOT" -name '*.usagi' -type f | head -1)"
fi

if [[ -z "${ARTIFACT:-}" ]]; then
  echo "OK (primary gate): staging tree is clean; no .usagi artifact to scan for target '$TARGET'."
  echo "artifacts in: $OUTROOT"
  exit 0
fi

# Secondary gate (defense in depth, on the actual artifact): scan for SHIPPED
# test/tool file paths. Matches precise `.lua/.py/.sh` filenames so it is not
# fooled by legit runtime comments that mention "tests" / "tools/map_lab".
echo "scanning $ARTIFACT for forbidden file paths ..."
hits="$(strings "$ARTIFACT" | grep -nE \
  -e 'tests/[A-Za-z0-9_]+\.lua' \
  -e 'tools/[A-Za-z0-9_]+\.(lua|py|sh)' \
  -e '(^|/)smoke[A-Za-z0-9_]*\.lua' \
  -e '(^|/)(baseline|harness)\.lua' || true)"
if [[ -n "$hits" ]]; then
  echo "  FAIL: bundle contains test/tool source:" >&2
  echo "$hits" | sed 's/^/    /' >&2
  exit 1
fi

size="$(du -h "$ARTIFACT" | cut -f1)"
echo "OK: no test/tool source in the bundle."
echo "artifact: $ARTIFACT  ($size)  (persisted in ./export/)"

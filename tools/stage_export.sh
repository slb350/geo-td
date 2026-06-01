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
NAME="usagi-geo-td"           # explicit output name (the staging dir is a temp path)
mkdir -p "$OUTROOT"
echo "exporting (--target $TARGET) -> $OUTROOT"
# `-o` semantics differ by target: a directory for `all`, a file path otherwise
# (`usagi export` errors on a directory for single-platform/bundle targets).
# Always pass an explicit path so the artifact name comes from $NAME, not the
# temp staging dir basename.
case "$TARGET" in
  bundle)
    ARTIFACT="$OUTROOT/$NAME.usagi"
    "$USAGI" export "$STAGE" --target bundle -o "$ARTIFACT"
    ;;
  all)
    "$USAGI" export "$STAGE" --target all -o "$OUTROOT"
    ARTIFACT="$OUTROOT/$NAME.usagi"   # the portable bundle that `all` also emits
    ;;
  web)
    # The web export hosts the canvas in an HTML shell. We ship a custom
    # shell.html (the engine default + a right-click contextmenu suppressor so
    # in-game RMB works on the web build). The engine's default `<project>/
    # shell.html` lookup would resolve against $STAGE (which has no shell.html,
    # and we keep it out of the runtime set), so pass it explicitly from $ROOT.
    ARTIFACT="$OUTROOT/$NAME-$TARGET.zip"
    SHELL_HTML="$ROOT/shell.html"
    if [[ ! -f "$SHELL_HTML" ]]; then echo "  ERROR: missing $SHELL_HTML for web shell" >&2; exit 1; fi
    "$USAGI" export "$STAGE" --target "$TARGET" --web-shell "$SHELL_HTML" -o "$ARTIFACT"
    ;;
  linux | macos | windows)
    ARTIFACT="$OUTROOT/$NAME-$TARGET.zip"
    "$USAGI" export "$STAGE" --target "$TARGET" -o "$ARTIFACT"
    ;;
  *)
    echo "  ERROR: unknown target '$TARGET' (use bundle|all|web|linux|macos|windows)" >&2
    exit 1
    ;;
esac

# Secondary gate (defense in depth, on the actual artifact): scan for SHIPPED
# test/tool file paths. The primary gate (clean staging tree) is authoritative;
# this re-checks the produced artifact's bytes. Matches precise `.lua/.py/.sh`
# filenames so it is not fooled by legit runtime comments ("tests" / "tools/map_lab").
scan_forbidden() {  # read a byte stream on stdin, print any forbidden path hits
  grep -nE \
    -e 'tests/[A-Za-z0-9_]+\.lua' \
    -e 'tools/[A-Za-z0-9_]+\.(lua|py|sh)' \
    -e '(^|/)smoke[A-Za-z0-9_]*\.lua' \
    -e '(^|/)(baseline|harness)\.lua' || true
}
echo "scanning $ARTIFACT for forbidden file paths ..."
case "$ARTIFACT" in
  *.usagi)   hits="$(strings "$ARTIFACT" | scan_forbidden)" ;;
  *-web.zip) hits="$( (unzip -p "$ARTIFACT" '*.usagi' 2>/dev/null || true) | strings | scan_forbidden)" ;;  # scan the embedded bundle
  *.zip)     hits="$(strings "$ARTIFACT" | scan_forbidden)" ;;  # fused exe zip (best effort; primary gate authoritative)
esac
if [[ -n "$hits" ]]; then
  echo "  FAIL: artifact contains test/tool source:" >&2
  echo "$hits" | sed 's/^/    /' >&2
  exit 1
fi

size="$(du -h "$ARTIFACT" | cut -f1)"
echo "OK: no test/tool source in the artifact."
echo "artifact: $ARTIFACT  ($size)  (persisted in ./export/)"

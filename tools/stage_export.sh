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
# Engine config (name / game_id / resolution) rides in main.lua's FRONTMATTER
# comment block, not a `usagi.conf`: `usagi export` (v1.3.0) does not copy
# usagi.conf into the bundle, so a conf-configured build ships with NO config --
# it falls back to 320x180 and a default save key, which would orphan every live
# player's save. main.lua is bundled, so frontmatter survives. The save-key gate
# below fails the export if that ever stops being true.
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
# Save-key gate: `game_id` is what the engine keys save data on (localStorage on
# web), so the LIVE build's players' saves hang off this exact string. A dropped
# or edited usagi.conf would ship a build that silently can't see their data.
SAVE_KEY="com.brandon.usagigeotd"
if ! grep -qE "^--[[:space:]]*game_id[[:space:]]*=[[:space:]]*$SAVE_KEY[[:space:]]*$" "$STAGE/main.lua"; then
  echo "  ERROR: staged main.lua frontmatter does not set game_id = $SAVE_KEY (would orphan live saves)" >&2; exit 1
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
    ARTIFACTS=("$ARTIFACT")
    ;;
  all)
    "$USAGI" export "$STAGE" --target all -o "$OUTROOT"
    # `all` emits the bundle AND four platform zips; every one ships, so gate
    # every one. Named explicitly rather than globbed: $OUTROOT persists, so a
    # glob would also re-gate stale artifacts from earlier single-target runs.
    ARTIFACTS=("$OUTROOT/$NAME.usagi")
    for plat in linux macos windows web; do
      [[ -f "$OUTROOT/$NAME-$plat.zip" ]] && ARTIFACTS+=("$OUTROOT/$NAME-$plat.zip")
    done
    ;;
  web | linux | macos | windows)
    # `web` needs no --web-shell: engine v1.3.0's baked shell already suppresses
    # the right-click menu, which is all our old custom shell.html added. See
    # docs/EXPORT.md.
    ARTIFACT="$OUTROOT/$NAME-$TARGET.zip"
    "$USAGI" export "$STAGE" --target "$TARGET" -o "$ARTIFACT"
    ARTIFACTS=("$ARTIFACT")
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
# Both gates below read the artifact's bytes, so extract them ONCE to a temp file.
# Every zip target must be decompressed first: the fused exe (and the embedded
# .usagi in the web zip) is Deflated, so scanning the raw zip finds nothing --
# which would silently weaken the forbidden scan and hard-fail the save-key gate.
BYTES="$(mktemp)"
cleanup_bytes() { command -v trash >/dev/null 2>&1 && trash "$BYTES" 2>/dev/null || true; }
trap 'cleanup; cleanup_bytes' EXIT

gate_artifact() {  # $1 = artifact path; runs both content gates over its bytes
  local art="$1"
  # Both gates read the same bytes, so extract ONCE. Every zip must be
  # decompressed first: the fused exe (and the embedded .usagi in the web zip)
  # is Deflated, so scanning raw zip bytes finds nothing -- which would silently
  # weaken the forbidden scan and hard-fail the save-key gate on a good build.
  case "$art" in
    *.zip) (unzip -p "$art" 2>/dev/null || true) | strings > "$BYTES" ;;
    *)     strings "$art" > "$BYTES" ;;
  esac

  local hits
  hits="$(scan_forbidden < "$BYTES")"
  if [[ -n "$hits" ]]; then
    echo "  FAIL: $art contains test/tool source:" >&2
    echo "$hits" | sed 's/^/    /' >&2
    exit 1
  fi

  # Positive counterpart to the scan above: the save key must actually be
  # PRESENT in the shipped bytes, not merely present in the staging tree.
  # Reading from a file (not a pipe) so `grep -q` exiting early can't SIGPIPE a
  # writer into a false failure under `pipefail`. Anchored to the frontmatter
  # line itself, not a bare substring, so prose that merely quotes the key
  # can't satisfy the gate.
  if ! grep -qE "^--[[:space:]]*game_id[[:space:]]*=[[:space:]]*$SAVE_KEY" "$BYTES"; then
    echo "  FAIL: $art does not contain game_id $SAVE_KEY -- shipped saves would not resolve" >&2
    exit 1
  fi

  echo "  OK  $(basename "$art")  ($(du -h "$art" | cut -f1))"
}

echo "gating ${#ARTIFACTS[@]} artifact(s) ..."
for art in "${ARTIFACTS[@]}"; do
  if [[ ! -f "$art" ]]; then echo "  ERROR: expected artifact missing: $art" >&2; exit 1; fi
  gate_artifact "$art"
done
echo "OK: no test/tool source in any artifact; save key $SAVE_KEY present in all."
echo "artifacts persisted in ./export/"

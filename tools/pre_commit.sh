#!/bin/sh
# Git pre-commit quality gate for authored Lua. Keep this script POSIX-sh so Git
# can run it on a fresh checkout without assuming the user's interactive shell.

set -eu

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'pre-commit: missing required command: %s\n' "$1" >&2
    printf 'pre-commit: install luacheck/stylua and ensure LuaJIT is on PATH.\n' >&2
    exit 127
  fi
}

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

require_cmd stylua
require_cmd luacheck
require_cmd luajit

run stylua --check --output-format Summary main.lua lib scenes tests tools
run luacheck main.lua lib scenes tests tools

printf '\n==> LuaJIT syntax gate\n'
for f in main.lua lib/*.lua scenes/*.lua tests/*.lua tools/*.lua; do
  luajit -bl "$f" /dev/null
done

if [ "${USAGI_PRECOMMIT_SMOKE:-1}" != "0" ]; then
  run luajit tests/smoke.lua
fi

printf '\npre-commit: all Lua quality gates passed\n'

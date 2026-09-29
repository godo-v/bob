#!/usr/bin/env bash
# Runs the AI scenario tests outside Roblox using a mocked engine and a
# virtual clock. Needs the `luau` CLI (https://github.com/luau-lang/luau/releases)
# on PATH, or set LUAU=/path/to/luau.
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${LUAU:-luau}"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
{
  echo "local SOURCES = {}"
  for f in $(find src -name '*.luau' | sort); do
    echo "SOURCES[\"$f\"] = [==["
    cat "$f"
    echo "]==]"
  done
  cat tests/ai_scenarios.luau
} > "$out"
"$LUAU" "$out" | tee /dev/stderr | tail -1 | grep -q "ALL TESTS PASSED"

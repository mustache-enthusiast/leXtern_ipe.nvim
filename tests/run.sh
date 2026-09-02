#!/usr/bin/env sh
# Run the test suite: every tests/test_*.lua in its own headless Neovim.
#
#   tests/run.sh            run everything
#   tests/run.sh watcher    run tests/test_watcher.lua only
#
# Each test gets a fresh temp working directory and isolated XDG_* dirs,
# so nothing touches ~/.local/share/nvim or your real config. TEXINPUTS
# points at the isolated package dir so pdflatex-based checks can find
# the generated lextern-ipe.sty. Tests needing a tool that's missing
# (ipetoipe, kpsewhich, pdflatex) skip themselves.
#
# Opt-in: LEXTERN_TEST_LIVE=1 also runs checks that open real windows
# (the Hyprland floating launch), which need a running session.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ $# -gt 0 ]; then
  set -- "$ROOT/tests/test_$1.lua"
else
  set -- "$ROOT"/tests/test_*.lua
fi

total=0
failed=0
skipped=0
for test in "$@"; do
  name=$(basename "$test" .lua)
  work="$TMP/$name"
  mkdir -p "$work/xdg"
  total=$((total + 1))
  printf '\n== %s\n' "$name"
  (
    cd "$work" || exit 2
    XDG_DATA_HOME="$work/xdg" XDG_CONFIG_HOME="$work/xdg" XDG_STATE_HOME="$work/xdg" XDG_CACHE_HOME="$work/xdg" \
      TEXINPUTS="$work/xdg/nvim/lextern_ipe//:${TEXINPUTS:-}" LEXTERN_TEST_ROOT="$ROOT" \
      nvim --headless -u NONE -i NONE -c 'filetype on' \
        -c "luafile $ROOT/tests/helpers.lua" \
        -c "lua T.run('$test')" \
        -c 'cquit 3'
  ) >"$work/log" 2>&1
  status=$?
  grep -v '^$' "$work/log" | grep -v ' ✓$'
  if grep -q '^SKIP:' "$work/log"; then
    skipped=$((skipped + 1))
  elif [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
    echo "-> FAILED (exit $status)"
  fi
done

printf '\n%d test file(s): %d failed, %d skipped\n' "$total" "$failed" "$skipped"
[ "$failed" -eq 0 ]

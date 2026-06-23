################################################################################
# Test file   : tests/scripts/test_tampermonkey_install.sh
# Description : Behavioural tests for src/scripts/tampermonkey-install.sh. The
#               script runs Main on source (Execution section), so it is driven
#               as a subprocess and asserted on exit code + output. The final
#               URL is always logged, so URL construction is asserted by reading
#               the captured output. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

TMI="$REPO_ROOT/src/scripts/tampermonkey-install.sh"

# run_tmi() runs the script with the given args, capturing combined output to a
# temp file (not a pipe) and echoing it. xdg-open is stubbed as a no-op so the
# browser is never opened during tests; the script always LogInfos the URL
# regardless, so URL assertions remain stable.
run_tmi()
{
  local tmp out stub_dir
  tmp="$(mktemp)"
  stub_dir="$(mktemp -d)"
  printf '#!/bin/sh\n' > "$stub_dir/xdg-open"
  chmod +x "$stub_dir/xdg-open"
  PATH="$stub_dir:$PATH" bash "$TMI" "$@" > "$tmp" 2>&1
  out="$(cat "$tmp")"
  rm -f "$tmp" "$stub_dir/xdg-open"
  rmdir "$stub_dir"
  echo "$out"
}

# --- Help / argument parsing --------------------------------------------------

assert_exit 0 "-h prints help and exits 0" -- bash "$TMI" -h
assert_contains "$ASSERT_OUTPUT" \
  "Build a GitHub userscript URL and open it for Tampermonkey" \
  "-h output describes the script"

assert_exit 1 "-d with no value exits 1" -- bash "$TMI" -d
assert_exit 1 "-s with no value exits 1" -- bash "$TMI" -s
assert_exit 1 "-r with no value exits 1" -- bash "$TMI" -r
assert_exit 1 "unknown argument exits 1" -- bash "$TMI" --bogus

# --- Required-argument validation ---------------------------------------------

assert_exit 1 "missing -d exits 1" -- bash "$TMI" -s video-speed
assert_exit 1 "missing -s exits 1" -- bash "$TMI" -d youtube.com

# --- Input validation ---------------------------------------------------------

assert_exit 1 "domain with a space exits 1" -- \
  bash "$TMI" -d "bad domain" -s video-speed
assert_exit 1 "script with a slash exits 1" -- \
  bash "$TMI" -d youtube.com -s "bad/name"

# --- URL construction ---------------------------------------------------------

OUT="$(run_tmi -d youtube.com -s video-speed -r https://example.com/scripts)"
assert_contains "$OUT" \
  "https://example.com/scripts/youtube.com/video-speed.user.js" \
  "run builds the expected userscript URL"

OUT="$(run_tmi -d youtube.com -s video-speed.user.js \
  -r https://example.com/scripts)"
assert_contains "$OUT" \
  "example.com/scripts/youtube.com/video-speed.user.js" \
  ".user.js suffix stripped and re-appended"

OUT="$(run_tmi -d youtube.com -s video-speed \
  -r https://example.com/scripts/)"
assert_contains "$OUT" \
  "scripts/youtube.com/video-speed.user.js" \
  "trailing slash on base is collapsed"

# --- Missing-base error -------------------------------------------------------

# Runs from a temp src/ tree (no .env at its root) so the script's mandatory
# source "$PROJECT_ROOT/.env" can't re-define TAMPERMONKEY_REPO_BASE_URLS.
assert_missing_base_exits_1()
{
  local proj rc
  proj="$(mktemp -d)"
  mkdir -p "$proj/src/scripts" "$proj/src/lib"
  cp "$REPO_ROOT/src/scripts/tampermonkey-install.sh" \
    "$proj/src/scripts/"
  cp "$REPO_ROOT/src/lib/common.sh" "$proj/src/lib/"
  env -u TAMPERMONKEY_REPO_BASE_URLS \
    bash "$proj/src/scripts/tampermonkey-install.sh" \
    -d youtube.com -s video-speed >/dev/null 2>&1
  rc=$?
  rm -rf "$proj"
  return "$rc"
}

assert_exit 1 "missing base with no -r exits 1" \
  -- assert_missing_base_exits_1

################################################################################

################################################################################
# Test file   : tests/scripts/test_rain_alert.sh
# Description : Behavioural tests for src/scripts/rain-alert.sh. The script runs
#               Main on source (Execution section), so it is driven as a
#               subprocess and asserted on exit code + output. curl and msmtp
#               are stubbed via a PATH-prepended fixture bin so no network call
#               or real mail is made; the curl stub serves rainy/dry/error JSON
#               keyed off the requested coordinates and the msmtp stub records
#               its invocation to a file. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

RAIN="$REPO_ROOT/src/scripts/rain-alert.sh"

# --- Help / argument parsing --------------------------------------------------

assert_exit 0 "-h prints help and exits 0" -- bash "$RAIN" -h
assert_contains "$ASSERT_OUTPUT" "rain alert" "-h output describes the script"

assert_exit 1 "unknown argument exits 1" -- bash "$RAIN" --bogus

# --- Fixture harness ----------------------------------------------------------

# A scratch dir holding: a fake bin (curl/msmtp stubs) prepended to PATH, an
# isolated cache file, and an msmtp invocation recorder. rain() runs the script
# with a controlled environment so .env on the dev box never bleeds in.
RAIN_TMP="$(mktemp -d)"
RAIN_BIN="$RAIN_TMP/bin"
mkdir -p "$RAIN_BIN"
RAIN_CACHE="$RAIN_TMP/cache.txt"
MSMTP_LOG="$RAIN_TMP/msmtp.log"

# curl stub: emits JSON chosen by RAIN_FIXTURE (rainy/dry/error). On "error" it
# exits non-zero like a real curl -fsS transport/HTTP failure. The forecast time
# is generated one hour from now (UTC) so it always lands inside the lookahead.
cat > "$RAIN_BIN/curl" <<'STUB'
#!/bin/bash
case "${RAIN_FIXTURE:-dry}" in
  error)
    echo "curl: (22) HTTP error" >&2
    exit 22
    ;;
  rainy)
    soon="$(date -u -d '+1 hour' '+%Y-%m-%dT%H:00:00Z')"
    cat <<JSON
{ "properties": { "timeseries": [
  { "time": "$soon",
    "data": { "next_1_hours": {
      "summary": { "symbol_code": "rain" },
      "details": { "precipitation_amount": 1.2 } } } } ] } }
JSON
    ;;
  tailmix)
    # One rainy entry WITH next_1_hours and one tail entry WITHOUT it (as met.no
    # emits beyond ~2 days). The jq ?/// guards must tolerate the missing block.
    soon="$(date -u -d '+1 hour' '+%Y-%m-%dT%H:00:00Z')"
    later="$(date -u -d '+2 hours' '+%Y-%m-%dT%H:00:00Z')"
    cat <<JSON
{ "properties": { "timeseries": [
  { "time": "$soon",
    "data": { "next_1_hours": {
      "summary": { "symbol_code": "lightrain" },
      "details": { "precipitation_amount": 0.4 } } } },
  { "time": "$later",
    "data": { "instant": { "details": { "air_temperature": 12.3 } } } } ] } }
JSON
    ;;
  *)
    soon="$(date -u -d '+1 hour' '+%Y-%m-%dT%H:00:00Z')"
    cat <<JSON
{ "properties": { "timeseries": [
  { "time": "$soon",
    "data": { "next_1_hours": {
      "summary": { "symbol_code": "clearsky_day" },
      "details": { "precipitation_amount": 0 } } } } ] } }
JSON
    ;;
esac
STUB
chmod +x "$RAIN_BIN/curl"

# msmtp stub: records its argv and stdin so tests can assert it was (or was not)
# called and with what.
cat > "$RAIN_BIN/msmtp" <<STUB
#!/bin/bash
{ echo "ARGS: \$*"; echo "---"; cat; } >> "$MSMTP_LOG"
STUB
chmod +x "$RAIN_BIN/msmtp"

# rain FIXTURE [args...]: run the script with the stub bin on PATH, a clean
# config (single city, isolated cache), and the chosen fixture. Output is
# captured into ASSERT_OUTPUT-compatible $RAIN_OUT via a temp file (not a pipe).
rain()
{
  local fixture="$1"; shift
  local tmp out
  tmp="$(mktemp)"
  PATH="$RAIN_BIN:$PATH" \
  RAIN_FIXTURE="$fixture" \
  RAIN_ALERT_CITIES="Testville:1.0:2.0" \
  RAIN_ALERT_RECIPIENT="me@example.com" \
  RAIN_ALERT_MSMTP_ACCOUNT="default" \
  RAIN_ALERT_THROTTLE_SECONDS=0 \
  RAIN_ALERT_CACHE_FILE="$RAIN_CACHE" \
  bash "$RAIN" "$@" > "$tmp" 2>&1
  RAIN_RC=$?
  RAIN_OUT="$(cat "$tmp")"
  rm -f "$tmp"
}

# RAIN_ALERT_CITIES is a scalar (whitespace/comma-separated "name:lat:lon"); the
# rain() helper injects a single city via the environment. These tests are
# designed to pass in a clean no-.env checkout (the CI gate); a dev-box .env that
# defines RAIN_ALERT_* keys would override this env injection (.env is sourced
# over in-script/env defaults by house style) and could perturb the city count.

# --- Missing recipient --------------------------------------------------------

assert_exit 1 "missing recipient exits 1" -- env \
  PATH="$RAIN_BIN:$PATH" RAIN_FIXTURE=dry \
  RAIN_ALERT_RECIPIENT="" RAIN_ALERT_CACHE_FILE="$RAIN_CACHE" \
  bash "$RAIN"
assert_contains "$ASSERT_OUTPUT" "Missing required arguments" \
  "missing recipient reports missing required arguments"

# --- msmtp missing failure path -----------------------------------------------

# A bin with curl but NO msmtp: a real send must hard-fail with guidance.
RAIN_BIN_NOMSMTP="$RAIN_TMP/bin-nomsmtp"
mkdir -p "$RAIN_BIN_NOMSMTP"
cp "$RAIN_BIN/curl" "$RAIN_BIN_NOMSMTP/curl"
assert_exit 1 "msmtp missing exits 1 on a real send" -- env \
  PATH="$RAIN_BIN_NOMSMTP:/usr/bin:/bin" RAIN_FIXTURE=rainy \
  RAIN_ALERT_RECIPIENT="me@example.com" \
  RAIN_ALERT_CITIES="Testville:1.0:2.0" \
  RAIN_ALERT_THROTTLE_SECONDS=0 \
  RAIN_ALERT_CACHE_FILE="$RAIN_TMP/nomsmtp-cache.txt" \
  bash "$RAIN"
assert_contains "$ASSERT_OUTPUT" "msmtp is required" \
  "msmtp-missing failure prints install guidance"

# --- All-dry: silent exit 0, no email -----------------------------------------

: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain dry
assert_eq 0 "$RAIN_RC" "all-dry fixture exits 0"
assert_eq "" "$(cat "$MSMTP_LOG")" "all-dry fixture sends no email (msmtp not called)"

# --- Rainy: composes expected subject/body and sends --------------------------

: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain rainy
assert_eq 0 "$RAIN_RC" "rainy fixture exits 0"
MSMTP_CONTENT="$(cat "$MSMTP_LOG")"
assert_contains "$MSMTP_CONTENT" "Rain expected in 1 city" \
  "rainy fixture composes the expected subject"
assert_contains "$MSMTP_CONTENT" "Testville" \
  "rainy fixture body lists the rainy city"
assert_contains "$MSMTP_CONTENT" "me@example.com" \
  "rainy fixture addresses the configured recipient"

# --- Cache de-dupe: second identical run does not re-send ---------------------

: > "$MSMTP_LOG"
rain rainy
assert_eq 0 "$RAIN_RC" "repeat rainy run exits 0"
assert_contains "$RAIN_OUT" "unchanged" \
  "repeat rainy run reports the forecast unchanged"
assert_eq "" "$(cat "$MSMTP_LOG")" "repeat rainy run sends no email (cache suppresses)"

# --- Dry-run: prints would-send, never calls msmtp ----------------------------

: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain rainy -n
assert_eq 0 "$RAIN_RC" "--dry-run rainy run exits 0"
assert_contains "$RAIN_OUT" "would send" \
  "--dry-run prints the would-send email"
assert_contains "$RAIN_OUT" "Rain expected in 1 city" \
  "--dry-run shows the composed subject"
assert_eq "" "$(cat "$MSMTP_LOG")" "--dry-run never calls msmtp"
assert_exit 1 "missing cache file proves dry-run wrote no cache" -- \
  test -f "$RAIN_CACHE"

# --- Display mode: prints data, never sends, no recipient/msmtp needed --------

: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain rainy -d
assert_eq 0 "$RAIN_RC" "--display rainy run exits 0"
assert_contains "$RAIN_OUT" "Rain expected in 1 city" \
  "--display prints the forecast subject"
assert_contains "$RAIN_OUT" "Testville" \
  "--display lists the rainy city"
assert_eq "" "$(cat "$MSMTP_LOG")" "--display never calls msmtp"
assert_exit 1 "--display writes no cache" -- test -f "$RAIN_CACHE"

# All-dry under --display still prints an explicit no-rain line (not silent).
: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain dry -d
assert_eq 0 "$RAIN_RC" "--display all-dry run exits 0"
assert_contains "$RAIN_OUT" "No rain expected" \
  "--display reports no rain explicitly"
assert_eq "" "$(cat "$MSMTP_LOG")" "--display all-dry never calls msmtp"

# Display mode needs neither a recipient nor msmtp on PATH.
assert_exit 0 "--display works without recipient or msmtp" -- env \
  PATH="$RAIN_BIN_NOMSMTP:/usr/bin:/bin" RAIN_FIXTURE=rainy \
  RAIN_ALERT_RECIPIENT="" \
  RAIN_ALERT_CITIES="Testville:1.0:2.0" \
  RAIN_ALERT_THROTTLE_SECONDS=0 \
  RAIN_ALERT_CACHE_FILE="$RAIN_TMP/display-cache.txt" \
  bash "$RAIN" -d
assert_contains "$ASSERT_OUTPUT" "Testville" \
  "--display without recipient/msmtp still lists the rainy city"

# --- jq tail-robustness: missing next_1_hours must not error ------------------

# The plan's top risk: a timeseries entry beyond ~2 days has no next_1_hours
# block. The run must still exit 0 and report the one rainy hour, not crash.
: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
rain tailmix -d
assert_eq 0 "$RAIN_RC" "missing-next_1_hours fixture exits 0 (no jq error)"
assert_contains "$RAIN_OUT" "Testville" \
  "tail-robustness fixture still lists the rainy city"
assert_eq "" "$(cat "$MSMTP_LOG")" "tail-robustness display run sends no email"

# --- Multi-city: subject pluralizes to 'cities' -------------------------------

: > "$MSMTP_LOG"
rm -f "$RAIN_CACHE"
MULTI_OUT="$(mktemp)"
PATH="$RAIN_BIN:$PATH" \
RAIN_FIXTURE="rainy" \
RAIN_ALERT_CITIES="Testville:1.0:2.0 Otherville:3.0:4.0" \
RAIN_ALERT_RECIPIENT="me@example.com" \
RAIN_ALERT_MSMTP_ACCOUNT="default" \
RAIN_ALERT_THROTTLE_SECONDS=0 \
RAIN_ALERT_CACHE_FILE="$RAIN_TMP/multi-cache.txt" \
bash "$RAIN" > "$MULTI_OUT" 2>&1
assert_eq 0 "$?" "two-city rainy run exits 0"
MSMTP_CONTENT="$(cat "$MSMTP_LOG")"
assert_contains "$MSMTP_CONTENT" "Rain expected in 2 cities" \
  "two-city run pluralizes the subject to 'cities'"
assert_contains "$MSMTP_CONTENT" "Otherville" \
  "two-city run body lists the second city"
rm -f "$MULTI_OUT"

# --- Empty msmtp account: send omits the --account token ----------------------

# The documented default (empty RAIN_ALERT_MSMTP_ACCOUNT) must invoke msmtp with
# no --account= argument, exercising SendEmail's conditional-argv path.
: > "$MSMTP_LOG"
ACCT_OUT="$(mktemp)"
PATH="$RAIN_BIN:$PATH" \
RAIN_FIXTURE="rainy" \
RAIN_ALERT_CITIES="Testville:1.0:2.0" \
RAIN_ALERT_RECIPIENT="me@example.com" \
RAIN_ALERT_MSMTP_ACCOUNT="" \
RAIN_ALERT_THROTTLE_SECONDS=0 \
RAIN_ALERT_CACHE_FILE="$RAIN_TMP/acct-cache.txt" \
bash "$RAIN" > "$ACCT_OUT" 2>&1
assert_eq 0 "$?" "empty-account rainy run exits 0"
ACCT_ARGS="$(grep '^ARGS:' "$MSMTP_LOG")"
assert_eq "ARGS: me@example.com" "$ACCT_ARGS" \
  "empty account invokes msmtp with just the recipient (no --account token)"
rm -f "$ACCT_OUT"

# --- Cleanup ------------------------------------------------------------------

rm -rf "$RAIN_TMP"
unset RAIN_TMP RAIN_BIN RAIN_BIN_NOMSMTP RAIN_CACHE MSMTP_LOG \
  RAIN_RC RAIN_OUT MSMTP_CONTENT MULTI_OUT ACCT_OUT ACCT_ARGS

################################################################################

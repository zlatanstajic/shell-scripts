################################################################################
# Test file   : tests/scripts/test_shutdown_guard.sh
# Description : Behaviour tests for src/scripts/shutdown-guard.sh. Uses a
#               copied-tree fixture with its own .env so PROJECT_ROOT resolves
#               to the fixture and the developer's gitignored repo .env is never
#               read, and ambient SHUTDOWN_GUARD_* variables are scrubbed from
#               every run so a dev/CI shell export cannot leak into a case.
#               Every run is a dry-run (-n), so no power command can ever
#               execute. Sourced by tests/run.sh
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Hermetic fixture (do NOT stage the repo-root .env). PROJECT_ROOT resolves to
# $SG_TMP via readlink (two levels up from src/scripts/).
SG_TMP="$(mktemp -d)"
mkdir -p "$SG_TMP/src/scripts" "$SG_TMP/src/lib"
cp "$REPO_ROOT/src/scripts/shutdown-guard.sh" "$SG_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$SG_TMP/src/lib/"

SG_SCRIPT="$SG_TMP/src/scripts/shutdown-guard.sh"

################################################################################
# Function    : SgEnv
# Description : Rewrites the fixture .env from the given lines (one per arg)
# Parameters  : line...
################################################################################

SgEnv()
{
  printf '%s\n' "$@" > "$SG_TMP/.env"
}

################################################################################
# Function    : SgRun
# Description : Runs the fixture script with every SHUTDOWN_GUARD_* variable
#               scrubbed from the environment, so only the fixture .env can
#               configure the guards (an exported var in the dev's or CI's shell
#               must not leak past the fixture)
# Parameters  : script-arguments
################################################################################

SgRun()
{
  local scrub=(-u SHUTDOWN_GUARD_TIMEOUT -u SHUTDOWN_GUARD_STRICT)
  local i
  for i in 1 2 3 4 5
  do
    scrub+=(-u "SHUTDOWN_GUARD_${i}_CMD" -u "SHUTDOWN_GUARD_${i}_DESC" \
      -u "SHUTDOWN_GUARD_${i}_MODE")
  done
  env "${scrub[@]}" bash "$SG_SCRIPT" "$@"
}

# --- Usage / argument parsing -------------------------------------------------

SgEnv '# no guards'

assert_exit 0 "shutdown-guard -h exits 0" -- \
  SgRun -h
assert_contains "$ASSERT_OUTPUT" "Running shutdown-guard.sh" \
  "shutdown-guard -h prints the banner"

assert_exit 1 "shutdown-guard with no mode flag exits 1" -- \
  SgRun
assert_contains "$ASSERT_OUTPUT" "Missing required arguments" \
  "shutdown-guard with no mode flag reports missing arguments"

assert_exit 1 "shutdown-guard -s -r exits 1 (mutually exclusive)" -- \
  SgRun -s -r
assert_contains "$ASSERT_OUTPUT" "mutually exclusive" \
  "shutdown-guard -s -r explains the conflict"

assert_exit 1 "shutdown-guard with an unknown flag exits 1" -- \
  SgRun --bogus

# Zero configured guards is a warning, not an error.
assert_exit 0 "shutdown-guard with zero guards exits 0" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "No guards are configured" \
  "shutdown-guard warns when no guards are configured"
assert_contains "$ASSERT_OUTPUT" "would: systemctl poweroff" \
  "shutdown-guard with zero guards still reaches the power command"

# --- Passing guard ------------------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="true"'

assert_exit 0 "shutdown-guard -n -y -s exits 0 with a passing guard" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "would: systemctl poweroff" \
  "shutdown-guard -s delegates to systemctl poweroff"

assert_exit 0 "shutdown-guard -n -y -r exits 0 with a passing guard" -- \
  SgRun -n -y -r
assert_contains "$ASSERT_OUTPUT" "would: systemctl reboot" \
  "shutdown-guard -r delegates to systemctl reboot"

# --- empty-mode blocker -------------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo vm-1"' \
  'SHUTDOWN_GUARD_1_DESC="VirtualBox VMs still running"' \
  'SHUTDOWN_GUARD_1_MODE="empty"'

assert_exit 3 "shutdown-guard exits 3 on an empty-mode blocker" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "VirtualBox VMs still running" \
  "shutdown-guard reports the blocking guard description"
assert_contains "$ASSERT_OUTPUT" "Shutdown BLOCKED by 1 guard(s)" \
  "shutdown-guard prints the blocked summary"
assert_eq "0" "$(printf '%s' "$ASSERT_OUTPUT" | grep -c 'would:')" \
  "shutdown-guard runs no power command when blocked"

# --- status-mode blocker ------------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="false"' \
  'SHUTDOWN_GUARD_1_DESC="job still running"'

assert_exit 3 "shutdown-guard exits 3 on a status-mode blocker" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "job still running" \
  "shutdown-guard reports the status-mode blocker"

# --- match / nomatch modes ----------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo abc"' \
  'SHUTDOWN_GUARD_1_MODE="match:a.c"'

assert_exit 3 "shutdown-guard exits 3 when match:<ERE> matches" -- \
  SgRun -n -y -s

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo abc"' \
  'SHUTDOWN_GUARD_1_MODE="nomatch:zzz"'

assert_exit 3 "shutdown-guard exits 3 when nomatch:<ERE> does not match" -- \
  SgRun -n -y -s

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo abc"' \
  'SHUTDOWN_GUARD_1_MODE="nomatch:a.c"'

assert_exit 0 "shutdown-guard exits 0 when nomatch:<ERE> matches" -- \
  SgRun -n -y -s

# --- Invalid mode -------------------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="true"' 'SHUTDOWN_GUARD_1_MODE="bogus"'

assert_exit 1 "shutdown-guard exits 1 on an unknown guard mode" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "unknown mode" \
  "shutdown-guard names the unknown mode"

# --- Timeout is fail-closed ---------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="sleep 5"' 'SHUTDOWN_GUARD_TIMEOUT=1'

assert_exit 3 "shutdown-guard fails closed when a guard times out" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "timed out" \
  "shutdown-guard explains the timeout block"

# --- Missing binary: strict vs non-strict -------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="sg-definitely-not-a-binary"'

assert_exit 0 "shutdown-guard skips an unrunnable guard under STRICT=0" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "command not found" \
  "shutdown-guard warns about the unrunnable guard"

SgEnv 'SHUTDOWN_GUARD_1_CMD="sg-definitely-not-a-binary"' \
  'SHUTDOWN_GUARD_STRICT=1'

assert_exit 3 "shutdown-guard blocks an unrunnable guard under STRICT=1" -- \
  SgRun -n -y -s

# --- Force bypass -------------------------------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo vm-1"' 'SHUTDOWN_GUARD_1_MODE="empty"'

assert_exit 0 "shutdown-guard -f bypasses a blocking guard" -- \
  SgRun -n -y -f -s
assert_contains "$ASSERT_OUTPUT" "ALL guards bypassed" \
  "shutdown-guard -f warns that guards were bypassed"
assert_contains "$ASSERT_OUTPUT" "would: systemctl poweroff" \
  "shutdown-guard -f still reaches the power command"

# --- Multiple guards: no short-circuit ----------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="false"' 'SHUTDOWN_GUARD_1_DESC="first blocker"' \
  'SHUTDOWN_GUARD_2_CMD="false"' 'SHUTDOWN_GUARD_2_DESC="second blocker"'

assert_exit 3 "shutdown-guard exits 3 with two blockers" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "second blocker" \
  "shutdown-guard evaluates every guard (no short-circuit)"
assert_contains "$ASSERT_OUTPUT" "Shutdown BLOCKED by 2 guard(s)" \
  "shutdown-guard counts every blocker"

# --- Global validation (ValidateGlobals) --------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="true"' 'SHUTDOWN_GUARD_TIMEOUT=abc'

assert_exit 1 "shutdown-guard rejects a non-numeric timeout" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "SHUTDOWN_GUARD_TIMEOUT" \
  "shutdown-guard names the bad timeout key"

# timeout 0 means NO limit in GNU coreutils, which would silently remove the
# fail-closed protection, so 0 must be rejected.
SgEnv 'SHUTDOWN_GUARD_1_CMD="true"' 'SHUTDOWN_GUARD_TIMEOUT=0'

assert_exit 1 "shutdown-guard rejects a zero timeout" -- \
  SgRun -n -y -s

# All digits, but wider than the shell's integer range: the -lt test itself
# fails on such a value, so it must be rejected by the pattern check first.
SgEnv 'SHUTDOWN_GUARD_1_CMD="true"' \
  'SHUTDOWN_GUARD_TIMEOUT=99999999999999999999'

assert_exit 1 "shutdown-guard rejects an implausibly large timeout" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "implausibly large" \
  "shutdown-guard explains the implausible timeout"

SgEnv 'SHUTDOWN_GUARD_1_CMD="true"' 'SHUTDOWN_GUARD_STRICT=2'

assert_exit 1 "shutdown-guard rejects an out-of-range strict flag" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "SHUTDOWN_GUARD_STRICT" \
  "shutdown-guard names the bad strict key"

# --- A failing guard command blocks in the stdout-inspecting modes ------------

# Regression: a guard that exits non-zero and writes only to stderr leaves
# stdout empty; empty mode must NOT read that as "nothing running".
SgEnv 'SHUTDOWN_GUARD_1_CMD="echo boom >&2; exit 1"' \
  'SHUTDOWN_GUARD_1_DESC="vm lister is broken"' \
  'SHUTDOWN_GUARD_1_MODE="empty"'

assert_exit 3 "shutdown-guard blocks when an empty-mode guard fails" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "state unknown" \
  "shutdown-guard explains the failed-guard block"
assert_eq "0" "$(printf '%s' "$ASSERT_OUTPUT" | grep -c 'would:')" \
  "shutdown-guard runs no power command when a guard fails"

SgEnv 'SHUTDOWN_GUARD_1_CMD="exit 2"' 'SHUTDOWN_GUARD_1_MODE="match:x"'

assert_exit 3 "shutdown-guard blocks when a match-mode guard fails" -- \
  SgRun -n -y -s

SgEnv 'SHUTDOWN_GUARD_1_CMD="exit 2"' 'SHUTDOWN_GUARD_1_MODE="nomatch:x"'

assert_exit 3 "shutdown-guard blocks when a nomatch-mode guard fails" -- \
  SgRun -n -y -s

# --- Invalid ERE is a configuration error ------------------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo abc"' \
  'SHUTDOWN_GUARD_1_MODE="match:[unclosed"'

assert_exit 1 "shutdown-guard exits 1 on an invalid match: ERE" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "invalid ERE" \
  "shutdown-guard names the invalid ERE"

SgEnv 'SHUTDOWN_GUARD_1_CMD="echo abc"' \
  'SHUTDOWN_GUARD_1_MODE="nomatch:[unclosed"'

assert_exit 1 "shutdown-guard exits 1 on an invalid nomatch: ERE" -- \
  SgRun -n -y -s

# --- Ambient environment cannot configure a guard -----------------------------

SgEnv 'SHUTDOWN_GUARD_1_CMD="true"'

export SHUTDOWN_GUARD_2_CMD="false"
assert_exit 0 "an exported guard var does not leak past the fixture" -- \
  SgRun -n -y -s
assert_contains "$ASSERT_OUTPUT" "would: systemctl poweroff" \
  "the leaked guard var did not block the run"
unset SHUTDOWN_GUARD_2_CMD

rm -rf "$SG_TMP"

################################################################################

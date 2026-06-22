################################################################################
# Test file   : tests/test_common.sh
# Description : Unit tests for the shared helpers in src/lib/common.sh. Pure
#               helpers are sourced and called directly; helpers that call exit
#               (End, MissingRequiredArguments) are exercised in subshells so
#               the runner survives. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# common.sh requires SCRIPT_NAME to be set by its caller before sourcing.
SCRIPT_NAME="test-runner"
# shellcheck source=../src/lib/common.sh
source "$REPO_ROOT/src/lib/common.sh"

# --- UrlEncode ----------------------------------------------------------------

assert_eq "hello" "$(UrlEncode "hello")" \
  "UrlEncode leaves plain alphanumerics untouched"
assert_eq "a%20b" "$(UrlEncode "a b")" \
  "UrlEncode encodes a space as %20"
assert_eq "A.~_-Z" "$(UrlEncode "A.~_-Z")" \
  "UrlEncode keeps the unreserved set . ~ _ - intact"
assert_eq "a%2Fb%3Fc%3Dd" "$(UrlEncode "a/b?c=d")" \
  "UrlEncode encodes / ? = reserved characters"
assert_eq "100%25" "$(UrlEncode "100%")" \
  "UrlEncode encodes a literal percent sign"

# --- EchoBold / Log helpers ---------------------------------------------------

assert_contains "$(EchoBold "loud")" "loud" \
  "EchoBold echoes the message text"
assert_contains "$(LogInfo "info line")" "info line" \
  "LogInfo echoes the message text"
assert_contains "$(LogWarn "careful")" "WARNING:" \
  "LogWarn prefixes the WARNING: label"
assert_contains "$(LogWarn "careful")" "careful" \
  "LogWarn includes the message text"
assert_contains "$(LogError "boom")" "ERROR:" \
  "LogError prefixes the ERROR: label"

# --- End ----------------------------------------------------------------------

assert_exit 0 "End 0 exits with code 0" -- \
  bash -c "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; End 0"
assert_contains "$ASSERT_OUTPUT" "finishing OK" \
  "End 0 prints the OK finishing message"

assert_exit 1 "End 1 exits with code 1" -- \
  bash -c "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; End 1 'bad thing'"
assert_contains "$ASSERT_OUTPUT" "bad thing" \
  "End 1 includes the supplied error text"

# Default argument: End with no code is treated as success (0).
assert_exit 0 "End with no argument defaults to success" -- \
  bash -c "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; End"

# --- MissingRequiredArguments -------------------------------------------------

assert_exit 1 "MissingRequiredArguments exits with code 1" -- \
  bash -c "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; MissingRequiredArguments"
assert_contains "$ASSERT_OUTPUT" "Missing required arguments" \
  "MissingRequiredArguments prints the standard message"

# --- RunOrEcho ----------------------------------------------------------------

# Dry-run: prints a %q-quoted would-line to STDERR, returns 0, touches nothing.
RUNORECHO_TMP="$(mktemp -u)"
RUNORECHO_CAP="$(mktemp)"
( DRY_RUN=1 RunOrEcho touch "$RUNORECHO_TMP" ) 2> "$RUNORECHO_CAP"
assert_eq 0 "$?" "RunOrEcho dry-run returns 0"
assert_eq "0" "$([ -e "$RUNORECHO_TMP" ] && echo 1 || echo 0)" \
  "RunOrEcho dry-run does not create the file"
assert_contains "$(cat "$RUNORECHO_CAP")" "would:" \
  "RunOrEcho dry-run prints a would: line to stderr"

# Space-containing argument round-trips %q-escaped (no raw embedded space).
RUNORECHO_SPACE="$(mktemp -u)/a b.txt"
RUNORECHO_CAP2="$(mktemp)"
( DRY_RUN=1 RunOrEcho touch "$RUNORECHO_SPACE" ) 2> "$RUNORECHO_CAP2"
assert_contains "$(cat "$RUNORECHO_CAP2")" 'a\ b.txt' \
  "RunOrEcho dry-run %q-escapes a space-containing argument"
rm -f "$RUNORECHO_CAP" "$RUNORECHO_CAP2"

# Real mode: executes the command and returns 0.
RUNORECHO_REAL="$(mktemp -u)"
( DRY_RUN=0 RunOrEcho touch "$RUNORECHO_REAL" )
assert_eq 0 "$?" "RunOrEcho real mode returns 0"
assert_eq "1" "$([ -e "$RUNORECHO_REAL" ] && echo 1 || echo 0)" \
  "RunOrEcho real mode creates the file"
rm -f "$RUNORECHO_REAL"

# --- DoYouWishToProceed (EOF) -------------------------------------------------

# Driven with closed stdin it must NOT hang (current bug hung forever). The
# timeout wrapper yields 124 on hang; assert it does not. Echoes "0" (decline).
assert_exit 0 "DoYouWishToProceed does not hang on closed stdin" -- \
  timeout 3 bash -c \
  "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; DoYouWishToProceed </dev/null"
assert_contains "$ASSERT_OUTPUT" "0" \
  "DoYouWishToProceed echoes 0 on EOF (declines)"

# --- ConfirmOrAbort -----------------------------------------------------------

# Bypass paths return 0 without prompting (run in subshells; no stdin needed).
( DRY_RUN=1 ASSUME_YES=0 ConfirmOrAbort </dev/null )
assert_eq 0 "$?" "ConfirmOrAbort returns 0 under DRY_RUN=1"
( DRY_RUN=0 ASSUME_YES=1 ConfirmOrAbort </dev/null )
assert_eq 0 "$?" "ConfirmOrAbort returns 0 under ASSUME_YES=1"

# Abort path: with closed stdin DoYouWishToProceed echoes 0, so ConfirmOrAbort
# reaches End 0 (clean abort exit). Driven in a child per the End convention.
assert_exit 0 "ConfirmOrAbort aborts cleanly (End 0) when declined" -- \
  bash -c \
  "SCRIPT_NAME=t; source '$REPO_ROOT/src/lib/common.sh'; ConfirmOrAbort </dev/null"
assert_contains "$ASSERT_OUTPUT" "finishing OK" \
  "ConfirmOrAbort abort path prints the clean-finish message"

################################################################################

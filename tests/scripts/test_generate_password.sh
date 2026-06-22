################################################################################
# Test file   : tests/test_generate_password.sh
# Description : Behavioural tests for src/scripts/generate-password.sh. The
#               script runs Main on source (Execution section), so it is driven
#               as a subprocess and asserted on exit code + output. Sourced by
#               tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

GENPW="$REPO_ROOT/src/scripts/generate-password.sh"

# Output layout (see the script's Execution section):
#   line 1: "Script ... starting..."
#   line 2: (blank)
#   line 3: the generated password
# password() extracts line 3 from a run with the given args. Output goes through
# a temp file rather than a pipe: the script can leave a `tr < /dev/urandom`
# reader holding the pipe open, which would hang a `| sed` / $() reader on EOF.
password()
{
  local tmp out
  tmp="$(mktemp)"
  bash "$GENPW" "$@" > "$tmp" 2>/dev/null
  out="$(sed -n '3p' "$tmp")"
  rm -f "$tmp"
  echo "$out"
}

# --- Help / argument parsing --------------------------------------------------

assert_exit 0 "-h prints help and exits 0" -- bash "$GENPW" -h
assert_contains "$ASSERT_OUTPUT" "Generate strong and secure password" \
  "-h output describes the script"

assert_exit 1 "-l with no value exits 1" -- bash "$GENPW" -l
assert_exit 1 "unknown argument exits 1" -- bash "$GENPW" --bogus

# --- Length validation --------------------------------------------------------

assert_exit 1 "non-integer length exits 1" -- bash "$GENPW" -l abc
assert_contains "$ASSERT_OUTPUT" "positive integer" \
  "non-integer length explains the integer requirement"

assert_exit 1 "length below minimum (7) exits 1" -- bash "$GENPW" -l 7
assert_contains "$ASSERT_OUTPUT" "greater than or equal to 8" \
  "below-minimum length explains the minimum"

assert_exit 1 "length not divisible by 4 (10) exits 1" -- bash "$GENPW" -l 10
assert_contains "$ASSERT_OUTPUT" "divisible by 4" \
  "indivisible length explains the divisibility rule"

# --- Successful generation ----------------------------------------------------

assert_exit 0 "valid length exits 0" -- bash "$GENPW" -l 16

PW_DEFAULT="$(password)"
assert_eq 20 "${#PW_DEFAULT}" "default password length is 20"

PW16="$(password -l 16)"
assert_eq 16 "${#PW16}" "-l 16 produces a 16-character password"

PW_LONG="$(password --length 32)"
assert_eq 32 "${#PW_LONG}" "--length 32 produces a 32-character password"

# With length 20 each of the 4 chunks is 5 chars, so every class is present.
assert_match "$PW_DEFAULT" "[a-z]"   "password contains a lowercase letter"
assert_match "$PW_DEFAULT" "[A-Z]"   "password contains an uppercase letter"
assert_match "$PW_DEFAULT" "[0-9]"   "password contains a digit"
assert_match "$PW_DEFAULT" "[]!#\$%&()+,.:=?@_{|}~-]" \
  "password contains a punctuation character"

################################################################################

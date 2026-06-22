################################################################################
# Library     : tests/lib/assert.sh
# Description : Minimal zero-dependency assertion helpers for the pure-bash test
#               harness. Sourced by tests/run.sh before each test file. Tracks
#               pass/fail counts in TESTS_RUN / TESTS_FAILED and prints a
#               per-assertion ✓/✗ line. No external test framework required.
# Parameters  : /
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Counters are intentionally global so every sourced test file accumulates into
# the same totals that run.sh reports at the end.
TESTS_RUN=0
TESTS_FAILED=0

# Resolve the repository root so test files can reference scripts by a stable
# path regardless of the caller's working directory.
TESTS_DIR="$(readlink -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/..")"
REPO_ROOT="$(dirname "$TESTS_DIR")"

_pass()
{
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "  \e[32m✓\e[0m $1"
}

_fail()
{
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  \e[31m✗\e[0m $1"
  [ -n "${2:-}" ] && echo -e "      $2"
}

################################################################################
# Function    : assert_eq
# Description : Passes when expected equals actual (string compare)
# Parameters  : expected actual message
################################################################################

assert_eq()
{
  if [ "$1" = "$2" ]
  then
    _pass "$3"
  else
    _fail "$3" "expected [$1] got [$2]"
  fi
}

################################################################################
# Function    : assert_contains
# Description : Passes when haystack contains needle as a substring
# Parameters  : haystack needle message
################################################################################

assert_contains()
{
  if [[ "$1" == *"$2"* ]]
  then
    _pass "$3"
  else
    _fail "$3" "[$1] does not contain [$2]"
  fi
}

################################################################################
# Function    : assert_match
# Description : Passes when value matches the given POSIX/ERE bash regex
# Parameters  : value regex message
################################################################################

assert_match()
{
  if [[ "$1" =~ $2 ]]
  then
    _pass "$3"
  else
    _fail "$3" "[$1] does not match /$2/"
  fi
}

################################################################################
# Function    : assert_exit
# Description : Runs a command, asserts its exit code. Command output is
#               captured into the global ASSERT_OUTPUT for follow-up checks.
# Parameters  : expected-code message -- command [args...]
################################################################################

assert_exit()
{
  local expected="$1" message="$2"
  shift 2
  [ "${1:-}" = "--" ] && shift
  # Capture via a temp file rather than $("$@") on purpose: some scripts spawn a
  # long-lived `tr < /dev/urandom` reader that can keep a pipe write-end open and
  # make command-substitution block on EOF. A file sink makes the wait depend
  # only on the direct child exiting.
  local actual tmp
  tmp="$(mktemp)"
  "$@" > "$tmp" 2>&1
  actual=$?
  ASSERT_OUTPUT="$(cat "$tmp")"
  rm -f "$tmp"
  if [ "$actual" -eq "$expected" ]
  then
    _pass "$message"
  else
    _fail "$message" "expected exit $expected got $actual"
  fi
}

################################################################################

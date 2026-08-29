################################################################################
# Test file   : tests/scripts/test_my_scripts.sh
# Description : Behavioural tests for src/scripts/my-scripts.sh. The script runs
#               Main on source (Execution section), so it is driven as a
#               subprocess and asserted on exit code + captured output. The
#               python_scripts side runs against a HERMETIC temp repo passed
#               through MY_SCRIPTS_PYTHON_REPO_PATH, so the developer's real
#               sibling repo is never a test input; the one case that exercises
#               the default path scrubs the ambient variable with env -u.
#               Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

MYS="$REPO_ROOT/src/scripts/my-scripts.sh"

# mys(): run the script with MY_SCRIPTS_PYTHON_REPO_PATH pinned to the given
# path, so no assertion depends on the developer's real python_scripts repo.
mys()
{
  local repo="$1"
  shift
  MY_SCRIPTS_PYTHON_REPO_PATH="$repo" bash "$MYS" "$@"
}

# mys_fixture(): a minimal python_scripts repo - a pyproject.toml carrying one
# [project.scripts] entry (plus tables on either side, so the table boundaries
# are exercised) and the module it points at, with a two-line docstring whose
# FIRST line is the expected description.
mys_fixture()
{
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/scripts"
  {
    printf '[project]\n'
    printf 'name = "fixture"\n\n'
    printf '[project.scripts]\n'
    printf 'fixture-command = "scripts.fixture_module:main"\n\n'
    printf '[tool.black]\n'
    printf 'line-length = 88\n'
  } > "$root/pyproject.toml"
  {
    printf '#!/usr/bin/env python3\n'
    printf '"""Fixture module: first docstring line.\n\n'
    printf 'Second line, which must never be listed.\n'
    printf '"""\n'
  } > "$root/scripts/fixture_module.py"
  echo "$root"
}

MYS_PY="$(mys_fixture)"
MYS_MISSING="$(mktemp -d)/absent"

# --- Help / argument parsing --------------------------------------------------

assert_exit 0 "-h prints help and exits 0" -- bash "$MYS" -h
assert_contains "$ASSERT_OUTPUT" \
  "List the custom commands provided by the shell-scripts" \
  "-h output describes the script"
assert_contains "$ASSERT_OUTPUT" "-f, --filter" "-h output documents --filter"
assert_contains "$ASSERT_OUTPUT" "MY_SCRIPTS_PYTHON_REPO_PATH" \
  "-h output documents the python repo environment variable"
assert_contains "$ASSERT_OUTPUT" "NOT a .env key" \
  "-h states the variable is not a .env key"

assert_exit 1 "unknown argument exits 1" -- bash "$MYS" --bogus
assert_contains "$ASSERT_OUTPUT" "Unknown argument" \
  "unknown argument is reported"

assert_exit 1 "-f with no value exits 1" -- bash "$MYS" -f
assert_contains "$ASSERT_OUTPUT" "requires a value" \
  "valueless -f reports the standard message"
assert_exit 1 "--filter with no value exits 1" -- bash "$MYS" --filter

# --- Default listing ----------------------------------------------------------

assert_exit 0 "a plain run exits 0" -- mys "$MYS_PY"
assert_contains "$ASSERT_OUTPUT" "shell-scripts (" \
  "plain run renders the shell-scripts section heading"
assert_match "$ASSERT_OUTPUT" \
  'generate-password[[:space:]]+\[(not )?on PATH\]' \
  "a known shell command is listed with a PATH marker"
assert_contains "$ASSERT_OUTPUT" "my-scripts" "the script lists itself"
assert_contains "$ASSERT_OUTPUT" "Backup documents on Linux machine" \
  "each entry carries its header Description line"

if [[ "$ASSERT_OUTPUT" == *"gen-docs"* ]]
then
  _fail "gen-docs is never listed" "output mentions gen-docs"
else
  _pass "gen-docs is never listed"
fi

# Both markers are ASCII text, never a symbol.
assert_match "$ASSERT_OUTPUT" '\[(not )?on PATH\]' \
  "PATH markers render as [on PATH] / [not on PATH]"

# --- python_scripts section (hermetic fixture) --------------------------------

assert_exit 0 "run against the python fixture exits 0" -- mys "$MYS_PY"
assert_contains "$ASSERT_OUTPUT" "python_scripts ($MYS_PY)" \
  "python section heading names the resolved repo path"
assert_contains "$ASSERT_OUTPUT" "fixture-command" \
  "the [project.scripts] entry point is listed"
assert_contains "$ASSERT_OUTPUT" "Fixture module: first docstring line." \
  "the module docstring's first line is the description"

if [[ "$ASSERT_OUTPUT" == *"Second line, which must never be listed."* ]]
then
  _fail "only the first docstring line is used" "a later docstring line leaked"
else
  _pass "only the first docstring line is used"
fi

# --- python_scripts degradation -----------------------------------------------

assert_exit 0 "a missing python repo still exits 0" -- mys "$MYS_MISSING"
assert_contains "$ASSERT_OUTPUT" "No readable pyproject.toml" \
  "a missing python repo warns once"
assert_contains "$ASSERT_OUTPUT" "MY_SCRIPTS_PYTHON_REPO_PATH" \
  "the warning names the environment variable"
assert_contains "$ASSERT_OUTPUT" "$MYS_MISSING" \
  "the warning names the resolved path"

if [[ "$ASSERT_OUTPUT" == *"python_scripts ($MYS_MISSING)"* ]]
then
  _fail "a missing python repo omits the section" "the section was rendered"
else
  _pass "a missing python repo omits the section"
fi

# A pyproject.toml without a [project.scripts] table degrades the same way.
MYS_NO_TABLE="$(mktemp -d)"
printf '[project]\nname = "x"\n' > "$MYS_NO_TABLE/pyproject.toml"
assert_exit 0 "a pyproject without [project.scripts] still exits 0" -- \
  mys "$MYS_NO_TABLE"
assert_contains "$ASSERT_OUTPUT" "No [project.scripts] entries found" \
  "an absent [project.scripts] table warns once"

# The DEFAULT path (no variable in the environment) must not break the run.
assert_exit 0 "run with the ambient variable scrubbed exits 0" -- \
  env -u MY_SCRIPTS_PYTHON_REPO_PATH bash "$MYS"
assert_contains "$ASSERT_OUTPUT" "shell-scripts (" \
  "the shell-scripts section renders on the default python path"

# --- Filtering ----------------------------------------------------------------

assert_exit 0 "-f narrows the listing" -- mys "$MYS_PY" -f git
assert_contains "$ASSERT_OUTPUT" "git-copy" "-f git keeps the matching command"

if [[ "$ASSERT_OUTPUT" == *"generate-password"* ]]
then
  _fail "-f git drops non-matching commands" "generate-password still listed"
else
  _pass "-f git drops non-matching commands"
fi

assert_exit 0 "--filter is case-insensitive" -- mys "$MYS_PY" --filter GIT
assert_contains "$ASSERT_OUTPUT" "git-copy" \
  "--filter GIT matches git-copy case-insensitively"

# The filter matches the NAME only, never the description.
assert_exit 0 "filter matches names only" -- mys "$MYS_PY" -f documents

if [[ "$ASSERT_OUTPUT" == *"backup "* ]]
then
  _fail "a description-only word matches nothing" "backup was listed"
else
  _pass "a description-only word matches nothing"
fi

assert_exit 0 "a non-matching filter exits 0" -- mys "$MYS_PY" -f zzz
assert_contains "$ASSERT_OUTPUT" "No command name matched the filter: zzz" \
  "a non-matching filter warns"

rm -rf "$MYS_PY" "$MYS_NO_TABLE" "$(dirname "$MYS_MISSING")"
unset MYS MYS_PY MYS_MISSING MYS_NO_TABLE

################################################################################

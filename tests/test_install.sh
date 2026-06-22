################################################################################
# Test file   : tests/test_install.sh
# Description : Tests for install.sh / uninstall.sh: the bare-name -> command
#               mapping and 9-script count, the -h self-test (catches an
#               unset-SCRIPT_NAME abort from a misordered common.sh source),
#               install into a temp prefix with symlink-target assertions, an
#               EXECUTABLE bare-path invocation (the assertion that catches the
#               exec-bit/resolution bug), idempotent re-run, uninstall cleanup,
#               and a completion drift guard. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

INSTALL="$REPO_ROOT/install.sh"
UNINSTALL="$REPO_ROOT/uninstall.sh"
SCRIPTS_DIR="$REPO_ROOT/src/scripts"
COMPLETION_FILE="$REPO_ROOT/src/completion/shell-scripts.bash"

# gen-docs.sh is a maintainer tool and is intentionally NOT installed; the
# user-facing set is every src/scripts/*.sh except gen-docs.sh.
EXPECTED_NAMES=(
  "backup"
  "dev-setup"
  "generate-password"
  "git-copy"
  "hash-filenames"
  "php-switch"
  "restore-vscode-folder"
  "splice-images"
  "splice-videos"
)

# --- Name mapping + count -----------------------------------------------------

# Build the actual user-facing name list from the glob, excluding gen-docs.sh.
ACTUAL_NAMES=()
for _f in "$SCRIPTS_DIR"/*.sh
do
  _base="$(basename "$_f")"
  [ "$_base" = "gen-docs.sh" ] && continue
  ACTUAL_NAMES+=("$(basename "$_f" .sh)")
done
unset _f _base

assert_eq "9" "${#ACTUAL_NAMES[@]}" \
  "exactly 9 user-facing scripts in src/scripts/ (gen-docs.sh excluded)"

assert_eq "${EXPECTED_NAMES[*]}" "${ACTUAL_NAMES[*]}" \
  "src/scripts/*.sh maps to the expected 9 bare command names"

# basename "<file>" .sh strips the .sh extension for every expected mapping.
for _name in "${EXPECTED_NAMES[@]}"
do
  assert_eq "$_name" "$(basename "$SCRIPTS_DIR/$_name.sh" .sh)" \
    "basename $_name.sh .sh maps to $_name"
done
unset _name

# --- -h self-test (unset-SCRIPT_NAME guard) -----------------------------------

assert_exit 0 "install.sh -h exits 0" -- bash "$INSTALL" -h
assert_contains "$ASSERT_OUTPUT" "Running install.sh" \
  "install.sh -h prints usage"

assert_exit 0 "uninstall.sh -h exits 0" -- bash "$UNINSTALL" -h
assert_contains "$ASSERT_OUTPUT" "Running uninstall.sh" \
  "uninstall.sh -h prints usage"

# --- Install / idempotency / runtime ------------------------------------------

TMP_PREFIX="$(mktemp -d)"

assert_exit 0 "install.sh installs into a temp prefix" -- \
  bash "$INSTALL" --prefix "$TMP_PREFIX"

# All 9 commands exist as symlinks resolving into src/scripts/.
_src_real="$(readlink -f "$SCRIPTS_DIR")"
for _name in "${EXPECTED_NAMES[@]}"
do
  _target="$TMP_PREFIX/$_name"
  if [ -L "$_target" ]
  then
    _pass "$_name is a symlink in the prefix"
  else
    _fail "$_name is a symlink in the prefix" "[$_target] is not a symlink"
  fi
  assert_eq "$_src_real" "$(dirname "$(readlink -f "$_target")")" \
    "$_name resolves into src/scripts/"
done
unset _name _target _src_real

# The load-bearing assertion: invoke a command by its installed path AS AN
# EXECUTABLE (NOT via bash) to catch the exec-bit/resolution failure.
assert_exit 0 "bare-name generate-password runs as an executable" -- \
  "$TMP_PREFIX/generate-password" -l 16
assert_match "$ASSERT_OUTPUT" '[^[:space:]]{16}' \
  "bare-name generate-password emits a 16-char password line"

# Re-run install: idempotent, still exactly 9 symlinks, exit 0.
assert_exit 0 "re-running install.sh is idempotent" -- \
  bash "$INSTALL" --prefix "$TMP_PREFIX"

_link_count=0
for _name in "${EXPECTED_NAMES[@]}"
do
  [ -L "$TMP_PREFIX/$_name" ] && _link_count=$((_link_count + 1))
done
assert_eq "9" "$_link_count" "still exactly 9 symlinks after a re-run"
unset _name _link_count

# --- Uninstall cleanup --------------------------------------------------------

# A decoy regular file at a command name must survive uninstall.
touch "$TMP_PREFIX/backup-decoy"

assert_exit 0 "uninstall.sh removes the installed links" -- \
  bash "$UNINSTALL" --prefix "$TMP_PREFIX"

_remaining=0
for _name in "${EXPECTED_NAMES[@]}"
do
  [ -e "$TMP_PREFIX/$_name" ] && _remaining=$((_remaining + 1))
done
assert_eq "0" "$_remaining" "all 9 symlinks removed after uninstall"
unset _name _remaining

if [ -e "$TMP_PREFIX/backup-decoy" ]
then
  _pass "uninstall leaves unrelated files untouched"
else
  _fail "uninstall leaves unrelated files untouched" "decoy was removed"
fi

rm -rf "$TMP_PREFIX"
unset TMP_PREFIX

# --- Completion drift guard ---------------------------------------------------

# The bash completion file must list exactly the 9 user-facing command names.
# Extract the names from the _ssc_names assignment lines (strip the assignment
# scaffolding and the self-referential $_ssc_names token).
COMPLETION_LIST="$(
  awk '/^_ssc_names=/{
    gsub(/^_ssc_names="/, "");
    gsub(/"$/, "");
    gsub(/\$_ssc_names/, "");
    print
  }' "$COMPLETION_FILE" | tr "\n" " " | tr -s " "
)"
# Normalize to a sorted space-joined list for comparison.
COMPLETION_SORTED="$(printf '%s\n' $COMPLETION_LIST | sort | tr "\n" " " | \
  sed 's/ *$//')"
EXPECTED_SORTED="$(printf '%s\n' "${EXPECTED_NAMES[@]}" | sort | \
  tr "\n" " " | sed 's/ *$//')"

assert_eq "$EXPECTED_SORTED" "$COMPLETION_SORTED" \
  "completion file lists exactly the 9 user-facing command names"

unset COMPLETION_LIST COMPLETION_SORTED EXPECTED_SORTED

################################################################################

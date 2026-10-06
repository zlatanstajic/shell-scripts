################################################################################
# Test file   : tests/test_install.sh
# Description : Tests for install.sh / uninstall.sh: the bare-name -> command
#               mapping and 13-script count, the -h self-test (catches an
#               unset-SCRIPT_NAME abort from a misordered common.sh source),
#               install into a temp prefix with symlink-target assertions, an
#               EXECUTABLE bare-path invocation (the assertion that catches the
#               exec-bit/resolution bug), idempotent re-run, uninstall cleanup,
#               and uninstall's removal of a legacy completion file. Every
#               install/uninstall run gets a temp HOME and a no-op xclip, so
#               the suite never touches the developer's home or clipboard.
#               Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

INSTALL="$REPO_ROOT/install.sh"
UNINSTALL="$REPO_ROOT/uninstall.sh"
SCRIPTS_DIR="$REPO_ROOT/src/scripts"

# gen-docs.sh is a maintainer tool and is intentionally NOT installed; the
# user-facing set is every src/scripts/*.sh except gen-docs.sh.
EXPECTED_NAMES=(
  "backup"
  "decrypt-env-files"
  "dev-setup"
  "generate-password"
  "git-copy"
  "hash-filenames"
  "my-scripts"
  "php-switch"
  "restore-vscode-folder"
  "shutdown-guard"
  "splice-images"
  "splice-videos"
  "tampermonkey-install"
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

assert_eq "13" "${#ACTUAL_NAMES[@]}" \
  "exactly 13 user-facing scripts in src/scripts/ (gen-docs.sh excluded)"

assert_eq "${EXPECTED_NAMES[*]}" "${ACTUAL_NAMES[*]}" \
  "src/scripts/*.sh maps to the expected 13 bare command names"

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
TMP_HOME="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"
LEGACY_DIR="$TMP_HOME/.local/share/bash-completion/completions"

# A no-op xclip that drains stdin, so the bare-name generate-password run below
# cannot overwrite the developer's clipboard.
printf '#!/bin/sh\ncat > /dev/null\n' > "$STUB_DIR/xclip"
chmod +x "$STUB_DIR/xclip"

# sandboxed: run a command with HOME pointed at a temp dir, any ambient
# BASH_COMPLETION_USER_DIR scrubbed and the stub dir first on PATH, so no
# install/uninstall run can reach the developer's real home or clipboard.
sandboxed()
{
  env -u BASH_COMPLETION_USER_DIR HOME="$TMP_HOME" PATH="$STUB_DIR:$PATH" "$@"
}

assert_exit 0 "install.sh installs into a temp prefix" -- \
  sandboxed bash "$INSTALL" --prefix "$TMP_PREFIX"

# All 13 commands exist as symlinks resolving into src/scripts/.
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

# install.sh ships no bash completion (bash already completes command names
# from PATH), so it must not create the completion directory.
if [ -e "$LEGACY_DIR" ]
then
  _fail "install.sh writes no completion file" "[$LEGACY_DIR] was created"
else
  _pass "install.sh writes no completion file"
fi

# The load-bearing assertion: invoke a command by its installed path AS AN
# EXECUTABLE (NOT via bash) to catch the exec-bit/resolution failure.
assert_exit 0 "bare-name generate-password runs as an executable" -- \
  sandboxed "$TMP_PREFIX/generate-password" -l 16
assert_match "$ASSERT_OUTPUT" '[^[:space:]]{16}' \
  "bare-name generate-password emits a 16-char password line"

# Re-run install: idempotent, still exactly 13 symlinks, exit 0.
assert_exit 0 "re-running install.sh is idempotent" -- \
  sandboxed bash "$INSTALL" --prefix "$TMP_PREFIX"

_link_count=0
for _name in "${EXPECTED_NAMES[@]}"
do
  [ -L "$TMP_PREFIX/$_name" ] && _link_count=$((_link_count + 1))
done
assert_eq "13" "$_link_count" "still exactly 13 symlinks after a re-run"
unset _name _link_count

# --- Uninstall cleanup --------------------------------------------------------

# A decoy regular file at a command name must survive uninstall.
touch "$TMP_PREFIX/backup-decoy"

# A completion file an older install.sh copied carries the shipped header
# line; uninstall must remove it.
mkdir -p "$LEGACY_DIR"
printf '%s\n' "# File        : src/completion/shell-scripts.bash" \
  > "$LEGACY_DIR/shell-scripts.bash"

assert_exit 0 "uninstall.sh removes the installed links" -- \
  sandboxed bash "$UNINSTALL" --prefix "$TMP_PREFIX"

_remaining=0
for _name in "${EXPECTED_NAMES[@]}"
do
  [ -e "$TMP_PREFIX/$_name" ] && _remaining=$((_remaining + 1))
done
assert_eq "0" "$_remaining" "all 13 symlinks removed after uninstall"
unset _name _remaining

if [ -e "$TMP_PREFIX/backup-decoy" ]
then
  _pass "uninstall leaves unrelated files untouched"
else
  _fail "uninstall leaves unrelated files untouched" "decoy was removed"
fi

if [ -e "$LEGACY_DIR/shell-scripts.bash" ]
then
  _fail "uninstall removes a legacy completion file" "file still present"
else
  _pass "uninstall removes a legacy completion file"
fi

# A same-named file without that header is not ours and must survive.
printf 'complete -F _foreign foreign\n' > "$LEGACY_DIR/shell-scripts.bash"

assert_exit 0 "re-running uninstall.sh exits 0" -- \
  sandboxed bash "$UNINSTALL" --prefix "$TMP_PREFIX"

if [ -f "$LEGACY_DIR/shell-scripts.bash" ]
then
  _pass "uninstall leaves a foreign shell-scripts.bash untouched"
else
  _fail "uninstall leaves a foreign shell-scripts.bash untouched" \
    "foreign file was removed"
fi

rm -rf "$TMP_PREFIX" "$TMP_HOME" "$STUB_DIR"
unset TMP_PREFIX TMP_HOME STUB_DIR LEGACY_DIR

################################################################################

################################################################################
# Test file   : tests/scripts/test_backup.sh
# Description : Dry-run behaviour test for src/scripts/backup.sh. Uses a
#               copied-tree fixture with its own .env so PROJECT_ROOT resolves
#               to the fixture and the developer's gitignored repo .env is never
#               touched. Asserts a -n -y dry-run exits 0, prints "would" lines,
#               and leaves the backup destination empty. Sourced by tests/run.sh
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Hermetic fixture (do NOT stage the repo-root .env). PROJECT_ROOT resolves to
# $tmp via readlink (two levels up from src/scripts/), so the real .env is never
# read.
BK_TMP="$(mktemp -d)"
mkdir -p "$BK_TMP/src/scripts" "$BK_TMP/src/lib" "$BK_TMP/backup-dest" \
  "$BK_TMP/sys-src"
cp "$REPO_ROOT/src/scripts/backup.sh" "$BK_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$BK_TMP/src/lib/"
printf 'BACKUP_LOCATION=%q\nSYSTEM_DESTINATION_FOLDER_NAME=sys\nSYSTEM_SOURCE_PATHS=%q\n' \
  "$BK_TMP/backup-dest" "$BK_TMP/sys-src/file" > "$BK_TMP/.env"
: > "$BK_TMP/sys-src/file"

BK_SCRIPT="$BK_TMP/src/scripts/backup.sh"

assert_exit 0 "backup -n -y dry-run exits 0" -- \
  bash "$BK_SCRIPT" -n -y
assert_contains "$ASSERT_OUTPUT" "would" \
  "backup dry-run prints would lines"

# Destination must stay empty (no clear/create/copy actually happened).
assert_eq "" "$(find "$BK_TMP/backup-dest" -mindepth 1)" \
  "backup dry-run leaves the destination empty"

rm -rf "$BK_TMP"

################################################################################

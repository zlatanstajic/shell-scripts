################################################################################
# Test file   : tests/scripts/test_hash_filenames.sh
# Description : Dry-run behaviour test for src/scripts/hash-filenames.sh. Runs
#               the script as a subprocess against a temp fixture and asserts a
#               -n -y dry-run prints "would rename" lines, makes no filesystem
#               change, and writes no mapping file. A copied-tree fixture (with
#               its own .env) keeps the test independent of the developer's
#               gitignored repo .env. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Hermetic fixture: copy script + lib into a temp tree so PROJECT_ROOT (two
# levels up from src/scripts/) resolves to the fixture and our .env is used.
HF_TMP="$(mktemp -d)"
mkdir -p "$HF_TMP/src/scripts" "$HF_TMP/src/lib" "$HF_TMP/data"
cp "$REPO_ROOT/src/scripts/hash-filenames.sh" "$HF_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$HF_TMP/src/lib/"
printf 'HASH_FILENAMES_FILE_EXTENSIONS=jpg,png\n' > "$HF_TMP/.env"
: > "$HF_TMP/data/photo.jpg"
: > "$HF_TMP/data/image.png"
: > "$HF_TMP/data/ignore.txt"

HF_SCRIPT="$HF_TMP/src/scripts/hash-filenames.sh"

# Snapshot the data dir contents before the dry-run.
HF_BEFORE="$(cd "$HF_TMP/data" && find . | sort)"

assert_exit 0 "hash-filenames dry-run exits 0" -- \
  bash "$HF_SCRIPT" -d "$HF_TMP/data" -n -y
assert_contains "$ASSERT_OUTPUT" "would rename" \
  "hash-filenames dry-run prints would rename lines"

# Files unchanged: same listing, originals still present.
HF_AFTER="$(cd "$HF_TMP/data" && find . | sort)"
assert_eq "$HF_BEFORE" "$HF_AFTER" \
  "hash-filenames dry-run leaves the directory unchanged"
assert_eq "1" "$([ -f "$HF_TMP/data/photo.jpg" ] && echo 1 || echo 0)" \
  "hash-filenames dry-run keeps photo.jpg"
assert_eq "1" "$([ -f "$HF_TMP/data/image.png" ] && echo 1 || echo 0)" \
  "hash-filenames dry-run keeps image.png"
assert_eq "0" \
  "$([ -e "$HF_TMP/data/hash_filenames_mapping.txt" ] && echo 1 || echo 0)" \
  "hash-filenames dry-run writes no mapping file"

rm -rf "$HF_TMP"

################################################################################

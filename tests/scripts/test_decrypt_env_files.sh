################################################################################
# Test file   : tests/scripts/test_decrypt_env_files.sh
# Description : Behavioural tests for src/scripts/decrypt-env-files.sh, focused
#               on the -c/--clean remove-only mode. Uses a copied-tree fixture
#               with its own .env so PROJECT_ROOT (two levels up from
#               src/scripts/) resolves to the fixture and the developer's
#               gitignored repo .env is never sourced (copy, not symlink: the
#               script resolves itself with readlink -f). Asserts the argument
#               surface, the dry-run preview plus no-mutation snapshot, that only
#               the two names DoDecrypt writes are removed (decoys and .enc
#               originals survive), idempotent reruns, the missing-projects-tree
#               and missing-config paths, and openssl independence. Sourced by
#               tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

DEF_TMP="$(mktemp -d)"
mkdir -p "$DEF_TMP/src/scripts" "$DEF_TMP/src/lib" \
  "$DEF_TMP/backup/projects/project-a" "$DEF_TMP/backup/projects/project-b" \
  "$DEF_TMP/elsewhere"
cp "$REPO_ROOT/src/scripts/decrypt-env-files.sh" "$DEF_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$DEF_TMP/src/lib/"
printf 'BACKUP_LOCATION=%q\nPROJECTS_DESTINATION_FOLDER_NAME=projects\n' \
  "$DEF_TMP/backup" > "$DEF_TMP/.env"

DEF_SCRIPT="$DEF_TMP/src/scripts/decrypt-env-files.sh"
DEF_PROJECTS="$DEF_TMP/backup/projects"

# Targets (the exact image of DoDecrypt's ${src%.enc}.decrypted derivation).
: > "$DEF_PROJECTS/project-a/.env.decrypted"
: > "$DEF_PROJECTS/project-b/.env.rb.decrypted"
# Ciphertext originals (must never be touched).
: > "$DEF_PROJECTS/project-a/.env.enc"
: > "$DEF_PROJECTS/project-b/.env.rb.enc"
# Decoys: unrelated *.decrypted files inside the tree, plus one outside it.
: > "$DEF_PROJECTS/project-b/notes.decrypted"
: > "$DEF_PROJECTS/project-a/.env.other.decrypted"
: > "$DEF_PROJECTS/secrets.decrypted"
: > "$DEF_TMP/elsewhere/.env.decrypted"

# def_exists() prints 1/0 for use with assert_eq.
def_exists()
{
  [ -e "$1" ] && echo 1 || echo 0
}

# def_omits() prints 1 when the captured output does NOT mention the needle.
def_omits()
{
  [[ "$1" == *"$2"* ]] && echo 0 || echo 1
}

# --- Argument surface ---------------------------------------------------------

assert_exit 0 "decrypt-env-files -h exits 0" -- bash "$DEF_SCRIPT" -h
assert_contains "$ASSERT_OUTPUT" "--clean" \
  "-h documents the --clean flag"
assert_exit 1 "unknown argument exits 1" -- bash "$DEF_SCRIPT" --bogus

# --- Name pairing guard -------------------------------------------------------

# DoClean hardcodes its two -name predicates, mirroring DoDecrypt. Assert they
# stay the exact image of DoDecrypt's ${src%.enc}.decrypted derivation, so a
# change to one side cannot silently desynchronise the other.
DEF_ENC_NAMES="$(
  grep -oE -- "-name '\.env[a-z.]*\.enc'" "$DEF_SCRIPT" \
    | sed -e "s/-name //" -e "s/'//g" | sort
)"
DEF_DEC_NAMES="$(
  grep -oE -- "-name '\.env[a-z.]*\.decrypted'" "$DEF_SCRIPT" \
    | sed -e "s/-name //" -e "s/'//g" | sort
)"
DEF_EXPECTED_NAMES=""
for DEF_NAME in $DEF_ENC_NAMES
do
  DEF_EXPECTED_NAMES+="${DEF_NAME%.enc}.decrypted"$'\n'
done
assert_eq "${DEF_EXPECTED_NAMES%$'\n'}" "$DEF_DEC_NAMES" \
  "clean predicates are the decrypt output names"

# --- Clean dry-run ------------------------------------------------------------

DEF_BEFORE="$(find "$DEF_TMP/backup" | sort)"

assert_exit 0 "clean dry-run exits 0" -- bash "$DEF_SCRIPT" -c -n -y
assert_contains "$ASSERT_OUTPUT" "would" \
  "clean dry-run prints would lines"
assert_contains "$ASSERT_OUTPUT" "project-a/.env.decrypted" \
  "clean dry-run previews .env.decrypted"
assert_contains "$ASSERT_OUTPUT" "project-b/.env.rb.decrypted" \
  "clean dry-run previews .env.rb.decrypted"
assert_eq "1" "$(def_omits "$ASSERT_OUTPUT" "notes.decrypted")" \
  "clean dry-run ignores notes.decrypted"
assert_eq "1" "$(def_omits "$ASSERT_OUTPUT" "secrets.decrypted")" \
  "clean dry-run ignores secrets.decrypted"
assert_eq "1" "$(def_omits "$ASSERT_OUTPUT" "other.decrypted")" \
  "clean dry-run ignores .env.other.decrypted"

assert_eq "$DEF_BEFORE" "$(find "$DEF_TMP/backup" | sort)" \
  "clean dry-run leaves the tree unchanged"

# --- Real clean run -----------------------------------------------------------

assert_exit 0 "clean run exits 0" -- bash "$DEF_SCRIPT" -c -y
assert_eq "0" "$(def_exists "$DEF_PROJECTS/project-a/.env.decrypted")" \
  "clean run removes .env.decrypted"
assert_eq "0" "$(def_exists "$DEF_PROJECTS/project-b/.env.rb.decrypted")" \
  "clean run removes .env.rb.decrypted"
assert_eq "1" "$(def_exists "$DEF_PROJECTS/project-a/.env.enc")" \
  "clean run keeps .env.enc"
assert_eq "1" "$(def_exists "$DEF_PROJECTS/project-b/.env.rb.enc")" \
  "clean run keeps .env.rb.enc"
assert_eq "1" "$(def_exists "$DEF_PROJECTS/project-b/notes.decrypted")" \
  "clean run keeps notes.decrypted"
assert_eq "1" "$(def_exists "$DEF_PROJECTS/project-a/.env.other.decrypted")" \
  "clean run keeps .env.other.decrypted"
assert_eq "1" "$(def_exists "$DEF_PROJECTS/secrets.decrypted")" \
  "clean run keeps secrets.decrypted"
assert_eq "1" "$(def_exists "$DEF_TMP/elsewhere/.env.decrypted")" \
  "clean run keeps plaintext outside the projects tree"

# --- Idempotent rerun ---------------------------------------------------------

assert_exit 0 "clean rerun on a clean tree exits 0" -- bash "$DEF_SCRIPT" -c -y
assert_contains "$ASSERT_OUTPUT" "nothing to remove" \
  "clean rerun reports nothing to remove"

# --- openssl independence -----------------------------------------------------

# Restricted PATH holding only the externals the clean path needs; bash itself is
# invoked by absolute path. Extend the list if the clean path gains an external
# call. Degrades to the plain output assertion when a stub cannot be resolved.
DEF_STUB_BIN="$DEF_TMP/stub-bin"
mkdir -p "$DEF_STUB_BIN"
DEF_STUBS_OK=1
for DEF_NAME in basename dirname readlink find rm
do
  DEF_REAL="$(command -v "$DEF_NAME")" || DEF_STUBS_OK=0
  [ -n "${DEF_REAL:-}" ] || DEF_STUBS_OK=0
  [ "$DEF_STUBS_OK" -eq 1 ] && ln -sf "$DEF_REAL" "$DEF_STUB_BIN/$DEF_NAME"
done

if [ "$DEF_STUBS_OK" -eq 1 ]
then
  assert_exit 0 "clean run exits 0 without openssl on PATH" -- \
    env PATH="$DEF_STUB_BIN" "$BASH" "$DEF_SCRIPT" -c -y
else
  assert_exit 0 "clean run exits 0 (restricted PATH unavailable)" -- \
    bash "$DEF_SCRIPT" -c -y
fi
assert_eq "1" "$(def_omits "$ASSERT_OUTPUT" "openssl is required")" \
  "clean run never demands openssl"

# --- Missing projects tree ----------------------------------------------------

printf 'BACKUP_LOCATION=%q\nPROJECTS_DESTINATION_FOLDER_NAME=absent\n' \
  "$DEF_TMP/backup" > "$DEF_TMP/.env"
assert_exit 0 "clean run with a missing projects tree exits 0" -- \
  bash "$DEF_SCRIPT" -c -y
assert_contains "$ASSERT_OUTPUT" "nothing to remove" \
  "missing projects tree reports nothing to remove"

# --- Missing required configuration -------------------------------------------

DEF_TMP2="$(mktemp -d)"
mkdir -p "$DEF_TMP2/src/scripts" "$DEF_TMP2/src/lib"
cp "$REPO_ROOT/src/scripts/decrypt-env-files.sh" "$DEF_TMP2/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$DEF_TMP2/src/lib/"
printf 'PROJECTS_DESTINATION_FOLDER_NAME=projects\n' > "$DEF_TMP2/.env"

assert_exit 1 "clean run without BACKUP_LOCATION exits 1" -- \
  bash "$DEF_TMP2/src/scripts/decrypt-env-files.sh" -c -y

rm -rf "$DEF_TMP" "$DEF_TMP2"

################################################################################

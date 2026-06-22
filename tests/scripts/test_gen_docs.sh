################################################################################
# Test file   : tests/scripts/test_gen_docs.sh
# Description : Behavioural tests for src/scripts/gen-docs.sh. The generator
#               writes into $PROJECT_ROOT (two levels up from its own dir), so
#               every test runs against an isolated temp mirror of src/ + a temp
#               README.md + a temp docs/ tree — the committed docs are never
#               mutated. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

GENDOCS_SRC="$REPO_ROOT/src/scripts/gen-docs.sh"

EXPECTED_SCRIPTS=(
  "Backup"
  "Dev Setup"
  "Generate Password"
  "Git Copy"
  "Hash Filenames"
  "PHP Switch"
  "Restore VSCode Folder"
  "Splice Images"
  "Splice Videos"
)

# new_sandbox: mirror src/ (scripts + lib travel together so `source` resolves),
# plus a README.md carrying exactly one BEGIN/END marker pair and an empty docs/
# tree. Echoes the sandbox root; the caller runs $root/src/scripts/gen-docs.sh
# so PROJECT_ROOT resolves to $root and all writes stay inside it.
new_sandbox()
{
  local root
  root="$(mktemp -d)"
  cp -R "$REPO_ROOT/src" "$root/src"
  mkdir -p "$root/docs"
  {
    printf '# Sandbox README\n\n'
    printf '## List of Available Scripts\n\n'
    printf 'Intro line.\n\n'
    printf '<!-- BEGIN GENERATED: command-reference -->\n'
    printf '<!-- END GENERATED: command-reference -->\n\n'
    printf '<details><summary>curated</summary>untouched</details>\n'
  } > "$root/README.md"
  echo "$root"
}

# run_gen: run the sandbox generator with the given args, capture combined
# output into a temp file (not a pipe), echo the file path; caller reads it.
run_gen()
{
  local root="$1"; shift
  local tmp
  tmp="$(mktemp)"
  bash "$root/src/scripts/gen-docs.sh" "$@" > "$tmp" 2>&1
  echo "$tmp"
}

# --- Help / argument parsing --------------------------------------------------

assert_exit 0 "-h prints help and exits 0" -- bash "$GENDOCS_SRC" -h
assert_contains "$ASSERT_OUTPUT" "Generate the flags/usage reference" \
  "-h output describes the generator"
assert_contains "$ASSERT_OUTPUT" "--check" "-h output mentions --check mode"

assert_exit 1 "unknown argument exits 1" -- bash "$GENDOCS_SRC" --bogus
assert_contains "$ASSERT_OUTPUT" "Unknown argument" \
  "unknown argument is reported"

# --- Write-then-check round-trip ----------------------------------------------

SANDBOX="$(new_sandbox)"
assert_exit 0 "write mode exits 0" -- \
  bash "$SANDBOX/src/scripts/gen-docs.sh"
assert_eq 1 \
  "$([ -f "$SANDBOX/docs/_includes/command-reference.md" ] && echo 1 || echo 0)" \
  "write mode creates docs/_includes/command-reference.md"

assert_exit 0 "check passes immediately after a write" -- \
  bash "$SANDBOX/src/scripts/gen-docs.sh" --check

# Idempotency: a second write yields a byte-identical include.
cp "$SANDBOX/docs/_includes/command-reference.md" "$SANDBOX/include.first"
OUT="$(run_gen "$SANDBOX")"; rm -f "$OUT"
assert_exit 0 "second write keeps the include byte-identical" -- \
  diff "$SANDBOX/include.first" "$SANDBOX/docs/_includes/command-reference.md"

# --- Stale detection ----------------------------------------------------------

printf '\nSTALE\n' >> "$SANDBOX/docs/_includes/command-reference.md"
assert_exit 1 "corrupted include makes --check exit non-zero" -- \
  bash "$SANDBOX/src/scripts/gen-docs.sh" --check
assert_contains "$ASSERT_OUTPUT" "command-reference.md" \
  "--check names the stale include file"
# regenerate to clean the sandbox
OUT="$(run_gen "$SANDBOX")"; rm -f "$OUT"

# Marker guard: a README missing the markers ends with an error.
grep -v 'GENERATED: command-reference' "$SANDBOX/README.md" \
  > "$SANDBOX/README.nomarkers"
mv "$SANDBOX/README.nomarkers" "$SANDBOX/README.md"
assert_exit 1 "missing markers in README makes write exit non-zero" -- \
  bash "$SANDBOX/src/scripts/gen-docs.sh"
assert_contains "$ASSERT_OUTPUT" "exactly one BEGIN and one END" \
  "missing-marker error explains the marker contract"

# --- Rendered content invariants (against a fresh sandbox) --------------------

SANDBOX="$(new_sandbox)"
OUT="$(run_gen "$SANDBOX")"; rm -f "$OUT"
REF="$SANDBOX/docs/_includes/command-reference.md"
REF_BODY="$(cat "$REF")"

assert_eq 9 "$(grep -cF '<summary>' "$REF")" \
  "rendered reference has exactly nine collapsible sections"
for name in "${EXPECTED_SCRIPTS[@]}"
do
  assert_contains "$REF_BODY" "<summary><strong>$name</strong>" \
    "rendered reference includes section: $name"
done

assert_eq 0 "$(grep -c 'gen-docs' "$REF")" \
  "rendered reference never mentions gen-docs"
assert_eq 0 "$(grep -cE '/home/|^/' "$REF")" \
  "no rendered line carries an absolute filesystem path"
assert_eq 0 "$(grep -cE 'Script .* (starting\.\.\.|finishing OK)' "$REF")" \
  "no rendered line carries a wrapper banner"
assert_eq 0 "$(grep -cE ' +$' "$REF")" \
  "no rendered line carries trailing whitespace"

# Curated content outside the markers is preserved verbatim.
assert_eq 1 "$(grep -c 'curated' "$SANDBOX/README.md")" \
  "curated <details> outside the markers is untouched"

# --- Determinism: php-switch sanitized output is host-independent --------------

# Stub update-alternatives so php-switch -h behaves as on a host with no PHP
# alternatives; the sanitized section must be byte-identical to the real-host
# render (region delete + path rewrite erase the host-dependent difference).
extract_php()
{
  awk '
    /<summary><strong>PHP Switch<\/strong>/ { f=1 }
    f { print }
    f && /^<\/details>$/ { exit }
  ' "$1"
}

SANDBOX="$(new_sandbox)"
OUT="$(run_gen "$SANDBOX")"; rm -f "$OUT"
extract_php "$SANDBOX/docs/_includes/command-reference.md" > "$SANDBOX/php.with"

STUB_DIR="$(mktemp -d)"
printf '#!/bin/bash\nexit 1\n' > "$STUB_DIR/update-alternatives"
chmod +x "$STUB_DIR/update-alternatives"
PATH="$STUB_DIR:$PATH" bash "$SANDBOX/src/scripts/gen-docs.sh" \
  > /dev/null 2>&1
extract_php "$SANDBOX/docs/_includes/command-reference.md" \
  > "$SANDBOX/php.without"
rm -rf "$STUB_DIR"

assert_exit 0 \
  "php-switch sanitized output is identical with/without update-alternatives" -- \
  diff "$SANDBOX/php.with" "$SANDBOX/php.without"

################################################################################

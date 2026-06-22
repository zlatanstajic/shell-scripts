---
layout: default
title: Testing
nav_order: 3
---

# Testing

The repository ships a zero-dependency, pure-bash test harness under `tests/` —
no `bats`, `shunit2`, or any other framework required.

```bash
# Run the whole suite
bash tests/run.sh

# Run a single test file
bash tests/run.sh tests/test_common.sh
```

Layout: shared-library tests live at the `tests/` root; per-script tests live
under `tests/scripts/`. The runner discovers every `test_*.sh` under `tests/`
recursively. It prints a ✓/✗ line per assertion and exits non-zero if any
assertion fails, so it doubles as a CI gate.

- `tests/run.sh` — discovers and sources every `tests/test_*.sh` file, then
  prints a summary.
- `tests/lib/assert.sh` — assertion helpers (`assert_eq`, `assert_contains`,
  `assert_match`, `assert_exit`) plus shared `TESTS_RUN`/`TESTS_FAILED` counters
  and a resolved `REPO_ROOT`.
- `tests/test_common.sh` — unit tests for the shared library
  `src/lib/common.sh` (`UrlEncode`, the `Log*`/`EchoBold` helpers, and the
  `End`/`MissingRequiredArguments` exit codes — the last run in subshells
  because they call `exit`).
- `tests/scripts/test_generate_password.sh` — behavioural tests driving
  `generate-password.sh` as a subprocess (help text, argument and length
  validation, output length, character-class coverage).

## Adding a test

Drop a `tests/scripts/test_<name>.sh` file: use `$REPO_ROOT` for paths, run
`exit`-calling code through `assert_exit` in a subshell, and assert whole-script
behaviour by running it with `bash "$SCRIPT"` and checking the exit code plus
the captured `$ASSERT_OUTPUT`.

Capture script output via a temp file rather than a pipe — `generate-password.sh`
can leave a `tr < /dev/urandom` reader holding a pipe open, which hangs
`| sed` / `$()` readers on EOF.

## Continuous integration

Every push to `master` and every pull request runs the test suite (and an
advisory `shellcheck` lint) via GitHub Actions — see
`.github/workflows/ci.yml`.

### Pre-commit hook

Run the same checks locally before each commit with a native git hook (no
`husky`, `npm`, or other dependency). The hook lives at `.githooks/pre-commit`:
it runs the test suite as a hard gate and `shellcheck` as an advisory step,
mirroring CI so failures surface before you push.

Git does not enable repository hooks automatically on clone — enable them once
per clone:

```bash
git config core.hooksPath .githooks
```

A failing test aborts the commit; a missing `shellcheck` is skipped. Bypass for
a single commit with:

```bash
git commit --no-verify
```

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
- `tests/test_install.sh` — tests for `install.sh` and `uninstall.sh`,
  including the assertion that the user-facing command set and
  `src/completion/shell-scripts.bash` stay in step.
- `tests/scripts/` — behavioural tests driving one script each as a
  subprocess. Covered today: `backup`, `decrypt-env-files`, `gen-docs`,
  `generate-password`, `hash-filenames`, `my-scripts`, `shutdown-guard`,
  `splice-images`, `splice-videos`, `tampermonkey-install`. Not yet covered:
  `dev-setup`, `git-copy`, `php-switch`, `restore-vscode-folder`.

## Adding a test

Drop a `tests/scripts/test_<name>.sh` file: use `$REPO_ROOT` for paths, run
`exit`-calling code through `assert_exit` in a subshell, and assert whole-script
behaviour by running it with `bash "$SCRIPT"` and checking the exit code plus
the captured `$ASSERT_OUTPUT`.

Capture script output via a temp file rather than a pipe — `generate-password.sh`
can leave a `tr < /dev/urandom` reader holding a pipe open, which hangs
`| sed` / `$()` readers on EOF.

## Continuous integration

Every push to `master` and every pull request runs three jobs via GitHub
Actions — see `.github/workflows/ci.yml`. **All three are hard gates**; a
failure in any of them fails the build.

| Job | Command |
|-----|---------|
| Test suite | `bash tests/run.sh` |
| Docs reference | `bash src/scripts/gen-docs.sh --check` |
| ShellCheck | `shellcheck src/scripts/*.sh src/lib/common.sh install.sh uninstall.sh` |

The `shellcheck` version is pinned in the workflow (and its download checksum
verified), so a refreshed runner image cannot introduce new findings and break
`master` without a change in this repository. The workflow declares
`permissions: contents: read` and cancels superseded runs for the same ref.

### Pre-commit hook

Run the same three checks locally before each commit with a native git hook
(no `husky`, `npm`, or other dependency). The hook lives at
`.githooks/pre-commit`, so failures surface before you push.

**Enforcement differs from CI on purpose.** In CI all three checks are hard
gates. In the hook only the test suite blocks a commit; the docs-reference
check and `shellcheck` warn and let the commit through. A local hook must not
block you because of your own `.env` (`gen-docs.sh` runs every script's `-h`,
which sources it) or because `shellcheck` is missing or a different version.
CI is the enforcement boundary; the hook is the fast heads-up.

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

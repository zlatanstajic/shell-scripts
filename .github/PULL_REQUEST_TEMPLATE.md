## What changed

<!-- What this PR does, and why. Link the issue: Closes #123 -->

## Checklist

<!-- Tick what applies. Delete rows that do not. -->

- [ ] Branched off `master` as `issues/<num>-short-description`.
- [ ] Edited scripts in `src/` only — never a copy under `deploy/`.
- [ ] Ran the affected script with `-h` and through a normal run.

### The three checks CI enforces (all hard gates)

- [ ] `bash tests/run.sh`
- [ ] `bash src/scripts/gen-docs.sh --check`
- [ ] `shellcheck src/scripts/*.sh src/lib/common.sh install.sh uninstall.sh`

### If you changed a script's flags or usage

- [ ] Edited that script's `Help()` / `GetArguments`, then ran
      `bash src/scripts/gen-docs.sh` and committed both regenerated outputs.
- [ ] Did **not** hand-edit the generated region in `README.md` or
      `docs/_includes/command-reference.md`.
- [ ] Updated the hand-maintained Parameters table in `docs/scripts/<name>.md`.

### If you added or removed a user-facing script

- [ ] Updated `src/completion/shell-scripts.bash` — `tests/test_install.sh`
      asserts the command list and the completion file stay in step.
- [ ] Added `docs/scripts/<name>.md` with a `nav_order`, and a row in
      `docs/scripts/index.md`.
- [ ] Updated the `## Commands` block in `CLAUDE.md`.
- [ ] Added a new `.env` key to `.env.example` if the script reads one.

### If you added a test

- [ ] It is hermetic: `mktemp -d` fixture, `env -u` for ambient config, and
      `-n -y` for anything that would otherwise mutate the host.

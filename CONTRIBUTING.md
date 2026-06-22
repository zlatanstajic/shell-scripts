# Contributing

Contributions are welcome. To propose a change:

1. **Fork and branch.** Fork the repository, then create a branch off `master` (e.g. `issues/12_short_description`).
2. **Edit in `src/`.** Make changes to the scripts in [`src/scripts/`](src/scripts/), not in any `deploy/` copy. Shared logic belongs in [`src/lib/common.sh`](src/lib/common.sh) — each script sources it via `source "$SCRIPT_DIR/../lib/common.sh"`, so reuse helpers there instead of duplicating code.
3. **Match conventions.** Follow the existing style: `-x/--xxxx` flag pairs, a `-h/--help` handler, and configuration read from a project-root `.env` (see [`.env.example`](.env.example)). Never commit a real `.env`.
4. **Regenerate the flags/usage reference.** The flags/usage reference (each script as a collapsible `<details>` block: title and source path in the `<summary>`, sanitized `-h` body inside) is generated — by [`gen-docs.sh`](src/scripts/gen-docs.sh) — into the marked region of [`README.md`](README.md) and into [`docs/_includes/command-reference.md`](docs/_includes/command-reference.md). The README per-script collapsible entries are generated; there is no hand-maintained `<details>` prose in the README. Everything else stays hand-maintained: the per-script Parameters tables under [`docs/scripts/`](docs/scripts/) and the `CLAUDE.md` notes. If you change a script's flags or usage, edit its `Help()`/`GetArguments`, then run `bash src/scripts/gen-docs.sh` and commit the regenerated region and include. `bash src/scripts/gen-docs.sh --check` reports drift; it runs as an advisory (non-blocking) step in CI and the pre-commit hook.
5. **Test before submitting.** Run the affected script(s) with `bash [script-name].sh -h` and through a normal run to confirm behavior on a Unix-like system.
6. **Open a pull request.** Push your branch and open a PR against `master` with a clear description of what changed and why. Open an issue first for larger changes.

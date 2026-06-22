---
layout: default
title: Install
nav_order: 5
---

# Install

Make every script a first-class command on your `PATH` with one command. From
the repository root:

```bash
bash install.sh
```

This symlinks each script in `src/scripts/` into `~/.local/bin` under its bare
name (the `.sh` is stripped), so `generate-password -l 20`,
`dev-setup -nu 1 -na "..."`, `backup`, and the rest run directly. The
maintainer-only `gen-docs.sh` is intentionally not installed.

## Options

- **Custom location:** `bash install.sh --prefix ~/bin` installs into `~/bin`
  instead of `~/.local/bin`. `install.sh -h` prints usage.
- **Idempotent:** re-running is safe — existing links are re-pointed (handy if
  you move the clone) and unrelated files in the prefix are never clobbered.
- **PATH warning:** if the prefix is not on your `PATH`, the installer prints
  (but does not fail on) the exact `export PATH="..."` line to add to your
  shell rc.
- **Completion:** a bash completion file for the command names is installed
  into your user bash-completion directory when bash completion is available;
  otherwise the installer prints a `source` line you can add to `~/.bashrc`.

## How resolution works

The installed symlinks resolve back into the clone — each script does
`SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"`, and `readlink -f`
dereferences the symlink to the real file in `src/scripts/`. As a result the
clone must stay where it is, and `src/lib/` must remain beside `src/scripts/`
(the scripts `source "$SCRIPT_DIR/../lib/common.sh"`). If you move the clone,
re-run `bash install.sh` to re-point the links.

## Uninstall

Remove the installed commands at any time:

```bash
bash uninstall.sh            # or: bash uninstall.sh --prefix ~/bin
```

`uninstall.sh` removes only the symlinks that point into this repo's
`src/scripts/`, leaving any other files in the prefix untouched.

## Requirements

Linux with GNU coreutils (the scripts rely on `readlink -f`, which BSD/macOS
`readlink` lacks). `bash`, `ln -s`, `mkdir -p`, and `chmod` are all part of the
base requirements already.

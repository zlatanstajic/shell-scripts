---
layout: default
title: My Scripts
parent: Scripts
nav_order: 14
---

# My Scripts

**File:** `src/scripts/my-scripts.sh` · List custom commands from
`shell-scripts` and `python_scripts`.

A **read-only** helper answering "what custom commands do I have, and can I run
them right now?". It writes nothing, creates nothing, and runs none of the
commands it lists — it only reads and prints.

Two repositories are listed, each discovered from its own declarations rather
than by scanning `PATH`:

- **shell-scripts** — every `src/scripts/*.sh` except the maintainer-only
  `gen-docs.sh` (the same exclusion [`install.sh`](https://github.com/zlatanstajic/shell-scripts/blob/master/install.sh)
  applies), listed under its bare command name. The description is that
  script's first `# Description :` header line, truncated to one line.
- **python_scripts** — the keys of the `[project.scripts]` table in the sibling
  repository's `pyproject.toml`, described by the first line of the target
  module's docstring.

Every entry carries a marker derived from `command -v <name>`: `[on PATH]` or
`[not on PATH]`.

```text
shell-scripts (/home/you/repos/shell-scripts)
  backup                   [on PATH]      Backup documents on Linux machine
  git-copy                 [on PATH]      Copy all differences between two git commits

python_scripts (/home/you/repos/python_scripts)
  cv-generator             [not on PATH]  CV generator: convert a Markdown CV into a single-page, ATS-friendly PDF.
```

`[not on PATH]` is normal, not a defect:

- python entry points are console scripts installed **inside the
  `python_scripts` virtualenv**, so they resolve only while that virtualenv is
  active;
- a shell command reads `[not on PATH]` until `bash install.sh` has linked it
  into `~/.local/bin`.

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-f`, `--filter` | no | none | List only commands whose **name** contains this text (case-insensitive substring; descriptions are never matched) |
| `-h`, `--help` | — | — | Print usage and exit |

A filter that matches nothing prints a warning and still exits `0`.

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `MY_SCRIPTS_PYTHON_REPO_PATH` | `$HOME/repos/python_scripts` | Path to the sibling `python_scripts` checkout |

This is an **exported environment variable, not a `.env` key**: `my-scripts.sh`
never sources `.env`, so setting it there has no effect. The `shell-scripts`
location is derived from the script's own path (`readlink -f "$0"` dereferences
the installed symlink) and is never configurable.

When the resolved path has no readable `pyproject.toml`, or that file has no
`[project.scripts]` table, the python section is skipped with a single warning
and the run still exits `0`.

## Usage

```bash
# Show help
bash my-scripts.sh -h

# List every command from both repositories
bash my-scripts.sh

# Only the commands whose name contains "git" (case-insensitive)
bash my-scripts.sh -f git

# Point at a python_scripts checkout somewhere else
MY_SCRIPTS_PYTHON_REPO_PATH=/opt/python_scripts bash my-scripts.sh
```

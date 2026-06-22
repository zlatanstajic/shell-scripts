---
layout: default
title: Git Copy
parent: Scripts
nav_order: 7
---

# Git Copy

**File:** `src/scripts/git-copy.sh` · Copy all differences between two git
commits.

Copies the files changed between two commits into a target directory, then zips
it to `<target>_<timestamp>.zip` (when `zip` is absent it warns and leaves the
copied folder un-zipped). Defaults are computed at runtime: start is the
penultimate commit, end is
the last commit. When `-t` is omitted the target defaults to
`$GIT_COPY_TARGET_DIRECTORY_PATH/<repo-basename>` (set
`GIT_COPY_TARGET_DIRECTORY_PATH` in the project root `.env`, copy `.env.example`
to `.env`); when `-t` is given its value is used verbatim (repo basename **not**
appended).

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-s`, `--start_commit_hash` | no | penultimate commit | Range start |
| `-e`, `--end_commit_hash` | no | last commit | Range end |
| `-t`, `--target_directory_path` | no | `$GIT_COPY_TARGET_DIRECTORY_PATH/<repo-basename>` | Target dir (used verbatim) |
| `-h`, `--help` | — | — | Print usage and exit |

## `.env` keys

`GIT_COPY_TARGET_DIRECTORY_PATH`

## Usage

```bash
# Show help
bash git-copy.sh -h

# Copy penultimate→last commit diff to the default target
bash git-copy.sh

# Copy a specific commit range to a specific target
bash git-copy.sh -s <start_hash> -e <end_hash> -t /path/to/target
```

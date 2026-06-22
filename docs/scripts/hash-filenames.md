---
layout: default
title: Hash Filenames
parent: Scripts
nav_order: 6
---

# Hash Filenames

**File:** `src/scripts/hash-filenames.sh` · Rename files in a directory to
random hash names.

Renames matching files in the target directory (defaults to the current
directory) to random hashes. Pass `-v/--verbose` for per-file output and
`-m/--move` to move the hashed files into `hashed_00X` batch folders. Target
extensions are read from `HASH_FILENAMES_FILE_EXTENSIONS` in the project root
`.env` (copy `.env.example` to `.env`); this key is required.

The original→hash pairs are persisted as JSON to a `hash_filenames_mapping.txt`
file in the target directory. On a rerun the script reads that mapping and skips
files already recorded there (idempotency otherwise relies on detecting
already-hashed names). The mapping step needs `jq`: when `jq` is absent the
script logs a warning and skips reading/writing the mapping rather than failing.

Pass `-n/--dry-run` to preview the run: it prints `would rename`/`would move`/
`would remove` lines and makes no filesystem change (no rename, no batch move,
no mapping file). Before its first real mutation the script prompts for
confirmation; pass `-y/--yes` (or `-n/--dry-run`) to bypass the prompt.

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-d`, `--directory` | no | current dir | Directory to process |
| `-v`, `--verbose` | no | off | Per-file output |
| `-m`, `--move` | no | off | Move hashed files into `hashed_00X` batches |
| `-n`, `--dry-run` | no | off | Print intended changes; make no filesystem change |
| `-y`, `--yes` | no | off | Skip the confirmation prompt before mutating |
| `-h`, `--help` | — | — | Print usage and exit |

## `.env` keys

`HASH_FILENAMES_FILE_EXTENSIONS` (required) — comma-separated, case-insensitive,
leading dot optional.

## Usage

```bash
# Show help
bash hash-filenames.sh -h

# Hash a directory, verbose, move into batches
bash hash-filenames.sh -d /path/to/dir -v -m
```

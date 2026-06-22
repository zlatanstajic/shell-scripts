---
layout: default
title: Restore VS Code Folder
parent: Scripts
nav_order: 5
---

# Restore VS Code Folder

**File:** `src/scripts/restore-vscode-folder.sh` · Restore the `.vscode` folder
from backup into the current directory.

Run from a project directory that has no `.vscode/` yet; the script copies
`.vscode/` from
`<BACKUP_LOCATION>/<PROJECTS_DESTINATION_FOLDER_NAME>/<current-dir-basename>/.vscode`
(the same tree `backup.sh` populates) into the current directory. When
`.vscode/` already exists it logs a no-op message and exits.

Configuration is read from an optional `.env` in the project root (copy
`.env.example` to `.env`); both `BACKUP_LOCATION` and
`PROJECTS_DESTINATION_FOLDER_NAME` are required. The copy uses `rsync -a` when
available and falls back to `cp -r` with a warning.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-h`, `--help` | — | Print usage and exit (no other flags; all config via `.env`) |

## `.env` keys

`BACKUP_LOCATION`, `PROJECTS_DESTINATION_FOLDER_NAME` (both reused from
`backup.sh`)

## Usage

```bash
# Show help
bash restore-vscode-folder.sh -h

# Restore .vscode into the current directory from backup
bash restore-vscode-folder.sh
```

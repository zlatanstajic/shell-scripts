---
layout: default
title: Backup
parent: Scripts
nav_order: 4
---

# Backup

**File:** `src/scripts/backup.sh` · Back up documents on a Linux machine.

Configuration is read entirely from an optional `.env` in the project root
(copy `.env.example` to `.env`). `BACKUP_LOCATION` is required; every
per-section variable is optional and a section whose `*_SOURCE_PATHS` is empty
is silently skipped.

The script runs three phases:

1. **Simple file backups** — `SYSTEM` and VS Code source paths.
2. **Projects backup** — encrypts `.env`/`.env.rb` files to recoverable `.enc`
   ciphertext (AES-256-CBC with `-pbkdf2`, computed with `openssl`, password
   `ENV_FILES_PASSWORD`; warns and skips encryption when `openssl` is
   absent), skipping files whose source is not newer than the existing `.enc`,
   and copies `config.json` and `.vscode/`. Recover a file with
   `openssl enc -d -aes-256-cbc -pbkdf2 -in <file>.enc -pass pass:<password>`.
3. **Deployments backup**.

Directory-tree copies use `rsync -a` when available and fall back to `cp -r`
with a warning; privileged directory create/remove falls back to `sudo` when
needed, warning and continuing when `sudo` is absent.

Pass `-n/--dry-run` to preview the run: it prints every would-be destination
clear/create, copy, and encrypt-write, and mutates nothing. Before its first real
mutation the script prompts for confirmation; pass `-y/--yes` (or `-n/--dry-run`)
to bypass the prompt.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-n`, `--dry-run` | no | Print intended changes; make no filesystem change |
| `-y`, `--yes` | no | Skip the confirmation prompt before mutating |
| `-h`, `--help` | — | Print usage and exit (config via `.env`) |

## `.env` keys

`BACKUP_LOCATION` (required), `SYSTEM_DESTINATION_FOLDER_NAME`,
`SYSTEM_SOURCE_PATHS`, `VSCODE_DESTINATION_FOLDER_NAME`, `VSCODE_SOURCE_PATHS`,
`PROJECTS_DESTINATION_FOLDER_NAME`, `PROJECTS_SOURCE_PATHS`,
`ENV_FILES_PASSWORD`, `DEPLOYMENTS_DESTINATION_FOLDER_NAME`,
`DEPLOYMENT_SOURCE_PATHS`

## Usage

```bash
# Show help
bash backup.sh -h

# Run the backup (driven by .env)
bash backup.sh
```

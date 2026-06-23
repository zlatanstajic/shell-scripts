---
layout: default
title: Decrypt Env Files
parent: Scripts
nav_order: 11
---

# Decrypt Env Files

**File:** `src/scripts/decrypt-env-files.sh` · Decrypt backed-up project env
files.

The inverse of `backup.sh`'s projects-backup encryption. It walks the backup
projects tree, decrypts every `.env.enc` and `.env.rb.enc` ciphertext
(AES-256-CBC with `-pbkdf2` — the only two names `backup.sh` writes, so
unrelated `.enc` files are never touched), and writes the plaintext to a
sibling file whose `.enc` suffix is replaced with `.decrypted` — so
`<project>/.env.enc` becomes `<project>/.env.decrypted` and
`<project>/.env.rb.enc` becomes
`<project>/.env.rb.decrypted`. The `.enc` originals are never modified or
removed.

Configuration is read entirely from an optional `.env` in the project root
(copy `.env.example` to `.env`). It reuses three of `backup.sh`'s keys —
`BACKUP_LOCATION`, `PROJECTS_DESTINATION_FOLDER_NAME` and `ENV_FILES_PASSWORD`
— and all three are required. The projects tree is read from
`<BACKUP_LOCATION>/<PROJECTS_DESTINATION_FOLDER_NAME>/`.

Behaviour:

- **Hard dependency on `openssl`.** Because decryption is the script's entire
  purpose, a missing `openssl` is fatal (`End 1`), unlike `backup.sh` which only
  warns and skips when `openssl` is absent.
- **Skip-when-unchanged.** A file is skipped when its `.decrypted` output
  already exists and is not older than the `.enc` source.
- **No matches is not an error.** When the projects tree is missing or holds no
  `.env.enc`/`.env.rb.enc` files, the script logs that there is nothing to
  decrypt and exits `0`.

**Warning:** this writes plaintext secrets next to the ciphertext in the backup
tree. Remove the `.decrypted` files manually once you are done with them.

Pass `-n/--dry-run` to preview the run: it prints every would-be decryption and
mutates nothing (the password is never echoed). Before its first real mutation
the script prompts for confirmation; pass `-y/--yes` (or `-n/--dry-run`) to
bypass the prompt.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-n`, `--dry-run` | no | Print intended changes; make no filesystem change |
| `-y`, `--yes` | no | Skip the confirmation prompt before mutating |
| `-h`, `--help` | — | Print usage and exit (config via `.env`) |

## `.env` keys

`BACKUP_LOCATION` (required), `PROJECTS_DESTINATION_FOLDER_NAME` (required),
`ENV_FILES_PASSWORD` (required)

## Usage

```bash
# Show help
bash decrypt-env-files.sh -h

# Preview what would be decrypted (writes nothing)
bash decrypt-env-files.sh -n

# Decrypt every backed-up .env.enc/.env.rb.enc into a sibling .decrypted file
bash decrypt-env-files.sh
```

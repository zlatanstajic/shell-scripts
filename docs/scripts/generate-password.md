---
layout: default
title: Generate Password
parent: Scripts
nav_order: 3
---

# Generate Password

**File:** `src/scripts/generate-password.sh` · Generate a strong and secure
password.

The length defaults to 20, must be at least 8, and must be divisible by 4. The
generated password is automatically copied to the clipboard via `xclip` (a
warning is logged if `xclip` is not installed).

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-l`, `--length` | no | 20 | Password length (≥ 8, divisible by 4) |
| `-h`, `--help` | — | — | Print usage and exit |

## Usage

```bash
# Show help
bash generate-password.sh -h

# Generate a 20-character password
bash generate-password.sh -l 20
```

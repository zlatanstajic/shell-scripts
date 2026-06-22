---
layout: default
title: PHP Switch
parent: Scripts
nav_order: 2
---

# PHP Switch

**File:** `src/scripts/php-switch.sh` · Switch the main version of PHP on your OS.

Installed versions are auto-detected via `update-alternatives --list php`. Pass
`-v/--version` to switch directly, or run with no arguments to pick
interactively by number. Apache module and `systemctl` steps run resiliently
and are skipped with a warning when the relevant tools are absent.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-v`, `--version` | no | PHP version to switch to (interactive pick if omitted) |
| `-h`, `--help` | — | Print usage, list detected versions, show current selection |

## Usage

```bash
# Show help (also lists detected versions and the current selection)
bash php-switch.sh -h

# Switch to PHP version 8.1
bash php-switch.sh -v 8.1

# Pick interactively by number
bash php-switch.sh
```

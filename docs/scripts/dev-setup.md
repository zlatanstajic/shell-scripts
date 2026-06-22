---
layout: default
title: Dev Setup
parent: Scripts
nav_order: 1
---

# Dev Setup

**File:** `src/scripts/dev-setup.sh` · Development setup for git repositories.

If you're setting up development for a git repository, you're ready to go by
default. Configuration is read from an optional `.env` in the project root
(copy `.env.example` to `.env`); otherwise in-script defaults apply.

1. Each branch has a prefix, by default `issues`. Change it via `BRANCH_PREFIX`
   in `.env`.
2. On completion the script copies helper text (message name and, when
   configured, description) to the clipboard and opens a prefilled GitLab
   merge-request URL. `REQUEST_PREFIX` prefixes request titles, `ISSUE_BASE_PATH`
   builds the description, and `GITLAB_ASSIGNEE_ID` pre-assigns the merge
   request.

The source branch is selected interactively by number from the enumerated
branch list. Both `-nu/--number` and `-na/--name` are required.

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-nu`, `--number` | yes | Issue number |
| `-na`, `--name` | yes | Issue name |
| `-h`, `--help` | — | Print usage and exit |

## `.env` keys

`BRANCH_PREFIX`, `REQUEST_PREFIX`, `ISSUE_BASE_PATH`, `GITLAB_ASSIGNEE_ID`

## Usage

```bash
# Show help
bash dev-setup.sh -h

# Set up development for issue #1 "Example issue name"
bash dev-setup.sh -nu 1 -na "Example issue name"
```

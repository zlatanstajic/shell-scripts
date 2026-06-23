---
layout: default
title: Tampermonkey Install
parent: Scripts
nav_order: 10
---

# Tampermonkey Install

**File:** `src/scripts/tampermonkey-install.sh` · Build a GitHub userscript URL
and open it for Tampermonkey.

Composes a userscript URL as `<base>/<domain>/<script>.user.js` from a
domain-name folder and a script name, then opens it with `xdg-open` so
Tampermonkey can pick it up (when `xdg-open` is absent it warns and prints the
URL for manual use rather than failing). The base defaults to
`TAMPERMONKEY_REPO_BASE_URLS` (set it in the project root `.env`, copy
`.env.example` to `.env`) and can be overridden per-run with `-r/--repo`. When
`TAMPERMONKEY_REPO_BASE_URLS` holds multiple comma-separated values the script
probes each in order with `curl --head` (following redirects, 5 s timeout) and
opens the first that returns HTTP 2xx; it falls back to the first entry when
none return 2xx or `curl` is absent. A single URL skips probing entirely. For
**private** repos the probe authenticates with a GitHub token (first of
`$GH_TOKEN`, `$GITHUB_TOKEN`, then `gh auth token`), sent only to `github.com`
candidates — without it every private candidate probes as 404 and the first
entry is used. The domain and script must match
`[A-Za-z0-9._-]+`; any trailing `.user.js` supplied on the script name is
stripped before the extension is re-appended.

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-d`, `--domain` | yes | — | Domain-name folder (e.g. `youtube.com`) |
| `-s`, `--script` | yes | — | Script name without extension (e.g. `video-speed`) |
| `-r`, `--repo` | no | `$TAMPERMONKEY_REPO_BASE_URLS` | Override the configured GitHub base URL |
| `-h`, `--help` | — | — | Print usage and exit |

## `.env` keys

`TAMPERMONKEY_REPO_BASE_URLS` — accepts a single URL or a comma-separated list
of URLs (probed in order; first HTTP 2xx is used; `curl` is a soft dependency;
private repos need `$GH_TOKEN`/`$GITHUB_TOKEN` or `gh` for the probe to see them)

## Usage

```bash
# Show help
bash tampermonkey-install.sh -h

# Build and open the URL for a userscript
bash tampermonkey-install.sh -d youtube.com -s video-speed

# Override the configured base URL
bash tampermonkey-install.sh -d youtube.com -s video-speed -r <base-url>
```

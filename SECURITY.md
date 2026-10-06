# Security Policy

## Supported versions

This is a small, single-maintainer toolkit. Only the latest release receives
fixes; older tags stay available but are not patched.

| Version | Supported |
|---------|-----------|
| 5.x     | ✅ Yes    |
| < 5.0   | ❌ No     |

See the [releases page](https://github.com/zlatanstajic/shell-scripts/releases)
for the current version.

## Reporting a vulnerability

**Do not open a public issue for a vulnerability.** A public issue discloses the
problem before there is a fix, and issue text is indexed immediately.

Email **contact@zlatanstajic.com** with `shell-scripts security` in the subject.

Please include:

- the script and the release, tag, or commit you were running;
- the exact command, with any secret value redacted;
- what happens, and what you expected instead;
- your OS and `bash --version`;
- whether you installed via `install.sh`, the `deploy/` copy, or ran the script
  directly from a clone;
- a proof of concept, if you have one.

**Never include a real credential, password, token, or the contents of your
`.env` in a report.** Describe the shape of the value rather than the value.

### What to expect

This project is maintained in spare time, so no response-time guarantee is
offered. In practice you can expect an acknowledgement of the report, a note on
whether it is accepted, a fix in a new release when it is, and credit in the
release notes unless you would rather stay anonymous. Please give a reasonable
window for a fix before disclosing publicly.

## Scope

These are local Bash scripts. They run as the user who invokes them, on that
user's machine, with that user's privileges. There is no server, no service,
and no network listener. The interesting boundary is what a script does with
local configuration, local files, and the few external tools it shells out to.

### In scope

- A script mishandling a secret read from `.env` — writing it to a log, a file,
  a process argument list, the terminal, or the clipboard when it should not.
- A command injection or unsafe-quoting bug that lets an attacker-controlled
  filename, argument, or configuration value run as a command.
- `backup.sh` or `decrypt-env-files.sh` weakening the `openssl` AES-256-CBC
  encryption of `.env` files, or leaving plaintext where it should not.
- `generate-password.sh` producing predictable or low-entropy output.
- `tampermonkey-install.sh` sending a GitHub token (`$GH_TOKEN`,
  `$GITHUB_TOKEN`, or `gh auth token`) to any host other than `github.com`.
- `shutdown-guard.sh` failing open — running the power command when a guard
  should have blocked it. Note that a guard timeout is intentionally
  fail-closed.
- A privilege-escalation path, an unsafe `sudo` fallback, or an insecure
  temporary-file pattern.
- A path-traversal or unintended-deletion bug in any script that removes or
  overwrites files.

### Out of scope

These are known, documented design characteristics, not vulnerabilities:

- **`.env` is sourced as shell, not parsed.** Any shell in your `.env` executes,
  including on a `-h` run, because the `source` happens at file scope before
  argument parsing. Treat your `.env` as executable code you own. A report that
  a hostile `.env` can run commands describes the documented design.
- **`shutdown-guard.sh` only gates shutdowns routed through itself.** The
  desktop power menu, the physical power button, `sudo poweroff`,
  `systemctl --force`, and remote or cron shutdowns all bypass it by design. It
  is a guard against your own habit, not a security control.
- **`-f/--force` bypasses every `shutdown-guard.sh` guard.** That is the
  documented purpose of the flag.
- Anything requiring an attacker who already has your shell, your user account,
  or write access to your `.env` or to the clone itself. At that point they do
  not need these scripts.
- Vulnerabilities in the external tools the scripts call — `openssl`, `ffmpeg`,
  `jq`, `curl`, `git`, `rsync`, `xclip`, `xdg-open`, `systemctl`. Report those
  upstream. A report is in scope only if this project calls one of them in an
  unsafe way.
- Findings against a modified copy under `deploy/`, which is by design your own
  local edit of the scripts.

## Secrets and this repository

No real secret should ever be committed here. `.env` is gitignored and must
stay that way; [`.env.example`](.env.example) documents key names with
placeholder values only. If you believe a real credential has been committed,
report it privately using the process above rather than opening an issue or a
pull request that references it.

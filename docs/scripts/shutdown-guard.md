---
layout: default
title: Shutdown Guard
parent: Scripts
nav_order: 13
---

# Shutdown Guard

**File:** `src/scripts/shutdown-guard.sh` · Gate a shell-initiated
shutdown/restart behind `.env` guards.

A **gate-and-delegate wrapper**. It evaluates the guard commands declared in
the project-root `.env`, and:

- when **every** guard passes, it asks for confirmation and delegates to
  `systemctl poweroff` (`-s`) or `systemctl reboot` (`-r`);
- when **any** guard blocks, it prints each blocker and exits with code `3`
  without running any power command.

Guards are declared as a contiguous numbered set, scanned from `1` upwards
until the first missing (or empty) `SHUTDOWN_GUARD_<i>_CMD` — a numbering gap
ends the scan. Each guard runs in a child `bash` under
`timeout "$SHUTDOWN_GUARD_TIMEOUT"`, with stdout captured for the mode test and
stderr captured for logging only. No guard short-circuits the rest: every guard
runs and every blocker is reported.

## Guard modes

| `_MODE` | Blocks when |
|---------|-------------|
| `status` (default) | the command exits non-zero |
| `empty` | the command writes anything to stdout |
| `match:<ERE>` | stdout matches the extended regular expression |
| `nomatch:<ERE>` | stdout does **not** match the extended regular expression |

An unknown mode is a configuration error (exit `1`), never a silent pass, so a
typo cannot open the gate.

Edge-case behaviour:

- **Timeout is fail-closed.** A guard that exceeds `SHUTDOWN_GUARD_TIMEOUT`
  (default 10 s) blocks, because its state is unknown. The value must be `>= 1`:
  `0` is rejected (GNU `timeout 0` means *no* limit, which would silently remove
  the protection), as is any non-numeric value and any value wider than five
  digits (such a number breaks the range test itself).
- **A failing guard command blocks.** In the `empty`, `match:` and `nomatch:`
  modes a non-zero exit status blocks on its own, before the stdout test: a
  broken tool that writes only to stderr has not answered the question, so an
  empty stdout must never score a pass. Watch for commands that exit non-zero on
  their "nothing found" path — `pgrep -a rsync` and `grep pat file` both exit 1
  — and append `|| true` to those, or they veto every shutdown.
- **An invalid ERE is a configuration error.** `match:`/`nomatch:` patterns are
  validated at load time (exit `1`); an unusable pattern at evaluation time
  blocks rather than passing.
- **Unrunnable guard (exit 127).** Warned and skipped under
  `SHUTDOWN_GUARD_STRICT=0` (default); blocks under `=1`.
- **Zero guards is not an error.** The script warns that nothing is configured
  and proceeds.
- **`timeout` is a soft dependency.** When absent the guards still run, without
  a time limit, behind a loud warning.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | all guards passed (power command run, or printed under `-n`) |
| `1` | usage or configuration error |
| `3` | **BLOCKED** by at least one guard; nothing was shut down |

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `-s`, `--shutdown` | yes* | Power off when every guard passes |
| `-r`, `--restart` | yes* | Reboot when every guard passes |
| `-n`, `--dry-run` | no | Run the guards; print the power command, never run it |
| `-y`, `--yes` | no | Skip the confirmation prompt before powering off |
| `-f`, `--force` | no | Bypass ALL guards (use with care) |
| `-h`, `--help` | — | Print usage and exit |

\* Exactly one of `-s/--shutdown` or `-r/--restart` is required; passing both is
an error.

## `.env` keys

`SHUTDOWN_GUARD_<i>_CMD` (required per guard), `SHUTDOWN_GUARD_<i>_DESC`
(optional, defaults to the command string), `SHUTDOWN_GUARD_<i>_MODE`
(optional, defaults to `status`), `SHUTDOWN_GUARD_TIMEOUT` (optional, default
`10`), `SHUTDOWN_GUARD_STRICT` (optional, default `0`).

**Warning:** guard strings are executed as shell and printed verbatim in log and
dry-run output, and guard **output** is logged too — a blocker's stdout is
echoed (truncated to 5 lines) and the first stderr lines are shown as a
warning. Never embed credentials in a guard string, and never let a guard print
secrets. The power commands themselves (`systemctl poweroff` / `systemctl
reboot`) are hardcoded and deliberately **not** `.env`-overridable.

## Usage

```bash
# Show help
bash shutdown-guard.sh -h

# Preview: run the guards, print the power command, power nothing off
bash shutdown-guard.sh -n -s

# Power off if every guard passes (prompts first)
bash shutdown-guard.sh -s

# Reboot without the prompt
bash shutdown-guard.sh -y -r

# Bypass every guard
bash shutdown-guard.sh -f -y -s
```

Example `.env` guard refusing to power off while VirtualBox VMs run:

```bash
SHUTDOWN_GUARD_1_CMD="vboxmanage list runningvms"
SHUTDOWN_GUARD_1_DESC="VirtualBox VMs still running"
SHUTDOWN_GUARD_1_MODE="empty"
```

## Wrapper recipe

Route the usual command names through the guard by adding shell functions to
`~/.bashrc` (after `install.sh` has put `shutdown-guard` on `PATH`):

```bash
poweroff() { shutdown-guard -y -s; }
reboot()   { shutdown-guard -y -r; }
shutdown() { shutdown-guard -y -s; }
```

Pass `-y` in wrappers: `ConfirmOrAbort` exits `0` when a prompt is declined
(library design), so a caller cannot distinguish "user cancelled" from
"shutdown started". Treat **only exit code 3** as a veto.

## Limits (read this)

This is a **voluntary gate, not enforcement**. A real kernel/systemd-level veto
is not achievable from user space. It gates only shutdowns routed through the
script, and cannot stop:

- the GNOME (or any desktop) power menu;
- the physical power button;
- `sudo poweroff` / `sudo shutdown` / the SysV binaries;
- `systemctl --force poweroff` or `systemctl start poweroff.target`;
- remote, `at`- or cron-triggered shutdowns.

Hardening beyond this wrapper — a `systemd-inhibit --what=shutdown
--mode=block` inhibitor lock held while work is in flight, or a PolicyKit rule
denying `org.freedesktop.login1.power-off` — is deliberately out of scope here.

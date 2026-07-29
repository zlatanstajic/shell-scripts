#!/bin/bash

################################################################################
# Script name : shutdown-guard.sh
# Description : Gate a shell-initiated shutdown/restart behind .env guards
# Parameters  : -s | -r | -n | -y | -f | -h
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################
# Scope contract:
#   This is a VOLUNTARY gate-and-delegate wrapper, not enforcement. It evaluates
#   the guard commands declared in $PROJECT_ROOT/.env and, when any of them
#   blocks, refuses to run the power command (exit code 3). When all guards pass
#   it delegates to `systemctl poweroff` / `systemctl reboot`.
#   It gates only shutdowns routed THROUGH it (direct invocation, or shell
#   functions aliasing shutdown/reboot/poweroff). It CANNOT stop the GNOME power
#   menu, the physical power button, `sudo poweroff`, `systemctl --force`, or
#   remote/cron-triggered shutdowns. A real kernel/systemd-level veto is not
#   achievable from user space.
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/common.sh"

set -u

# Defaults (overridden by $PROJECT_ROOT/.env when present). The power commands
# themselves are deliberately NOT .env-overridable: an overridable, word-split
# argv for a privileged command would be an unauditable substitution hook.
SHUTDOWN_GUARD_TIMEOUT=10
SHUTDOWN_GUARD_STRICT=0

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Dry-run / confirm flags (CLI only). Declared AFTER the .env source so a stray
# .env var cannot pin the mode.
# shellcheck disable=SC2034  # read by RunOrEcho/ConfirmOrAbort in common.sh
DRY_RUN=0
# shellcheck disable=SC2034  # read by ConfirmOrAbort in common.sh
ASSUME_YES=0

# Script-local state.
ACTION=""
FORCE=0
HAVE_TIMEOUT=1

# Loaded guards (parallel arrays) and the blockers collected from them.
GUARD_CMDS=()
GUARD_DESCS=()
GUARD_MODES=()
BLOCK_DESCS=()
BLOCK_MODES=()
BLOCK_REASONS=()
BLOCK_OUTPUTS=()

# Per-guard result channel (bash cannot return strings).
GUARD_VERDICT=""
GUARD_REASON=""
GUARD_OUTPUT=""

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Gate a shell-initiated shutdown/restart behind .env guards"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME -s"
  echo "Preview only    : $SCRIPT_NAME -n -s"
  echo ""
  echo "  -s, --shutdown  Power off when every guard passes"
  echo "  -r, --restart   Reboot when every guard passes"
  echo "  -n, --dry-run   Run the guards; print the power command, never run it"
  echo "  -y, --yes       Skip the confirmation prompt before powering off"
  echo "  -f, --force     Bypass ALL guards (use with care)"
  echo "  -h, --help      Show this help and exit"
  echo ""
  echo "Exactly one of -s/--shutdown or -r/--restart is required."
  echo ""
  echo "Configuration is read from $PROJECT_ROOT/.env (see .env.example):"
  echo "SHUTDOWN_GUARD_<i>_CMD / _DESC / _MODE declare the guards (scanned from"
  echo "1 until the first missing _CMD); modes are status, empty, match:<ERE>"
  echo "and nomatch:<ERE>. SHUTDOWN_GUARD_TIMEOUT (default 10 seconds, fail"
  echo "closed) and SHUTDOWN_GUARD_STRICT (default 0) tune the evaluation."
  echo ""
  echo "Exit codes: 0 proceeded, 1 usage/configuration error, 3 BLOCKED by a"
  echo "guard (nothing was shut down)."
  echo ""
  echo "This gates only shutdowns routed through this script. It cannot stop"
  echo "the desktop power menu, the power button, sudo poweroff, --force,"
  echo "or remote/cron-triggered shutdowns."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -s | -r | -n | -y | -f | -h
################################################################################

GetArguments()
{
  while [ $# -gt 0 ]
  do
    case "$1" in
      -h|--help)
        Help
        End 0
        ;;
      -s|--shutdown)
        if [ -n "$ACTION" ] && [ "$ACTION" != "shutdown" ]
        then
          End 1 "-s/--shutdown and -r/--restart are mutually exclusive"
        fi
        ACTION="shutdown"
        shift
        ;;
      -r|--restart)
        if [ -n "$ACTION" ] && [ "$ACTION" != "restart" ]
        then
          End 1 "-s/--shutdown and -r/--restart are mutually exclusive"
        fi
        ACTION="restart"
        shift
        ;;
      -n|--dry-run)
        # shellcheck disable=SC2034  # read by RunOrEcho/ConfirmOrAbort
        DRY_RUN=1
        shift
        ;;
      -y|--yes)
        # shellcheck disable=SC2034  # read by ConfirmOrAbort in common.sh
        ASSUME_YES=1
        shift
        ;;
      -f|--force)
        FORCE=1
        shift
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done
  if [ -z "$ACTION" ]
  then
    Help
    MissingRequiredArguments
  fi
}

################################################################################
# Function    : ValidateGlobals
# Description : Validates the .env-provided globals, ending with an error on a
#               non-numeric, zero, or implausibly large timeout (a typo must not
#               silently disable the fail-closed timeout: GNU `timeout 0` means
#               NO time limit, so status 124 could never fire again; a value
#               wider than the shell's integer range would break the -lt test)
# Parameters  : /
################################################################################

ValidateGlobals()
{
  case "${SHUTDOWN_GUARD_TIMEOUT:-}" in
    ''|*[!0-9]*)
      End 1 "SHUTDOWN_GUARD_TIMEOUT must be a whole number of seconds"
      ;;
    # Reject 6+ digits before any arithmetic: a value wider than the shell's
    # integer range makes `[ ... -lt ... ]` itself fail, bypassing the check.
    ??????*)
      End 1 "SHUTDOWN_GUARD_TIMEOUT is implausibly large (max 5 digits)"
      ;;
  esac
  if [ "$SHUTDOWN_GUARD_TIMEOUT" -lt 1 ]
  then
    End 1 "SHUTDOWN_GUARD_TIMEOUT must be >= 1 second (0 disables the limit)"
  fi
  case "${SHUTDOWN_GUARD_STRICT:-}" in
    0|1) ;;
    *)
      End 1 "SHUTDOWN_GUARD_STRICT must be 0 or 1"
      ;;
  esac
  if ! command -v timeout > /dev/null 2>&1
  then
    HAVE_TIMEOUT=0
    LogWarn "timeout is not installed: guards run WITHOUT a time limit, so a"
    LogWarn "hanging guard command will hang this script indefinitely."
  fi
}

################################################################################
# Function    : LoadGuards
# Description : Reads SHUTDOWN_GUARD_<i>_CMD / _DESC / _MODE from the sourced
#               .env, scanning i=1,2,3... until the first unset or empty _CMD
#               (a numbering gap ENDS the scan) into the parallel guard arrays.
#               An unknown _MODE or an invalid match:/nomatch: ERE is a
#               configuration error, never a silent pass
# Parameters  : /
################################################################################

LoadGuards()
{
  local i=1 cmd_var desc_var mode_var cmd desc mode pattern status
  while true
  do
    cmd_var="SHUTDOWN_GUARD_${i}_CMD"
    desc_var="SHUTDOWN_GUARD_${i}_DESC"
    mode_var="SHUTDOWN_GUARD_${i}_MODE"
    # Indirect expansion with the +set test keeps this safe under set -u.
    if [ -z "${!cmd_var+set}" ] || [ -z "${!cmd_var}" ]
    then
      break
    fi
    cmd="${!cmd_var}"
    desc="$cmd"
    if [ -n "${!desc_var+set}" ] && [ -n "${!desc_var}" ]
    then
      desc="${!desc_var}"
    fi
    mode="status"
    if [ -n "${!mode_var+set}" ] && [ -n "${!mode_var}" ]
    then
      mode="${!mode_var}"
    fi
    case "$mode" in
      status|empty) ;;
      match:*|nomatch:*)
        # Reject a malformed ERE here: an invalid pattern makes the later
        # [[ =~ ]] test return 2, which would score match: as a pass.
        pattern="${mode#*:}"
        { [[ "" =~ $pattern ]]; } 2> /dev/null
        status=$?
        if [ "$status" -gt 1 ]
        then
          End 1 "Guard $i has an invalid ERE: $pattern"
        fi
        ;;
      *)
        End 1 "Guard $i has an unknown mode: $mode"
        ;;
    esac
    GUARD_CMDS+=("$cmd")
    GUARD_DESCS+=("$desc")
    GUARD_MODES+=("$mode")
    i=$((i + 1))
  done
  if [ "${#GUARD_CMDS[@]}" -eq 0 ]
  then
    LogWarn "No guards are configured (SHUTDOWN_GUARD_1_CMD is unset);"
    LogWarn "nothing will be checked before the power command."
  fi
}

################################################################################
# Function    : RunGuard
# Description : Runs one guard in a subshell with stdout captured for the mode
#               test and stderr captured separately for logging only, then
#               reports a pass/block/skip verdict through GUARD_VERDICT,
#               GUARD_REASON and GUARD_OUTPUT
# Parameters  : command mode
################################################################################

RunGuard()
{
  local cmd="$1"
  local mode="$2"
  local errfile out err status pattern match_status

  GUARD_VERDICT="pass"
  GUARD_REASON=""
  GUARD_OUTPUT=""

  errfile="$(mktemp)"
  # The guard string is intentionally evaluated as shell (that is the .env
  # contract); it runs in a child bash, under timeout, with output captured.
  if [ "$HAVE_TIMEOUT" -eq 1 ]
  then
    out="$(timeout "$SHUTDOWN_GUARD_TIMEOUT" bash -c "$cmd" 2> "$errfile")"
    status=$?
  else
    out="$(bash -c "$cmd" 2> "$errfile")"
    status=$?
  fi
  err="$(cat "$errfile")"
  rm -f "$errfile"
  # Command substitution already strips trailing newlines from $out.
  GUARD_OUTPUT="$out"

  if [ -n "$err" ]
  then
    LogWarn "guard stderr: $(printf '%s' "$err" | head -n 3 | tr '\n' ' ')"
  fi

  if [ "$HAVE_TIMEOUT" -eq 1 ] && [ "$status" -eq 124 ]
  then
    # Fail closed: the guard never answered, so the state is unknown.
    GUARD_VERDICT="block"
    GUARD_REASON="timed out after ${SHUTDOWN_GUARD_TIMEOUT}s, state unknown"
    return 0
  fi

  if [ "$status" -eq 127 ]
  then
    if [ "$SHUTDOWN_GUARD_STRICT" -eq 1 ]
    then
      GUARD_VERDICT="block"
      GUARD_REASON="command not found (SHUTDOWN_GUARD_STRICT=1)"
    else
      GUARD_VERDICT="skip"
      GUARD_REASON="command not found; guard skipped"
    fi
    return 0
  fi

  # The stdout-inspecting modes must still fail closed on an operational
  # failure: a guard that exits non-zero (broken tool, bad arguments, output on
  # stderr only) has NOT answered the question, so an empty stdout must not
  # score a pass. Only mode status interprets the exit code as the answer.
  if [ "$mode" != "status" ] && [ "$status" -ne 0 ]
  then
    GUARD_VERDICT="block"
    GUARD_REASON="guard command failed (status $status), state unknown"
    return 0
  fi

  case "$mode" in
    status)
      if [ "$status" -ne 0 ]
      then
        GUARD_VERDICT="block"
        GUARD_REASON="exited with status $status"
      fi
      ;;
    empty)
      if [ -n "$out" ]
      then
        GUARD_VERDICT="block"
        GUARD_REASON="produced output (expected none)"
      fi
      ;;
    match:*)
      pattern="${mode#match:}"
      { [[ "$out" =~ $pattern ]]; } 2> /dev/null
      match_status=$?
      if [ "$match_status" -gt 1 ]
      then
        # Defence in depth (LoadGuards pre-validates the ERE): an unusable
        # pattern blocks rather than silently passing.
        GUARD_VERDICT="block"
        GUARD_REASON="unusable ERE $pattern, cannot evaluate"
      elif [ "$match_status" -eq 0 ]
      then
        GUARD_VERDICT="block"
        GUARD_REASON="output matches $pattern"
      fi
      ;;
    nomatch:*)
      pattern="${mode#nomatch:}"
      { [[ "$out" =~ $pattern ]]; } 2> /dev/null
      match_status=$?
      if [ "$match_status" -gt 1 ]
      then
        GUARD_VERDICT="block"
        GUARD_REASON="unusable ERE $pattern, cannot evaluate"
      elif [ "$match_status" -ne 0 ]
      then
        GUARD_VERDICT="block"
        GUARD_REASON="output does not match $pattern"
      fi
      ;;
  esac
  return 0
}

################################################################################
# Function    : TruncateOutput
# Description : Echoes at most the first 5 lines of the given text, appending an
#               ellipsis line when it was longer
# Parameters  : text
################################################################################

TruncateOutput()
{
  local text="$1"
  local lines
  if [ -z "$text" ]
  then
    return 0
  fi
  lines="$(printf '%s\n' "$text" | wc -l)"
  printf '%s\n' "$text" | head -n 5
  if [ "$lines" -gt 5 ]
  then
    echo "    ... ($((lines - 5)) more line(s))"
  fi
}

################################################################################
# Function    : RunGuards
# Description : Runs every loaded guard with NO short-circuit (one log line per
#               guard) and collects the blockers. Under -f/--force the whole
#               loop is skipped with a loud warning
# Parameters  : /
################################################################################

RunGuards()
{
  if [ "$FORCE" -eq 1 ]
  then
    LogWarn "--force given: ALL guards bypassed, nothing was checked."
    return 0
  fi
  local i total desc mode
  total="${#GUARD_CMDS[@]}"
  for (( i = 0; i < total; i++ ))
  do
    desc="${GUARD_DESCS[$i]}"
    mode="${GUARD_MODES[$i]}"
    RunGuard "${GUARD_CMDS[$i]}" "$mode"
    case "$GUARD_VERDICT" in
      pass)
        LogInfo "guard $((i + 1)) ok      : $desc"
        ;;
      skip)
        LogWarn "guard $((i + 1)) skipped : $desc ($GUARD_REASON)"
        ;;
      block)
        LogInfo "guard $((i + 1)) BLOCK   : $desc"
        BLOCK_DESCS+=("$desc")
        BLOCK_MODES+=("$mode")
        BLOCK_REASONS+=("$GUARD_REASON")
        BLOCK_OUTPUTS+=("$(TruncateOutput "$GUARD_OUTPUT")")
        ;;
    esac
  done
}

################################################################################
# Function    : ReportBlockers
# Description : Logs every collected blocker (description, mode, reason,
#               truncated output) and the closing summary line
# Parameters  : /
################################################################################

ReportBlockers()
{
  local i total line
  total="${#BLOCK_DESCS[@]}"
  echo ""
  for (( i = 0; i < total; i++ ))
  do
    line="${BLOCK_DESCS[$i]} [mode: ${BLOCK_MODES[$i]}]"
    line="$line - ${BLOCK_REASONS[$i]}"
    LogError "$line"
    if [ -n "${BLOCK_OUTPUTS[$i]}" ]
    then
      printf '%s\n' "${BLOCK_OUTPUTS[$i]}"
    fi
  done
  echo ""
  EchoBold "Shutdown BLOCKED by $total guard(s): $ACTION was refused."
  LogInfo "Nothing was shut down or restarted. Resolve the items above, or"
  LogInfo "re-run with -f/--force to bypass every guard."
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  ValidateGlobals
  LoadGuards
  RunGuards

  if [ "${#BLOCK_DESCS[@]}" -gt 0 ]
  then
    ReportBlockers
    # The ONLY exit-3 path; no power command is reached from here.
    EndCode 3 "Blocked by ${#BLOCK_DESCS[@]} guard(s)"
  fi

  # The power command is hardcoded (no .env override). Neither -i/--force nor
  # the SysV poweroff binary is used.
  local words
  if [ "$ACTION" = "restart" ]
  then
    words=(systemctl reboot)
  else
    words=(systemctl poweroff)
  fi

  # Confirm immediately before the irreversible call; bypassed under -y/--yes
  # and dry-run. KNOWN ASYMMETRY: ConfirmOrAbort exits 0 when declined (library
  # design), so a caller cannot tell "user cancelled" from "shutdown started".
  # Wrapper shell functions should therefore pass -y and treat ONLY exit code 3
  # as a veto.
  ConfirmOrAbort
  RunOrEcho "${words[@]}"
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

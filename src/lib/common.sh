################################################################################
# Library     : lib/common.sh
# Description : Shared helpers sourced by the shell scripts (lifecycle, prompts,
#               logging). Not executable on its own; source it after setting
#               SCRIPT_NAME via: source "$SCRIPT_DIR/../lib/common.sh"
# Parameters  : /
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# shellcheck shell=bash

# Dry-run / assume-yes mode globals. These library defaults exist ONLY for
# set -u safety; every script RE-ASSIGNS them after its .env source so a stray
# .env var cannot pin the mode. RunOrEcho/ConfirmOrAbort read them.
# shellcheck disable=SC2034
DRY_RUN=0
# shellcheck disable=SC2034
ASSUME_YES=0

################################################################################
# Function    : End
# Description : Terminates shell script
# Parameters  : is-with-error [error-text]
################################################################################

End()
{
  if [ "${1:-0}" -eq 0 ]
  then
    echo ""
    echo "Script $SCRIPT_NAME finishing OK"
    exit 0
  else
    echo ""
    echo -e "Script $SCRIPT_NAME finishing with \e[1mERROR [$2]\e[0m"
    exit 1
  fi
}

################################################################################
# Function    : RunScript
# Description : Installs a Ctrl-C/error trap routed through End, then runs the
#               provided main function (mirrors Python run_script wrapper)
# Parameters  : main-function-name
################################################################################

RunScript()
{
  trap 'End 1 "Interrupted by user (Ctrl+C)"' INT
  "$@"
}

################################################################################
# Function    : EchoBold
# Description : Echoes text wrapped in ANSI bold
# Parameters  : message
################################################################################

EchoBold()
{
  echo -e "\e[1m$1\e[0m"
}

################################################################################
# Function    : LogInfo
# Description : Leveled info echo helper
# Parameters  : message
################################################################################

LogInfo()
{
  echo -e "$1"
}

################################################################################
# Function    : LogWarn
# Description : Leveled warning echo helper
# Parameters  : message
################################################################################

LogWarn()
{
  echo -e "\e[1mWARNING:\e[0m $1"
}

################################################################################
# Function    : LogError
# Description : Leveled error echo helper
# Parameters  : message
################################################################################

LogError()
{
  echo -e "\e[1mERROR:\e[0m $1"
}

################################################################################
# Function    : UserInput
# Description : Handles user input
# Parameters  : message
################################################################################

UserInput()
{
  read -rp "$1: " input
  echo "$input"
}

################################################################################
# Function    : DoYouWishToProceed
# Description : Handles proceeding dialog
# Parameters  : /
################################################################################

DoYouWishToProceed()
{
  local yn
  while true; do
    # A read failure (EOF / closed stdin) must terminate the loop rather than
    # spin forever; treat it as a decline (echo "0"). The prompt goes to stderr
    # (bash default for read -rp), so $(DoYouWishToProceed) captures only 0/1.
    if ! read -rp "Do you wish to proceed? [y/n]: " yn
    then
      echo "0"
      break
    fi
    case $yn in
      [Yy]* )
        echo "1"
      break;;
      [Nn]* )
        echo "0"
      break;;
      * )
        # Unrecognized input: re-prompt (the next read's EOF check breaks).
        ;;
    esac
  done
}

################################################################################
# Function    : RunOrEcho
# Description : Dry-run-aware command wrapper. When DRY_RUN=1, prints a
#               printf %q-quoted "[dry-run] would: ..." line to STDERR (so it
#               never contaminates a $(...) capture) and returns 0 without
#               executing. Otherwise executes the command verbatim via "$@"
#               (preserving argument boundaries) and propagates its exit status.
# Parameters  : command [args...]
################################################################################

RunOrEcho()
{
  if [ "${DRY_RUN:-0}" -eq 1 ]
  then
    { printf '[dry-run] would: '; printf '%q ' "$@"; printf '\n'; } 1>&2
    return 0
  fi
  "$@"
  return $?
}

################################################################################
# Function    : ConfirmOrAbort
# Description : Interactive confirmation gate. Returns 0 immediately when
#               DRY_RUN=1 or ASSUME_YES=1 (non-interactive bypass); otherwise
#               prompts via DoYouWishToProceed and cleanly aborts (End 0) when
#               the user declines. Because DoYouWishToProceed echoes "0" on EOF,
#               this aborts cleanly under closed stdin instead of hanging.
# Parameters  : /
################################################################################

ConfirmOrAbort()
{
  if [ "${DRY_RUN:-0}" -eq 1 ] || [ "${ASSUME_YES:-0}" -eq 1 ]
  then
    return 0
  fi
  local ans
  ans="$(DoYouWishToProceed)"
  if [ "$ans" = "0" ]
  then
    End 0
  fi
}

################################################################################
# Function    : MissingRequiredArguments
# Description : Emits the standard missing-arguments message and ends with error
# Parameters  : /
################################################################################

MissingRequiredArguments()
{
  End 1 "Missing required arguments! Use -h or --help to see which ones..."
}

################################################################################
# Function    : UrlEncode
# Description : Percent-encodes a string for safe use in a URL query value
# Parameters  : string
################################################################################

UrlEncode()
{
  local string="$1"
  local length=${#string}
  local i char encoded=""
  for (( i = 0; i < length; i++ ))
  do
    char="${string:$i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-])
        encoded+="$char"
        ;;
      *)
        encoded+=$(printf '%%%02X' "'$char")
        ;;
    esac
  done
  echo "$encoded"
}

################################################################################

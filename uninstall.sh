#!/bin/bash

################################################################################
# Script name : uninstall.sh
# Description : Remove the symlinks install.sh created (those pointing into this
#               repo's src/scripts/), leaving unrelated files in the prefix
# Parameters  : -p prefix | -h
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# uninstall.sh lives at the repo root, so common.sh is under src/lib (NOT
# ../lib as in src/scripts/*.sh). SCRIPT_NAME must be set before sourcing
# because common.sh's End/RunScript reference it unbraced under set -u.
source "$SCRIPT_DIR/src/lib/common.sh"

set -u

PREFIX="$HOME/.local/bin"

SRC_DIR="$SCRIPT_DIR/src/scripts"
COMPLETION_SRC="$SCRIPT_DIR/src/completion/shell-scripts.bash"
_completion_default="$HOME/.local/share/bash-completion/completions"
COMPLETION_DIR="${BASH_COMPLETION_USER_DIR:-$_completion_default}"

# Mirror install.sh: gen-docs.sh is never installed, so never look for it here.
EXCLUDE_NAMES=("gen-docs.sh")

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Remove the symlinks install.sh created in a bin directory"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo "Custom prefix   : $SCRIPT_NAME -p ~/bin"
  echo ""
  echo "  -p, --prefix   Install directory (default: ~/.local/bin)"
  echo "  -h, --help     Show this help and exit"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -p prefix
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
      -p|--prefix)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        PREFIX="$2"
        shift 2
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done
}

################################################################################
# Function    : IsExcluded
# Description : Returns 0 when the given filename is in EXCLUDE_NAMES
# Parameters  : filename
################################################################################

IsExcluded()
{
  local name="$1" excluded
  for excluded in "${EXCLUDE_NAMES[@]}"
  do
    [ "$name" = "$excluded" ] && return 0
  done
  return 1
}

################################################################################
# Function    : RemoveLinks
# Description : Removes a target only when it is a symlink resolving into this
#               repo's src/scripts/; never touches unrelated files or links
# Parameters  : /
################################################################################

RemoveLinks()
{
  local f base name target resolved src_real
  src_real="$(readlink -f "$SRC_DIR")"

  for f in "$SRC_DIR"/*.sh
  do
    base="$(basename "$f")"
    IsExcluded "$base" && continue

    name="$(basename "$f" .sh)"
    target="$PREFIX/$name"

    if [ ! -L "$target" ]
    then
      continue
    fi

    resolved="$(readlink -f "$target")"
    if [ "$(dirname "$resolved")" = "$src_real" ]
    then
      rm -f "$target"
      LogInfo "Removed $target"
    else
      LogWarn "Skipping $target (does not point into $src_real)."
    fi
  done
}

################################################################################
# Function    : RemoveCompletion
# Description : Removes the completion file this repo installed, if present
# Parameters  : /
################################################################################

RemoveCompletion()
{
  local installed="$COMPLETION_DIR/shell-scripts.bash"
  if [ -f "$installed" ] && [ -f "$COMPLETION_SRC" ] && \
     cmp -s "$installed" "$COMPLETION_SRC"
  then
    rm -f "$installed"
    LogInfo "Removed $installed"
  fi
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"

  RemoveLinks
  RemoveCompletion

  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

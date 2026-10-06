#!/bin/bash

################################################################################
# Script name : install.sh
# Description : Symlink every user-facing script in src/scripts/ into a bin
#               directory on PATH (default ~/.local/bin) under its bare name
# Parameters  : -p prefix | -h
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# install.sh lives at the repo root, so common.sh is under src/lib (NOT
# ../lib as in src/scripts/*.sh). SCRIPT_NAME must be set before sourcing
# because common.sh's End/RunScript reference it unbraced under set -u.
source "$SCRIPT_DIR/src/lib/common.sh"

set -u

PREFIX="$HOME/.local/bin"

SRC_DIR="$SCRIPT_DIR/src/scripts"

# gen-docs.sh is a maintainer tool (it regenerates the docs reference and is
# excluded from gen-docs.sh's own discovery); it is not a user-facing command,
# so it is not installed onto PATH.
EXCLUDE_NAMES=("gen-docs.sh")

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Symlink src/scripts/*.sh onto PATH under their bare names"
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
# Function    : LinkScripts
# Description : Symlinks each user-facing src/scripts/*.sh into PREFIX, choosing
#               by target type so existing files/dirs are never clobbered
# Parameters  : /
################################################################################

LinkScripts()
{
  local f base name target
  for f in "$SRC_DIR"/*.sh
  do
    base="$(basename "$f")"
    IsExcluded "$base" && continue

    name="$(basename "$f" .sh)"
    target="$PREFIX/$name"

    # Defensively re-apply the exec bit so a clone that lost it (noexec mount,
    # Windows-origin checkout) still yields runnable bare-name commands.
    chmod +x "$f"

    if [ -L "$target" ]
    then
      # ln -sfn re-points an existing symlink (idempotent re-run / moved repo).
      ln -sfn "$f" "$target"
      LogInfo "Updated $target -> $f"
    elif [ -e "$target" ]
    then
      # A regular file or directory already lives here; never clobber it.
      LogWarn "Skipping $target (a file or directory already exists there)."
    else
      ln -s "$f" "$target"
      LogInfo "Created $target -> $f"
    fi
  done
}

################################################################################
# Function    : CheckPath
# Description : Warns (does not fail) when PREFIX is not on PATH
# Parameters  : /
################################################################################

CheckPath()
{
  case ":$PATH:" in
    *":$PREFIX:"*)
      :
      ;;
    *)
      LogWarn "$PREFIX is not on your PATH. Add it with:"
      LogInfo ""
      LogInfo "  export PATH=\"$PREFIX:\$PATH\""
      LogInfo ""
      LogInfo "Add that line to your shell rc (e.g. ~/.bashrc) to persist it."
      ;;
  esac
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"

  mkdir -p "$PREFIX"

  LinkScripts
  CheckPath

  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

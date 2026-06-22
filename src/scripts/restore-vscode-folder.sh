#!/bin/bash

################################################################################
# Script name : restore-vscode-folder.sh
# Description : Restore the .vscode folder from backup to current directory
# Parameters  : /
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/common.sh"

set -u

# Defaults (overridden by $PROJECT_ROOT/.env when present)
BACKUP_LOCATION=""
PROJECTS_DESTINATION_FOLDER_NAME=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

VSCODE_FOLDER_NAME=".vscode"
CURRENT_DIR=""
VSCODE_FOLDER=""

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Restore the .vscode folder from backup into the current"
  echo "directory (only when it has no .vscode yet)."
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo ""
  echo "Configuration is read from $PROJECT_ROOT/.env (see .env.example)."
  echo "Reuses BACKUP_LOCATION and PROJECTS_DESTINATION_FOLDER_NAME; both are"
  echo "required. Restores from <BACKUP_LOCATION>/"
  echo "<PROJECTS_DESTINATION_FOLDER_NAME>/<current-dir-basename>/.vscode."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h
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
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done
}

################################################################################
# Function    : ResolvePaths
# Description : Resolves the current directory and the target .vscode path
# Parameters  : /
################################################################################

ResolvePaths()
{
  CURRENT_DIR="$(pwd)"
  VSCODE_FOLDER="$CURRENT_DIR/$VSCODE_FOLDER_NAME"
}

################################################################################
# Function    : CheckVscodeExists
# Description : When .vscode already exists in the current directory, logs the
#               no-op message and ends OK without copying
# Parameters  : /
################################################################################

CheckVscodeExists()
{
  if [ -d "$VSCODE_FOLDER" ]
  then
    LogInfo ".vscode folder already exists in $CURRENT_DIR. Nothing to do."
    End 0
  fi
}

################################################################################
# Function    : ValidateEnvironment
# Description : Ends with the standard missing-arguments error when either
#               required .env value is unset
# Parameters  : /
################################################################################

ValidateEnvironment()
{
  if [ -z "${BACKUP_LOCATION:-}" ] \
    || [ -z "${PROJECTS_DESTINATION_FOLDER_NAME:-}" ]
  then
    Help
    MissingRequiredArguments
  fi
}

################################################################################
# Function    : DoRestore
# Description : Copies the backed-up .vscode folder into the current directory.
#               Uses rsync -a when available, else cp -r with a warning.
#               Ends with error when the backup source is missing or copy fails
# Parameters  : /
################################################################################

DoRestore()
{
  local current_basename backup_vscode_path
  current_basename="$(basename "$CURRENT_DIR")"
  backup_vscode_path="$BACKUP_LOCATION/$PROJECTS_DESTINATION_FOLDER_NAME"
  backup_vscode_path="$backup_vscode_path/$current_basename/$VSCODE_FOLDER_NAME"

  if [ ! -d "$backup_vscode_path" ]
  then
    End 1 "Failed to copy .vscode folder: source not found: $backup_vscode_path"
  fi

  if command -v rsync >/dev/null 2>&1
  then
    mkdir -p "$VSCODE_FOLDER"
    if ! rsync -a "$backup_vscode_path/" "$VSCODE_FOLDER/"
    then
      End 1 "Failed to copy .vscode folder: $backup_vscode_path"
    fi
  else
    LogWarn "rsync unavailable; falling back to cp -r for $backup_vscode_path"
    if ! cp -r "$backup_vscode_path" "$VSCODE_FOLDER"
    then
      End 1 "Failed to copy .vscode folder: $backup_vscode_path"
    fi
  fi

  LogInfo ".vscode folder restored from backup: $backup_vscode_path"
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  ResolvePaths
  CheckVscodeExists
  ValidateEnvironment
  DoRestore
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

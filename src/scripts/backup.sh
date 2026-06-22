#!/bin/bash

################################################################################
# Script name : backup.sh
# Description : Backup documents on Linux machine
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
ENV_FILES_ZIP_PASSWORD="pa55"
# Documented .env keys, reserved for future system/vscode backups.
# shellcheck disable=SC2034
SYSTEM_DESTINATION_FOLDER_NAME=""
# shellcheck disable=SC2034
SYSTEM_SOURCE_PATHS=""
# shellcheck disable=SC2034
VSCODE_DESTINATION_FOLDER_NAME=""
# shellcheck disable=SC2034
VSCODE_SOURCE_PATHS=""
PROJECTS_DESTINATION_FOLDER_NAME=""
PROJECTS_SOURCE_PATHS=""
DEPLOYMENTS_DESTINATION_FOLDER_NAME=""
DEPLOYMENT_SOURCE_PATHS=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Dry-run / confirm flags (CLI only). Declared AFTER the .env source so a stray
# .env var cannot pin the mode.
DRY_RUN=0
# shellcheck disable=SC2034  # read by ConfirmOrAbort in common.sh
ASSUME_YES=0

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Backup documents on Linux machine"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo "Preview only    : $SCRIPT_NAME -n"
  echo ""
  echo "  -h, --help     Show this help and exit"
  echo "  -n, --dry-run  Print intended changes; make no filesystem change"
  echo "  -y, --yes      Skip the confirmation prompt before mutating"
  echo ""
  echo "Configuration is read from $PROJECT_ROOT/.env (see .env.example)."
  echo "BACKUP_LOCATION is required; per-section variables are optional."
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
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -y|--yes)
        # shellcheck disable=SC2034  # read by ConfirmOrAbort in common.sh
        ASSUME_YES=1
        shift
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done
}

################################################################################
# Function    : SplitCsv
# Description : Splits a comma-separated list, trims each item, drops empties,
#               emitting one non-empty item per line (caller uses readarray -t)
# Parameters  : csv
################################################################################

SplitCsv()
{
  local csv="$1"
  local item parts=()
  IFS=',' read -ra parts <<< "$csv"
  for item in "${parts[@]}"
  do
    # Strip leading/trailing whitespace
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [ -n "$item" ]
    then
      echo "$item"
    fi
  done
}

################################################################################
# Function    : SudoMakedirs
# Description : Creates a directory tree; retries with sudo on failure (only
#               when sudo is available), warns and skips otherwise
# Parameters  : path
################################################################################

SudoMakedirs()
{
  local path="$1"
  # Dry-run guard at the function TOP covers every caller and BOTH the
  # unprivileged mkdir and the sudo fallback below.
  if [ "$DRY_RUN" -eq 1 ]
  then
    LogInfo "would create $path"
    return 0
  fi
  if [ -d "$path" ]
  then
    return 0
  fi
  if mkdir -p "$path" 2>/dev/null
  then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1
  then
    sudo mkdir -p "$path"
  else
    LogWarn "Unable to create directory (sudo unavailable): $path"
  fi
}

################################################################################
# Function    : SudoRmtree
# Description : Removes a directory tree; retries with sudo on failure (only
#               when sudo is available), warns and skips otherwise
# Parameters  : path
################################################################################

SudoRmtree()
{
  local path="$1"
  # Dry-run guard at the function TOP covers every caller and BOTH the
  # unprivileged rm and the sudo fallback below.
  if [ "$DRY_RUN" -eq 1 ]
  then
    LogInfo "would clear $path"
    return 0
  fi
  if [ ! -e "$path" ]
  then
    return 0
  fi
  if rm -rf "$path" 2>/dev/null
  then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1
  then
    sudo rm -rf "$path"
  else
    LogWarn "Unable to remove directory (sudo unavailable): $path"
  fi
}

################################################################################
# Function    : ComputeFileHash
# Description : Computes the HMAC-SHA256 hex digest of a file. Echoes the hex on
#               success; warns and returns non-zero when openssl is unavailable
# Parameters  : file key
################################################################################

ComputeFileHash()
{
  local file="$1"
  local key="$2"
  if ! command -v openssl >/dev/null 2>&1
  then
    LogWarn "openssl unavailable; cannot hash $file"
    return 1
  fi
  # openssl output: "HMAC-SHA256(file)= <hex>" or "SHA2-256(...)= <hex>";
  # the hex digest is always the last whitespace-separated field.
  openssl dgst -sha256 -hmac "$key" "$file" | awk '{print $NF}'
}

################################################################################
# Function    : GetParentFolderName
# Description : Returns the name of the directory two levels up from the leaf
#               (basename of the path's parent). A single trailing slash is
#               stripped first so behavior matches no-trailing-slash .env values
# Parameters  : path
################################################################################

GetParentFolderName()
{
  local path="$1"
  # Strip a single trailing slash (mirrors Python os.path.split expectations)
  path="${path%/}"
  basename "$(dirname "$path")"
}

################################################################################
# Function    : IsSubfolderOfProject
# Description : Returns success when the path's basename is api/frontend/backend
# Parameters  : path
################################################################################

IsSubfolderOfProject()
{
  local path="$1"
  path="${path%/}"
  case "$(basename "$path")" in
    api|frontend|backend)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

################################################################################
# Function    : GetProjectName
# Description : Returns "<parent>/<basename>" when the path is an api/frontend/
#               backend subfolder, else just the basename
# Parameters  : path
################################################################################

GetProjectName()
{
  local path="$1"
  path="${path%/}"
  local folder_name
  folder_name="$(basename "$path")"
  if IsSubfolderOfProject "$path"
  then
    echo "$(GetParentFolderName "$path")/$folder_name"
  else
    echo "$folder_name"
  fi
}

################################################################################
# Function    : CopyTree
# Description : Copies a directory tree. Removes the destination first, then
#               uses rsync -a when available, else cp -r with a warning. Copy
#               failures warn only (no sudo retry)
# Parameters  : src-dir dest-dir
################################################################################

CopyTree()
{
  local src="$1"
  local dest="$2"
  SudoRmtree "$dest"
  if command -v rsync >/dev/null 2>&1
  then
    if ! RunOrEcho rsync -a "$src/" "$dest/"
    then
      LogWarn "Unable to copy directory tree: $src -> $dest"
    fi
  else
    LogWarn "rsync unavailable; falling back to cp -r for $src"
    if ! RunOrEcho cp -r "$src" "$dest"
    then
      LogWarn "Unable to copy directory tree: $src -> $dest"
    fi
  fi
}

################################################################################
# Function    : DoSimpleBackup
# Description : Backs up a simple section (SYSTEM/VSCODE): clears and recreates
#               the destination folder, then copies each listed source file in
# Parameters  : prefix
################################################################################

DoSimpleBackup()
{
  local prefix="$1"
  local src_var="${prefix}_SOURCE_PATHS"
  local dest_var="${prefix}_DESTINATION_FOLDER_NAME"
  local src_csv="${!src_var:-}"
  local src_paths=()
  readarray -t src_paths < <(SplitCsv "$src_csv")
  if [ "${#src_paths[@]}" -eq 0 ]
  then
    return 0
  fi
  local dest_folder_name="${!dest_var:-}"
  if [ -z "$dest_folder_name" ]
  then
    LogWarn "$dest_var unset; skipping $prefix backup"
    return 0
  fi
  local dest="$BACKUP_LOCATION/$dest_folder_name"
  SudoRmtree "$dest"
  SudoMakedirs "$dest"
  local src
  for src in "${src_paths[@]}"
  do
    if ! RunOrEcho cp "$src" "$dest"
    then
      LogWarn "Error in $dest_folder_name backup: unable to copy $src"
    fi
  done
}

################################################################################
# Function    : DoProjectsBackup
# Description : Backs up each project: .env/.env.rb hashed via HMAC-SHA256 with
#               skip-if-unchanged, config.json copied, .vscode/ copied
# Parameters  : /
################################################################################

DoProjectsBackup()
{
  local src_csv="${PROJECTS_SOURCE_PATHS:-}"
  local projects=()
  readarray -t projects < <(SplitCsv "$src_csv")
  if [ "${#projects[@]}" -eq 0 ]
  then
    return 0
  fi
  local dest_folder_name="${PROJECTS_DESTINATION_FOLDER_NAME:-}"
  if [ -z "$dest_folder_name" ]
  then
    LogWarn "PROJECTS_DESTINATION_FOLDER_NAME unset; skipping projects backup"
    return 0
  fi
  local projects_dir="$BACKUP_LOCATION/$dest_folder_name"
  SudoMakedirs "$projects_dir"
  local project
  for project in "${projects[@]}"
  do
    SudoMakedirs "$projects_dir/$(GetProjectName "$project")"
  done
  for project in "${projects[@]}"
  do
    local project_name
    project_name="$(GetProjectName "$project")"
    # Env file (.env preferred, else .env.rb) backed up as <file>.hash
    local env_file=""
    if [ -f "$project/.env" ]
    then
      env_file=".env"
    elif [ -f "$project/.env.rb" ]
    then
      env_file=".env.rb"
    fi
    if [ -n "$env_file" ]
    then
      local hash_dst="$projects_dir/$project_name/$env_file.hash"
      SudoMakedirs "$(dirname "$hash_dst")"
      local new_hash env_src="$project/$env_file"
      if new_hash="$(ComputeFileHash "$env_src" "$ENV_FILES_ZIP_PASSWORD")"
      then
        local existing_hash=""
        if [ -f "$hash_dst" ]
        then
          existing_hash="$(cat "$hash_dst" 2>/dev/null)"
        fi
        if [ "$new_hash" = "$existing_hash" ]
        then
          LogInfo "Skipping $project $env_file: unchanged"
        elif [ "$DRY_RUN" -eq 1 ]
        then
          # A redirect cannot be routed through RunOrEcho (the > binds to the
          # outer command and would write), so branch explicitly here.
          LogInfo "would write hash to $hash_dst"
        elif echo "$new_hash" > "$hash_dst"
        then
          LogInfo "Backed up $project $env_file: hash updated"
        else
          LogWarn "Unable to backup $project $env_file"
        fi
      else
        LogWarn "Unable to backup $project $env_file"
      fi
    fi
    # config.json copied verbatim when present
    if [ -f "$project/config.json" ]
    then
      local config_dst="$projects_dir/$project_name/config.json"
      SudoMakedirs "$(dirname "$config_dst")"
      if ! RunOrEcho cp "$project/config.json" "$config_dst"
      then
        LogWarn "Unable to backup $project config.json"
      fi
    fi
    # .vscode/ folder. For api/frontend/backend subfolders the .vscode lives in
    # the project parent and is stored under the parent folder name.
    local vscode_src vscode_segment
    if IsSubfolderOfProject "$project"
    then
      vscode_src="$(dirname "${project%/}")/.vscode"
      vscode_segment="$(GetParentFolderName "$project")"
    else
      vscode_src="${project%/}/.vscode"
      vscode_segment="$(basename "${project%/}")"
    fi
    if [ -d "$vscode_src" ]
    then
      CopyTree "$vscode_src" "$projects_dir/$vscode_segment/.vscode"
    fi
  done
}

################################################################################
# Function    : DoDeploymentsBackup
# Description : Clears and recreates the deployments destination, then copies
#               each deployment dir into dest/<parent-folder-name>
# Parameters  : /
################################################################################

DoDeploymentsBackup()
{
  local src_csv="${DEPLOYMENT_SOURCE_PATHS:-}"
  local deployments=()
  readarray -t deployments < <(SplitCsv "$src_csv")
  if [ "${#deployments[@]}" -eq 0 ]
  then
    return 0
  fi
  local dest_folder_name="${DEPLOYMENTS_DESTINATION_FOLDER_NAME:-}"
  if [ -z "$dest_folder_name" ]
  then
    LogWarn "DEPLOYMENTS_DESTINATION_FOLDER_NAME unset; skipping"
    return 0
  fi
  local deployments_dir="$BACKUP_LOCATION/$dest_folder_name"
  SudoRmtree "$deployments_dir"
  SudoMakedirs "$deployments_dir"
  local deployment
  for deployment in "${deployments[@]}"
  do
    if [ ! -d "$deployment" ]
    then
      LogError "Source directory does not exist: $deployment"
      continue
    fi
    local seg
    seg="$(GetParentFolderName "$deployment")"
    CopyTree "$deployment" "$deployments_dir/$seg"
  done
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  if [ -z "${BACKUP_LOCATION:-}" ]
  then
    Help
    MissingRequiredArguments
  fi
  # Confirm before any real mutation; bypassed under -y/--yes and dry-run.
  ConfirmOrAbort
  DoSimpleBackup SYSTEM
  DoSimpleBackup VSCODE
  DoProjectsBackup
  DoDeploymentsBackup
  LogInfo "Completed all backup steps."
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

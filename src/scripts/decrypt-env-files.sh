#!/bin/bash

################################################################################
# Script name : decrypt-env-files.sh
# Description : Decrypt backed-up project env files (.env.enc/.env.rb.enc)
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

# Defaults (overridden by $PROJECT_ROOT/.env when present). ENV_FILES_PASSWORD
# mirrors backup.sh's default so the decrypt side matches the encrypt side.
BACKUP_LOCATION=""
PROJECTS_DESTINATION_FOLDER_NAME=""
ENV_FILES_PASSWORD="pa55"

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

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Decrypt backed-up project env files (.env.enc/.env.rb.enc)"
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
  echo "BACKUP_LOCATION, PROJECTS_DESTINATION_FOLDER_NAME and"
  echo "ENV_FILES_PASSWORD are all required."
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
        # shellcheck disable=SC2034  # read by RunOrEcho/ConfirmOrAbort
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
# Function    : RequireOpenssl
# Description : Ends with error when openssl is unavailable. Decryption is this
#               script's entire purpose, so openssl is a HARD dependency (like
#               ffmpeg in the splice scripts), unlike backup.sh which only
#               warns-and-skips because encryption is one optional phase there
# Parameters  : /
################################################################################

RequireOpenssl()
{
  if ! command -v openssl >/dev/null 2>&1
  then
    End 1 "openssl is required to decrypt; install it and retry."
  fi
}

################################################################################
# Function    : ValidateEnvironment
# Description : Ends with the standard missing-arguments error when any required
#               .env value is unset
# Parameters  : /
################################################################################

ValidateEnvironment()
{
  if [ -z "${BACKUP_LOCATION:-}" ] \
    || [ -z "${PROJECTS_DESTINATION_FOLDER_NAME:-}" ] \
    || [ -z "${ENV_FILES_PASSWORD:-}" ]
  then
    Help
    MissingRequiredArguments
  fi
}

################################################################################
# Function    : DecryptEnvFile
# Description : Decrypts a file with AES-256-CBC (-pbkdf2) into dst using the
#               given password. Dry-run aware via RunOrEcho. openssl presence is
#               enforced by RequireOpenssl in Main, so no per-call guard here
# Parameters  : src dst key
################################################################################

DecryptEnvFile()
{
  local src="$1"
  local dst="$2"
  local key="$3"
  # Use env: to avoid exposing the key as a CLI argument (ps visibility).
  local -x OPENSSL_DEC_PASS="$key"
  RunOrEcho openssl enc -d -aes-256-cbc -pbkdf2 -in "$src" -out "$dst" \
    -pass env:OPENSSL_DEC_PASS
}

################################################################################
# Function    : DoDecrypt
# Description : Walks the backup projects tree, decrypting every .env.enc and
#               .env.rb.enc to a sibling <name-without-.enc>.decrypted, skipping
#               when the decrypted output is up to date
# Parameters  : /
################################################################################

DoDecrypt()
{
  local projects_dir="$BACKUP_LOCATION/$PROJECTS_DESTINATION_FOLDER_NAME"
  if [ ! -d "$projects_dir" ]
  then
    LogInfo "No encrypted env files found; nothing to decrypt."
    End 0
  fi
  local found=0 count=0
  local src dst
  # Match only the two ciphertext names backup.sh writes (not every *.enc), so
  # unrelated .enc artifacts under the tree are never touched. Process
  # substitution (not a pipe) so the counters survive the loop; a piped while
  # runs in a subshell and would lose them.
  while IFS= read -r -d '' src
  do
    found=$((found + 1))
    dst="${src%.enc}.decrypted"
    if [ -f "$dst" ] && [ ! "$src" -nt "$dst" ]
    then
      LogInfo "Skipping $src: $dst is up to date"
      continue
    fi
    if DecryptEnvFile "$src" "$dst" "$ENV_FILES_PASSWORD"
    then
      LogInfo "Decrypted $src -> $dst"
      count=$((count + 1))
    else
      LogWarn "Unable to decrypt $src"
    fi
  done < <(
    find "$projects_dir" -type f \
      \( -name '.env.enc' -o -name '.env.rb.enc' \) -print0
  )
  if [ "$found" -eq 0 ]
  then
    LogInfo "No encrypted env files found; nothing to decrypt."
  elif [ "$count" -eq 0 ]
  then
    LogInfo "All encrypted env files already up to date; nothing to decrypt."
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
  RequireOpenssl
  ValidateEnvironment
  LogWarn "This writes plaintext secrets next to the ciphertext in the backup"
  LogInfo "tree. Remove the .decrypted files manually when you are done."
  # Confirm before any real mutation; bypassed under -y/--yes and dry-run.
  ConfirmOrAbort
  DoDecrypt
  LogInfo "Completed decryption."
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

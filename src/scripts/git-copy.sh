#!/bin/bash

################################################################################
# Script name : git-copy.sh
# Description : Copy all differences between two git commits
# Parameters  : [-s start] [-e end] [-t target]
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

START_COMMIT_HASH=""
END_COMMIT_HASH=""
TARGET_DIRECTORY_PATH=""

# Defaults (overridden by $PROJECT_ROOT/.env when present)
GIT_COPY_TARGET_DIRECTORY_PATH=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Copy all differences between two git commits"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo ""
  echo "  -s, --start_commit_hash      Start commit hash (optional)"
  echo "  -e, --end_commit_hash        End commit hash (optional)"
  echo "  -t, --target_directory_path  Target directory path (optional)"
  echo ""
  echo "Defaults are computed at runtime: start is the penultimate commit,"
  echo "end is the last commit. When -t is omitted the target defaults to"
  echo "\$GIT_COPY_TARGET_DIRECTORY_PATH/<repo-basename> (see .env.example);"
  echo "when -t is given its value is used verbatim."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | [-s start] [-e end] [-t target]
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
      -s|--start_commit_hash)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        START_COMMIT_HASH="$2"
        shift 2
        ;;
      -e|--end_commit_hash)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        END_COMMIT_HASH="$2"
        shift 2
        ;;
      -t|--target_directory_path)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        TARGET_DIRECTORY_PATH="$2"
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
# Function    : IsDirectoryGitRepository
# Description : Checks if directory is git repository
# Parameters  : /
################################################################################

IsDirectoryGitRepository()
{
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    End 1 "This script must be run in a git repository directory."
  fi
}

################################################################################
# Function    : DisplayDirectoryName
# Description : Displays directory name
# Parameters  : /
################################################################################

DisplayDirectoryName()
{
  CURRENT_WORKING_DIRECTORY="$(pwd)"
  DIRECTORY_NAME="$(basename "$CURRENT_WORKING_DIRECTORY")"
  EchoBold "Located in directory: $DIRECTORY_NAME"
  echo ""
}

################################################################################
# Function    : GetLastTwoGitHashes
# Description : Resolves the penultimate (start) and last (end) commit hashes,
#               filling START_COMMIT_HASH/END_COMMIT_HASH only when unset by the
#               user. Ends with error when the repo has fewer than two commits
# Parameters  : /
################################################################################

GetLastTwoGitHashes()
{
  local hashes=()
  local line
  while IFS= read -r line
  do
    [ -n "$line" ] && hashes+=("$line")
  done < <(git rev-list --max-count=2 HEAD 2>/dev/null)

  if [ "${#hashes[@]}" -lt 2 ]
  then
    End 1 "Repository must have at least two commits."
  fi

  DEFAULT_START_COMMIT_HASH="${hashes[1]}"
  DEFAULT_END_COMMIT_HASH="${hashes[0]}"

  if [ -z "$START_COMMIT_HASH" ]
  then
    START_COMMIT_HASH="$DEFAULT_START_COMMIT_HASH"
  fi
  if [ -z "$END_COMMIT_HASH" ]
  then
    END_COMMIT_HASH="$DEFAULT_END_COMMIT_HASH"
  fi
}

################################################################################
# Function    : ResolveTargetDirectoryPath
# Description : When -t was not supplied, defaults the target to
#               $GIT_COPY_TARGET_DIRECTORY_PATH/<repo-basename> and ends with
#               error when that variable is unset. When -t was supplied its
#               value is used verbatim (repo basename NOT appended)
# Parameters  : /
################################################################################

ResolveTargetDirectoryPath()
{
  if [ -z "$TARGET_DIRECTORY_PATH" ]
  then
    if [ -z "$GIT_COPY_TARGET_DIRECTORY_PATH" ]
    then
      End 1 "GIT_COPY_TARGET_DIRECTORY_PATH is not set; set it in $PROJECT_ROOT/.env or pass -t."
    fi
    TARGET_DIRECTORY_PATH="${GIT_COPY_TARGET_DIRECTORY_PATH%/}/$(basename "$(pwd)")"
  fi

  local resolved
  resolved="$(readlink -m -- "$TARGET_DIRECTORY_PATH" 2>/dev/null)"
  case "$resolved" in
    ""|"/")
      LogError "Refusing unsafe target directory: '$TARGET_DIRECTORY_PATH'"
      End 1 "Unsafe target directory path."
      ;;
  esac
}

################################################################################
# Function    : PrintCommitHashUsage
# Description : Logs whether default or provided start/end commit hashes are in
#               use (preserves the Python script's user-facing logging)
# Parameters  : /
################################################################################

PrintCommitHashUsage()
{
  if [ "$START_COMMIT_HASH" = "$DEFAULT_START_COMMIT_HASH" ]
  then
    LogInfo "Using default start_commit_hash (penultimate): $START_COMMIT_HASH"
  else
    LogInfo "Using provided start_commit_hash: $START_COMMIT_HASH"
  fi

  if [ "$END_COMMIT_HASH" = "$DEFAULT_END_COMMIT_HASH" ]
  then
    LogInfo "Using default end_commit_hash (last): $END_COMMIT_HASH"
  else
    LogInfo "Using provided end_commit_hash: $END_COMMIT_HASH"
  fi
}

################################################################################
# Function    : DoCopyFilesAndFolders
# Description : Copies files changed between the two commits into the target,
#               preserving directory structure, and always copies .vscode/ when
#               present (removing any pre-existing copy first). Ends with error
#               when no files changed; per-file copy failures warn and continue
# Parameters  : /
################################################################################

DoCopyFilesAndFolders()
{
  local files=()
  local line
  # -z + core.quotepath=false keep filenames with spaces, newlines, or
  # non-ASCII bytes intact (otherwise git double-quotes/escapes them and the
  # worktree existence check below silently skips the file).
  while IFS= read -r -d '' line
  do
    [ -n "$line" ] && files+=("$line")
  done < <(git -c core.quotepath=false diff -z --name-only "$START_COMMIT_HASH" "$END_COMMIT_HASH")

  if [ "${#files[@]}" -eq 0 ]
  then
    End 1 "No changed files to copy."
  fi

  local file_path target_path
  for file_path in "${files[@]}"
  do
    # Faithful to the Python original: git diff --name-only also lists files
    # deleted between the two commits, which are absent from the worktree.
    # Those warn-and-skip here (not a defect) instead of aborting the copy.
    [ -e "$file_path" ] || {
      LogWarn "skipping (not in worktree): $file_path"
      continue
    }
    target_path="$TARGET_DIRECTORY_PATH/$file_path"
    mkdir -p "$(dirname "$target_path")"
    if ! cp -p "$file_path" "$target_path"
    then
      LogWarn "Could not copy $file_path"
    fi
  done

  # Always copy the .vscode folder if it exists
  if [ -d .vscode ]
  then
    local vscode_target="$TARGET_DIRECTORY_PATH/.vscode"
    rm -rf "$vscode_target"
    if command -v rsync >/dev/null 2>&1
    then
      mkdir -p "$vscode_target"
      if rsync -a ".vscode/" "$vscode_target/"
      then
        LogInfo ".vscode folder copied to $vscode_target"
      else
        LogWarn "Unable to copy .vscode folder to $vscode_target"
      fi
    elif cp -r ".vscode" "$vscode_target"
    then
      LogInfo ".vscode folder copied to $vscode_target"
    else
      LogWarn "Unable to copy .vscode folder to $vscode_target"
    fi
  fi

  LogInfo "Files copied to $TARGET_DIRECTORY_PATH directory"
}

################################################################################
# Function    : ZipCopiedFiles
# Description : Zips the target directory to <target>_<timestamp>.zip (archive
#               paths relative to the target's parent, preserving the leaf
#               folder name) and removes the unzipped folder afterwards. When
#               zip is unavailable, warns and leaves the folder in place without
#               ending in error
# Parameters  : /
################################################################################

ZipCopiedFiles()
{
  if ! command -v zip >/dev/null 2>&1
  then
    LogWarn "zip is unavailable; leaving copied folder un-zipped at $TARGET_DIRECTORY_PATH"
    return 0
  fi

  local now_str
  now_str="$(date +%Y%m%d_%H%M%S)"
  local parent_dir leaf_name zip_path
  # Resolve parent to an absolute path so the archive lands beside the leaf
  # folder regardless of whether -t was a relative multi-segment path.
  parent_dir="$(cd "$(dirname "$TARGET_DIRECTORY_PATH")" && pwd)"
  leaf_name="$(basename "$TARGET_DIRECTORY_PATH")"
  zip_path="$parent_dir/${leaf_name}_${now_str}.zip"

  LogInfo "Zipping folder $TARGET_DIRECTORY_PATH to $zip_path"
  rm -f "$zip_path"
  if ! ( cd "$parent_dir" && zip -r "$zip_path" "$leaf_name" >/dev/null )
  then
    LogWarn "Unable to create archive $zip_path; leaving copied folder in place"
    return 0
  fi
  LogInfo "Zipped folder created at $zip_path"

  rm -rf "$TARGET_DIRECTORY_PATH"
  LogInfo "Deleted copied folder: $TARGET_DIRECTORY_PATH"
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  IsDirectoryGitRepository
  DisplayDirectoryName
  GetLastTwoGitHashes
  ResolveTargetDirectoryPath
  PrintCommitHashUsage
  DoCopyFilesAndFolders
  ZipCopiedFiles
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

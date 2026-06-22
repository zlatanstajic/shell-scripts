#!/bin/bash

################################################################################
# Script name : hash-filenames.sh
# Description : Renames files in a directory to random hash names
# Parameters  : -d directory | -v | -m
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
DIRECTORY="$(pwd)"
VERBOSE=0
MOVE=0
MAPPING_FILENAME="hash_filenames_mapping.txt"
HASH_LENGTH=10
BATCH_SIZE=100
BATCH_PREFIX="hashed_"
HASH_FILENAMES_FILE_EXTENSIONS=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Dry-run / confirm flags. Declared AFTER the .env source so a stray .env var
# cannot pin the mode; set only via CLI flags in GetArguments.
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
  echo "Description: Renames files in a directory to random hash names"
  echo ""
  echo "Show this help   : $SCRIPT_NAME -h"
  echo "Hash a directory : $SCRIPT_NAME -d /path/to/dir"
  echo "Verbose output   : $SCRIPT_NAME -d /path/to/dir -v"
  echo "Move into batches: $SCRIPT_NAME -d /path/to/dir -m"
  echo "Preview only     : $SCRIPT_NAME -d /path/to/dir -n"
  echo ""
  echo "  -h, --help       Show this help and exit"
  echo "  -d, --directory  Directory to process (defaults to current directory)"
  echo "  -v, --verbose    Enable verbose output"
  echo "  -m, --move       Move hashed files into ${BATCH_PREFIX}00X folders"
  echo "  -n, --dry-run    Print intended changes; make no filesystem change"
  echo "  -y, --yes        Skip the confirmation prompt before mutating"
  echo ""
  echo "Target extensions are read from HASH_FILENAMES_FILE_EXTENSIONS in"
  echo "$PROJECT_ROOT/.env (see .env.example)."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -d directory | -v | -m
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
      -d|--directory)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        DIRECTORY="$2"
        shift 2
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -m|--move)
        MOVE=1
        shift
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
# Function    : GetFileExtensions
# Description : Reads HASH_FILENAMES_FILE_EXTENSIONS into the global FILE_EXTS
#               array, lowercased and dot-prefixed. Ends with error when unset
# Parameters  : /
################################################################################

GetFileExtensions()
{
  if [ -z "${HASH_FILENAMES_FILE_EXTENSIONS:-}" ]
  then
    End 1 "Environment variable HASH_FILENAMES_FILE_EXTENSIONS not set."
  fi
  FILE_EXTS=()
  local ext
  while IFS= read -r ext
  do
    ext="${ext,,}"
    if [ "${ext:0:1}" != "." ]
    then
      ext=".$ext"
    fi
    FILE_EXTS+=("$ext")
  done < <(SplitCsv "$HASH_FILENAMES_FILE_EXTENSIONS")
  if [ "${#FILE_EXTS[@]}" -eq 0 ]
  then
    End 1 "Environment variable HASH_FILENAMES_FILE_EXTENSIONS is empty."
  fi
}

################################################################################
# Function    : GetExtension
# Description : Echoes the lowercased extension (including the leading dot) of a
#               filename, or empty string when there is no extension
# Parameters  : filename
################################################################################

GetExtension()
{
  local filename="$1"
  # Only treat text after the LAST dot as the extension when there is a
  # non-empty basename before it; a leading-dot name (e.g. ".png") has an
  # empty basename and thus no extension, matching os.path.splitext.
  local base="${filename%.*}"
  case "$filename" in
    *.*)
      if [ -z "$base" ]
      then
        echo ""
      else
        local ext=".${filename##*.}"
        echo "${ext,,}"
      fi
      ;;
    *)
      echo ""
      ;;
  esac
}

################################################################################
# Function    : IsTargetExtension
# Description : Returns success when the given lowercased extension is in the
#               target FILE_EXTS list
# Parameters  : extension
################################################################################

IsTargetExtension()
{
  local ext="$1"
  local target
  for target in "${FILE_EXTS[@]}"
  do
    if [ "$ext" = "$target" ]
    then
      return 0
    fi
  done
  return 1
}

################################################################################
# Function    : GenerateRandomHash
# Description : Generates a random alphanumeric ([A-Za-z0-9]) hash of
#               HASH_LENGTH characters
# Parameters  : /
################################################################################

GenerateRandomHash()
{
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$HASH_LENGTH"
}

################################################################################
# Function    : IsHashed
# Description : Returns success when the filename (without extension) is exactly
#               HASH_LENGTH alphanumeric characters
# Parameters  : filename
################################################################################

IsHashed()
{
  local filename="$1"
  local name="${filename%.*}"
  # When there is no dot, %.* leaves the name unchanged (matches splitext)
  if [ "${#name}" -ne "$HASH_LENGTH" ]
  then
    return 1
  fi
  case "$name" in
    *[!A-Za-z0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

################################################################################
# Function    : HashFiles
# Description : Walks the directory recursively and renames target-extension
#               files (not already hashed or mapped) to <random-hash><ext>.
#               Accumulates original->hashed pairs and persists them as JSON
# Parameters  : /
################################################################################

HashFiles()
{
  local mapping_file="$DIRECTORY/$MAPPING_FILENAME"

  # Existing mapping keys (original filenames already hashed in a prior run).
  # When jq is absent, this "skip already-mapped" path cannot fire, so
  # idempotency relies solely on IsHashed.
  local -A mapped=()
  if [ -f "$mapping_file" ] && command -v jq >/dev/null 2>&1
  then
    local key
    while IFS= read -r key
    do
      mapped["$key"]=1
    done < <(jq -r 'keys[]' "$mapping_file" 2>/dev/null)
  fi

  # Collected new pairs (parallel arrays: originals -> hashed names)
  local -a map_originals=()
  local -a map_hashed=()

  local file root filename file_ext new_name new_path
  while IFS= read -r -d '' file
  do
    root="$(dirname "$file")"
    filename="$(basename "$file")"

    # Skip mapping file itself
    if [ "$filename" = "$MAPPING_FILENAME" ]
    then
      continue
    fi

    file_ext="$(GetExtension "$filename")"

    # Skip if not in target extensions
    if ! IsTargetExtension "$file_ext"
    then
      continue
    fi

    # Skip if already in mapping (already hashed)
    if [ -n "${mapped["$filename"]:-}" ]
    then
      if [ "$VERBOSE" -eq 1 ]
      then
        LogInfo "Skipped (already hashed): $filename"
      fi
      continue
    fi

    # Skip if filename already looks hashed
    if IsHashed "$filename"
    then
      if [ "$VERBOSE" -eq 1 ]
      then
        LogInfo "Skipped (already hashed): $filename"
      fi
      continue
    fi

    new_name="$(GenerateRandomHash)$file_ext"
    new_path="$root/$new_name"

    # Avoid overwriting existing files
    if [ ! -e "$new_path" ]
    then
      # In dry-run, print the intended rename and skip BOTH the mv and the
      # array accumulation, so SaveMapping sees empty arrays and writes nothing.
      # (RunOrEcho is deliberately NOT used here: its 0 return would falsely
      # populate the arrays and trigger a mapping write.)
      if [ "$DRY_RUN" -eq 1 ]
      then
        LogInfo "would rename $file -> $new_path"
        continue
      fi
      mv "$file" "$new_path"
      mapped["$filename"]=1
      map_originals+=("$filename")
      map_hashed+=("$new_name")
      if [ "$VERBOSE" -eq 1 ]
      then
        LogInfo "Renamed: $file -> $new_path"
      fi
    else
      if [ "$VERBOSE" -eq 1 ]
      then
        LogInfo "Skipped (target exists): $file -> $new_path"
      fi
    fi
  done < <(find "$DIRECTORY" -type f -print0)

  SaveMapping "$mapping_file" map_originals map_hashed
}

################################################################################
# Function    : SaveMapping
# Description : Merges new original->hashed pairs into the JSON mapping file
#               (indent 2). Warns and skips persistence when jq is unavailable.
#               No-op when there are no new pairs
# Parameters  : mapping-file originals-array-name hashed-array-name
################################################################################

SaveMapping()
{
  local mapping_file="$1"
  local -n originals="$2"
  local -n hashed="$3"

  if [ "${#originals[@]}" -eq 0 ]
  then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1
  then
    LogWarn "jq unavailable; skipping mapping file ($mapping_file)."
    return 0
  fi

  # Build a JSON object of the new pairs, then merge over any existing mapping.
  local args=() jq_filter="."
  local i
  for i in "${!originals[@]}"
  do
    args+=(--arg "k$i" "${originals[$i]}")
    args+=(--arg "v$i" "${hashed[$i]}")
    jq_filter+=" + {(\$k$i): \$v$i}"
  done

  local base="{}"
  if [ -f "$mapping_file" ]
  then
    base="$(cat "$mapping_file")"
  fi

  if ! printf '%s' "$base" | jq "${args[@]}" "$jq_filter" \
    > "$mapping_file.tmp" 2>/dev/null
  then
    LogWarn "Could not save mapping file: $mapping_file"
    rm -f "$mapping_file.tmp"
    return 0
  fi
  mv "$mapping_file.tmp" "$mapping_file"
}

################################################################################
# Function    : MoveHashedFiles
# Description : Recursively collects target-extension hashed files and moves
#               them into flat batch folders (hashed_001, hashed_002, ...) at
#               the directory root, BATCH_SIZE per folder, then removes empty
#               hashed_* folders at the root
# Parameters  : /
################################################################################

MoveHashedFiles()
{
  local -a hashed_files=()
  local file filename file_ext
  while IFS= read -r -d '' file
  do
    filename="$(basename "$file")"
    file_ext="$(GetExtension "$filename")"
    if IsTargetExtension "$file_ext" && IsHashed "$filename"
    then
      hashed_files+=("$file")
    fi
  done < <(find "$DIRECTORY" -type f -print0)

  local total="${#hashed_files[@]}"
  local i folder_num folder_name target_folder file_path dest_path
  for (( i = 0; i < total; i += BATCH_SIZE ))
  do
    folder_num=$(( (i / BATCH_SIZE) + 1 ))
    folder_name="$(printf '%s%03d' "$BATCH_PREFIX" "$folder_num")"
    target_folder="$DIRECTORY/$folder_name"
    RunOrEcho mkdir -p "$target_folder"
    local j end
    end=$(( i + BATCH_SIZE ))
    if [ "$end" -gt "$total" ]
    then
      end="$total"
    fi
    for (( j = i; j < end; j++ ))
    do
      file_path="${hashed_files[$j]}"
      dest_path="$target_folder/$(basename "$file_path")"
      RunOrEcho mv "$file_path" "$dest_path"
      if [ "$VERBOSE" -eq 1 ]
      then
        LogInfo "Moved: $file_path -> $dest_path"
      fi
    done
  done

  # Remove any empty hashed_ folders directly under the target directory
  local item item_path
  for item_path in "$DIRECTORY"/"$BATCH_PREFIX"*
  do
    if [ -d "$item_path" ] && [ -z "$(ls -A "$item_path")" ]
    then
      RunOrEcho rmdir "$item_path"
      if [ "$VERBOSE" -eq 1 ]
      then
        item="$(basename "$item_path")"
        LogInfo "Deleted empty folder: $item_path"
      fi
    fi
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

  if [ ! -d "$DIRECTORY" ]
  then
    End 1 "Directory does not exist: $DIRECTORY"
  fi

  GetFileExtensions

  # Confirm before any real mutation. This single gate also covers
  # MoveHashedFiles below; bypassed under -y/--yes and dry-run.
  ConfirmOrAbort

  HashFiles

  if [ "$MOVE" -eq 1 ]
  then
    MoveHashedFiles
  fi

  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

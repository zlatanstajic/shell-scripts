#!/bin/bash

################################################################################
# Script name : splice-images.sh
# Description : Splices images horizontally using ffmpeg
# Parameters  : -i images... | -o output | --height H | -n number
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
# Note        : Extension matching uses TRUE file extensions (text after the
#               last dot, via GetExtension), so dotless names like "myjpg" are
#               rejected. This intentionally differs from the Python source's
#               bare str.endswith suffix match.
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/common.sh"

set -u

# Argument-driven defaults (overridden by GetArguments).
IMAGES=()
OUTPUT=""
HEIGHT=0
NUMBER=2

# Config key (overridden by $PROJECT_ROOT/.env when present).
SPLICE_IMAGES_FILE_EXTENSIONS=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Internal (non-config) globals. Declared AFTER the .env source so a stray
# .env var cannot silently override them.
HASH_LENGTH=10
OUTPUT_FOLDER="spliced_images"
STANDALONE_FOLDER="standalone_images"

# Dry-run flag (CLI only). --dry-run long form ONLY: -n is bound to --number.
DRY_RUN=0

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Splices images horizontally using ffmpeg"
  echo ""
  echo "Show this help    : $SCRIPT_NAME -h"
  echo "Splice given imgs : $SCRIPT_NAME -i a.jpg b.jpg"
  echo "Splice 3 images   : $SCRIPT_NAME -i a.jpg b.jpg c.jpg -n 3"
  echo "Random 2 from cwd : $SCRIPT_NAME"
  echo "Fixed scale height: $SCRIPT_NAME -i a.jpg b.jpg --height 200"
  echo ""
  echo "  -h, --help     Show this help and exit"
  echo "  -i, --images   One or more input image files"
  echo "  -o, --output   Output filename (only its extension is used)"
  echo "      --height   Target scale height (default: auto from first image)"
  echo "  -n, --number   Number of images to splice (default: 2)"
  echo "      --dry-run  Print intended changes; make no filesystem change"
  echo "                 (long form only; -n stays bound to --number)"
  echo ""
  echo "Valid extensions are read from SPLICE_IMAGES_FILE_EXTENSIONS in"
  echo "$PROJECT_ROOT/.env (see .env.example)."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -i images... | -o output | --height H | -n number
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
      -i|--images)
        shift
        # Collect following tokens until the next flag (a leading-dash arg).
        while [ $# -gt 0 ] && [ "${1:0:1}" != "-" ]
        do
          IMAGES+=("$1")
          shift
        done
        ;;
      -o|--output)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        OUTPUT="$2"
        shift 2
        ;;
      --height)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        if [[ ! "$2" =~ ^-?[0-9]+$ ]]
        then
          End 1 "Option $1 requires an integer value (got: $2)"
        fi
        HEIGHT="$2"
        shift 2
        ;;
      -n|--number)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        if [[ ! "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 2 ]
        then
          End 1 "Option $1 requires an integer >= 2 (got: $2)"
        fi
        NUMBER="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done

  # No flag is strictly required: with no arguments the script randomly selects
  # images from the current directory, and GetFilteredImages enforces the real
  # minimum (at least two images).
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
# Description : Reads SPLICE_IMAGES_FILE_EXTENSIONS into the global FILE_EXTS
#               array, lowercased and dot-prefixed. Ends with error when unset
# Parameters  : /
################################################################################

GetFileExtensions()
{
  if [ -z "${SPLICE_IMAGES_FILE_EXTENSIONS:-}" ]
  then
    End 1 "Environment variable SPLICE_IMAGES_FILE_EXTENSIONS not set."
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
  done < <(SplitCsv "$SPLICE_IMAGES_FILE_EXTENSIONS")
  if [ "${#FILE_EXTS[@]}" -eq 0 ]
  then
    End 1 "Environment variable SPLICE_IMAGES_FILE_EXTENSIONS is empty."
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
# Function    : GetRandomImages
# Description : Collects current-directory files whose extension is a target
#               extension, then selects NUMBER of them at random (no repeats)
#               into the global FILTERED_IMAGES array. Ends with error when
#               there are fewer than NUMBER candidates
# Parameters  : /
################################################################################

GetRandomImages()
{
  local dir candidates=()
  dir="$(pwd)"
  local file filename file_ext
  while IFS= read -r -d '' file
  do
    filename="$(basename "$file")"
    file_ext="$(GetExtension "$filename")"
    if IsTargetExtension "$file_ext"
    then
      candidates+=("$file")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -print0)

  if [ "${#candidates[@]}" -lt "$NUMBER" ]
  then
    End 1 "Not enough images in $dir (found ${#candidates[@]}, need $NUMBER)."
  fi

  FILTERED_IMAGES=()
  local picked
  while IFS= read -r picked
  do
    FILTERED_IMAGES+=("$picked")
  done < <(printf '%s\n' "${candidates[@]}" | shuf -n "$NUMBER")
}

################################################################################
# Function    : GetFilteredImages
# Description : When -i images were provided, filters them to valid extensions
#               and takes the first NUMBER; otherwise selects NUMBER random
#               images from the current directory. Stores the result in the
#               global FILTERED_IMAGES array and ends with error when fewer
#               than two images remain
# Parameters  : /
################################################################################

GetFilteredImages()
{
  if [ "${#IMAGES[@]}" -gt 0 ]
  then
    FILTERED_IMAGES=()
    local img file_ext
    for img in "${IMAGES[@]}"
    do
      if [ "${#FILTERED_IMAGES[@]}" -ge "$NUMBER" ]
      then
        break
      fi
      file_ext="$(GetExtension "$(basename "$img")")"
      if IsTargetExtension "$file_ext"
      then
        FILTERED_IMAGES+=("$img")
      fi
    done
  else
    GetRandomImages
  fi

  if [ "${#FILTERED_IMAGES[@]}" -lt 2 ]
  then
    End 1 "Please provide at least two images to splice."
  fi
}

################################################################################
# Function    : GetImageHeight
# Description : Echoes the pixel height of an image via ffprobe, or empty on
#               failure
# Parameters  : image-path
################################################################################

GetImageHeight()
{
  local image="$1"
  ffprobe -v error -select_streams v:0 -show_entries stream=height \
    -of csv=p=0 "$image" 2>/dev/null
}

################################################################################
# Function    : GetHeight
# Description : Resolves the global HEIGHT, defaulting to the first filtered
#               image's pixel height when HEIGHT is 0 or negative. Ends with
#               error when the height cannot be determined
# Parameters  : /
################################################################################

GetHeight()
{
  if [ "$HEIGHT" -le 0 ]
  then
    # In dry-run, skip the ffprobe read (the input may be a fake fixture) and
    # use a preview-only placeholder so the would-be ffmpeg command can still be
    # printed. A plain token (not a "<...>" form) keeps the printed
    # filter_complex copy-pasteable; this value never reaches a real ffmpeg run.
    if [ "$DRY_RUN" -eq 1 ]
    then
      HEIGHT="AUTO"
      return 0
    fi
    HEIGHT="$(GetImageHeight "${FILTERED_IMAGES[0]}")"
    if [ -z "$HEIGHT" ]
    then
      End 1 "Could not determine image height. Please provide --height."
    fi
  fi
}

################################################################################
# Function    : BuildFilterComplex
# Description : Builds the ffmpeg filter_complex string for horizontal stacking
#               into the global FILTER_COMPLEX, scaling each input to HEIGHT
# Parameters  : /
################################################################################

BuildFilterComplex()
{
  local num_inputs="${#FILTERED_IMAGES[@]}"
  local idx scaled="" labels=""
  for (( idx = 0; idx < num_inputs; idx++ ))
  do
    if [ -n "$scaled" ]
    then
      scaled="${scaled}; "
    fi
    scaled="${scaled}[$idx:v]scale=-1:${HEIGHT}[v$idx]"
    labels="${labels}[v$idx]"
  done
  FILTER_COMPLEX="$scaled; ${labels}hstack=inputs=${num_inputs}[v]"
}

################################################################################
# Function    : GetOutputPath
# Description : Echoes the output file path. The extension comes from OUTPUT
#               when it contains a dot, otherwise from the first filtered
#               image; the basename is always a fresh random hash. Creates the
#               output folder when missing
# Parameters  : /
################################################################################

GetOutputPath()
{
  local file_ext
  file_ext="$(GetExtension "$OUTPUT")"
  if [ -z "$file_ext" ]
  then
    file_ext="$(GetExtension "$(basename "${FILTERED_IMAGES[0]}")")"
  fi
  # Guard (do NOT route through RunOrEcho): this function echoes the path on
  # stdout, so a would-line here would corrupt the captured output_path.
  if [ "$DRY_RUN" -eq 0 ]
  then
    mkdir -p "$OUTPUT_FOLDER"
  fi
  echo "$OUTPUT_FOLDER/$(GenerateRandomHash)$file_ext"
}

################################################################################
# Function    : SpliceImages
# Description : Runs ffmpeg with one -i per filtered image, the built
#               filter_complex, mapping [v], writing to the output path. Ends
#               with error when ffmpeg exits non-zero
# Parameters  : /
################################################################################

SpliceImages()
{
  local output_path
  output_path="$(GetOutputPath)"
  # Guard against a (rare) random-hash collision; -n below is a second line of
  # defence in case the file appears between this check and ffmpeg running.
  # Skipped in dry-run: the output folder was never created, so a collision is
  # not possible and we only want to print the would-be command.
  if [ "$DRY_RUN" -eq 0 ] && [ -e "$output_path" ]
  then
    End 1 "Output path already exists: $output_path"
  fi

  local cmd=(ffmpeg)
  local img
  for img in "${FILTERED_IMAGES[@]}"
  do
    cmd+=(-i "$img")
  done
  # -n tells ffmpeg never to overwrite an existing output file.
  cmd+=(-filter_complex "$FILTER_COMPLEX" -map "[v]" -n "$output_path")

  # In dry-run RunOrEcho only prints the would-line (to stderr) and returns 0;
  # the >/dev/null 2>&1 redirect below would swallow it, so do not redirect.
  if [ "$DRY_RUN" -eq 1 ]
  then
    RunOrEcho "${cmd[@]}"
    return 0
  fi
  if ! "${cmd[@]}" >/dev/null 2>&1
  then
    End 1 "ffmpeg failed to splice the images."
  fi
}

################################################################################
# Function    : MoveImages
# Description : Moves every consumed input image into STANDALONE_FOLDER. A move
#               failure for one file logs a warning and does not abort the
#               remaining moves
# Parameters  : /
################################################################################

MoveImages()
{
  RunOrEcho mkdir -p "$STANDALONE_FOLDER"
  local img dest
  for img in "${FILTERED_IMAGES[@]}"
  do
    dest="$STANDALONE_FOLDER/$(basename "$img")"
    if [ "$DRY_RUN" -eq 1 ]
    then
      LogInfo "would move $img -> $dest"
      continue
    fi
    if [ -e "$dest" ]
    then
      LogWarn "Skipped $img: $dest already exists"
    elif mv -n "$img" "$dest"
    then
      LogInfo "Moved $img to $dest"
    else
      LogWarn "Could not move $img to $STANDALONE_FOLDER"
    fi
  done
}

################################################################################
# Function    : EnsureTools
# Description : Guards the presence of ffmpeg and ffprobe. Splicing cannot
#               proceed without them, so a warning is logged and the script
#               ends with error rather than silently degrading
# Parameters  : /
################################################################################

EnsureTools()
{
  if ! command -v ffmpeg >/dev/null 2>&1
  then
    LogWarn "ffmpeg is not installed; cannot splice images."
    End 1 "Required tool ffmpeg not found."
  fi
  if ! command -v ffprobe >/dev/null 2>&1
  then
    LogWarn "ffprobe is not installed; cannot read image height."
    End 1 "Required tool ffprobe not found."
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
  EnsureTools
  GetFileExtensions
  GetFilteredImages
  GetHeight
  BuildFilterComplex
  SpliceImages
  MoveImages
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

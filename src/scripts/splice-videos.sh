#!/bin/bash

################################################################################
# Script name : splice-videos.sh
# Description : Splices random fixed-length clips of one input video into a
#               single output video of a target duration using ffmpeg
# Parameters  : -i input | -d duration | -s segment
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
# Note        : Extension matching uses TRUE file extensions (text after the
#               last dot, via GetExtension), so dotless names like "mymp4" are
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
INPUT=""
DURATION=0
SEGMENT=3

# Config key (overridden by $PROJECT_ROOT/.env when present).
SPLICE_VIDEOS_FILE_EXTENSIONS=""

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Internal (non-config) globals. Declared AFTER the .env source so a stray
# .env var cannot silently override them.
CLIPS_FOLDER="random_clips"
OUTPUT_FOLDER="spliced_videos"
CONCAT_LIST_NAME="concat_list.txt"
MAX_FILE_SIZE_BYTES=$((1024 * 1024 * 1024))
ESTIMATED_BITRATE_BPS=1500000

# Dry-run / confirm flags (CLI only). Declared after the .env source so a
# stray .env var cannot pin the mode.
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
  echo "Description: Splices random clips of a video into one output video"
  echo ""
  echo "Show this help    : $SCRIPT_NAME -h"
  echo "Splice 12s output : $SCRIPT_NAME -i clip.mp4 -d 12"
  echo "Custom segment    : $SCRIPT_NAME -i clip.mp4 -d 12 -s 4"
  echo "Preview only      : $SCRIPT_NAME -i clip.mp4 -d 12 -n"
  echo ""
  echo "  -h, --help       Show this help and exit"
  echo "  -i, --input      Input video file (Required)"
  echo "  -d, --duration   Output video duration in seconds (Required)"
  echo "  -s, --segment    Random clip duration in seconds (default: 3)"
  echo "  -n, --dry-run    Print intended changes; make no filesystem change"
  echo "  -y, --yes        Skip the confirmation prompt before mutating"
  echo ""
  echo "Valid extensions are read from SPLICE_VIDEOS_FILE_EXTENSIONS in"
  echo "$PROJECT_ROOT/.env (see .env.example)."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -i input | -d duration | -s segment
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
      -i|--input)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        INPUT="$2"
        shift 2
        ;;
      -d|--duration)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        if [[ ! "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]
        then
          End 1 "Option $1 requires an integer >= 1 (got: $2)"
        fi
        DURATION="$2"
        shift 2
        ;;
      -s|--segment)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        if [[ ! "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]
        then
          End 1 "Option $1 requires an integer >= 1 (got: $2)"
        fi
        SEGMENT="$2"
        shift 2
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

  # Both an input video and a target duration are required.
  if [ -z "$INPUT" ] || [ "$DURATION" -le 0 ]
  then
    MissingRequiredArguments
  fi
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
    LogWarn "ffmpeg is not installed; cannot splice videos."
    End 1 "Required tool ffmpeg not found."
  fi
  if ! command -v ffprobe >/dev/null 2>&1
  then
    LogWarn "ffprobe is not installed; cannot read video duration."
    End 1 "Required tool ffprobe not found."
  fi
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
# Description : Reads SPLICE_VIDEOS_FILE_EXTENSIONS into the global FILE_EXTS
#               array, lowercased and dot-prefixed. Ends with error when unset
# Parameters  : /
################################################################################

GetFileExtensions()
{
  if [ -z "${SPLICE_VIDEOS_FILE_EXTENSIONS:-}" ]
  then
    End 1 "Environment variable SPLICE_VIDEOS_FILE_EXTENSIONS not set."
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
  done < <(SplitCsv "$SPLICE_VIDEOS_FILE_EXTENSIONS")
  if [ "${#FILE_EXTS[@]}" -eq 0 ]
  then
    End 1 "Environment variable SPLICE_VIDEOS_FILE_EXTENSIONS is empty."
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
  # non-empty basename before it; a leading-dot name (e.g. ".mp4") has an
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
# Function    : ResolveInput
# Description : Resolves the input video path relative to the current working
#               directory, ending with error when it is missing or its
#               extension is not a target extension. Stores the resolved path,
#               basename and extension in globals INPUT_PATH, INPUT_NAME and
#               INPUT_EXT
# Parameters  : /
################################################################################

ResolveInput()
{
  if [ ! -f "$INPUT" ]
  then
    End 1 "Input video not found: $INPUT"
  fi
  INPUT_PATH="$INPUT"
  INPUT_NAME="$(basename "$INPUT")"
  INPUT_EXT="$(GetExtension "$INPUT_NAME")"
  if ! IsTargetExtension "$INPUT_EXT"
  then
    End 1 "Input extension '$INPUT_EXT' not in\
 SPLICE_VIDEOS_FILE_EXTENSIONS."
  fi
}

################################################################################
# Function    : GetVideoDuration
# Description : Echoes the duration of a video in seconds via ffprobe. Ends with
#               error when the duration cannot be read or is not numeric
# Parameters  : video-path
################################################################################

GetVideoDuration()
{
  local video="$1"
  local duration
  duration="$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null)"
  if [[ ! "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]
  then
    End 1 "Could not get video duration for $video."
  fi
  echo "$duration"
}

################################################################################
# Function    : CalculateNumberOfRandomClips
# Description : Computes the number of clips needed to fill DURATION at SEGMENT
#               seconds each, reducing when the input is shorter than the
#               target and capping by the 1 GB estimated-output-size guard.
#               Stores the result in the global NUM_SEGMENTS. Integer
#               arithmetic on truncated whole seconds matches the Python
#               floor behaviour for positive durations
# Parameters  : total-duration-seconds (may be fractional)
################################################################################

CalculateNumberOfRandomClips()
{
  local total_float="$1"
  # Truncate fractional seconds to an integer, matching math.floor for
  # positive durations.
  local total="${total_float%.*}"
  local num_segments=$((DURATION / SEGMENT))

  if [ "$total" -lt "$DURATION" ]
  then
    LogInfo "Input video (${total_float}s) is shorter than target\
 (${DURATION}s). Adjusting target segments."
    num_segments=$((total / SEGMENT))
    if [ "$num_segments" -le 0 ]
    then
      End 1 "Input video is too short to create any segments."
    fi
  fi

  local actual_output_duration=$((num_segments * SEGMENT))
  local estimated_output_size=$(( \
    (actual_output_duration * ESTIMATED_BITRATE_BPS) / 8))

  if [ "$estimated_output_size" -gt "$MAX_FILE_SIZE_BYTES" ]
  then
    local max_duration=$(( \
      (MAX_FILE_SIZE_BYTES * 8) / ESTIMATED_BITRATE_BPS))
    local capped=$((max_duration / SEGMENT))
    LogInfo "Output would exceed 1 GB. Reducing segments from\
 $((DURATION / SEGMENT)) to $capped."
    num_segments="$capped"
    if [ "$num_segments" -le 0 ]
    then
      End 1 "Even a single segment would exceed 1 GB. Segment too long."
    fi
  fi

  NUM_SEGMENTS="$num_segments"
}

################################################################################
# Function    : CreateAvailableBlockIndices
# Description : Builds a shuffled list of candidate block indices, skipping the
#               first and last 10% of the source. Clamps NUM_SEGMENTS to the
#               available count when fewer blocks exist. Stores the shuffled
#               indices in the global BLOCK_INDICES array. Ends with error when
#               the trimmed range is empty
# Parameters  : total-duration-seconds (may be fractional)
################################################################################

CreateAvailableBlockIndices()
{
  local total_float="$1"
  local total="${total_float%.*}"
  local num_possible_blocks=$((total / SEGMENT))

  # ceil(num_possible_blocks * 0.1) via integer math.
  local skip=$(((num_possible_blocks + 9) / 10))
  local first_valid="$skip"
  local last_valid=$((num_possible_blocks - skip))

  if [ "$last_valid" -le "$first_valid" ]
  then
    End 1 "Input video is too short to create clips after trimming 10%."
  fi

  local available=()
  local idx
  for (( idx = first_valid; idx < last_valid; idx++ ))
  do
    available+=("$idx")
  done

  if [ "${#available[@]}" -lt "$NUM_SEGMENTS" ]
  then
    LogInfo "Not enough unique ${SEGMENT}-second blocks\
 (${#available[@]}) to fulfill $NUM_SEGMENTS segments."
    NUM_SEGMENTS="${#available[@]}"
  fi

  BLOCK_INDICES=()
  local picked
  while IFS= read -r picked
  do
    BLOCK_INDICES+=("$picked")
  done < <(printf '%s\n' "${available[@]}" | shuf)
}

################################################################################
# Function    : CreateRandomClips
# Description : Extracts NUM_SEGMENTS clips from the input video into
#               CLIPS_FOLDER as clip_000.<ext>, clip_001.<ext>, ... Each clip
#               re-encodes a SEGMENT-second window starting at a popped block
#               index. A failed extraction logs an error and continues
# Parameters  : /
################################################################################

CreateRandomClips()
{
  LogInfo "Generating $NUM_SEGMENTS random ${SEGMENT}-second clips..."
  local i block_index start_time clip
  local available=("${BLOCK_INDICES[@]}")
  for (( i = 0; i < NUM_SEGMENTS; i++ ))
  do
    if [ "${#available[@]}" -eq 0 ]
    then
      LogInfo "No more unique blocks to select from."
      break
    fi
    # Pop the last index, mirroring Python list.pop(). Use index-arithmetic
    # form for compatibility with bash older than 4.3.
    block_index="${available[${#available[@]}-1]}"
    unset "available[$((${#available[@]}-1))]"
    start_time=$((block_index * SEGMENT))
    clip="$CLIPS_FOLDER/clip_$(printf '%03d' "$i")$INPUT_EXT"
    if ! ffmpeg -ss "$start_time" -i "$INPUT_PATH" -t "$SEGMENT" \
      -c:v libx264 -preset ultrafast -crf 18 -an \
      -avoid_negative_ts make_zero -y "$clip" >/dev/null 2>&1
    then
      LogError "Error extracting clip $clip"
      continue
    fi
  done
}

################################################################################
# Function    : GatherClips
# Description : Collects this input's clip files in CLIPS_FOLDER (sorted) into
#               the global ALL_CLIPS array. Matching is restricted to
#               clip_*<INPUT_EXT> names so a stale clip from a different input
#               (e.g. another codec/extension) cannot break the -c copy concat.
#               Ends with error when none are found
# Parameters  : /
################################################################################

GatherClips()
{
  ALL_CLIPS=()
  local clip
  while IFS= read -r clip
  do
    ALL_CLIPS+=("$clip")
  done < <(find "$CLIPS_FOLDER" -maxdepth 1 -type f \
    -name "clip_*$INPUT_EXT" | sort)

  if [ "${#ALL_CLIPS[@]}" -eq 0 ]
  then
    End 1 "No clips found in $CLIPS_FOLDER. Nothing to concatenate."
  fi
}

################################################################################
# Function    : WriteConcatList
# Description : Writes the ffmpeg concat demuxer list file inside CLIPS_FOLDER,
#               one absolute-path entry per clip. Stores the list path in the
#               global CONCAT_LIST_PATH
# Parameters  : /
################################################################################

WriteConcatList()
{
  CONCAT_LIST_PATH="$CLIPS_FOLDER/$CONCAT_LIST_NAME"
  : > "$CONCAT_LIST_PATH"
  local clip abs
  for clip in "${ALL_CLIPS[@]}"
  do
    abs="$(readlink -f "$clip")"
    echo "file '$abs'" >> "$CONCAT_LIST_PATH"
  done
}

################################################################################
# Function    : ConcatenateClips
# Description : Concatenates ALL_CLIPS via the ffmpeg concat demuxer with stream
#               copy into OUTPUT_FOLDER/output_from_<input-basename>. Stores the
#               output path in the global OUTPUT_PATH. Ends with error when
#               ffmpeg exits non-zero
# Parameters  : /
################################################################################

ConcatenateClips()
{
  mkdir -p "$OUTPUT_FOLDER"
  OUTPUT_PATH="$OUTPUT_FOLDER/output_from_$INPUT_NAME"
  LogInfo "Concatenating ${#ALL_CLIPS[@]} clips into $OUTPUT_PATH..."
  if ! ffmpeg -f concat -safe 0 -i "$CONCAT_LIST_PATH" -c copy -y \
    "$OUTPUT_PATH" >/dev/null 2>&1
  then
    End 1 "Concatenation failed."
  fi
}

################################################################################
# Function    : PrintReport
# Description : Prints the closing splice report (input name and duration, clip
#               count, per-clip duration, output path and duration)
# Parameters  : /
################################################################################

PrintReport()
{
  local output_duration in_fmt out_fmt
  output_duration="$(GetVideoDuration "$OUTPUT_PATH")"
  # Match the Python report's %.2f formatting (e.g. 12.48s, not 12.480000s).
  in_fmt="$(printf '%.2f' "$INPUT_DURATION")"
  out_fmt="$(printf '%.2f' "$output_duration")"
  echo ""
  EchoBold "===== Splice Report ====="
  LogInfo "Input video:     $INPUT_NAME"
  LogInfo "Input duration:  ${in_fmt}s"
  LogInfo "Clips generated: ${#ALL_CLIPS[@]}"
  LogInfo "Clip duration:   ${SEGMENT}s each"
  LogInfo "Output file:     $OUTPUT_PATH"
  LogInfo "Output duration: ${out_fmt}s"
  LogInfo "Output location: $(readlink -f "$OUTPUT_PATH")"
  EchoBold "========================="
}

################################################################################
# Function    : HasExistingClips
# Description : Returns success when CLIPS_FOLDER already contains at least one
#               clip file for the current input extension (clip_*<INPUT_EXT>),
#               mirroring the Python resume-from-existing-clips branch while
#               ignoring stale clips from a different input extension
# Parameters  : /
################################################################################

HasExistingClips()
{
  if [ ! -d "$CLIPS_FOLDER" ]
  then
    return 1
  fi
  local clip
  while IFS= read -r clip
  do
    return 0
  done < <(find "$CLIPS_FOLDER" -maxdepth 1 -type f \
    -name "clip_*$INPUT_EXT")
  return 1
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
  ResolveInput

  # Dry-run short-circuit: print the would-be mutations and exit BEFORE any of
  # the read-only seams (GatherClips/WriteConcatList/ConcatenateClips/
  # PrintReport) that depend on artifacts dry-run never creates. INPUT_DURATION
  # is resolved AFTER this block because the would-lines never reference it, so
  # a probe failure on a corrupt/zero-byte input must not abort the preview.
  if [ "$DRY_RUN" -eq 1 ]
  then
    local out_path="$OUTPUT_FOLDER/output_from_$INPUT_NAME"
    if HasExistingClips
    then
      LogInfo "would reuse existing clips in $CLIPS_FOLDER"
    else
      LogInfo "would remove $CLIPS_FOLDER"
      RunOrEcho mkdir -p "$CLIPS_FOLDER"
      # Representative clip-extraction command (one of NUM_SEGMENTS such clips).
      RunOrEcho ffmpeg -ss 0 -i "$INPUT_PATH" -t "$SEGMENT" \
        -c:v libx264 -preset ultrafast -crf 18 -an \
        -avoid_negative_ts make_zero -y \
        "$CLIPS_FOLDER/clip_000$INPUT_EXT"
    fi
    RunOrEcho mkdir -p "$OUTPUT_FOLDER"
    RunOrEcho ffmpeg -f concat -safe 0 -i "$CLIPS_FOLDER/$CONCAT_LIST_NAME" \
      -c copy -y "$out_path"
    LogInfo "would write output to $out_path"
    End 0
  fi

  INPUT_DURATION="$(GetVideoDuration "$INPUT_PATH")"

  if HasExistingClips
  then
    GatherClips
    LogInfo "Found ${#ALL_CLIPS[@]} existing clips in $CLIPS_FOLDER.\
 Skipping clip generation."
  else
    LogInfo "No existing clips found. Generating new clips."
    LogWarn "Removing clips folder: $(readlink -f "$CLIPS_FOLDER")"
    # Confirm before wiping the existing clips folder; bypassed under -y/-n.
    ConfirmOrAbort
    RunOrEcho rm -rf "$CLIPS_FOLDER"
    RunOrEcho mkdir -p "$CLIPS_FOLDER"
    CalculateNumberOfRandomClips "$INPUT_DURATION"
    CreateAvailableBlockIndices "$INPUT_DURATION"
    CreateRandomClips
    GatherClips
  fi

  WriteConcatList
  ConcatenateClips
  PrintReport
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

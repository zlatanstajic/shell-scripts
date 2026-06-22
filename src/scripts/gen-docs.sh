#!/bin/bash

################################################################################
# Script name : gen-docs.sh
# Description : Generate a sanitized flags/usage reference from each script's -h
#               output and inject it into one narrow marked region.
# Parameters  : --check
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################
# Source-of-truth boundary:
#   This generator owns the flags/usage reference: per script, a collapsible
#   <details> block whose summary carries the title and source-file path and
#   whose body is the sanitized -h output. Those per-script collapsible entries
#   in README.md ARE generated (no hand-maintained <details> prose remains
#   there). It does NOT generate or overwrite the docs per-script Parameters
#   tables or the CLAUDE.md architectural notes. Those live outside the markers
#   and are hand-maintained. To change a script's flags/usage, edit that
#   script's Help()/GetArguments and re-run this generator; never hand-edit the
#   generated region.
#
# Marker contract:
#   In README.md the generated reference is written strictly between
#     <!-- BEGIN GENERATED: command-reference -->
#     <!-- END GENERATED: command-reference -->
#   The marker lines and every byte outside them are preserved. The file
#   docs/_includes/command-reference.md is generated in full (no markers).
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source "$SCRIPT_DIR/../lib/common.sh"

set -u

PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

CHECK_MODE=0

MARKER_BEGIN="<!-- BEGIN GENERATED: command-reference -->"
MARKER_END="<!-- END GENERATED: command-reference -->"

README_FILE="$PROJECT_ROOT/README.md"
INCLUDE_FILE="$PROJECT_ROOT/docs/_includes/command-reference.md"

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Generate the flags/usage reference from each script's -h"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Write reference : $SCRIPT_NAME"
  echo "Check drift     : $SCRIPT_NAME --check"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | --check
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
      --check)
        CHECK_MODE=1
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
# Function    : DiscoverScripts
# Description : Populates DISCOVERED_SCRIPTS with every src/scripts/*.sh except
#               this generator, sorted. Uses the same find ... | sort ordering
#               convention used elsewhere in the repo.
# Parameters  : /
################################################################################

DiscoverScripts()
{
  mapfile -t DISCOVERED_SCRIPTS < <(
    find "$PROJECT_ROOT/src/scripts" -maxdepth 1 -name '*.sh' \
      ! -name 'gen-docs.sh' | sort
  )

  [ "${#DISCOVERED_SCRIPTS[@]}" -gt 0 ] || End 1 "No scripts discovered."

  # Defensive: drop the generator even if the find predicate is ever changed.
  local kept=() script
  for script in "${DISCOVERED_SCRIPTS[@]}"
  do
    [ "$(basename "$script")" = "$SCRIPT_NAME" ] && continue
    kept+=("$script")
  done
  DISCOVERED_SCRIPTS=("${kept[@]}")
}

################################################################################
# Function    : CaptureHelp
# Description : Runs a script's -h and returns a sanitized, deterministic body:
#               wrapper banner removed, ANSI stripped, absolute repo path
#               rewritten to <repo-root>, php-switch host-dependent region
#               removed, trailing whitespace trimmed, no trailing blank line.
# Parameters  : script-path
################################################################################

CaptureHelp()
{
  local script="$1"
  local base
  base="$(basename "$script")"

  local raw
  raw="$(bash "$script" -h 2>&1)"

  # 1. Strip the wrapper banner (content-addressed), then collapse the now
  #    leading/trailing blank lines so the body neither starts nor ends blank.
  local body
  body="$(
    printf '%s\n' "$raw" \
      | grep -vE '^Script .* (starting\.\.\.|finishing OK)$' \
      | sed -e '/./,$!d' \
      | sed -e ':a' -e '/^\n*$/{$d;N;ba}'
  )"

  # 2. Strip ANSI escape sequences.
  body="$(printf '%s\n' "$body" | sed -E 's/\x1b\[[0-9;]*m//g')"

  # 3. Rewrite the absolute repo path to a stable placeholder. No-op for
  #    git-copy.sh's literal $GIT_COPY_TARGET_DIRECTORY_PATH token.
  body="$(
    printf '%s\n' "$body" \
      | sed -e "s#${PROJECT_ROOT}#<repo-root>#g"
  )"

  # 4. php-switch.sh ONLY: delete the host-dependent detected/current region,
  #    then collapse any consecutive blank lines the delete left behind so the
  #    rendered block keeps a single blank line like every other section. This
  #    stays host-deterministic: the same blank run forms whether or not PHP
  #    alternatives are detected.
  if [ "$base" = "php-switch.sh" ]
  then
    body="$(
      printf '%s\n' "$body" | awk '
        /^Installed PHP versions:$/ { skip = 1; next }
        skip == 1 {
          if ($0 ~ /^Currently set PHP version:/) { skip = 0; next }
          if ($0 ~ /^[0-9]+\. PHP /) { next }
          skip = 0
        }
        { print }
      ' | cat -s
    )"
  fi

  # 5. Strip trailing whitespace from every line; guarantee no trailing blank
  #    line (final-newline handling happens at render time).
  body="$(
    printf '%s\n' "$body" \
      | sed -E 's/[[:space:]]+$//' \
      | sed -e ':a' -e '/^\n*$/{$d;N;ba}'
  )"

  # Assert no captured line carries a host-specific absolute filesystem path.
  # Return failure (do NOT End) so the caller can abort: End's exit would only
  # kill the innermost command-substitution subshell, letting the outer render
  # continue and capturing the error banner into the published docs. The pattern
  # catches any embedded absolute path (at line start OR preceded by a
  # whitespace/(/=/:/quote); the legitimate <repo-root> placeholder (no leading
  # /) passes, and the repo-root rewrite above runs first so only real leaks
  # remain. The generic, host-independent documentation placeholder "/path/to/"
  # is masked for the check only (it is a stable literal, not a leak) so example
  # usage lines like "-d /path/to/dir" keep rendering.
  local probe
  probe="$(printf '%s\n' "$body" | sed -e 's#/path/to/#<path>/#g')"
  if printf '%s\n' "$probe" \
    | grep -qE '(^|[[:space:](=:"'\''])/[A-Za-z0-9._-]+/'
  then
    LogError "Absolute path leaked in $base -h output after sanitization." >&2
    return 1
  fi

  printf '%s\n' "$body"
}

################################################################################
# Function    : ScriptTitle
# Description : Derives a human heading from a script basename
#               (e.g. restore-vscode-folder.sh -> "Restore VSCode Folder").
#               Known acronyms render with their canonical casing via an
#               override map; everything else is title-cased word by word.
# Parameters  : script-basename
################################################################################

ScriptTitle()
{
  local base="$1"
  local stem="${base%.sh}"
  declare -A overrides=(
    [php]="PHP"
    [vscode]="VSCode"
  )
  local word title=""
  local IFS='-'
  for word in $stem
  do
    if [ -n "${overrides[$word]+set}" ]
    then
      title+="${overrides[$word]} "
    else
      title+="${word^} "
    fi
  done
  printf '%s' "${title% }"
}

################################################################################
# Function    : RenderReference
# Description : Renders the canonical flags/usage reference for every discovered
#               script in sorted order. Each section is a collapsible <details>
#               block whose summary carries the human title and source path and
#               whose body is the sanitized -h output in a fenced text block.
#               markdown="1" + the surrounding blank lines let the fenced body
#               render on BOTH GitHub and the kramdown Jekyll site. This SAME
#               output feeds the README region and the docs include, so the two
#               cannot diverge. Output is whitespace-clean (no trailing
#               whitespace, exactly one final newline).
# Parameters  : /
################################################################################

RenderReference()
{
  local script base title rel first=1
  for script in "${DISCOVERED_SCRIPTS[@]}"
  do
    base="$(basename "$script")"
    title="$(ScriptTitle "$base")"
    rel="src/scripts/$base"

    [ "$first" -eq 1 ] || printf '\n'
    first=0

    printf '<details markdown="1">\n'
    printf '<summary><strong>%s</strong> — <code>%s</code></summary>\n' \
      "$title" "$rel"
    printf '\n'
    printf '```text\n'
    CaptureHelp "$script" || return 1
    printf '```\n'
    printf '\n'
    printf '</details>\n'
  done
}

################################################################################
# Function    : AssertMarkers
# Description : Ends with an error unless the given file carries exactly one
#               BEGIN and one END marker with BEGIN strictly before END (a count
#               check alone would pass an END-before-BEGIN file that mangles on
#               inject/extract).
# Parameters  : file
################################################################################

AssertMarkers()
{
  local file="$1"

  local begin end
  begin="$(grep -cF "$MARKER_BEGIN" "$file")"
  end="$(grep -cF "$MARKER_END" "$file")"
  if [ "$begin" -ne 1 ] || [ "$end" -ne 1 ]
  then
    LogError "$file: found $begin BEGIN / $end END marker(s)."
    End 1 "$file must contain exactly one BEGIN and one END marker."
  fi

  local begin_line end_line
  begin_line="$(grep -nF "$MARKER_BEGIN" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -nF "$MARKER_END" "$file" | head -n 1 | cut -d: -f1)"
  if [ "$begin_line" -ge "$end_line" ]
  then
    End 1 "$file: BEGIN marker must come before END marker."
  fi
}

################################################################################
# Function    : InjectInto
# Description : Replaces the content strictly between the BEGIN/END markers in
#               the given file with the freshly rendered reference, preserving
#               the marker lines and every byte outside them. Ends with an error
#               when the file lacks exactly one BEGIN and one END marker.
# Parameters  : file rendered-reference
################################################################################

InjectInto()
{
  local file="$1"
  local rendered="$2"

  AssertMarkers "$file"

  local tmp
  tmp="$(mktemp)"
  if awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v block="$rendered" '
    $0 == begin { print; printf "\n%s\n", block; skip = 1; next }
    $0 == end   { skip = 0 }
    skip != 1   { print }
  ' "$file" > "$tmp"
  then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    End 1 "Inject failed for $file."
  fi
}

################################################################################
# Function    : ExtractRegion
# Description : Prints the content strictly between the BEGIN/END markers of the
#               given file (markers and surrounding blank padding excluded), so
#               it can be diffed against freshly rendered output in --check.
# Parameters  : file
################################################################################

ExtractRegion()
{
  AssertMarkers "$1"

  # Print the lines strictly between the markers, then strip the single blank
  # line of padding InjectInto adds on each side so the result equals the block
  # (which itself never starts or ends with a blank line).
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == end   { skip = 0 }
    skip == 1   { print }
    $0 == begin { skip = 1 }
  ' "$1" \
    | sed -e '/./,$!d' \
    | sed -e ':a' -e '/^\n*$/{$d;N;ba}'
}

################################################################################
# Function    : DiffFiles
# Description : Diffs two files, preferring git diff --no-index (falls back to
#               diff -u when git is unavailable). Returns the diff tool's exit
#               status (non-zero when the files differ).
# Parameters  : expected-file actual-file
################################################################################

DiffFiles()
{
  if command -v git &> /dev/null
  then
    git --no-pager diff --no-index --no-color --exit-code "$1" "$2"
  else
    diff -u "$1" "$2"
  fi
}

################################################################################
# Function    : WriteReference
# Description : Write mode. Renders once, injects into README.md, and writes the
#               full docs include (creating docs/_includes/ if absent).
# Parameters  : rendered-reference
################################################################################

WriteReference()
{
  local rendered="$1"

  InjectInto "$README_FILE" "$rendered"

  mkdir -p "$(dirname "$INCLUDE_FILE")"
  printf '%s\n' "$rendered" > "$INCLUDE_FILE"

  LogInfo "Wrote reference to $README_FILE and $INCLUDE_FILE."
}

################################################################################
# Function    : CheckReference
# Description : Check mode (no writes). Compares the freshly rendered reference
#               against the committed README region and the docs include. Ends
#               with an error naming each stale file; ends OK when both match.
# Parameters  : rendered-reference
################################################################################

CheckReference()
{
  local rendered="$1"
  local stale=()

  local fresh readme_region
  fresh="$(mktemp)"
  readme_region="$(mktemp)"
  printf '%s\n' "$rendered" > "$fresh"

  ExtractRegion "$README_FILE" > "$readme_region"
  if ! DiffFiles "$readme_region" "$fresh" > /dev/null 2>&1
  then
    stale+=("$README_FILE")
  fi

  if [ -f "$INCLUDE_FILE" ]
  then
    if ! DiffFiles "$INCLUDE_FILE" "$fresh" > /dev/null 2>&1
    then
      stale+=("$INCLUDE_FILE")
    fi
  else
    stale+=("$INCLUDE_FILE (missing)")
  fi

  rm -f "$fresh" "$readme_region"

  if [ "${#stale[@]}" -gt 0 ]
  then
    local file
    for file in "${stale[@]}"
    do
      LogError "Stale generated reference: $file"
    done
    End 1 "Generated docs are out of date. Run: bash src/scripts/$SCRIPT_NAME"
  fi

  LogInfo "Generated reference is up to date."
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  DiscoverScripts

  local rendered
  rendered="$(RenderReference)" \
    || End 1 "Failed to render reference (capture error)."

  if [ "$CHECK_MODE" -eq 1 ]
  then
    CheckReference "$rendered"
  else
    WriteReference "$rendered"
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

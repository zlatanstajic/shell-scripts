#!/bin/bash

################################################################################
# Script name : my-scripts.sh
# Description : List custom commands from shell-scripts and python_scripts
# Parameters  : [-f filter]
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

# This script deliberately does NOT source $PROJECT_ROOT/.env: it is read-only
# and its single external input is the EXPORTED environment variable below.
# Setting MY_SCRIPTS_PYTHON_REPO_PATH in .env therefore has no effect.
PYTHON_REPO_PATH="${MY_SCRIPTS_PYTHON_REPO_PATH:-$HOME/repos/python_scripts}"

FILTER=""
MATCH_COUNT=0

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: List the custom commands provided by the shell-scripts"
  echo "and python_scripts repositories, each with a one-line description and"
  echo "whether it currently resolves on PATH."
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo ""
  echo "  -f, --filter  Only list commands whose NAME contains this text"
  echo "                (case-insensitive substring match, optional)"
  echo "  -h, --help    Show this help"
  echo ""
  echo "The shell-scripts location is derived from this script's own path and"
  echo "is never configurable. The python_scripts location comes from the"
  echo "EXPORTED environment variable MY_SCRIPTS_PYTHON_REPO_PATH (default:"
  echo "\$HOME/repos/python_scripts). It is NOT a .env key - this script never"
  echo "reads .env, so setting it there has no effect. When that repository is"
  echo "missing, its section is skipped with a warning."
  echo ""
  echo "python_scripts commands are console entry points installed inside that"
  echo "repository's virtualenv, so they read as [not on PATH] unless the"
  echo "virtualenv is active. Shell commands read as [not on PATH] until"
  echo "install.sh has linked them onto PATH."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | [-f filter]
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
      -f|--filter)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        FILTER="$2"
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
# Function    : ExcludedFromListing
# Description : Returns 0 when the given script basename is NOT a user-facing
#               command. Mirrors install.sh's EXCLUDE_NAMES=("gen-docs.sh"):
#               install.sh remains the source of truth for the exclusion, so
#               keep the two in sync when it changes.
# Parameters  : script-basename
################################################################################

ExcludedFromListing()
{
  case "$1" in
    gen-docs.sh)
      return 0
      ;;
  esac
  return 1
}

################################################################################
# Function    : HeaderDescription
# Description : Prints the text of the FIRST "# Description :" line of a script.
#               The match is anchored at line start and limited to the leading
#               header comment block, so a "# Description :" line inside a
#               function's comment box can never win. A header that wraps onto a
#               continuation line is truncated to its first line by design.
# Parameters  : script-path
################################################################################

HeaderDescription()
{
  sed -n '1,20{s/^# Description : //p}' "$1" | head -n 1
}

################################################################################
# Function    : ListShellScriptCommands
# Description : Prints one "<name>\t<description>" line per user-facing script
#               in src/scripts/, sorted, under its bare command name (basename
#               minus .sh). Uses the same find ... | sort ordering convention as
#               gen-docs.sh.
# Parameters  : /
################################################################################

ListShellScriptCommands()
{
  local script base
  while IFS= read -r script
  do
    base="$(basename "$script")"
    if ExcludedFromListing "$base"
    then
      continue
    fi
    printf '%s\t%s\n' "${base%.sh}" "$(HeaderDescription "$script")"
  done < <(find "$PROJECT_ROOT/src/scripts" -maxdepth 1 -name '*.sh' | sort)
}

################################################################################
# Function    : ExtractPythonEntryPoints
# Description : Prints one "<command-name>\t<module-path>" line per entry of the
#               [project.scripts] table of the given pyproject.toml. Parsed with
#               awk, not a TOML parser: the table is read from its exact header
#               line until the next line opening a table, and only plain
#               name = "module.path:function" entries are understood. Anything
#               else yields no output, which the caller degrades to a warning.
# Parameters  : pyproject-path
################################################################################

ExtractPythonEntryPoints()
{
  awk '
    /^[[:space:]]*\[/ {
      in_table = ($0 ~ /^[[:space:]]*\[project\.scripts\][[:space:]]*$/)
      next
    }
    in_table != 1 { next }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      if (line !~ /=/) { next }
      name = line
      sub(/=.*$/, "", name)
      gsub(/[[:space:]]|"/, "", name)
      value = line
      sub(/^[^=]*=/, "", value)
      gsub(/[[:space:]]|"/, "", value)
      module = value
      sub(/:.*$/, "", module)
      if (name == "" || module == "") { next }
      printf "%s\t%s\n", name, module
    }
  ' "$1"
}

################################################################################
# Function    : ModuleDocstringSummary
# Description : Prints the first line of the leading """ docstring of the module
#               a python entry point points at (scripts.cv_generator resolves to
#               <python-repo>/scripts/cv_generator.py). A missing file or
#               docstring yields an empty description rather than an error.
# Parameters  : module-path
################################################################################

ModuleDocstringSummary()
{
  local file="$PYTHON_REPO_PATH/${1//./\/}.py"
  if [ ! -f "$file" ] || [ ! -r "$file" ]
  then
    return 0
  fi
  local summary
  summary="$(
    sed -n -e 's/^[[:space:]]*[rRuUbB]*"""//p' -e '/"""/q' "$file" | head -n 1
  )"
  summary="${summary%\"\"\"}"
  printf '%s' "$summary"
}

################################################################################
# Function    : ListPythonCommands
# Description : Prints one "<name>\t<description>" line per [project.scripts]
#               entry of the python_scripts repository. A missing or unreadable
#               pyproject.toml, and an absent or empty [project.scripts] table,
#               each warn ONCE and return without output so the caller omits the
#               section and still ends OK. The warning goes to STDERR (as
#               gen-docs.sh does) so it can never be read back as an entry line.
# Parameters  : /
################################################################################

ListPythonCommands()
{
  local pyproject="$PYTHON_REPO_PATH/pyproject.toml"
  local message
  if [ ! -f "$pyproject" ] || [ ! -r "$pyproject" ]
  then
    message="No readable pyproject.toml at $pyproject - skipping the"
    message="$message python_scripts section (point"
    message="$message MY_SCRIPTS_PYTHON_REPO_PATH at that repository)."
    LogWarn "$message" >&2
    return 0
  fi

  local entries
  entries="$(ExtractPythonEntryPoints "$pyproject")"
  if [ -z "$entries" ]
  then
    message="No [project.scripts] entries found in $pyproject - skipping the"
    message="$message python_scripts section (point"
    message="$message MY_SCRIPTS_PYTHON_REPO_PATH at that repository)."
    LogWarn "$message" >&2
    return 0
  fi

  local name module
  while IFS=$'\t' read -r name module
  do
    printf '%s\t%s\n' "$name" "$(ModuleDocstringSummary "$module")"
  done <<< "$entries"
}

################################################################################
# Function    : PathMarker
# Description : Prints the ASCII marker telling whether the given command name
#               currently resolves on PATH. Nothing is executed: only looked up.
# Parameters  : command-name
################################################################################

PathMarker()
{
  if command -v "$1" >/dev/null 2>&1
  then
    printf '[on PATH]'
  else
    printf '[not on PATH]'
  fi
}

################################################################################
# Function    : MatchesFilter
# Description : Returns 0 when no filter is set, or when the given command NAME
#               contains the filter as a case-insensitive substring.
#               Descriptions are never matched.
# Parameters  : command-name
################################################################################

MatchesFilter()
{
  if [ -z "$FILTER" ]
  then
    return 0
  fi
  local name="${1,,}"
  local needle="${FILTER,,}"
  case "$name" in
    *"$needle"*)
      return 0
      ;;
  esac
  return 1
}

################################################################################
# Function    : RenderSection
# Description : Renders one repository section from "<name>\t<description>"
#               lines read on STDIN: a bold heading naming the repository and
#               its resolved path, then one indented "name marker description"
#               line per command that passes the filter. A section whose entries
#               are all filtered out prints nothing at all, and the blank
#               separator line is printed only between two rendered sections.
#               MATCH_COUNT accumulates the rendered entries for the caller.
# Parameters  : heading repository-path
################################################################################

RenderSection()
{
  local heading="$1"
  local path="$2"

  local lines=()
  local name description
  while IFS=$'\t' read -r name description
  do
    if ! MatchesFilter "$name"
    then
      continue
    fi
    lines+=("$(
      printf '  %-24s %-14s %s' "$name" "$(PathMarker "$name")" "$description"
    )")
  done

  if [ "${#lines[@]}" -eq 0 ]
  then
    return 0
  fi

  if [ "$MATCH_COUNT" -gt 0 ]
  then
    echo ""
  fi
  MATCH_COUNT=$((MATCH_COUNT + ${#lines[@]}))

  EchoBold "$heading ($path)"
  local line
  for line in "${lines[@]}"
  do
    LogInfo "$line"
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

  # Both sections read their entries from a process substitution so the loop
  # (and MATCH_COUNT) stays in the current shell.
  RenderSection "shell-scripts" "$PROJECT_ROOT" < <(ListShellScriptCommands)
  RenderSection "python_scripts" "$PYTHON_REPO_PATH" < <(ListPythonCommands)

  if [ "$MATCH_COUNT" -eq 0 ] && [ -n "$FILTER" ]
  then
    LogWarn "No command name matched the filter: $FILTER"
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

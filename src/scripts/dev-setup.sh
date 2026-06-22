#!/bin/bash

################################################################################
# Script name : dev-setup.sh
# Description : Development setup for git
# Parameters  : number name
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

ISSUE_NUMBER=""
ISSUE_NAME=""

# Defaults (overridden by $PROJECT_ROOT/.env when present)
BRANCH_PREFIX="issues"
REQUEST_PREFIX="refs:"
ISSUE_BASE_PATH=""
GITLAB_ASSIGNEE_ID=""

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
  echo "Description: Development setup for git"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME -nu 1 -na \"Example issue name\""
  echo ""
  echo "  -nu, --number   Issue number (required)"
  echo "  -na, --name     Issue name (required)"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -nu number -na name
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
      -nu|--number)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        ISSUE_NUMBER="$2"
        shift 2
        ;;
      -na|--name)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        ISSUE_NAME="$2"
        shift 2
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done

  if [ -z "$ISSUE_NUMBER" ] || [ -z "$ISSUE_NAME" ]
  then
    Help
    MissingRequiredArguments
  fi
}

################################################################################
# Function    : IsDirectoryGitRepository
# Description : Checks if directory is git repository
# Parameters  : /
################################################################################

IsDirectoryGitRepository()
{
  if [ ! -d .git ]
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
  CURRENT_WORKING_DIRECTORY=$(pwd)
  DIRECTORY_NAME=$(basename "$CURRENT_WORKING_DIRECTORY")
  echo -e "Located in directory: \e[1m$DIRECTORY_NAME\e[0m\n"
}

################################################################################
# Function    : IssueNameForBranch
# Description : Converts issue name for branch (rejects digits, applies map)
# Parameters  : issue-name
################################################################################

IssueNameForBranch()
{
  local name="$1"

  if [[ "$name" =~ [0-9] ]]
  then
    End 1 "Issue name cannot contain numbers."
  fi

  name="${name// /_}"
  name="${name//&/_and_}"
  name="${name//|/_-_}"
  name="${name//./_dot_}"
  name="${name//\//_forward-slash_}"

  echo "${name,,}"
}

################################################################################
# Function    : SelectBranch
# Description : Lists branches enumerated and resolves a numeric pick
# Parameters  : /
################################################################################

SelectBranch()
{
  local branches=()
  local line
  while IFS= read -r line
  do
    line="${line//\*/}"
    line="$(echo "$line" | sed 's/^ *//;s/ *$//')"
    [ -n "$line" ] && branches+=("$line")
  done < <(git branch --list)

  if [ ${#branches[@]} -eq 0 ]
  then
    End 1 "Unable to list git branches."
  fi

  LogInfo "Available branches:"
  local i
  for i in "${!branches[@]}"
  do
    LogInfo "$((i + 1)). ${branches[$i]}"
  done

  local choice
  choice=$(UserInput $'\nSelect the branch number to create new branch from')

  if ! [[ "$choice" =~ ^[0-9]+$ ]]
  then
    End 1 "Invalid input. Please enter a number."
  fi

  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#branches[@]}" ]
  then
    End 1 "Invalid selection. Please enter a valid number."
  fi

  SOURCE_BRANCH="${branches[$((choice - 1))]}"
}

################################################################################
# Function    : GetGitLabProjectUrl
# Description : Derives the GitLab project web URL from origin remote
# Parameters  : /
################################################################################

GetGitLabProjectUrl()
{
  local remote
  remote=$(git config --get remote.origin.url 2>/dev/null)
  [ -z "$remote" ] && return

  remote="${remote%.git}"

  if [[ "$remote" == https://* ]] || [[ "$remote" == http://* ]]
  then
    local rest="${remote#*://}"
    local host="${rest%%/*}"
    local path="${rest#*/}"
    if [ -n "$host" ] && [ "$path" != "$rest" ] && [ -n "$path" ]
    then
      echo "https://$host/$path"
    fi
    return
  fi

  if [[ "$remote" == git@* ]]
  then
    local host_and_path="${remote#git@}"
    local host="${host_and_path%%:*}"
    local path="${host_and_path#*:}"
    if [ -n "$host" ] && [ "$path" != "$host_and_path" ] && [ -n "$path" ]
    then
      echo "https://$host/$path"
    fi
    return
  fi
}

################################################################################
# Function    : BuildMergeRequestUrl
# Description : Builds a prefilled GitLab merge-request-create URL
# Parameters  : project-url source-branch title description
################################################################################

BuildMergeRequestUrl()
{
  local project_url="$1"
  local source_branch="$2"
  local title="$3"
  local description="$4"

  [ -z "$project_url" ] && return

  local url="$project_url/-/merge_requests/new"
  url+="?$(UrlEncode 'merge_request[source_branch]')=$(UrlEncode "$source_branch")"
  url+="&$(UrlEncode 'merge_request[title]')=$(UrlEncode "$title")"
  url+="&$(UrlEncode 'merge_request[description]')=$(UrlEncode "$description")"
  if [ -n "$GITLAB_ASSIGNEE_ID" ]
  then
    url+="&$(UrlEncode 'merge_request[assignee_ids][]')=$(UrlEncode "$GITLAB_ASSIGNEE_ID")"
  fi

  echo "$url"
}

################################################################################
# Function    : HandleMergeRequestUrl
# Description : Logs the merge request URL and opens it via xdg-open
# Parameters  : url
################################################################################

HandleMergeRequestUrl()
{
  local url="$1"
  if [ -z "$url" ]
  then
    LogWarn "Could not build a GitLab merge request URL (origin remote is not a recognized GitLab remote)."
    return
  fi

  LogInfo ""
  LogInfo "Merge request URL:"
  LogInfo ""
  LogInfo "$url"

  if command -v xdg-open &> /dev/null
  then
    xdg-open "$url" &> /dev/null
  else
    LogWarn "xdg-open could not be found. Open the URL above manually."
  fi
}

################################################################################
# Function    : HandleCopyToClipboard
# Description : Copies message name (and description when present) to clipboard
# Parameters  : message-name message-description
################################################################################

HandleCopyToClipboard()
{
  local message_name="$1"
  local message_description="$2"

  if ! command -v xclip &> /dev/null
  then
    LogWarn "xclip could not be found. Please install xclip to enable clipboard copy."
    return
  fi

  if [ -n "$message_description" ]
  then
    echo -n "$message_description" | xclip -selection clipboard
    LogInfo ""
    LogInfo "Copied message description to the clipboard:"
    LogInfo ""
    LogInfo "$message_description"
  fi
  echo -n "$message_name" | xclip -selection clipboard
  LogInfo ""
  LogInfo "Copied message name info to the clipboard:"
  LogInfo ""
  LogInfo "$message_name"
}

################################################################################
# Function    : BuildMessageDescription
# Description : Builds the message description, with GitHub issue-path autodetect
# Parameters  : /
################################################################################

BuildMessageDescription()
{
  [ -z "$ISSUE_BASE_PATH" ] && return

  local value="$ISSUE_BASE_PATH"
  if [[ "$ISSUE_BASE_PATH" == https://github.com/* ]]
  then
    local trimmed="${ISSUE_BASE_PATH%/}"
    # Count path segments: https://github.com/username -> 4 parts
    local IFS='/'
    local parts
    read -ra parts <<< "$trimmed"
    if [ "${#parts[@]}" -eq 4 ]
    then
      value="$trimmed/$(basename "$(pwd)")/issues"
    else
      LogWarn "Couldn't determine GitHub issue path from: $ISSUE_BASE_PATH"
    fi
  fi

  echo "Based on $BRANCH_PREFIX [#$ISSUE_NUMBER]($value/$ISSUE_NUMBER)"
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

  SelectBranch
  local sanitized
  sanitized=$(IssueNameForBranch "$ISSUE_NAME")
  TARGET_BRANCH="${BRANCH_PREFIX}/${ISSUE_NUMBER}_${sanitized}"

  echo -e "Will create branch \e[1m$TARGET_BRANCH\e[0m from \e[1m$SOURCE_BRANCH\e[0m"
  echo ""

  if [ "$(DoYouWishToProceed)" -ne 1 ]
  then
    End 0
  fi

  git checkout "$SOURCE_BRANCH" || End 1 "Not able to checkout to the $SOURCE_BRANCH"
  git pull || End 1 "Not able to pull latest changes for $SOURCE_BRANCH"
  git branch "$TARGET_BRANCH" || End 1 "Not able to create branch $TARGET_BRANCH"
  git checkout "$TARGET_BRANCH" || End 1 "Not able to checkout to the $TARGET_BRANCH"

  echo ""
  echo "Will push local branch to remote"

  if [ "$(DoYouWishToProceed)" -eq 1 ]
  then
    git push -u origin "$TARGET_BRANCH"

    local message_name="$REQUEST_PREFIX #$ISSUE_NUMBER $ISSUE_NAME"
    local message_description
    message_description=$(BuildMessageDescription)

    HandleCopyToClipboard "$message_name" "$message_description"
    HandleMergeRequestUrl "$(BuildMergeRequestUrl "$(GetGitLabProjectUrl)" "$TARGET_BRANCH" "$message_name" "$message_description")"
  else
    git checkout "$SOURCE_BRANCH"
    git branch -D "$TARGET_BRANCH"
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

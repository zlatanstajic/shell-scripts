#!/bin/bash

################################################################################
# Script name : tampermonkey-install.sh
# Description : Build a GitHub userscript URL and open it for Tampermonkey
# Parameters  : [-d domain] [-s script] [-r base-url]
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

DOMAIN_NAME=""
SCRIPT_USER_NAME=""
REPO_BASE_OVERRIDE=""
URL=""

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
  echo "Description: Build a GitHub userscript URL and open it for Tampermonkey"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME -d <domain> -s <script>"
  echo ""
  echo "  -d, --domain   Domain-name folder (required, e.g. youtube.com)"
  echo "  -s, --script   Script name, no extension (required, e.g. video-speed)"
  echo "  -r, --repo     Override the configured GitHub base URL (optional)"
  echo "  -h, --help     Show this help and exit"
  echo ""
  echo "Base URL(s) read from TAMPERMONKEY_REPO_BASE_URLS in"
  echo "<repo-root>/.env (see .env.example). A comma-separated list is"
  echo "probed with curl (redirects followed); the first URL answering"
  echo "HTTP 2xx is opened, else the first entry. Private GitHub repos"
  echo "need GH_TOKEN/GITHUB_TOKEN or 'gh' for the probe to see them."
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | [-d domain] [-s script] [-r base-url]
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
      -d|--domain)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        DOMAIN_NAME="$2"
        shift 2
        ;;
      -s|--script)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        SCRIPT_USER_NAME="$2"
        shift 2
        ;;
      -r|--repo)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        REPO_BASE_OVERRIDE="$2"
        shift 2
        ;;
      *)
        Help
        End 1 "Unknown argument: $1"
        ;;
    esac
  done

  if [ -z "$DOMAIN_NAME" ] || [ -z "$SCRIPT_USER_NAME" ]
  then
    Help
    MissingRequiredArguments
  fi
}

################################################################################
# Function    : BuildCandidateUrl
# Description : Strips a trailing slash from base, validates the URL scheme,
#               then echoes <base>/<domain>/<script>.user.js. Exits 1 on an
#               invalid scheme. Domain/script are validated by the caller
# Parameters  : base
################################################################################

BuildCandidateUrl()
{
  local base="${1%/}"
  if ! [[ "$base" =~ ^https?:// ]]
  then
    End 1 "Invalid base URL '$base' (expected http(s)://...)."
  fi
  local script_name="${SCRIPT_USER_NAME%.user.js}"
  echo "$base/$DOMAIN_NAME/$script_name.user.js"
}

################################################################################
# Function    : GitHubToken
# Description : Echoes a GitHub token for authenticating probe requests, trying
#               $GH_TOKEN, then $GITHUB_TOKEN, then `gh auth token`. Echoes an
#               empty string when none is available. Needed because userscript
#               repos are often private: an unauthenticated probe sees 404 for
#               every candidate and the selection collapses to the first one
# Parameters  : /
################################################################################

GitHubToken()
{
  if [ -n "${GH_TOKEN:-}" ]
  then
    echo "$GH_TOKEN"
  elif [ -n "${GITHUB_TOKEN:-}" ]
  then
    echo "$GITHUB_TOKEN"
  elif command -v gh >/dev/null 2>&1
  then
    gh auth token 2>/dev/null
  fi
}

################################################################################
# Function    : ProbeAndSelectUrl
# Description : Probes each candidate URL with curl --head, following redirects
#               (5 s timeout), and echoes the first that returns an HTTP 2xx
#               status. Redirects matter: github.com /raw/ URLs answer HEAD with
#               a 302 to raw.githubusercontent.com, so the final status (not the
#               redirect) is what decides reachability. For github.com
#               candidates a GitHub token (when found) is sent so private repos
#               probe accurately; the token reaches github.com only (curl drops
#               the Authorization header on the cross-host redirect, but the
#               redirect URL is already signed). Falls back to the first
#               candidate when none return 2xx or curl is absent
# Parameters  : candidate1 [candidate2 ...]
################################################################################

ProbeAndSelectUrl()
{
  if ! command -v curl >/dev/null 2>&1
  then
    LogWarn "curl not available — skipping URL probe" >&2
    echo "$1"
    return
  fi

  local token
  token="$(GitHubToken)"
  if [ -z "$token" ]
  then
    LogWarn "No GitHub token — private repos will probe as 404" >&2
  fi

  local first="$1"
  local candidate
  for candidate in "$@"
  do
    local -a auth=()
    if [ -n "$token" ] && [[ "$candidate" =~ ^https://github\.com/ ]]
    then
      auth=(--header "Authorization: Bearer $token")
    fi

    local status
    status="$(curl --silent --location --head --max-time 5 --output /dev/null \
      "${auth[@]+"${auth[@]}"}" --write-out "%{http_code}" "$candidate")"
    if [[ "$status" =~ ^2[0-9][0-9]$ ]]
    then
      echo "$candidate"
      return
    fi
  done

  LogWarn "No URL returned HTTP 2xx — using first" >&2
  echo "$first"
}

################################################################################
# Function    : BuildUrl
# Description : Validates domain/script inputs, then resolves the final URL.
#               When -r is given it short-circuits to a single candidate (no
#               probing). When TAMPERMONKEY_REPO_BASE_URLS holds multiple
#               comma-separated bases the script probes each in order and
#               selects the first reachable (HTTP 2xx). A single base skips
#               probing
# Parameters  : /
################################################################################

BuildUrl()
{
  if ! [[ "$DOMAIN_NAME" =~ ^[A-Za-z0-9._-]+$ ]]
  then
    End 1 "Invalid domain '$DOMAIN_NAME' (allowed: A-Z a-z 0-9 . _ -)."
  fi
  if ! [[ "$SCRIPT_USER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]
  then
    End 1 "Invalid script '$SCRIPT_USER_NAME' (allowed: A-Z a-z 0-9 . _ -)."
  fi

  if [ -n "$REPO_BASE_OVERRIDE" ]
  then
    URL="$(BuildCandidateUrl "$REPO_BASE_OVERRIDE")"
    return
  fi

  local bases_raw="${TAMPERMONKEY_REPO_BASE_URLS:-}"
  if [ -z "$bases_raw" ]
  then
    End 1 "No base URL. Set TAMPERMONKEY_REPO_BASE_URLS in .env or use -r."
  fi
  local bases
  IFS=',' read -ra bases <<< "$bases_raw"

  if [ "${#bases[@]}" -le 1 ]
  then
    URL="$(BuildCandidateUrl "${bases[0]}")"
    return
  fi

  local candidates=()
  local base
  for base in "${bases[@]}"
  do
    candidates+=("$(BuildCandidateUrl "$base")")
  done

  URL="$(ProbeAndSelectUrl "${candidates[@]}")"
}

################################################################################
# Function    : OpenUrl
# Description : Opens the final URL with xdg-open when present (logging it
#               once). xdg-open is launched fully detached so it returns the
#               terminal immediately instead of staying attached to an existing
#               browser session (which would otherwise hold the prompt until
#               Ctrl-C): I/O is redirected and the process is disowned, run via
#               setsid when available (new session) else nohup. When xdg-open is
#               absent it warns and prints the URL for manual use, never ending
#               in error
# Parameters  : /
################################################################################

OpenUrl()
{
  if command -v xdg-open >/dev/null 2>&1
  then
    LogInfo "Opening $URL"
    if command -v setsid >/dev/null 2>&1
    then
      setsid xdg-open "$URL" </dev/null >/dev/null 2>&1 &
    else
      nohup xdg-open "$URL" </dev/null >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
  else
    LogWarn "xdg-open not available; open this URL manually:"
    LogInfo "$URL"
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
  BuildUrl
  OpenUrl
  End 0
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

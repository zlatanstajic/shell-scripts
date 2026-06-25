#!/bin/bash

################################################################################
# Script name : rain-alert.sh
# Description : Email a rain alert when MET Norway forecasts rain for any of a
#               configured list of cities within a lookahead window
# Parameters  : [-n dry-run] [-d display-only]
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

# Defaults. Each uses ${VAR:=default} so a value already present in the
# environment (or set later by $PROJECT_ROOT/.env, which is sourced below and
# wins over these built-ins) is preserved. RAIN_ALERT_CITIES is a SCALAR string
# of whitespace/comma-separated "name:lat:lon" entries (a scalar documents
# cleanly in .env and lets the environment inject cities); ParseCities splits it
# into the working array.
: "${RAIN_ALERT_CITIES:=Belgrade:44.7866:20.4489 Berlin:52.52:13.405}"
: "${RAIN_ALERT_LOOKAHEAD_HOURS:=24}"
: "${RAIN_ALERT_PRECIP_THRESHOLD_MM:=0}"
: "${RAIN_ALERT_RECIPIENT:=}"
: "${RAIN_ALERT_MSMTP_ACCOUNT:=}"
: "${RAIN_ALERT_USER_AGENT:=shell-scripts rain-alert (contact@zlatanstajic.com)}"
: "${RAIN_ALERT_THROTTLE_SECONDS:=1}"
: "${RAIN_ALERT_CACHE_FILE:=$HOME/.cache/rain-alert/last-alert.txt}"

# .env is sourced as a shell script (plain KEY=VALUE assignments expected),
# not parsed; any valid shell in it will be executed.
if [ -f "$PROJECT_ROOT/.env" ]
then
  source "$PROJECT_ROOT/.env"
fi

# Dry-run / assume-yes flags (CLI only). Declared AFTER the .env source so a
# stray .env var cannot pin the mode.
DRY_RUN=0
# shellcheck disable=SC2034  # read by ConfirmOrAbort in common.sh
ASSUME_YES=0
# Display-only mode (CLI only): print the forecast result to stdout and send
# nothing. Needs neither a recipient nor msmtp, and never touches the cache.
DISPLAY_ONLY=0

# met.no Locationforecast 2.0 compact endpoint.
API_BASE="https://api.met.no/weatherapi/locationforecast/2.0/compact"

# Accumulators populated during the run: parallel arrays of rainy city names and
# their human-readable "when rain is expected" detail blocks.
RAINY_CITIES=()
RAINY_DETAILS=()

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Email a rain alert when MET Norway forecasts rain for any"
  echo "             configured city within a lookahead window"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME"
  echo "Preview email   : $SCRIPT_NAME -n"
  echo "Display only    : $SCRIPT_NAME -d"
  echo ""
  echo "  -h, --help        Show this help and exit"
  echo "  -n, --dry-run     Print the email that WOULD be sent; send nothing"
  echo "  -d, --display     Print the forecast result to stdout and exit; send"
  echo "                    no email (needs no recipient or msmtp; ignores cache)"
  echo ""
  echo "Configuration is read from $PROJECT_ROOT/.env (see .env.example)."
  echo "RAIN_ALERT_RECIPIENT is required. Cities are queried against the MET"
  echo "Norway Locationforecast 2.0 compact API; no rain anywhere => no email"
  echo "(cron-noise-free). A last-alert cache de-dupes unchanged forecasts."
  echo ""
  echo "Mail is sent via msmtp (a hard dependency for a real send). Without"
  echo "msmtp you can pipe the composed message to curl instead, e.g.:"
  echo "  curl --ssl-reqd --mail-from you@example.com --mail-rcpt rcpt@x \\"
  echo "    --upload-file msg.txt --user you@example.com:pass smtps://host:465"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -n
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
      -d|--display)
        DISPLAY_ONLY=1
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
# Function    : CheckDependencies
# Description : Hard-checks for jq (parsing) and curl (fetching), which are
#               required to determine whether rain is expected at all. Ends with
#               an error when either is missing.
# Parameters  : /
################################################################################

CheckDependencies()
{
  if ! command -v jq >/dev/null 2>&1
  then
    LogError "jq is required to parse forecasts. Install it (e.g. apt install jq)."
    End 1 "Missing dependency: jq"
  fi
  if ! command -v curl >/dev/null 2>&1
  then
    LogError "curl is required to fetch forecasts. Install it (e.g. apt install curl)."
    End 1 "Missing dependency: curl"
  fi
}

################################################################################
# Function    : ValidateConfig
# Description : Validates the numeric .env-sourced config values up front, since
#               a malformed value (e.g. "24h", a decimal, or empty) would
#               otherwise silently break the lookahead arithmetic or `sleep`.
#               Lookahead/throttle must be non-negative integers; the precip
#               threshold may be a non-negative decimal. Ends with an error on
#               the first offender.
# Parameters  : /
################################################################################

ValidateConfig()
{
  if ! [[ "$RAIN_ALERT_LOOKAHEAD_HOURS" =~ ^[0-9]+$ ]]
  then
    LogError "RAIN_ALERT_LOOKAHEAD_HOURS must be a non-negative integer."
    End 1 "Invalid RAIN_ALERT_LOOKAHEAD_HOURS: '$RAIN_ALERT_LOOKAHEAD_HOURS'"
  fi
  if ! [[ "$RAIN_ALERT_THROTTLE_SECONDS" =~ ^[0-9]+$ ]]
  then
    LogError "RAIN_ALERT_THROTTLE_SECONDS must be a non-negative integer."
    End 1 "Invalid RAIN_ALERT_THROTTLE_SECONDS: '$RAIN_ALERT_THROTTLE_SECONDS'"
  fi
  if ! [[ "$RAIN_ALERT_PRECIP_THRESHOLD_MM" =~ ^[0-9]+(\.[0-9]+)?$ ]]
  then
    LogError "RAIN_ALERT_PRECIP_THRESHOLD_MM must be a non-negative number."
    End 1 "Invalid RAIN_ALERT_PRECIP_THRESHOLD_MM: '$RAIN_ALERT_PRECIP_THRESHOLD_MM'"
  fi
}

################################################################################
# Function    : CheckMsmtp
# Description : Hard-checks for msmtp when a real send is required. Under
#               --dry-run or --display no send happens, so absence is tolerated.
#               Ends with install guidance when msmtp is missing and a real send
#               is needed.
# Parameters  : /
################################################################################

CheckMsmtp()
{
  if [ "$DRY_RUN" -eq 1 ] || [ "$DISPLAY_ONLY" -eq 1 ]
  then
    return 0
  fi
  if ! command -v msmtp >/dev/null 2>&1
  then
    LogError "msmtp is required to send mail. Install it (e.g. apt install msmtp)"
    LogError "and configure ~/.msmtprc, or pipe the message to curl smtps://"
    LogError "(see -h). Re-run with -n/--dry-run to preview without sending."
    End 1 "Missing dependency: msmtp"
  fi
}

################################################################################
# Function    : ParseCities
# Description : Splits the RAIN_ALERT_CITIES scalar (whitespace- or comma-
#               separated "name:lat:lon" entries) and validates each, warning
#               and skipping malformed ones (non-numeric lat/lon, wrong field
#               count). Populates VALID_CITIES with the surviving entries.
# Parameters  : /
################################################################################

ParseCities()
{
  VALID_CITIES=()
  # Treat commas as separators too, then word-split on whitespace.
  local raw="${RAIN_ALERT_CITIES//,/ }"
  local entries=()
  read -ra entries <<< "$raw"
  local entry name lat lon
  for entry in "${entries[@]}"
  do
    IFS=':' read -r name lat lon <<< "$entry"
    if [ -z "$name" ] || [ -z "$lat" ] || [ -z "$lon" ]
    then
      LogWarn "Skipping malformed city entry: '$entry' (expected name:lat:lon)"
      continue
    fi
    if ! [[ "$lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] \
      || ! [[ "$lon" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
    then
      LogWarn "Skipping '$name': non-numeric coordinates ('$lat', '$lon')"
      continue
    fi
    VALID_CITIES+=("$name:$lat:$lon")
  done
}

################################################################################
# Function    : FetchForecast
# Description : Fetches the compact forecast JSON for lat/lon to stdout. Uses a
#               descriptive User-Agent (met.no TOS) and connect/total timeouts.
#               Returns non-zero on transport failure / non-2xx so one city's
#               failure does not abort the run.
# Parameters  : lat lon
################################################################################

FetchForecast()
{
  local lat="$1" lon="$2"
  curl -fsS \
    --connect-timeout 10 \
    --max-time 30 \
    -H "User-Agent: $RAIN_ALERT_USER_AGENT" \
    "$API_BASE?lat=$lat&lon=$lon"
}

################################################################################
# Function    : DetectRain
# Description : Given forecast JSON on stdin, emits one TAB-separated
#               "<utc-time>\t<symbol_code>\t<amount>" line per timeseries entry
#               within now..now+lookahead whose next_1_hours symbol matches
#               rain/sleet/thunder OR whose precipitation_amount exceeds the
#               threshold. Tolerates missing next_1_hours via jq ?/select guards
#               so a long lookahead never errors.
# Parameters  : lookahead-hours threshold-mm   (JSON on stdin)
################################################################################

DetectRain()
{
  local lookahead="$1" threshold="$2"
  local now_epoch end_epoch
  now_epoch="$(date -u +%s)"
  end_epoch=$(( now_epoch + lookahead * 3600 ))

  # $endt (not $end): "end" is a reserved keyword in jq's grammar.
  jq -r \
    --argjson now "$now_epoch" \
    --argjson endt "$end_epoch" \
    --argjson threshold "$threshold" '
    .properties.timeseries[]?
    | { t: .time
      , ep: (.time | fromdateiso8601)
      , sym: (.data.next_1_hours.summary.symbol_code? // "")
      , amt: (.data.next_1_hours.details.precipitation_amount? // 0)
      }
    | select(.ep >= $now and .ep <= $endt)
    | select((.sym | test("rain|sleet|thunder")) or (.amt > $threshold))
    | [ .t, .sym, (if .amt > 0 then (.amt | tostring) else "" end) ] | @tsv
  '
}

################################################################################
# Function    : FormatLocalTime
# Description : Converts a met.no UTC (Zulu) ISO-8601 timestamp into a readable
#               local-time string. Cron-env safe: feeds the explicit UTC string
#               to `date -d` (no reliance on inherited TZ for the source value).
#               Falls back to the raw timestamp if `date` cannot parse it.
# Parameters  : utc-iso8601
################################################################################

FormatLocalTime()
{
  local utc="$1"
  date -d "$utc" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || echo "$utc"
}

################################################################################
# Function    : CollectCity
# Description : Fetches + detects rain for one city entry, appending to the
#               RAINY_CITIES / RAINY_DETAILS accumulators when rain is found.
#               Fetch/parse failures warn and return without aborting the run.
# Parameters  : name:lat:lon
################################################################################

CollectCity()
{
  local entry="$1"
  local name lat lon
  IFS=':' read -r name lat lon <<< "$entry"

  local json
  if ! json="$(FetchForecast "$lat" "$lon")"
  then
    LogWarn "Failed to fetch forecast for $name ($lat,$lon); skipping."
    return 1
  fi

  # A 2xx with an empty body would parse as jq-success/no-rain and be silently
  # swallowed; warn and skip instead so a degenerate response is not mistaken
  # for "no rain expected".
  if [ -z "$json" ]
  then
    LogWarn "Empty forecast body for $name; skipping."
    return 1
  fi

  local matches
  if ! matches="$(printf '%s' "$json" \
    | DetectRain "$RAIN_ALERT_LOOKAHEAD_HOURS" "$RAIN_ALERT_PRECIP_THRESHOLD_MM")"
  then
    LogWarn "Failed to parse forecast for $name; skipping."
    return 1
  fi

  if [ -z "$matches" ]
  then
    LogInfo "No rain expected for $name."
    return 0
  fi

  local detail="" t sym amt local_t annots note
  while IFS=$'\t' read -r t sym amt
  do
    [ -z "$t" ] && continue
    local_t="$(FormatLocalTime "$t")"
    # Build the parenthesized annotation from whichever of symbol/amount exist.
    annots=()
    [ -n "$sym" ] && annots+=("$sym")
    # DetectRain emits an empty amount for any non-positive value, so a simple
    # non-empty test suppresses "0"/"0.0" without a second tool (no awk).
    [ -n "$amt" ] && annots+=("${amt} mm")
    note=""
    if [ "${#annots[@]}" -gt 0 ]
    then
      local joined
      joined="$(IFS=', '; echo "${annots[*]}")"
      note=" ($joined)"
    fi
    detail+="  ${local_t}${note}"$'\n'
  done <<< "$matches"

  RAINY_CITIES+=("$name")
  RAINY_DETAILS+=("$detail")
  LogInfo "Rain expected for $name."
}

################################################################################
# Function    : ComputeSignature
# Description : Emits a stable signature of the rainy-city/time result set so an
#               unchanged forecast can be de-duped against the cache. Built from
#               each city's name and its detail block, order-stable.
# Parameters  : /
################################################################################

ComputeSignature()
{
  local i
  for i in "${!RAINY_CITIES[@]}"
  do
    printf '%s\n%s\n' "${RAINY_CITIES[$i]}" "${RAINY_DETAILS[$i]}"
  done
}

################################################################################
# Function    : BuildSubject
# Description : Emits the email subject line, pluralizing city/cities.
# Parameters  : /
################################################################################

BuildSubject()
{
  local count="${#RAINY_CITIES[@]}"
  local noun="cities"
  [ "$count" -eq 1 ] && noun="city"
  echo "Rain expected in $count $noun"
}

################################################################################
# Function    : BuildEmail
# Description : Composes the full RFC-822-ish message (To/Subject/blank/body) on
#               stdout. The body lists each rainy city with its expected rain
#               times. RAIN_ALERT_RECIPIENT must be set (checked in Main).
# Parameters  : /
################################################################################

BuildEmail()
{
  local subject
  subject="$(BuildSubject)"
  printf 'To: %s\n' "$RAIN_ALERT_RECIPIENT"
  printf 'Subject: %s\n' "$subject"
  printf '\n'
  printf '%s\n\n' "$subject"
  local i
  for i in "${!RAINY_CITIES[@]}"
  do
    printf '%s:\n' "${RAINY_CITIES[$i]}"
    printf '%s\n' "${RAINY_DETAILS[$i]}"
  done
}

################################################################################
# Function    : SendEmail
# Description : Sends the composed message via msmtp (dry-run aware via
#               RunOrEcho), feeding the message on stdin. Under --dry-run prints
#               the recipient, subject, and full body that WOULD be sent without
#               invoking msmtp.
# Parameters  : message
################################################################################

SendEmail()
{
  local message="$1"
  if [ "$DRY_RUN" -eq 1 ]
  then
    LogInfo "[dry-run] would send the following email:"
    LogInfo "To: $RAIN_ALERT_RECIPIENT"
    LogInfo "$(BuildSubject)"
    LogInfo ""
    LogInfo "$message"
  fi
  # Only pass --account when configured; an empty --account= is rejected by
  # stricter msmtp builds, whereas omitting it selects the default account
  # (the documented empty-value behaviour).
  local args=()
  [ -n "$RAIN_ALERT_MSMTP_ACCOUNT" ] \
    && args+=("--account=$RAIN_ALERT_MSMTP_ACCOUNT")
  # ${args[@]+"${args[@]}"}: set -u-safe even when args is empty (Bash < 4.4
  # would otherwise abort on an empty "${args[@]}").
  RunOrEcho msmtp ${args[@]+"${args[@]}"} "$RAIN_ALERT_RECIPIENT" <<< "$message"
}

################################################################################
# Function    : DisplayForecast
# Description : Prints the rainy-city/time result set to stdout for --display
#               mode (no email). Reports an explicit no-rain line when nothing
#               matched, since display mode is interactive and should not be
#               silent like a cron send.
# Parameters  : /
################################################################################

DisplayForecast()
{
  if [ "${#RAINY_CITIES[@]}" -eq 0 ]
  then
    echo "No rain expected in any configured city within the lookahead window."
    return 0
  fi
  echo "$(BuildSubject):"
  echo ""
  local i
  for i in "${!RAINY_CITIES[@]}"
  do
    printf '%s:\n' "${RAINY_CITIES[$i]}"
    printf '%s\n' "${RAINY_DETAILS[$i]}"
  done
}

################################################################################
# Function    : Main
# Description : Main entry point: parse cities, fetch + detect rain per city, and
#               (when rain is expected anywhere and the forecast has changed
#               since the last alert) compose and send the email. No rain
#               anywhere => exit silently with no email.
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"
  CheckDependencies
  ValidateConfig
  CheckMsmtp

  # Display mode needs no recipient (it never sends); a real/dry-run send does.
  if [ "$DISPLAY_ONLY" -ne 1 ] && [ -z "${RAIN_ALERT_RECIPIENT:-}" ]
  then
    Help
    MissingRequiredArguments
  fi

  ParseCities
  if [ "${#VALID_CITIES[@]}" -eq 0 ]
  then
    LogWarn "No valid cities configured (check RAIN_ALERT_CITIES)."
    End 0
  fi

  local city first=1
  for city in "${VALID_CITIES[@]}"
  do
    # Throttle between cities to respect met.no's terms of service.
    [ "$first" -eq 1 ] || sleep "$RAIN_ALERT_THROTTLE_SECONDS"
    first=0
    CollectCity "$city"
  done

  # Display mode: print the result and exit; never send, never touch the cache.
  if [ "$DISPLAY_ONLY" -eq 1 ]
  then
    DisplayForecast
    End 0
  fi

  if [ "${#RAINY_CITIES[@]}" -eq 0 ]
  then
    # Cron-noise-free: no rain anywhere => no email, exit silently.
    End 0
  fi

  local signature
  signature="$(ComputeSignature)"

  if [ -f "$RAIN_ALERT_CACHE_FILE" ] \
    && [ "$signature" = "$(cat "$RAIN_ALERT_CACHE_FILE")" ]
  then
    LogInfo "Forecast unchanged since last alert; not re-sending."
    End 0
  fi

  local message
  message="$(BuildEmail)"
  SendEmail "$message"

  # Update the cache only after a real (non-dry-run) send. Write atomically via
  # a temp file + mv so an interrupted write cannot leave a truncated cache that
  # would never match and thus re-send every run.
  if [ "$DRY_RUN" -ne 1 ]
  then
    mkdir -p "$(dirname "$RAIN_ALERT_CACHE_FILE")"
    printf '%s' "$signature" > "$RAIN_ALERT_CACHE_FILE.tmp" \
      && mv "$RAIN_ALERT_CACHE_FILE.tmp" "$RAIN_ALERT_CACHE_FILE"
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

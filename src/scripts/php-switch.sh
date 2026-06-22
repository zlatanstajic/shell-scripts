#!/bin/bash

################################################################################
# Script name : php-switch.sh
# Description : Switch main version of PHP on OS
# Parameters  : version
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source "$SCRIPT_DIR/../lib/common.sh"

set -u

PHP_VERSION=""

# Parallel arrays acting as the version -> path map (sorted by version)
PHP_MAP_VERSIONS=()
PHP_MAP_PATHS=()

################################################################################
# Function    : DetectVersions
# Description : Detects installed PHP versions via update-alternatives and builds
#               the version -> path map (PHP_MAP_VERSIONS / PHP_MAP_PATHS)
# Parameters  : /
################################################################################

DetectVersions()
{
  # Non-fatal: leaves the map empty when PHP alternatives are unavailable so
  # that -h still prints help (Main enforces a populated map before switching).
  if ! command -v update-alternatives &> /dev/null
  then
    return
  fi

  local paths
  if ! paths=$(update-alternatives --list php 2>/dev/null) || [ -z "$paths" ]
  then
    return
  fi

  local version
  while IFS= read -r path
  do
    [ -z "$path" ] && continue
    version=""
    [[ "$path" =~ [0-9]+\.[0-9]+ ]] && version="${BASH_REMATCH[0]}"
    if [ -n "$version" ]
    then
      PHP_MAP_VERSIONS+=("$version")
      PHP_MAP_PATHS+=("$path")
    fi
  done < <(echo "$paths" | sort)
}

################################################################################
# Function    : PathForVersion
# Description : Echoes the path for a given version, or empty if not present
# Parameters  : version
################################################################################

PathForVersion()
{
  local i
  for i in "${!PHP_MAP_VERSIONS[@]}"
  do
    if [ "${PHP_MAP_VERSIONS[$i]}" = "$1" ]
    then
      echo "${PHP_MAP_PATHS[$i]}"
      return
    fi
  done
}

################################################################################
# Function    : ListVersions
# Description : Lists detected PHP versions
# Parameters  : /
################################################################################

ListVersions()
{
  local i
  LogInfo "Installed PHP versions:"
  for i in "${!PHP_MAP_VERSIONS[@]}"
  do
    LogInfo "$((i + 1)). PHP ${PHP_MAP_VERSIONS[$i]} (${PHP_MAP_PATHS[$i]})"
  done
}

################################################################################
# Function    : CurrentValue
# Description : Echoes the currently set php alternative path (Value: line)
# Parameters  : /
################################################################################

CurrentValue()
{
  update-alternatives --query php 2>/dev/null \
    | grep '^Value:' \
    | head -n 1 \
    | cut -d ':' -f 2- \
    | sed 's/^ *//'
}

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Switch main version of PHP on OS"
  echo ""
  ListVersions
  local current
  current=$(CurrentValue)
  if [ -n "$current" ]
  then
    echo -e "Currently set PHP version: \e[1m$current\e[0m"
  fi
  echo ""
  echo "Show this help : $SCRIPT_NAME -h"
  echo "Switch version : $SCRIPT_NAME -v 8.1"
  echo "Interactive    : $SCRIPT_NAME"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -v version
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
      -v|--version)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        PHP_VERSION="$2"
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
# Function    : ApacheSwitch
# Description : Resilient apache module handling for the chosen PHP version;
#               never hard-fails, warns and continues if tools/modules absent
# Parameters  : chosen-version
################################################################################

ApacheSwitch()
{
  local chosen="$1"
  local i version

  if command -v a2dismod &> /dev/null
  then
    for i in "${!PHP_MAP_VERSIONS[@]}"
    do
      version="${PHP_MAP_VERSIONS[$i]}"
      [ "$version" = "$chosen" ] && continue
      sudo a2dismod "php${version}" 2>/dev/null \
        || LogWarn "Could not disable apache module php${version} (may not be enabled)."
    done
  else
    LogWarn "a2dismod could not be found. Skipping apache module disabling."
  fi

  if command -v a2enmod &> /dev/null
  then
    sudo a2enmod "php${chosen}" 2>/dev/null \
      || LogWarn "Could not enable apache module php${chosen} (may not be installed)."
  else
    LogWarn "a2enmod could not be found. Skipping apache module enabling."
  fi

  if command -v systemctl &> /dev/null
  then
    LogInfo ""
    LogInfo "Running command systemctl restart apache2..."
    sudo systemctl restart apache2 2>/dev/null \
      || LogWarn "Could not restart apache2 (service may not be present)."
  else
    LogWarn "systemctl could not be found. Skipping apache2 restart."
  fi
}

################################################################################
# Function    : SwitchVersion
# Description : Switches php alternative to the given version, runs apache steps
# Parameters  : version
################################################################################

SwitchVersion()
{
  local version="$1"
  local path
  path=$(PathForVersion "$version")

  local current
  current=$(CurrentValue)
  if [ -n "$current" ]
  then
    LogInfo "Currently set PHP version: $current"
    if [ "$current" = "$path" ]
    then
      LogInfo "The selected PHP version is already set. No changes made."
      End 0
    fi
  fi

  sudo update-alternatives --set php "$path" || End 1 "Could not set php alternative to $path"

  ApacheSwitch "$version"

  LogInfo ""
  LogInfo "Current PHP version:"
  php --version
  End 0
}

################################################################################
# Function    : InteractivePick
# Description : Interactive numeric pick from the detected version map
# Parameters  : /
################################################################################

InteractivePick()
{
  ListVersions
  local choice
  choice=$(UserInput "Select the PHP version to switch to (by number)")

  if ! [[ "$choice" =~ ^[0-9]+$ ]]
  then
    End 1 "Invalid input. Please enter a number."
  fi

  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#PHP_MAP_VERSIONS[@]}" ]
  then
    End 1 "Invalid choice."
  fi

  SwitchVersion "${PHP_MAP_VERSIONS[$((choice - 1))]}"
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  DetectVersions
  GetArguments "$@"

  # -h/--help has already exited via GetArguments; any other path needs PHP.
  if [ "${#PHP_MAP_VERSIONS[@]}" -eq 0 ]
  then
    End 1 "Could not list PHP versions. No PHP alternatives found."
  fi

  if [ -n "$PHP_VERSION" ]
  then
    if [ -z "$(PathForVersion "$PHP_VERSION")" ]
    then
      ListVersions
      End 1 "PHP version $PHP_VERSION is not among the installed alternatives."
    fi
    SwitchVersion "$PHP_VERSION"
  else
    InteractivePick
  fi
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
RunScript Main "$@"

################################################################################

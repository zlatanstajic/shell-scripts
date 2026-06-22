#!/bin/bash

################################################################################
# Script name : generate-password.sh
# Description : Generate strong and secure password
# Parameters  : length
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

MINIMUM_PASSWORD_LENGTH=8
NUMBER_OF_CHUNKS=4
LENGTH=20

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  EchoBold "Running $SCRIPT_NAME"
  echo "Description: Generate strong and secure password"
  echo "Minimum length is $MINIMUM_PASSWORD_LENGTH and must be divisible by $NUMBER_OF_CHUNKS."
  echo ""
  echo "Show this help    : $SCRIPT_NAME -h"
  echo "Generate password : $SCRIPT_NAME -l 20"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | -l length
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
      -l|--length)
        if [ $# -lt 2 ]
        then
          Help
          End 1 "Option $1 requires a value"
        fi
        LENGTH="$2"
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
# Function    : GenerateChunk
# Description : Generates a random chunk of characters from a character set
# Parameters  : character-set count
################################################################################

GenerateChunk()
{
  # Characters may repeat within a chunk (intentional: drawn independently from
  # /dev/urandom, giving higher entropy than Python's unique-sampling approach).
  # Each pass reads a bounded 256-byte block (head -c exits on its own) and
  # filters it, looping until enough characters accumulate. This avoids the
  # `tr < /dev/urandom | head` idiom, where tr reads /dev/urandom indefinitely
  # and only stops on a SIGPIPE that may never arrive, hanging the caller.
  local set="$1" count="$2" out=""
  while [ "${#out}" -lt "$count" ]
  do
    out+="$(LC_ALL=C tr -dc "$set" < <(head -c 256 /dev/urandom))"
  done
  printf '%s' "${out:0:count}"
}

################################################################################
# Function    : GeneratePassword
# Description : Generates password from 4 shuffled character chunks
# Parameters  : length
################################################################################

GeneratePassword()
{
  local length=$1
  local per_chunk=$((length / NUMBER_OF_CHUNKS))

  local chunks=(
    "a-z"
    "A-Z"
    "0-9"
    '!#$%&()+,-.:=?@[]_{|}~'
  )
  # readarray (not unquoted command substitution) so the punctuation chunk,
  # which contains [ ] ?, is not glob-expanded against CWD filenames.
  readarray -t chunks < <(shuf -e "${chunks[@]}")

  local password=""
  for chunk in "${chunks[@]}"
  do
    password+=$(GenerateChunk "$chunk" "$per_chunk")
  done

  echo "$password"
}

################################################################################
# Function    : Main
# Description : Main entry point for the script
# Parameters  : arguments
################################################################################

Main()
{
  GetArguments "$@"

  if ! [[ "$LENGTH" =~ ^[0-9]+$ ]]
  then
    End 1 "Length must be a positive integer."
  fi

  if [ "$LENGTH" -lt "$MINIMUM_PASSWORD_LENGTH" ]
  then
    End 1 "Please enter length greater than or equal to $MINIMUM_PASSWORD_LENGTH."
  fi

  if [ $((LENGTH % NUMBER_OF_CHUNKS)) -ne 0 ]
  then
    End 1 "Please enter length divisible by $NUMBER_OF_CHUNKS like: 8, 12, 16, 20, ..."
  fi

  GENERATED_PASSWORD=$(GeneratePassword "$LENGTH")
  LogInfo "$GENERATED_PASSWORD"

  if command -v xclip &> /dev/null
  then
    echo -n "$GENERATED_PASSWORD" | xclip -selection clipboard
    LogInfo "Copied password to the clipboard."
  else
    LogWarn "xclip could not be found. Please install xclip to enable clipboard copy."
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

#!/bin/bash

################################################################################
# Script name : generate-password.sh
# Description : Generate strong and secure password
# Parameters  : /
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Variables
################################################################################

SCRIPT_NAME="`basename $(readlink -f $0)`"
SCRIPT_DIR="`dirname $(readlink -f $0)`"

################################################################################
# Function    : GenerateRandomString
# Description : Generates random string for given type
# Parameters  : type
################################################################################

GenerateRandomString()
{
  if [ "$1" = "numbers" ]
  then
    RANGE="0-9"
  elif [ "$1" = "characters" ]
  then
    RANGE="!#$%&()+,-.:=?@[\]_{|}~"
  elif [ "$1" = "letters-uppercase" ]
  then
    RANGE="A-Z"
  elif [ "$1" = "letters-lowercase" ]
  then
    RANGE="a-z"
  fi

  echo $(cat /dev/urandom | tr -dc $RANGE | fold -w 5 | head -n 1)
}

################################################################################
# Function    : GeneratePassword
# Description : Generates password
# Parameters  : /
################################################################################

GeneratePassword()
{
  GENERATE_RANDOM_STRING_TYPES=(
    "numbers"
    "characters"
    "letters-lowercase"
    "letters-uppercase"
  )
  GENERATE_RANDOM_STRING_TYPES=( $(shuf -e "${GENERATE_RANDOM_STRING_TYPES[@]}") )
  GENERATED_PASSWORD=''

  for type in ${GENERATE_RANDOM_STRING_TYPES[*]}
  do
    GENERATED_PASSWORD+=$(GenerateRandomString $type)
  done

  echo $GENERATED_PASSWORD
}

################################################################################
# Function    : DoYouWishToProceed
# Description : Handles proceeding dialog
# Parameters  : /
################################################################################

DoYouWishToProceed()
{
  while true; do
    read -p "Do you wish to proceed? [y/n]: " yn
    case $yn in
      [Yy]* )
        echo "1"
      break;;
      [Nn]* )
        echo "0"
      break;;
    esac
  done
}

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  echo -e "\e[1mRunning $SCRIPT_NAME\e[0m"
  echo "Description: Generate strong and secure password"
  echo ""
  echo "Show this help : $SCRIPT_NAME -h"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h
################################################################################

GetArguments()
{
  if [ $# -eq 1 ]
  then
    if [ "$1" = "-h" ]
    then
      Help
      End 0
    fi
  fi
}

################################################################################
# Function    : End
# Description : Terminates shell script
# Parameters  : is-with-error [error-text]
################################################################################

End()
{
  if [ $1 -eq 0 ]
  then
    echo ""
    echo "Script $SCRIPT_NAME finishing OK"
    exit 0
  else
    echo ""
    echo -e "Script $SCRIPT_NAME finishing with \e[1mERROR [$2]\e[0m"
    exit 1
  fi
}

################################################################################
# Execution
################################################################################

echo "Script $SCRIPT_NAME starting..."
echo ""
GetArguments $@
GENERATED_PASSWORD=$(GeneratePassword)

echo $GENERATED_PASSWORD
echo ""
echo "Will copy password to clipboard"

if [ "$(DoYouWishToProceed)" -eq 1 ]
then
  # Checks if xclip is installed
  if ! command -v xclip -selection clipboard &> /dev/null
  then
    END 1 "xclip could not be found"
  else
    echo $GENERATED_PASSWORD | xclip -selection clipboard
  fi
fi

End 0

################################################################################

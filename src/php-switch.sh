#!/bin/bash

################################################################################
# Script name : php-switch.sh
# Description : Switch main version of PHP on OS
# Parameters  : php-version
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Parameters
################################################################################

PHP_VERSION=$1

################################################################################
# Variables
################################################################################

SCRIPT_NAME="`basename $(readlink -f $0)`"
SCRIPT_DIR="`dirname $(readlink -f $0)`"

# PHP versions installed on your OS (remove # to declare as installed)
PHP_VERSIONS_INSTALLED=(
  #"5.6"
  #"7.0"
  #"7.1"
  #"7.2"
  #"7.3"
  #"7.4"
  #"8.0"
  #"8.1"
)

################################################################################
# Function    : CurrentPHPVersion
# Description : Shows current php version
# Parameters  : /
################################################################################

CurrentPHPVersion()
{
  CURRENT_PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")
  echo -e "Current PHP version: \e[1m$CURRENT_PHP_VERSION\e[0m"
}

################################################################################
# Function    : Help
# Description : Shows help text for script
# Parameters  : /
################################################################################

Help()
{
  echo -e "\e[1mRunning $SCRIPT_NAME\e[0m"
  echo "Description: Switch main version of PHP on OS"
  echo ""

  if [ ${#PHP_VERSIONS_INSTALLED[@]} -eq 0 ]
  then
    echo "Update PHP_VERSIONS_INSTALLED in $SCRIPT_DIR/$SCRIPT_NAME"
  else
    INSTALLED=""
    for version in ${PHP_VERSIONS_INSTALLED[*]}
    do
      INSTALLED+="${version} "
    done
    echo -e "Installed versions: \e[1m$INSTALLED\e[0m"
  fi

  CurrentPHPVersion
  echo ""
  echo "Show this help : $SCRIPT_NAME -h"
  echo "Switch version : $SCRIPT_NAME [php-version]"
}

################################################################################
# Function    : GetArguments
# Description : Gets arguments passed to the script
# Parameters  : -h | php-version
################################################################################

GetArguments()
{
  if [ $# -eq 1 ]
  then
    if [ "x$1" = "x-h" ]
    then
      Help
      End 0
    # Checking PHP version
    elif [[ ! " ${PHP_VERSIONS_INSTALLED[@]} " =~ " ${PHP_VERSION} " ]]
    then
      Help
      End 1 "Incorrect parameters: Non-existent PHP version"
    fi
  else
    Help
    End 1 "Incorrect parameters"
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

for version in ${PHP_VERSIONS_INSTALLED[*]}
do
  sudo a2dismod php${version}
done

sudo update-alternatives --set php /usr/bin/php${PHP_VERSION}
sudo a2enmod php${PHP_VERSION}
echo ""
echo "Running command systemctl restart apache2..."
sudo systemctl restart apache2
CurrentPHPVersion
End 0

################################################################################

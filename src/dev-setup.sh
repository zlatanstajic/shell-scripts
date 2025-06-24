#!/bin/bash

################################################################################
# Script name : dev-setup.sh
# Description : Development setup for git
# Parameters  : issue-number issue-name
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

################################################################################
# Parameters
################################################################################

ISSUE_NUMBER=$1
ISSUE_NAME=$2

################################################################################
# Variables
################################################################################

SCRIPT_NAME="`basename $(readlink -f $0)`"
SCRIPT_DIR="`dirname $(readlink -f $0)`"

# Prefix for branch name
BRANCH_PREFIX="issues"

# Prefix for pull/merge request name
REQUEST_PREFIX="refs:"

# Path to the issue (can be empty)
ISSUE_BASE_PATH=""

################################################################################
# Function    : IssueNameForBranch
# Description : Converts issue name for branch
# Parameters  : /
################################################################################

IssueNameForBranch()
{
  ISSUE_AS_SNAKE_CASE=${ISSUE_NAME// /_}
  declare -l ISSUE_NAME_FOR_BRANCH
  ISSUE_NAME_FOR_BRANCH=$ISSUE_AS_SNAKE_CASE
  echo ${ISSUE_NAME_FOR_BRANCH//[&]/and} | sed -e 's/|/\-/g'
}

################################################################################
# Function    : DisplayDirectoryName
# Description : Displays directory name
# Parameters  : /
################################################################################

DisplayDirectoryName()
{
  CURRENT_WORKING_DIRECTORY=`pwd`
  DIRECTORY_NAME=`basename "$CURRENT_WORKING_DIRECTORY"`
  echo -e "Located in directory: \e[1m$DIRECTORY_NAME\e[0m\n"
}

################################################################################
# Function    : IsDirectoryGitRepository
# Description : Checks if directory is git repository
# Parameters  : /
################################################################################

IsDirectoryGitRepository()
{
  if [ -d .git ]
  then
    return 1
  else
    End 1 "Not git repo"
  fi
}

################################################################################
# Function    : UserInput
# Description : Handles user input
# Parameters  : message
################################################################################

UserInput()
{
  read -p "$1: " input
  echo $input
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
  echo "Description: Development setup for git"
  echo ""
  echo "Show this help  : $SCRIPT_NAME -h"
  echo "Run this script : $SCRIPT_NAME [issue-number] [issue-name]"
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
    if [ "x$1" = "x-h" ]
    then
      Help
      End 0
    else
      Help
      End 1 "Two parameters are required!"
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
DisplayDirectoryName
IsDirectoryGitRepository

echo "Available branches:"
git branch
echo ""

SOURCE_BRANCH=$(UserInput "Enter name of the branch you want to create new branch from")
TARGET_BRANCH=${BRANCH_PREFIX}/${ISSUE_NUMBER}_$(IssueNameForBranch)
echo -e "Will create branch \e[1m$TARGET_BRANCH\e[0m from \e[1m$SOURCE_BRANCH\e[0m"
echo ""

if [ "$(DoYouWishToProceed)" -eq 1 ]
then
  git checkout ${SOURCE_BRANCH} || END 1 "Not able to checkout to the ${SOURCE_BRANCH}"
  git pull
  git branch ${TARGET_BRANCH}
  git checkout ${TARGET_BRANCH}
  echo ""
  echo "Will push local branch to remote"
  if [ "$(DoYouWishToProceed)" -eq 1 ]
  then
    git push -u origin ${TARGET_BRANCH}
    echo ""
    echo "Copy following info:"
    echo ""
    echo "Name: $REQUEST_PREFIX #$ISSUE_NUMBER $ISSUE_NAME"
    if [ -n "${ISSUE_BASE_PATH}" ]
    then
      echo "Description: Based on $BRANCH_PREFIX [#$ISSUE_NUMBER]($ISSUE_BASE_PATH/$ISSUE_NUMBER)"
    fi
  else
    git checkout ${SOURCE_BRANCH}
    git branch -D ${TARGET_BRANCH}
  fi
fi

End 0

################################################################################

#!/bin/bash

################################################################################
# Script name : tests/run.sh
# Description : Pure-bash test runner. Sources tests/lib/assert.sh then every
#               test_*.sh file found under tests/ (recursively, sorted),
#               printing a per-assertion report and a final summary. Exits
#               non-zero if any assertion failed, so it doubles as a CI gate.
#               No external dependencies.
# Parameters  : [test-file ...]  (defaults to all test_*.sh under tests/)
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

set -u

RUNNER_DIR="$(dirname "$(readlink -f "$0")")"

source "$RUNNER_DIR/lib/assert.sh"

# Run an explicit list if given, otherwise discover every test file.
if [ "$#" -gt 0 ]
then
  TEST_FILES=("$@")
else
  mapfile -t TEST_FILES < <(find "$RUNNER_DIR" -name 'test_*.sh' | sort)
fi

for test_file in "${TEST_FILES[@]}"
do
  echo -e "\e[1m$(basename "$test_file")\e[0m"
  # shellcheck source=/dev/null
  source "$test_file"
done

echo ""
echo "--------------------------------------------------------------------------------"
if [ "$TESTS_FAILED" -eq 0 ]
then
  echo -e "\e[32mAll $TESTS_RUN assertions passed\e[0m"
  exit 0
else
  echo -e "\e[31m$TESTS_FAILED of $TESTS_RUN assertions failed\e[0m"
  exit 1
fi

################################################################################

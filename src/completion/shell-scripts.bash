# shellcheck shell=bash
################################################################################
# File        : src/completion/shell-scripts.bash
# Description : Bash completion for the commands install.sh links onto PATH.
#               These scripts take flags, not subcommands, so each name is just
#               registered as completable. Installed by install.sh into the user
#               bash-completion directory. Keep the name list in sync with the
#               user-facing src/scripts/*.sh (the drift test enforces this).
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# A single complete -W line over all 9 names exceeds 80 cols, so build the list
# across wrapped assignments, then register each name.
_ssc_names="backup dev-setup generate-password git-copy"
_ssc_names="$_ssc_names hash-filenames php-switch restore-vscode-folder"
_ssc_names="$_ssc_names splice-images splice-videos"

for _ssc in $_ssc_names; do
  complete -W "" "$_ssc"
done

unset _ssc _ssc_names

################################################################################

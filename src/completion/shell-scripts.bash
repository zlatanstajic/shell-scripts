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

# A single complete -W line over all 11 names exceeds 80 cols, so build the list
# across wrapped assignments, then register each name.
_ssc_names="backup decrypt-env-files dev-setup generate-password"
_ssc_names="$_ssc_names git-copy hash-filenames php-switch"
_ssc_names="$_ssc_names restore-vscode-folder splice-images splice-videos"
_ssc_names="$_ssc_names tampermonkey-install"

for _ssc in $_ssc_names; do
  complete -W "" "$_ssc"
done

unset _ssc _ssc_names

################################################################################

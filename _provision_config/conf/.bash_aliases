#!/bin/bash

source "$HOME/.profile"

source "$DIR_WORKSPACE/conf/.bash/shortcuts.sh"
source "$DIR_WORKSPACE/conf/.bash/tools.sh"
source "$DIR_WORKSPACE/conf/.bash/webserver.sh"
source "$DIR_WORKSPACE/conf/.bash/docker.sh"
source "$DIR_WORKSPACE/conf/.bash/git.sh"
source "$DIR_WORKSPACE/conf/.bash/fm.sh"
source "$DIR_WORKSPACE/conf/.bash/cwd.sh"
source "$DIR_WORKSPACE/conf/.bash/preexec.sh"
source "$DIR_WORKSPACE/conf/.bash/ps1.sh"

#. "$HOME/.atuin/bin/env"
eval "$(atuin init bash --disable-up-arrow)"

# bash completion
[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

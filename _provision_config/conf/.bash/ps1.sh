#!/bin/bash

ps1_git_branch() {
    if git rev-parse --is-inside-work-tree 2>/dev/null 1>/dev/null
    then
        STATUS=$(git status -s)
        if [[ $STATUS ]]; then
            echo "[$(gb 2>/dev/null)/*] "
        else
            echo "[$(gb 2>/dev/null)/ ] "
        fi
    fi
}

ps1_eta() {
    ETA_ELAPSED_0="    ${ETA_ELAPSED}"
    if [[ $LAST_RES -eq 0 ]]
    then
        echo -e "/${ETA_ELAPSED_0: -5}s: \001\033[42;30m\002[${LAST_RES}]\001\033[00m\002 "
    else
        echo -e "/${ETA_ELAPSED_0: -5}s: \001\033[41m\002[${LAST_RES}]\001\033[00m\002 "
    fi
}

PS1_FULL='${debian_chroot:+($debian_chroot)}\001\033[01;90m\002\t\001\033[00m\002: $(ps1_git_branch)$(ps1_eta)\001\033[01;32m\002\u@\h\001\033[00m\002:\001\033[01;34m\002\w\001\033[00m\002\$ '
PS1_SHORT='${debian_chroot:+($debian_chroot)}\001\033[01;90m\002\t\001\033[00m\002: $(ps1_git_branch)$(ps1_eta)\001\033[01;32m\002\u@\h\001\033[00m\002:\001\033[01;34m\002/`basename \w`\001\033[00m\002\$ '

alias prt0='export PS1="> "'
alias prt1='export PS1=$PS1_SHORT'
alias prt2='export PS1=$PS1_FULL'

export PS1=$PS1_SHORT

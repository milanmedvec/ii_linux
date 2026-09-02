#!/bin/bash

alias git_perm_reset='git diff -p -R --no-ext-diff --no-color | grep -E "^(diff|(old|new) mode)" --color=never | git apply'
alias gclean='git clean -dfX'
alias gru='git remote update'
alias ga='git add -A .'
alias gap='git add -p'
alias gb='git rev-parse --abbrev-ref HEAD'
alias gm='git commit --no-verify'
alias st='git status'

gr() {
    git reset --soft HEAD~$1
}

gp() {
    if [ -z "$1" ]
    then
        git push -u origin `gb`
    else
        git push -u $1 `gb`
    fi
}

cdr() {
    cd `git rev-parse --show-toplevel`
}

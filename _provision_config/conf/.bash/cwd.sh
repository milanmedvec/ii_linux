#!/bin/bash

alias cdpush='cwd set-default'
alias cdpop='cd `cwd get-default`'

cdq() {
    RESULT=$(cwd)
    clear
    if [[ $? -eq 0 ]]
    then
        cd $RESULT
    fi
}

cdi() {
  local dir

  while true; do
    clear

    dir="$(
      {
        echo ..
        find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
      } | fzf --prompt="$PWD > "
    )"

    [ -z "$dir" ] && break

    cd "$dir" || break
  done
}

